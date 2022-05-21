#!/bin/bash

if [[ $USER != "root" ]]; then
    echo "must run as root!"
    exit 1
fi

set_mirror()
{
    MIRROR=${1:="mirrors.tuna.tsinghua.edu.cn"}
    MIRROR=${MIRROR//\//\\\/}
    sed -i 's/(archive|security).ubuntu.com/${MIRROR}/g' /etc/apt/sources.list
}

apt_install()
{
    # basic packages
    apt update
    for i in {man-db,vim,ca-certificates}; do apt install $i -y; done

    # mass installation
    apt update
    apt install git tmux zsh curl wget dialog net-tools dnsutils netcat traceroute sudo python3 python3-pip cron inetutils-ping openssh-client openssh-server htop gcc g++ cmake make
    for i in {fzf,ripgrep}; do apt install $i -y; done

    # who am i
    git config --global user.email "me@beardic.cn"
    git config --global user.name "Dict Xiong"
}

router()
{
    case $1 in
        apt-install ) apt_install ;;
        set-mirror  ) set_mirror $2 ;;  
        *           ) echo unknown command "$1". available: apt-install, set-mirror;;
    esac
}

router $@
