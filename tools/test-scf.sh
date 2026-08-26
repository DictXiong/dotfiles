#!/usr/bin/env bash
set -euo pipefail

THIS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCF="$THIS_DIR/../scripts/scf"
TEST_DIR=$(mktemp -d /tmp/scf.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

MOCK_BIN="$TEST_DIR/bin"
DATA_DIR="$TEST_DIR/data"
MOCK_SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
MOCK_MAIN="$DATA_DIR/main.yaml"
MOCK_CHILD="$DATA_DIR/child.conf"
MOCK_NOTE="$DATA_DIR/notes.txt"
mkdir -p "$MOCK_BIN" "$DATA_DIR"
export MOCK_SYSTEMCTL_LOG MOCK_MAIN MOCK_CHILD MOCK_NOTE

printf 'include %s\n' "$MOCK_CHILD" > "$MOCK_MAIN"
printf 'child configuration\n' > "$MOCK_CHILD"
printf 'not a configuration candidate\n' > "$MOCK_NOTE"

cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$MOCK_SYSTEMCTL_LOG"
service=${@: -1}
case "$service" in
    demo.service)
        printf 'path=/usr/bin/demo ; argv[0]=demo ; argv[1]=%s ; argv[2]=%s ;\n' \
            "$MOCK_MAIN" "$MOCK_NOTE"
        ;;
    empty.service)
        printf 'path=/usr/bin/empty ; argv[0]=empty ;\n'
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "$MOCK_BIN/systemctl"

run_scf() {
    PATH="$MOCK_BIN:$PATH" "$SCF" "$@"
}

# A service name without .service is accepted, and non-interactive mode prints
# the only configuration candidate instead of opening an editor.
output=$(run_scf demo 2> "$TEST_DIR/stderr")
grep -Fxq 'include '"$MOCK_CHILD" <<< "$output"
grep -Fq -- '--property=ExecStart --value demo.service' "$MOCK_SYSTEMCTL_LOG"

# Recursive mode discovers configuration files referenced by the first one.
output=$(run_scf -r -n 2 demo)
grep -Fxq 'child configuration' <<< "$output"

# Decimal values with a leading zero must not be treated as invalid octal.
output=$(SCF_MAX_DEPTH=08 SCF_MAX_CANDIDATES=08 run_scf demo)
grep -Fxq 'include '"$MOCK_CHILD" <<< "$output"
if run_scf -n 08 demo > "$TEST_DIR/out" 2> "$TEST_DIR/stderr"; then
    echo 'expected scf -n 08 to fail because only one candidate exists' >&2
    exit 1
fi
grep -Fq 'candidate number 8 is out of range' "$TEST_DIR/stderr"

# Invalid service names are rejected before systemctl is invoked.
before=$(wc -l < "$MOCK_SYSTEMCTL_LOG")
if run_scf 'demo; touch /tmp/unexpected' > "$TEST_DIR/out" 2> "$TEST_DIR/stderr"; then
    echo 'expected an invalid service name to fail' >&2
    exit 1
fi
grep -Fq 'invalid service name' "$TEST_DIR/stderr"
after=$(wc -l < "$MOCK_SYSTEMCTL_LOG")
test "$before" -eq "$after"

# A service without a referenced file reports a useful failure.
if run_scf empty > "$TEST_DIR/out" 2> "$TEST_DIR/stderr"; then
    echo 'expected a service without a config path to fail' >&2
    exit 1
fi
grep -Fq 'no existing configuration path found' "$TEST_DIR/stderr"

echo 'scf tests passed'
