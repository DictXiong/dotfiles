#!/usr/bin/env bash
# This file was generated entirely by AI.
# It has not been reviewed line by line by a human.
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
export GNUPGHOME="$fixture/gnupg"
cleanup() {
    gpgconf --kill all || :
    rm -rf -- "$fixture"
}
trap cleanup EXIT
mkdir -m 700 "$GNUPGHOME"
unset DFS_IGNORE_COMMIT_SIGN DFS_UPDATE_GPG_KEY_FILE DFS_UPDATE_CHANNEL

old_signer=old@example.invalid
new_signer=new@example.invalid
for signer in "$old_signer" "$new_signer"; do
    gpg --batch --passphrase '' --quick-generate-key "$signer" ed25519 sign 0
done

remote="$fixture/remote"
client="$fixture/client"
git init -q -b dev "$remote"
git -C "$remote" config user.name 'Dotfiles Test'
git -C "$remote" config user.email fixture@example.invalid
git -C "$remote" config gpg.format openpgp
git -C "$remote" config gpg.openpgp.program "$(command -v gpg)"
mkdir "$remote/tools" "$remote/pki"
cp "$source_dir/.update.sh" "$remote/.update.sh"
gpg --batch --export --armor "$old_signer" > "$remote/pki/update-signing-key.asc"
cat > "$remote/tools/common.sh" <<'EOF'
# This file was generated entirely by AI.
# It has not been reviewed line by line by a human.
set -e
DOTFILES=$THIS_DIR
if [[ -n "$DOTFILES_TEST_CONFIG_IGNORE_COMMIT_SIGN" ]]; then
    DFS_IGNORE_COMMIT_SIGN=$DOTFILES_TEST_CONFIG_IGNORE_COMMIT_SIGN
fi
fmt_info() { printf '%s\n' "$*"; }
fmt_fatal() { printf '%s\n' "$*" >&2; exit 1; }
fmt_warning() { printf '%s\n' "$*" >&2; }
apost_beacon() { :; }
curl() { printf '%s\n' "$DOTFILES_TEST_RELEASE"; }
EOF
printf 'update.sh\n' > "$remote/.gitignore"
git -C "$remote" add .
GIT_COMMITTER_DATE='2025-01-01T00:00:10Z' git -C "$remote" commit -q -S"$old_signer" -m 'Installed dotfiles'
initial_commit=$(git -C "$remote" rev-parse HEAD)
git clone -q "$remote" "$client"
cp "$client/.update.sh" "$client/update.sh"

update() {
    DFS_UPDATE_CHANNEL="${DFS_UPDATE_CHANNEL:-dev}" DFS_DDNS_ENABLE=0 DFS_DEV=0 DFS_UPDATED_RET="${DFS_UPDATED_RET:-0}" bash "$client/update.sh"
}

reject_update() {
    local previous_commit
    previous_commit=$(git -C "$client" rev-parse HEAD)
    if update > "$fixture/update.log" 2>&1; then
        printf 'Expected update to be rejected: %s\n' "$1" >&2
        exit 1
    fi
    grep -F "$1" "$fixture/update.log"
    test "$(git -C "$client" rev-parse HEAD)" = "$previous_commit"
}

ln "$client/update.sh" "$fixture/running-updater"
printf '\n# Updated updater fixture.\n' >> "$remote/.update.sh"
GIT_COMMITTER_DATE='2025-01-01T00:00:20Z' git -C "$remote" commit -qam 'Developer commit' -S"$old_signer"
developer_commit=$(git -C "$remote" rev-parse HEAD)
if DFS_UPDATED_RET=85 DFS_UPDATE_CHANNEL=main DOTFILES_TEST_RELEASE="$developer_commit" update > "$fixture/update.log" 2>&1; then
    printf '%s\n' 'Expected updater to exit with status 85' >&2
    exit 1
else
    test "$?" -eq 85
fi
grep -F 'verified OpenPGP signature for commit' "$fixture/update.log"
test "$(git -C "$client" rev-parse HEAD)" = "$developer_commit"
cmp "$client/update.sh" "$client/.update.sh"
test ! "$fixture/running-updater" -ef "$client/update.sh"
cmp "$fixture/running-updater" "$source_dir/.update.sh"

# Simulate a squash merge that does not contain the already-installed dev commit.
git -C "$remote" switch -q -c main "$initial_commit"
GIT_COMMITTER_DATE='2025-01-01T00:00:15Z' git -C "$remote" commit -q --allow-empty -S"$new_signer" -m 'Merge signed by the hosting service'
release=$(git -C "$remote" rev-parse HEAD)
tag="dfs-release/$release"
export DFS_UPDATE_CHANNEL=main DOTFILES_TEST_RELEASE="$release"
reject_update 'has no trusted signature or signed release tag'
git -C "$remote" tag -u "$old_signer" "$tag" "$developer_commit" -m 'Wrong target'
reject_update 'has an unexpected name or target'
git -C "$remote" tag -d "$tag" >/dev/null
git -C "$client" tag -d "$tag" >/dev/null
git -C "$remote" tag -u "$new_signer" "$tag" "$release" -m 'Untrusted publisher'
reject_update 'was not signed by a trusted dotfiles signer'
git -C "$remote" tag -d "$tag" >/dev/null
git -C "$client" tag -d "$tag" >/dev/null
GIT_COMMITTER_DATE='2025-01-01T00:00:30Z' git -C "$remote" tag -u "$old_signer" "$tag" "$release" -m 'Publish dotfiles'
update > "$fixture/update.log" 2>&1
grep -F "verified OpenPGP signature for release tag $tag" "$fixture/update.log"
test "$(git -C "$client" rev-parse HEAD)" = "$release"
update > "$fixture/update.log" 2>&1
grep -F 'nothing to do' "$fixture/update.log"

unset DFS_UPDATE_CHANNEL DOTFILES_TEST_RELEASE
git -C "$remote" switch -q -C dev "$release"
GIT_COMMITTER_DATE='2025-01-01T00:00:30Z' git -C "$remote" commit -q --allow-empty -S"$old_signer" -m 'Different commit at the same time'
same_time_commit=$(git -C "$remote" rev-parse HEAD)
GIT_COMMITTER_DATE='2025-01-01T00:00:45Z' git -C "$remote" tag -u "$old_signer" "dfs-release/$same_time_commit" "$same_time_commit" -m 'Later tag'
reject_update 'timestamp 1735689630 must be newer than installed timestamp 1735689630'
git -C "$remote" reset -q --hard "$release"

gpg --batch --export --armor "$new_signer" > "$remote/pki/update-signing-key.asc"
GIT_COMMITTER_DATE='2025-01-01T00:00:40Z' git -C "$remote" commit -qam 'Unauthorized signer replacement' -S"$new_signer"
reject_update 'has no trusted signature or signed release tag'
GIT_COMMITTER_DATE='2025-01-01T00:00:40Z' git -C "$remote" commit -q --amend --no-edit -S"$old_signer"
update
GIT_COMMITTER_DATE='2025-01-01T00:00:35Z' git -C "$remote" commit -q --allow-empty -S"$new_signer" -m 'Signed after key rotation'
update > "$fixture/update.log" 2>&1
grep -F 'has no verifiable timestamp; accepting the signed candidate' "$fixture/update.log"

git -C "$remote" reset -q --hard "$release"
reject_update 'timestamp 1735689615 must be newer than installed timestamp 1735689635'

git -C "$remote" commit -q --allow-empty --no-gpg-sign -m 'Unsigned commit'
reject_update 'has no trusted signature or signed release tag'
without_gpg="$fixture/bin-without-gpg"
mkdir "$without_gpg"
for tool in bash dirname basename git grep mktemp cp chmod mv rm; do
    ln -s "$(command -v "$tool")" "$without_gpg/$tool"
done
PATH="$without_gpg" reject_update 'gpg not found. Set DFS_IGNORE_COMMIT_SIGN=1'
api_commit=$(git -C "$remote" rev-parse HEAD)
PATH="$without_gpg" DOTFILES_TEST_CONFIG_IGNORE_COMMIT_SIGN=0 DFS_IGNORE_COMMIT_SIGN=1 DFS_UPDATE_CHANNEL=main DOTFILES_TEST_RELEASE="$api_commit" update > "$fixture/update.log" 2>&1
grep -F 'DFS_IGNORE_COMMIT_SIGN=1' "$fixture/update.log"
test "$(git -C "$client" rev-parse HEAD)" = "$api_commit"
PATH="$without_gpg" reject_update 'gpg not found. Set DFS_IGNORE_COMMIT_SIGN=1'
PATH="$without_gpg" DFS_IGNORE_COMMIT_SIGN=1 update > "$fixture/update.log"
grep -F 'DFS_IGNORE_COMMIT_SIGN=1' "$fixture/update.log"
test "$(git -C "$client" rev-parse HEAD)" = "$(git -C "$remote" rev-parse HEAD)"
