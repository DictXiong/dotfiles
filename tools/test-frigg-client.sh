#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/frigg-client.XXXXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
mock_bin="$fixture/bin"
test_home="$fixture/home"
mkdir -p "$mock_bin" "$test_home/.config/dotfiles"
printf 'fixture-uuid\n' > "$test_home/.config/dotfiles/uuid"

# Restrict PATH to the mock curl and the commands needed by the client.
for tool in bash dirname tr grep cat; do
    ln -s "$(command -v "$tool")" "$mock_bin/$tool"
done
cat > "$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$MOCK_RESPONSE"
exit "$MOCK_CURL_STATUS"
EOF
chmod +x "$mock_bin/curl"

run_client() {
    env -i HOME="$test_home" PATH="$mock_bin" DFS_HOSTNAME=fixture.invalid \
        DFS_DDNS_IP4=auto MOCK_RESPONSE="$response" MOCK_CURL_STATUS="$curl_status" \
        "$mock_bin/bash" "$source_dir/frigg-client.sh" "$@"
}

expect_failure() {
    local expected_status=$1
    shift
    local status=0
    run_client "$@" > "$fixture/stdout" 2> "$fixture/stderr" || status=$?
    if [[ $status -ne $expected_status ]]; then
        printf 'Expected exit %s, got %s for %s\n' "$expected_status" "$status" "$*" >&2
        exit 1
    fi
}

for operation in beacon ddns; do
    response=200
    curl_status=0
    run_client "$operation" fixture.beacon > "$fixture/stdout" 2> "$fixture/stderr"
    grep -Fxq '200' "$fixture/stdout"

    # A rejected request must reach the caller as a failure.
    response=403
    expect_failure 1 "$operation" fixture.beacon
    [[ ! -s "$fixture/stdout" ]]
    grep -Fq 'authentification failed' "$fixture/stderr"

    response=500
    expect_failure 1 "$operation" fixture.beacon
    grep -Fq 'server returned an error' "$fixture/stderr"

    # Transport failures retain curl's exit status, even with a success body.
    response=200
    curl_status=22
    expect_failure 22 "$operation" fixture.beacon
done

echo 'frigg client tests passed'
