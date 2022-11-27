#!/bin/bash

THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
THIS_FILE=$(basename "${BASH_SOURCE}")
source "$THIS_DIR/tools/common.sh"

DFS_UPDATED_RET=${DFS_UPDATED_RET:-0}
DFS_UPDATE_CHANNEL=${DFS_UPDATE_CHANNEL:-"main"}

# fetch origin
cd $DOTFILES
git fetch --all --prune
if [[ -n "$(git status -s)" ]]; then
    fmt_error "directory not clean"
    post_beacon "dfs.dirty" 1>/dev/null &
    exit
fi

# get the specified commit id
case $DFS_UPDATE_CHANNEL in
    "main" ) DFS_COMMIT=$(curl -fsSL https://api.beardic.cn/get-var/dfs-commit-id) ;;
    "dev" ) DFS_COMMIT=$(git rev-parse origin/dev 2> /dev/null) || DFS_COMMIT=$(git rev-parse origin/main) ;;
    "latest" ) DFS_COMMIT=$(git for-each-ref --sort=-committerdate refs/heads refs/remotes --format='%(objectname)' | head -n 1) ;;
    * ) fmt_fatal "invalid update channel: $DFS_UPDATE_CHANNEL" ;;
esac
if [[ ${#DFS_COMMIT} != 40 ]]; then
    fmt_error "invalid commit id"
    post_beacon "dfs.invalid-commit" 1>/dev/null &
    post_log "ERROR" "$THIS_FILE" "invalid commit id: ${DFS_COMMIT}"
    exit
fi

# update
if [[ "$(git rev-parse HEAD)" == "$DFS_COMMIT" ]]; then
    fmt_info "nothing to do"
else
    fmt_info "checking out to commit $DFS_COMMIT ..."
    if [[ -z "$DFS_DEV" ]]; then
        post_beacon "dfs.updated" 1>/dev/null &
        git -c advice.detachedHead=false checkout $DFS_COMMIT
        cp ./.update.sh ./update.sh && chmod +x ./update.sh && exit $DFS_UPDATED_RET
    else
        fmt_warning "won't really checkout in dev mode"
    fi
fi
