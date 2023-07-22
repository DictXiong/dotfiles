#!/usr/bin/env bash
set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/common.sh"

set_mirror()
{
    MIRROR=${1:-"mirrors.tuna.tsinghua.edu.cn"}
    sed -i "s@dl-cdn.alpinelinux.org@${MIRROR}@g" /etc/apk/repositories
}

apk_add()
{
    apk update
    # lite
    apk add zsh bash git tmux vim curl fzf iputils coreutils util-linux
    # full
    if [[ -z "$DFS_LITE" || "$DFS_LITE" == "0" ]]; then
        apk add wget python3 py3-pip htop gcc g++ cmake make perl linux-headers bind-tools man-db
    fi
}

set_timezone()
{
    apk update
    apk add tzdata
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    echo "Asia/Shanghai" > /etc/timezone
}

router()
{
    case $1 in
        apk-add ) apk_add ;;
        set-timezone | set-tz ) set_timezone ;;
        set-mirror  ) set_mirror $2 ;;
        *           ) echo unknown command \"$1\". available: apk-add, set-timezone;;
    esac
}

router "${GOT_OPTS[@]}"
