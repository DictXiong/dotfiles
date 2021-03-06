#!/bin/bash

if [[ $USER != "root" ]]; then
    echo "must run as root!"
    exit 1
fi

set_mirror()
{
    #MIRROR=${1:="mirrors.tuna.tsinghua.edu.cn"}
    #MIRROR=${MIRROR//\//\\\/}
    #sed -i 's/(archive|security).ubuntu.com/${MIRROR}/g' /etc/apt/sources.list
    echo "to-do ..."
}

apk_add()
{
    apk update

    # mass installation
    apk add zsh git tmux vim curl wget bash python3 htop gcc g++ cmake make fzf perl linux-headers bind-tools iputils man-db
    #for i in {fzf,ripgrep}; do apk add $i -y; done

    # who am i
    git config --global user.email "me@beardic.cn"
    git config --global user.name "Dict Xiong"
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
        #set-mirror  ) set_mirror $2 ;;  
        *           ) echo unknown command "$1". available: apk-add, set-timezone;;
    esac
}

router $@
