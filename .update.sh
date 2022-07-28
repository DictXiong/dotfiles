#!/bin/bash

export DOTFILES=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
# get the specified commit id
dfs_commit=$(curl -fsSL https://api.beardic.cn/get-dfs-commit)
if [[ ${#dfs_commit} != 40 ]]; then
    echo "Error: invalid commit id."
    exit
fi
# fetch origin
cd $DOTFILES
git fetch
if [[ -n "$(git status -s)" ]]; then
    echo "Error: directory not clean."
    exit
fi
# update
if [[ "$(git rev-parse HEAD)" == "$dfs_commit" ]]; then
    echo "Nothing to do."
else
    echo "Checking out to commit $dfs_commit ..."
    git checkout $dfs_commit
    cp ./.update.sh ./update.sh
    chmod +x ./update.sh
fi
