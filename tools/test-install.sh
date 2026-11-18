#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
test_home="$fixture/home"
remote="$fixture/remote"
client="$test_home/dotfiles"
mock_bin="$fixture/bin"
real_git=$(command -v git)
real_cat=$(command -v cat)
real_stat=$(command -v stat)
mkdir -p "$test_home" "$remote" "$mock_bin"

git -C "$source_dir" archive HEAD | tar -x -C "$remote"
cp "$source_dir/install.sh" "$source_dir/.update.sh" "$source_dir/.gitignore" "$remote/"
env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$remote" init -q -b dev
git -C "$remote" add .
env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$remote" \
    -c user.name=Fixture -c user.email=fixture@example.invalid \
    -c commit.gpgsign=false commit -qm fixture
git clone -q "$remote" "$client"
release=$(git -C "$client" rev-parse HEAD)

cat > "$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl\n' >> "$TEST_CALLS"
printf '%s\n' "$TEST_RELEASE"
EOF
cat > "$mock_bin/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    fetch) printf 'fetch\n' >> "$TEST_CALLS" ;;
    clone) echo 'unexpected plugin clone' >&2; exit 1 ;;
esac
exec "$TEST_GIT" "$@"
EOF
cat > "$mock_bin/crontab" <<'EOF'
#!/usr/bin/env bash
printf 'crontab %s\n' "$*" >> "$TEST_CALLS"
case "$1" in
    -l) [[ -f "$TEST_CRONTAB" ]] && cat "$TEST_CRONTAB" ;;
    -) cat > "$TEST_CRONTAB" ;;
    *) exit 1 ;;
esac
EOF
cat > "$mock_bin/cat" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "$TEST_WRITE_TARGET".???????? ]]; then
    case "$TEST_FAIL_WRITE" in
        1|2) printf 'partial write\n'; exit 74 ;;
        HUP|INT|TERM|TERM-restore-failure)
            printf 'partial write\n'
            printf 'signal %s\n' "$TEST_FAIL_WRITE" >> "$TEST_CALLS"
            kill -s "${TEST_FAIL_WRITE%%-*}" "$PPID"
            exit 0
            ;;
    esac
fi
if [[ ( "$TEST_FAIL_WRITE" == 2 || "$TEST_FAIL_WRITE" == TERM-restore-failure ) \
    && "$1" == "$TEST_WRITE_TARGET".backup.???????? ]]; then
    exit 75
fi
exec "$TEST_CAT" "$@"
EOF
cat > "$mock_bin/stat" <<'EOF'
#!/usr/bin/env bash
if [[ "$TEST_BSD_STAT" == 1 ]]; then
    case "$1" in
        -c) exit 1 ;;
        -f) shift 2; exec "$TEST_STAT" -c '%h' "$@" ;;
    esac
fi
exec "$TEST_STAT" "$@"
EOF
for command in ping vim tmux zsh; do
    printf '#!/usr/bin/env bash\necho "unexpected dependency execution" >&2\nexit 1\n' > "$mock_bin/$command"
done
chmod +x "$mock_bin/"*
: > "$fixture/calls"

run_install() {
    env -i HOME="$test_home" PATH="$mock_bin:$PATH" \
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        DFS_IGNORE_COMMIT_SIGN=1 DFS_ORPHAN=1 DFS_UPDATE_CHANNEL=dev \
        TEST_CALLS="$fixture/calls" TEST_RELEASE="$release" \
        TEST_GIT="$real_git" TEST_CRONTAB="$fixture/crontab" \
        TEST_CAT="$real_cat" TEST_STAT="$real_stat" \
        TEST_WRITE_TARGET="$test_home/.tmux.conf" \
        TEST_FAIL_WRITE="${TEST_FAIL_WRITE:-0}" TEST_BSD_STAT="${TEST_BSD_STAT:-0}" \
        bash "$client/install.sh" "$@" > "$fixture/output" 2>&1
}

expect_failure() {
    if run_install "$@"; then
        echo "expected installer to reject arguments: $*" >&2
        exit 1
    fi
}

# Dry-run must avoid dependency installation, remote requests, files, and prompts.
run_install -a --dry-run -x 'DFS_AUDIT_VALUE=hello world'
grep -Fq 'dry run: install' "$fixture/output"
run_install -r --dry-run < /dev/null
grep -Fq 'dry run: uninstall' "$fixture/output"
[[ ! -s "$fixture/calls" && ! -e "$fixture/crontab" ]]
[[ ! -e "$client/update.sh" && ! -e "$test_home/.zshrc" && ! -e "$test_home/.config" ]]
expect_failure -x
expect_failure -H
expect_failure --dry-run -x 'BAD-KEY=value'
[[ ! -s "$fixture/calls" ]]

mkdir -p "$test_home/state" "$test_home/.vim/bundle/Vundle.vim" \
    "$test_home/.tmux/plugins/tpm" "$test_home/.config/dotfiles"
printf '# user configuration without newline' > "$test_home/state/zshrc"
chmod 640 "$test_home/state/zshrc"
ln "$test_home/state/zshrc" "$test_home/state/zshrc-linked"
ln -s state/zshrc "$test_home/.zshrc"
printf 'set -g history-limit 99\n' > "$test_home/.tmux.conf"
chmod 640 "$test_home/.tmux.conf"
ln "$test_home/.tmux.conf" "$test_home/state/tmux-linked"
printf 'source ~/dotfiles/.vimrc2\n' > "$test_home/.vimrc"
printf '[user]\n    email = local@example.invalid\n' > "$test_home/.gitconfig"
printf 'SOURCED_VALUE="local source"\n' > "$test_home/state/local-env"
cat > "$test_home/.config/dotfiles/env" <<'EOF'
# local settings
KEEP_VALUE="keep me"
source "$HOME/state/local-env"
DFS_AUDIT_VALUE="old
multiline value"
if true; then
    DFS_AUDIT_VALUE=conditional
fi
EOF
cp "$test_home/.config/dotfiles/env" "$fixture/original-env"

# Preserve hard links, including a relative symlink to a hard-linked target.
# Emulate BSD stat here to exercise the macOS link-count fallback.
TEST_BSD_STAT=1 run_install -q -x 'DFS_AUDIT_VALUE=hello world'
[[ -L "$test_home/.zshrc" && "$(readlink "$test_home/.zshrc")" == state/zshrc ]]
[[ "$test_home/.zshrc" -ef "$test_home/state/zshrc-linked" ]]
[[ "$test_home/.tmux.conf" -ef "$test_home/state/tmux-linked" ]]
[[ "$(ls -l "$test_home/state/zshrc")" == '-rw-r-----'* ]]
[[ "$(ls -l "$test_home/.tmux.conf")" == '-rw-r-----'* ]]
printf '# user configuration without newline\nsource ~/dotfiles/.zshrc2\n' > "$fixture/expected-zshrc"
cmp "$fixture/expected-zshrc" "$test_home/state/zshrc"
cmp "$fixture/expected-zshrc" "$test_home/state/zshrc-linked"
grep -Fxq 'source-file ~/dotfiles/.tmux.conf2' "$test_home/state/tmux-linked"
[[ -L "$test_home/.ssh/authorized_keys2" && -L "$test_home/.eid/authorized_certificates" ]]
[[ $(grep -c '^0 \* \* \* \* ' "$fixture/crontab") == 1 ]]
env -i HOME="$test_home" PATH="$PATH" bash -c \
    'source "$HOME/.config/dotfiles/env"; [[ $DFS_AUDIT_VALUE == "hello world" && $KEEP_VALUE == "keep me" && $SOURCED_VALUE == "local source" ]]'
head -n "$(wc -l < "$fixture/original-env")" "$test_home/.config/dotfiles/env" > "$fixture/preserved-env"
cmp "$fixture/original-env" "$fixture/preserved-env"

# Repeated writes replace the key, even when an older value already occurred.
for value in one two one; do run_install -q -x "DFS_AUDIT_VALUE=$value"; done
env -i HOME="$test_home" PATH="$PATH" bash -c \
    'source "$HOME/.config/dotfiles/env"; [[ $DFS_AUDIT_VALUE == one ]]'
[[ $(grep -cF 'source ~/dotfiles/.zshrc2' "$test_home/.zshrc") == 1 ]]
[[ $(grep -c '^0 \* \* \* \* ' "$fixture/crontab") == 1 ]]

# Shell metacharacters and embedded newlines remain literal configuration data.
value=$'line one; $(false)\nline two "quoted" \\ end'
run_install -q -x "DFS_AUDIT_VALUE=$value"
printf '%s' "$value" > "$fixture/expected-value"
env -i HOME="$test_home" PATH="$PATH" bash -c \
    'source "$HOME/.config/dotfiles/env"; printf "%s" "$DFS_AUDIT_VALUE"' > "$fixture/actual-value"
cmp "$fixture/expected-value" "$fixture/actual-value"

# Uninstall only removes its own entries, including an include-only file.
rm "$test_home/.ssh/authorized_keys2"
printf 'user supplied authorized key\n' > "$test_home/.ssh/authorized_keys2"
printf '12 3 * * * echo keep\n' >> "$fixture/crontab"
printf 'y\n' | run_install -r
[[ -L "$test_home/.zshrc" ]]
[[ "$test_home/.zshrc" -ef "$test_home/state/zshrc-linked" ]]
[[ "$test_home/.tmux.conf" -ef "$test_home/state/tmux-linked" ]]
printf '# user configuration without newline\n' > "$fixture/expected-zshrc"
cmp "$fixture/expected-zshrc" "$test_home/state/zshrc"
cmp "$fixture/expected-zshrc" "$test_home/state/zshrc-linked"
grep -Fxq 'set -g history-limit 99' "$test_home/.tmux.conf"
! grep -Fq '.tmux.conf2' "$test_home/state/tmux-linked"
[[ "$(ls -l "$test_home/state/zshrc")" == '-rw-r-----'* ]]
[[ "$(ls -l "$test_home/.tmux.conf")" == '-rw-r-----'* ]]
[[ ! -s "$test_home/.vimrc" ]]
grep -Fq 'local@example.invalid' "$test_home/.gitconfig"
! grep -Fq '.gitconfig2' "$test_home/.gitconfig"
grep -Fxq 'user supplied authorized key' "$test_home/.ssh/authorized_keys2"
[[ ! -e "$test_home/.eid/authorized_certificates" && ! -L "$test_home/.eid/authorized_certificates" ]]
grep -Fxq '12 3 * * * echo keep' "$fixture/crontab"
[[ $(wc -l < "$fixture/crontab") -eq 1 ]]
printf 'y\n' | run_install -r
cmp "$fixture/expected-zshrc" "$test_home/state/zshrc"
[[ "$test_home/.zshrc" -ef "$test_home/state/zshrc-linked" ]]
[[ "$test_home/.tmux.conf" -ef "$test_home/state/tmux-linked" ]]

# A user-replaced link must also survive repeated uninstall.
printf 'custom certificates\n' > "$test_home/state/certificates"
ln -s ../state/certificates "$test_home/.eid/authorized_certificates"
printf 'y\n' | run_install -r
[[ -L "$test_home/.eid/authorized_certificates" ]]
grep -Fxq 'custom certificates' "$test_home/.eid/authorized_certificates"

# A failed in-place write restores the original bytes without splitting links.
cp "$test_home/.tmux.conf" "$fixture/original-tmux"
TEST_FAIL_WRITE=1 expect_failure -q
cmp "$fixture/original-tmux" "$test_home/.tmux.conf"
[[ "$test_home/.tmux.conf" -ef "$test_home/state/tmux-linked" ]]
[[ "$(ls -l "$test_home/.tmux.conf")" == '-rw-r-----'* ]]
backups=("$test_home"/.tmux.conf.backup.*)
[[ ! -e "${backups[0]}" ]]

# Caught signals during the in-place write restore the original shared inode.
# The mock signals only its direct parent and exits immediately, so every case
# completes synchronously without background jobs or interactive prompts.
for signal in HUP INT TERM; do
    TEST_FAIL_WRITE="$signal" expect_failure -q
    grep -Fxq "signal $signal" "$fixture/calls"
    cmp "$fixture/original-tmux" "$test_home/.tmux.conf"
    [[ "$test_home/.tmux.conf" -ef "$test_home/state/tmux-linked" ]]
    [[ "$(ls -l "$test_home/.tmux.conf")" == '-rw-r-----'* ]]
    backups=("$test_home"/.tmux.conf.backup.*)
    [[ ! -e "${backups[0]}" ]]
done

# If restoration also fails, retain a complete backup and report its path.
for failure in 2 TERM-restore-failure; do
    TEST_FAIL_WRITE="$failure" expect_failure -q
    backups=("$test_home"/.tmux.conf.backup.*)
    [[ ${#backups[@]} -eq 1 && -f "${backups[0]}" ]]
    cmp "$fixture/original-tmux" "${backups[0]}"
    grep -Fq -- "${backups[0]}" "$fixture/output"
    [[ "$test_home/.tmux.conf" -ef "$test_home/state/tmux-linked" ]]
    cat "${backups[0]}" > "$test_home/.tmux.conf"
    rm "${backups[0]}"
done
grep -Fxq 'signal TERM-restore-failure' "$fixture/calls"
run_install -q
grep -Fxq 'source-file ~/dotfiles/.tmux.conf2' "$test_home/state/tmux-linked"
printf 'y\n' | run_install -r
cmp "$fixture/original-tmux" "$test_home/state/tmux-linked"

echo 'installer regression tests passed'
