#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
test_home="$fixture/home"
remote="$fixture/remote"
client="$test_home/dotfiles"
mock_bin="$fixture/bin"
mkdir -p "$test_home" "$remote/tools" "$mock_bin"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null

cp "$source_dir/.update.sh" "$remote/.update.sh"
cp "$source_dir/.gitignore" "$remote/.gitignore"
cp "$source_dir/tools/common.sh" "$remote/tools/common.sh"
cat > "$remote/tools/frigg-client.sh" <<'EOF'
#!/usr/bin/env bash
[[ "${DFS_ORPHAN:-0}" == 1 ]] && exit 0
printf '%s\n' "$*" >> "$DOTFILES_TEST_SIDE_EFFECTS"
EOF
chmod +x "$remote/tools/frigg-client.sh"
git init -q -b dev "$remote"
git -C "$remote" config user.name 'Dotfiles Test'
git -C "$remote" config user.email fixture@example.invalid
git -C "$remote" config commit.gpgsign false
git -C "$remote" add .
git -C "$remote" commit -qm 'Installed revision'
git clone -q "$remote" "$client"
cp "$client/.update.sh" "$client/update.sh"
chmod +x "$client/update.sh"
initial_commit=$(git -C "$client" rev-parse HEAD)

cat > "$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$DOTFILES_TEST_RELEASE"
EOF
cat > "$mock_bin/cp" <<'EOF'
#!/usr/bin/env bash
exit 74
EOF
chmod +x "$mock_bin/curl" "$mock_bin/cp"

update() {
    env -i HOME="$test_home" PATH="$PATH" \
        GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
        DFS_IGNORE_COMMIT_SIGN=1 DFS_UPDATE_CHANNEL=dev DFS_DDNS_ENABLE=0 DFS_ORPHAN=1 \
        DOTFILES_TEST_SIDE_EFFECTS="$fixture/side-effects" \
        "$@" bash "$client/update.sh"
}

expect_failure() {
    local expected=$1
    shift
    if update "$@" > "$fixture/update.log" 2>&1; then
        printf 'Expected update failure: %s\n' "$expected" >&2
        exit 1
    fi
    grep -Fq -- "$expected" "$fixture/update.log"
}

# Refused updates must return an error and preserve the installed checkout.
printf 'user work\n' > "$client/untracked-file"
expect_failure 'directory not clean'
grep -Fxq 'user work' "$client/untracked-file"
rm "$client/untracked-file"
expect_failure 'invalid commit id' PATH="$mock_bin:$PATH" \
    DFS_UPDATE_CHANNEL=main DOTFILES_TEST_RELEASE=invalid
test "$(git -C "$client" rev-parse HEAD)" = "$initial_commit"

# Dry-run must skip fetch, DNS updates, beacons, and updater repairs.
git -C "$client" remote set-url origin "$fixture/missing-remote"
ln "$client/update.sh" "$fixture/running-updater"
printf '\n# stale updater\n' >> "$client/update.sh"
update DFS_DRY_RUN=1 DFS_DDNS_ENABLE=1 DFS_ORPHAN=0 > "$fixture/update.log" 2>&1
grep -Fq 'dry-run:' "$fixture/update.log"
test ! -e "$fixture/side-effects"
test "$fixture/running-updater" -ef "$client/update.sh"
grep -Fxq '# stale updater' "$client/update.sh"
expect_failure 'does not appear to be a git repository'
test "$(git -C "$client" rev-parse HEAD)" = "$initial_commit"
git -C "$client" remote set-url origin "$remote"

# A retry repairs a stale updater even when the checkout already matches.
update > "$fixture/update.log" 2>&1
grep -Fq 'refreshing update.sh' "$fixture/update.log"
cmp "$client/update.sh" "$client/.update.sh"
test ! "$fixture/running-updater" -ef "$client/update.sh"
grep -Fxq '# stale updater' "$fixture/running-updater"
chmod -x "$client/update.sh"
update > "$fixture/update.log" 2>&1
test -x "$client/update.sh"

# SIGKILL can leave a temporary file behind. It must not block the next update.
printf 'interrupted refresh\n' > "$client/.update.sh.interrupted"
printf '\n# Updated updater fixture.\n' >> "$remote/.update.sh"
git -C "$remote" commit -qam 'New revision'
candidate=$(git -C "$remote" rev-parse HEAD)

# A failed refresh returns its error. Retrying finishes the interrupted update.
status=0
update PATH="$mock_bin:$PATH" > "$fixture/update.log" 2>&1 || status=$?
test "$status" -eq 74
grep -Fq 'refreshing update.sh' "$fixture/update.log"
test "$(git -C "$client" rev-parse HEAD)" = "$candidate"
if cmp -s "$client/update.sh" "$client/.update.sh"; then
    printf '%s\n' 'Expected the failed refresh to leave the old updater' >&2
    exit 1
fi
update > "$fixture/update.log" 2>&1
cmp "$client/update.sh" "$client/.update.sh"
test -x "$client/update.sh"

# An atomic replacement failure is also recoverable and cleans its temporary copy.
mkdir "$fixture/failing-mv"
printf '#!/usr/bin/env bash\nexit 73\n' > "$fixture/failing-mv/mv"
chmod +x "$fixture/failing-mv/mv"
printf '\n# Revision for replacement failure.\n' >> "$remote/.update.sh"
git -C "$remote" commit -qam 'Replacement failure revision'
status=0
update PATH="$fixture/failing-mv:$PATH" > "$fixture/update.log" 2>&1 || status=$?
test "$status" -eq 73
temporary_files=("$client"/.update.sh.*)
test "${#temporary_files[@]}" -eq 1
test "${temporary_files[0]}" = "$client/.update.sh.interrupted"
update > "$fixture/update.log" 2>&1
cmp "$client/update.sh" "$client/.update.sh"

# Successful updates preserve the installer's special restart status.
printf '\n# Next revision.\n' >> "$remote/.update.sh"
git -C "$remote" commit -qam 'Next revision'
status=0
update DFS_UPDATED_RET=85 > "$fixture/update.log" 2>&1 || status=$?
test "$status" -eq 85
test "$(git -C "$client" rev-parse HEAD)" = "$(git -C "$remote" rev-parse HEAD)"
cmp "$client/update.sh" "$client/.update.sh"

echo 'updater recovery tests passed'
