#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d /tmp/riot-cli.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/home"

cat > "$fixture/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf 'COMMAND=%s\n' "${0##*/}" >> "$MOCK_COMMAND_LOG"
printf 'ARG=%s\n' "$@" >> "$MOCK_COMMAND_LOG"
EOF
cp "$fixture/bin/ssh" "$fixture/bin/scp"
cp "$fixture/bin/ssh" "$fixture/bin/ssh-keygen"
chmod +x "$fixture/bin/ssh" "$fixture/bin/scp" "$fixture/bin/ssh-keygen"

run_riot() {
    env -i HOME="$fixture/home" PATH="$fixture/bin:$PATH" \
        MOCK_COMMAND_LOG="$fixture/command.log" RIOT_TRUST_CLIENT=0 \
        MOCK_SCP_LOG="$fixture/scp.log" MOCK_SCP_COUNT="$fixture/scp.count" \
        MOCK_SCP_MUTATION="${scp_mutation:-none}" MOCK_SCP_FAIL_CALL="${scp_fail_call:-0}" \
        "$source_dir/scripts/riot" "$@"
}

cd "$fixture"

# Removing a host key must follow the same dry-run contract as SSH commands.
run_riot -D example.test rm > "$fixture/out" 2> "$fixture/err"
grep -Fxq 'ssh-keygen -R [example.test]:12022' "$fixture/out"
test ! -e "$fixture/command.log"
run_riot example.test rm > "$fixture/out" 2> "$fixture/err"
grep -Fxq 'COMMAND=ssh-keygen' "$fixture/command.log"
grep -Fxq 'ARG=[example.test]:12022' "$fixture/command.log"

# The built-in batch appends seventeen remotes to the processing queue.
run_riot -D nasps > "$fixture/out" 2> "$fixture/err"
test "$(wc -l < "$fixture/out")" -eq 17
grep -Fq 'root@g1' "$fixture/out"
grep -Fq 'dictxiong@g15' "$fixture/out"
tail -n 1 "$fixture/out" | grep -Fq 'root@g17'

cat > "$fixture/riot-config.sh" <<'EOF'
first.batch() { remotes+=(inside.example); }
nested.batch() { remotes+=(first); }
empty.batch() { remotes+=("" tail.example); }
loop.batch() { remotes+=(loop); }
left.batch() { remotes+=(right); }
right.batch() { remotes+=(left); }
pair.batch() { remotes+=(one.example two.example); }
EOF

# Appended and nested batches are processed in queue order. Repeated use of
# a batch is valid when it is not part of a recursive expansion.
: > "$fixture/command.log"
run_riot 'first,,outside.example,nested,first,empty' > "$fixture/out" 2> "$fixture/err"
grep '^ARG=root@' "$fixture/command.log" > "$fixture/hosts"
cat > "$fixture/expected" <<'EOF'
ARG=root@outside.example
ARG=root@inside.example
ARG=root@inside.example
ARG=root@tail.example
ARG=root@inside.example
EOF
diff -u "$fixture/expected" "$fixture/hosts"

for batch in loop left; do
    if run_riot -D "$batch" > "$fixture/out" 2> "$fixture/err"; then
        echo "expected recursive batch $batch to fail" >&2
        exit 1
    fi
    grep -Fq 'recursive batch:' "$fixture/err"
done

# Optional internal placeholders must not remove explicit empty command args.
: > "$fixture/command.log"
run_riot example.test ssh printf '%s' '' 'two words' > "$fixture/out" 2> "$fixture/err"
tail -n 4 "$fixture/command.log" > "$fixture/args"
printf 'ARG=printf\nARG=%%s\nARG=\nARG=two words\n' > "$fixture/expected"
diff -u "$fixture/expected" "$fixture/args"

# SCP needs brackets around IPv6 hosts in both directions. SSH retains its
# original destination format and uses the separate port option.
run_riot -D '[2001:db8::1]:2222' scp ./local /remote > "$fixture/out" 2> "$fixture/err"
grep -Fq ' ./local root@[2001:db8::1]:/remote' "$fixture/out"
run_riot -D '[2001:db8::1]:2222' scp /remote ./local > "$fixture/out" 2> "$fixture/err"
grep -Fq ' root@[2001:db8::1]:/remote ./local' "$fixture/out"
run_riot -D '[2001:db8::1]:2222' ssh > "$fixture/out" 2> "$fixture/err"
grep -Fq 'ssh -p 2222 ' "$fixture/out"
grep -Fq ' root@2001:db8::1' "$fixture/out"

# Assert the actual operands, then change the local source between transfers.
# Each target must retain the direction selected before the first transfer.
cat > "$fixture/bin/scp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
operands=()
while (( $# > 0 )); do
    case $1 in
        -P|-o) shift 2 ;;
        -r) shift ;;
        *) operands+=("$1"); shift ;;
    esac
done
[[ ${#operands[@]} -eq 2 ]] || { echo 'expected exactly two SCP operands' >&2; exit 1; }
printf 'SOURCE=%s\nDESTINATION=%s\n' "${operands[@]}" >> "$MOCK_SCP_LOG"
call=0
[[ ! -f $MOCK_SCP_COUNT ]] || read -r call < "$MOCK_SCP_COUNT"
call=$((call + 1))
printf '%s\n' "$call" > "$MOCK_SCP_COUNT"
case $MOCK_SCP_MUTATION in
    create) touch foo ;;
    remove) rm -f foo ;;
esac
[[ $call -ne $MOCK_SCP_FAIL_CALL ]] || exit 42
EOF
chmod +x "$fixture/bin/scp"

reset_scp_log() {
    : > "$fixture/scp.log"
    rm -f "$fixture/scp.count"
}

for remotes in one.example,two.example pair; do
    rm -f foo
    reset_scp_log
    scp_mutation=create run_riot "$remotes" scp foo . > "$fixture/out" 2> "$fixture/err"
    cat > "$fixture/expected" <<'EOF'
SOURCE=root@one.example:foo
DESTINATION=.
SOURCE=root@two.example:foo
DESTINATION=.
EOF
    diff -u "$fixture/expected" "$fixture/scp.log"

    # Removing an initially local file must not turn the next upload into a
    # download, even when both local arguments were initially present.
    touch foo
    reset_scp_log
    scp_mutation=remove run_riot "$remotes" scp foo . > "$fixture/out" 2> "$fixture/err"
    cat > "$fixture/expected" <<'EOF'
SOURCE=foo
DESTINATION=root@one.example:.
SOURCE=foo
DESTINATION=root@two.example:.
EOF
    diff -u "$fixture/expected" "$fixture/scp.log"

    # The ./ prefix continues to force the local side in either position.
    touch foo
    reset_scp_log
    scp_mutation=remove run_riot "$remotes" scp foo ./destination > "$fixture/out" 2> "$fixture/err"
    cat > "$fixture/expected" <<'EOF'
SOURCE=root@one.example:foo
DESTINATION=./destination
SOURCE=root@two.example:foo
DESTINATION=./destination
EOF
    diff -u "$fixture/expected" "$fixture/scp.log"

    rm -f foo
    reset_scp_log
    scp_mutation=create run_riot "$remotes" scp ./foo . > "$fixture/out" 2> "$fixture/err"
    cat > "$fixture/expected" <<'EOF'
SOURCE=./foo
DESTINATION=root@one.example:.
SOURCE=./foo
DESTINATION=root@two.example:.
EOF
    diff -u "$fixture/expected" "$fixture/scp.log"

    reset_scp_log
    scp_status=0
    scp_fail_call=1 run_riot "$remotes" scp ./foo /remote > "$fixture/out" 2> "$fixture/err" || scp_status=$?
    [[ $scp_status -eq 42 && $(cat "$fixture/scp.count") -eq 1 ]]
done

echo 'riot command tests passed'
