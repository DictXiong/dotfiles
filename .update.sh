#!/usr/bin/env bash

THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
THIS_FILE=$(basename "${BASH_SOURCE}")
# Preserve an explicit per-call override when loading the user configuration.
requested_ignore_commit_sign=${DFS_IGNORE_COMMIT_SIGN-}
source "$THIS_DIR/tools/common.sh"
DFS_IGNORE_COMMIT_SIGN=${requested_ignore_commit_sign:-${DFS_IGNORE_COMMIT_SIGN:-0}}

DFS_UPDATED_RET=${DFS_UPDATED_RET:-0}
DFS_UPDATE_CHANNEL=${DFS_UPDATE_CHANNEL:-"main"}

signed_commit_timestamp()
{
    local commit=$1
    shift
    local timestamp signed_object
    if "$@" verify-commit "$commit" >/dev/null 2>&1; then
        timestamp=$(git show -s --no-notes --no-show-signature --format=%ct "$commit") || return 1
        signed_object="commit $commit"
    else
        local tag="dfs-release/$commit"
        local tag_id tag_header verification
        tag_id=$(git rev-parse --verify "refs/tags/$tag^{tag}" 2>/dev/null) ||
            fmt_fatal "commit $commit has no trusted signature or signed release tag $tag"
        tag_header=$(git cat-file tag "$tag_id" | sed -n '1,4p') || return 1
        if [[ "$tag_header" != "$(printf 'object %s\ntype commit\ntag %s\ntagger ' "$commit" "$tag")"* ]]; then
            fmt_fatal "release tag $tag has an unexpected name or target"
        fi
        if ! verification=$("$@" verify-tag "$tag_id" 2>&1); then
            printf '%s\n' "$verification" >&2
            fmt_fatal "release tag $tag was not signed by a trusted dotfiles signer"
        fi
        timestamp=$(printf '%s\n' "$tag_header" | sed -n '4s/^tagger .* \([0-9][0-9]*\) [+-][0-9]\{4\}$/\1/p')
        signed_object="release tag $tag"
    fi
    if [[ ! "$timestamp" =~ ^(0|[1-9][0-9]{0,17})$ ]]; then
        fmt_fatal "$signed_object has an invalid timestamp"
    fi
    fmt_info "verified OpenPGP signature for $signed_object (timestamp $timestamp)" >&2
    printf '%s\n' "$timestamp"
}

verify_update()
(
    local gpg_program
    gpg_program=$(command -v gpg) ||
        fmt_fatal "gpg not found. Set DFS_IGNORE_COMMIT_SIGN=1 in ~/.config/dotfiles/env to skip signature checks."

    GNUPGHOME=$(mktemp -d) || exit 1
    export GNUPGHOME
    trap 'rm -rf -- "$GNUPGHOME"' EXIT
    printf 'no-auto-key-retrieve\nno-auto-key-import\n' > "$GNUPGHOME/gpg.conf"
    local key_file
    if [[ "${DFS_UPDATE_GPG_KEY_FILE+x}" == x ]]; then
        key_file=$DFS_UPDATE_GPG_KEY_FILE
        if [[ "$key_file" != /* || ! -f "$key_file" ]]; then
            fmt_fatal "DFS_UPDATE_GPG_KEY_FILE must point to a local OpenPGP public key file"
        fi
    else
        key_file="$GNUPGHOME/update-signing-key.asc"
        # Read the trust anchor from HEAD, before checking out the candidate.
        git show HEAD:pki/update-signing-key.asc > "$key_file" ||
            fmt_fatal "the installed commit has no dotfiles signing key"
    fi

    local verification
    if ! verification=$("$gpg_program" --batch --no-options --no-autostart --quiet --import "$key_file" 2>&1); then
        printf '%s\n' "$verification" >&2
        fmt_fatal "could not load the configured dotfiles signing key"
    fi

    # This keyring defines trust for OpenPGP only.
    local -a verify_git=(git -c "gpg.openpgp.program=$gpg_program" -c gpg.minTrustLevel=undefined
        -c gpg.ssh.program=false -c gpg.x509.program=false)
    local candidate_time installed_time
    candidate_time=$(signed_commit_timestamp "$1" "${verify_git[@]}") || exit 1
    if [[ "$1" == "$2" ]]; then
        return 0
    fi

    if installed_time=$(signed_commit_timestamp "$2" "${verify_git[@]}" 2>/dev/null); then
        if (( candidate_time <= installed_time )); then
            fmt_fatal "signed update timestamp $candidate_time must be newer than installed timestamp $installed_time"
        fi
    else
        fmt_info "installed commit $2 has no verifiable timestamp; accepting the signed candidate"
    fi
)

# send beacon online
apost_beacon "sys.online"

# update dns
if [[ "$DFS_DDNS_ENABLE" == "1" ]]; then
    fmt_info "updating dns ..."
    if ! is_tty; then
        time_to_sleep=$((RANDOM%600))
        fmt_note "sleep for $time_to_sleep seconds"
        sleep $time_to_sleep
    fi
    "$THIS_DIR/tools/frigg-client.sh" ddns || (fmt_error "failed to update dns" && apost_beacon "dfs.ddns.fail")
fi

# fetch origin
cd "$DOTFILES"
git fetch --all --prune --tags
if [[ -n "$(git status -s)" ]]; then
    fmt_error "directory not clean"
    apost_beacon "dfs.dirty"
    exit
fi

# get the specified commit id
case $DFS_UPDATE_CHANNEL in
    "main" ) DFS_COMMIT=$(curl $DFS_CURL_OPTIONS -fsSL https://api.beardic.cn/get-var/dfs-commit-id) ;;
    "dev" ) DFS_COMMIT=$(git rev-parse origin/dev 2> /dev/null) || DFS_COMMIT=$(git rev-parse origin/main) ;;
    "latest" ) DFS_COMMIT=$(git for-each-ref --sort=-committerdate refs/heads refs/remotes --format='%(objectname)' | head -n 1) ;;
    * ) fmt_fatal "invalid update channel: $DFS_UPDATE_CHANNEL" ;;
esac
if [[ ! "$DFS_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    fmt_error "invalid commit id"
    apost_beacon "dfs.invalid-commit" "invalid commit id: ${DFS_COMMIT}"
    exit
fi

installed_commit=$(git rev-parse HEAD)
if [[ "$DFS_IGNORE_COMMIT_SIGN" == 1 ]]; then
    fmt_info "skipped signature verification for commit $DFS_COMMIT (DFS_IGNORE_COMMIT_SIGN=1)"
else
    verify_update "$DFS_COMMIT" "$installed_commit"
fi

# update
if [[ "$installed_commit" == "$DFS_COMMIT" ]]; then
    fmt_info "nothing to do"
else
    fmt_info "checking out to commit $DFS_COMMIT ..."
    if [[ -z "$DFS_DEV" || "$DFS_DEV" == "0" ]]; then
        git -c advice.detachedHead=false checkout $DFS_COMMIT
        # Bash may still be reading the running updater. Keep its inode intact.
        updater_tmp=$(mktemp ./.update.sh.XXXXXXXX)
        trap 'rm -f -- "$updater_tmp"' EXIT
        cp -p ./.update.sh "$updater_tmp"
        chmod +x "$updater_tmp"
        mv -f -- "$updater_tmp" ./update.sh
        apost_beacon "dfs.updated"
        exit "$DFS_UPDATED_RET"
    else
        fmt_warning "won't really checkout in dev mode"
    fi
fi
