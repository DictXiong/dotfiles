#!/usr/bin/env bash
set -euo pipefail

THIS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIOT="$THIS_DIR/../scripts/riot"
TEST_DIR=$(mktemp -d /tmp/riot-gpg.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

MOCK_BIN="$TEST_DIR/bin"
MOCK_HOME="$TEST_DIR/home"
MOCK_LOCAL_SOCKET="$TEST_DIR/local/S.gpg-agent.extra"
MOCK_REMOTE_SOCKET="$TEST_DIR/remote/S.gpg-agent"
MOCK_GPG_LOG="$TEST_DIR/gpg.log"
MOCK_SSH_LOG="$TEST_DIR/ssh.log"
mkdir -p "$MOCK_BIN" "$MOCK_HOME" "${MOCK_LOCAL_SOCKET%/*}" "${MOCK_REMOTE_SOCKET%/*}"
export MOCK_LOCAL_SOCKET MOCK_REMOTE_SOCKET MOCK_GPG_LOG MOCK_SSH_LOG

make_stale_socket() {
    rm -f "$1"
    python3 - "$1" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_UNIX)
sock.bind(sys.argv[1])
sock.close()
PY
}

cat > "$MOCK_BIN/gpgconf" <<'EOF'
#!/usr/bin/env bash
printf 'gpgconf %s\n' "$*" >> "$MOCK_GPG_LOG"
case "$*" in
    '--list-dirs agent-extra-socket') printf '%s\n' "$MOCK_LOCAL_SOCKET" ;;
    '--list-dirs agent-socket') printf '%s\n' "$MOCK_REMOTE_SOCKET" ;;
    '--kill gpg-agent') exit "${MOCK_KILL_STATUS:-0}" ;;
    *) exit 1 ;;
esac
EOF

cat > "$MOCK_BIN/gpg-connect-agent" <<'EOF'
#!/usr/bin/env bash
printf 'gpg-connect-agent %s\n' "$*" >> "$MOCK_GPG_LOG"
case "$*" in
    *'GETINFO pid'*) printf 'D 123\nOK\n' ;;
    *'GETINFO version'*)
        [[ "${MOCK_LOCAL_LIVE:-1}" == 1 ]] || exit 1
        printf 'D 2.4.0\nOK\n'
        ;;
    *'GETINFO restricted'*) printf 'D %s\nOK\n' "${MOCK_REMOTE_RESTRICTED:-0}" ;;
    *) exit 1 ;;
esac
EOF

cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ "${MOCK_SYSTEMD_ACTIVE:-0}" == 1 ]]
EOF

cat > "$MOCK_BIN/ssh" <<'EOF'
#!/usr/bin/env bash
{
    printf 'CALL\n'
    printf 'ARG=%s\n' "$@"
} >> "$MOCK_SSH_LOG"

is_probe=0
last_arg=''
for arg in "$@"; do
    [[ "$arg" == '-T' ]] && is_probe=1
    last_arg=$arg
done
if [[ "$is_probe" == 1 ]]; then
    sh -c "$last_arg"
fi
EOF

chmod +x "$MOCK_BIN/gpgconf" "$MOCK_BIN/gpg-connect-agent" "$MOCK_BIN/systemctl" "$MOCK_BIN/ssh"

run_riot() {
    HOME="$MOCK_HOME" RIOT_TRUST_CLIENT=0 PATH="$MOCK_BIN:$PATH" "$RIOT" "$@"
}

expect_failure() {
    local expected=$1
    shift
    if run_riot "$@" > "$TEST_DIR/out" 2> "$TEST_DIR/err"; then
        echo "expected riot to fail: $*" >&2
        exit 1
    fi
    grep -Fq "$expected" "$TEST_DIR/err"
}

# Dry-run must not inspect or mutate either host.
: > "$MOCK_GPG_LOG"
: > "$MOCK_SSH_LOG"
DFS_DRY_RUN=1 run_riot -g example.test > "$TEST_DIR/out" 2> "$TEST_DIR/err"
grep -Fq '<remote-gpg-agent-socket>:<local-gpg-agent-extra-socket>' "$TEST_DIR/out"
[[ ! -s "$MOCK_GPG_LOG" && ! -s "$MOCK_SSH_LOG" ]]

# A socket inode without a listener must be rejected locally.
make_stale_socket "$MOCK_LOCAL_SOCKET"
MOCK_LOCAL_LIVE=0 expect_failure 'extra socket exists but is not accepting connections' -g example.test

# -g is valid only for an interactive SSH login.
expect_failure 'only supported for interactive SSH login' -g example.test scp ./a ./b
expect_failure 'only supported for interactive SSH login' -g example.test ssh -- true

# Never remove a regular file merely because it has the expected basename.
MOCK_LOCAL_LIVE=1
printf 'keep me\n' > "$MOCK_REMOTE_SOCKET"
expect_failure 'refusing to remove the non-socket remote gpg-agent path' -g example.test
grep -Fqx 'keep me' "$MOCK_REMOTE_SOCKET"

# A restricted agent at the remote socket represents another forwarding session.
make_stale_socket "$MOCK_REMOTE_SOCKET"
MOCK_REMOTE_RESTRICTED=1 expect_failure 'another forwarded gpg-agent is already using the remote socket' -g example.test

# A normal remote agent can be cleaned up; systemd activation is reported.
make_stale_socket "$MOCK_REMOTE_SOCKET"
: > "$MOCK_SSH_LOG"
MOCK_REMOTE_RESTRICTED=0 MOCK_SYSTEMD_ACTIVE=1 run_riot -g example.test > "$TEST_DIR/out" 2> "$TEST_DIR/err"
grep -Fq 'remote gpg-agent.socket is active' "$TEST_DIR/err"
grep -Fq 'ARG=none' "$MOCK_SSH_LOG"
grep -Fq 'ARG=ClearAllForwardings=yes' "$MOCK_SSH_LOG"
grep -Fq 'ARG=-T' "$MOCK_SSH_LOG"
! grep -Fq 'ARG=RequestTTY=' "$MOCK_SSH_LOG"
grep -Fq 'ARG=StreamLocalBindUnlink=no' "$MOCK_SSH_LOG"
grep -Fq "ARG=$MOCK_REMOTE_SOCKET:$MOCK_LOCAL_SOCKET" "$MOCK_SSH_LOG"
[[ ! -e "$MOCK_REMOTE_SOCKET" ]]

echo 'riot gpg forwarding tests passed'
