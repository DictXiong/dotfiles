#!/bin/bash

if [[ $USER != "root" ]]; then
    echo "must run as root!"
    exit 1
fi

init()
{
    # basic packages
    apt update
    for i in {man-db,vim,ca-certificates}; do apt install $i -y; done

    # apt source
    ${MIRROR:="mirrors.tuna.tsinghua.edu.cn"}
    MIRROR=${MIRROR//\//\\\/}
    sed -i 's/(archive|security).ubuntu.com/${MIRROR}/g' /etc/apt/sources.list

    # mass installation
    apt update
    apt install git tmux zsh curl wget dialog net-tools dnsutils netcat traceroute sudo python3 python3-pip cron inetutils-ping openssh-client openssh-server htop gcc g++ cmake
    for i in {fzf,ripgrep}; do apt install $i -y; done

    # custom dotfiles (usually not needed)
    mkdir -p ~/.ssh
    # cd ~ && git clone https://gitee.com/dictxiong/dotfiles && ./dotfiles/install.sh
    
    # who am i
    git config --global user.email "me@beardic.cn"
    git config --global user.name "Dict Xiong"
}

router()
{
    case $1 in
        init    ) init ;;
        *       ) echo unknown command "$1". available: init ;;
    esac
}

router $@
