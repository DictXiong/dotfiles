#!/bin/bash

set -e

set_mirror()
{
    MIRROR=${1:-"mirrors.tuna.tsinghua.edu.cn"}
    MIRROR=${MIRROR//\//\\\/}
    sed -i "s/dl-cdn.alpinelinux.org/$MIRROR/g" /etc/apk/repositories
}

apk_add()
{
    apk update

    # mass installation
    apk add zsh git tmux vim curl wget bash python3 py3-pip htop gcc g++ cmake make fzf perl linux-headers bind-tools iputils man-db coreutils
    #for i in {fzf,ripgrep}; do apk add $i -y; done
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
        *           ) echo unknown command "$1". available: apk-add, set-timezone;;
    esac
}

router $@
