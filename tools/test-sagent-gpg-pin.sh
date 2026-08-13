#!/usr/bin/env bash
set -euo pipefail

THIS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SAGENT="$THIS_DIR/sagent.sh"
TEST_DIR=$(mktemp -d /tmp/sagent-gpg-pin.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

MOCK_BIN="$TEST_DIR/bin"
MOCK_HOME="$TEST_DIR/home"
MOCK_TMP="$TEST_DIR/tmp"
MOCK_GPG_ARGS="$TEST_DIR/gpg-args"
MOCK_GPG_INPUT="$TEST_DIR/gpg-input"
MOCK_AGENT_LOG="$TEST_DIR/agent-log"
mkdir -p "$MOCK_BIN" "$MOCK_HOME/gnupg" "$MOCK_HOME/sysconf" "$MOCK_TMP"
export MOCK_BIN MOCK_HOME MOCK_GPG_ARGS MOCK_GPG_INPUT MOCK_AGENT_LOG

cat > "$MOCK_BIN/gpgconf" <<'EOF'
#!/usr/bin/env bash
printf 'gpgconf %s\n' "$*" >> "$MOCK_AGENT_LOG"
case "$*" in
    '--list-dirs homedir') printf '%s\n' "$MOCK_HOME/gnupg" ;;
    '--list-dirs sysconfdir') printf '%s\n' "$MOCK_HOME/sysconf" ;;
    '--list-dirs bindir') printf '%s\n' "$MOCK_BIN" ;;
    '--launch gpg-agent') ;;
    *) exit 1 ;;
esac
EOF

cat > "$MOCK_BIN/gpg-connect-agent" <<'EOF'
#!/usr/bin/env bash
printf 'gpg-connect-agent %s\n' "$*" >> "$MOCK_AGENT_LOG"
EOF

cat > "$MOCK_BIN/tty" <<'EOF'
#!/usr/bin/env bash
printf '/dev/pts/mock\n'
EOF

cat > "$MOCK_BIN/gpg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MOCK_GPG_ARGS"
output=''
while [[ $# -gt 0 ]]; do
    if [[ "$1" == '--output' ]]; then
        output=$2
        shift 2
    else
        shift
    fi
done
cat > "$MOCK_GPG_INPUT"
printf 'mock signature\n' > "$output"
EOF

printf '#!/usr/bin/env bash\n' > "$MOCK_BIN/pinentry"
chmod +x "$MOCK_BIN/gpgconf" "$MOCK_BIN/gpg-connect-agent" "$MOCK_BIN/tty" \
    "$MOCK_BIN/gpg" "$MOCK_BIN/pinentry"

output=$(HOME="$MOCK_HOME" TMPDIR="$MOCK_TMP" PATH="$MOCK_BIN:$PATH" "$SAGENT" gpg-pin TEST-KEY 2> "$TEST_DIR/stderr")
[[ -z "$output" ]]
grep -Fxq -- '--detach-sign' "$MOCK_GPG_ARGS"
grep -Fxq -- '--local-user' "$MOCK_GPG_ARGS"
grep -Fxq -- 'TEST-KEY' "$MOCK_GPG_ARGS"
grep -Fxq -- 'sagt gpg-pin' "$MOCK_GPG_INPUT"
grep -Fq -- 'gpgconf --launch gpg-agent' "$MOCK_AGENT_LOG"
grep -Fq -- 'gpg-connect-agent updatestartuptty /bye' "$MOCK_AGENT_LOG"
grep -Fq -- 'test signature completed' "$TEST_DIR/stderr"

output=$(HOME="$MOCK_HOME" TMPDIR="$MOCK_TMP" PATH="$MOCK_BIN:$PATH" "$SAGENT" gpg-pin 2> "$TEST_DIR/stderr")
[[ -z "$output" ]]
! grep -Fxq -- '--local-user' "$MOCK_GPG_ARGS"
[[ -z $(find "$MOCK_TMP" -mindepth 1 -print -quit) ]]

echo "sagent gpg-pin tests passed"
