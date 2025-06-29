#!/usr/bin/env bash

THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
THIS_FILE=$(basename "${BASH_SOURCE}")
source "$THIS_DIR/tools/common.sh"

DFS_UPDATED_RET=${DFS_UPDATED_RET:-0}
DFS_UPDATE_CHANNEL=${DFS_UPDATE_CHANNEL:-"main"}

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
cd $DOTFILES
git fetch --all --prune
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
if [[ ${#DFS_COMMIT} != 40 ]]; then
    fmt_error "invalid commit id"
    apost_beacon "dfs.invalid-commit" "invalid commit id: ${DFS_COMMIT}"
    exit
fi

# update
if [[ "$(git rev-parse HEAD)" == "$DFS_COMMIT" ]]; then
    fmt_info "nothing to do"
else
    fmt_info "checking out to commit $DFS_COMMIT ..."
    if [[ -z "$DFS_DEV" || "$DFS_DEV" == "0" ]]; then
        post_beacon "dfs.updated"
        git -c advice.detachedHead=false checkout $DFS_COMMIT
        cp ./.update.sh ./update.sh && chmod +x ./update.sh && exit $DFS_UPDATED_RET
    else
        fmt_warning "won't really checkout in dev mode"
    fi
fi
