#!/bin/bash

export DOTFILES=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
# get the specified commit id
dfs_commit=$(curl -fsSL https://api.beardic.cn/get-var/dfs-commit-id)
if [[ ${#dfs_commit} != 40 ]]; then
    echo "Error: invalid commit id."
    python3 "${DOTFILES}/post-log.py" "[ERROR] update.sh: invalid commit id: ${dfs_commit}"
    exit
fi
# fetch origin
cd $DOTFILES
git fetch
if [[ -n "$(git status -s)" ]]; then
    echo "Error: directory not clean."
    python3 "${DOTFILES}/post-log.py" "[ERROR] update.sh: directory not clean"
    exit
fi
# update
if [[ "$(git rev-parse HEAD)" == "$dfs_commit" ]]; then
    echo "Nothing to do."
    python3 "${DOTFILES}/post-log.py" "[INFO] update.sh: Nothing to do"
else
    echo "Checking out to commit $dfs_commit ..."
    git -c advice.detachedHead=false checkout $dfs_commit
    cp ./.update.sh ./update.sh
    chmod +x ./update.sh
    python3 "${DOTFILES}/post-log.py" "[INFO] update.sh: Checked out to commit $dfs_commit"
fi
