#!/bin/bash

THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
THIS_FILE=$(basename "${BASH_SOURCE}")
source "$THIS_DIR/tools/common.sh"

# get the specified commit id
dfs_commit=$(curl -fsSL https://api.beardic.cn/get-var/dfs-commit-id)
if [[ ${#dfs_commit} != 40 ]]; then
    fmt_error "invalid commit id"
    post_log "ERROR" "$THIS_FILE" "invalid commit id: ${dfs_commit}"
    exit
fi
# fetch origin
cd $DOTFILES
git fetch --all
if [[ -n "$(git status -s)" ]]; then
    fmt_error "directory not clean"
    post_log "ERROR" "$THIS_FILE" "directory not clean"
    exit
fi
# update
if [[ "$(git rev-parse HEAD)" == "$dfs_commit" ]]; then
    fmt_info "nothing to do"
    post_log "INFO" "$THIS_FILE" "nothing to do"
else
    fmt_info "checking out to commit $dfs_commit ..."
    if [[ -z "$DFS_DEV" ]]; then
        git -c advice.detachedHead=false checkout $dfs_commit
    else
        fmt_warning "won't really checkout in dev mode"
    fi
    post_log "INFO" "$THIS_FILE" "will check out to commit $dfs_commit"
    cp ./.update.sh ./update.sh && chmod +x ./update.sh && exit
fi
