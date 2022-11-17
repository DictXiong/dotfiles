#!/bin/bash

set -e

set_mirror()
{
    MIRROR=${1:-"mirrors.tuna.tsinghua.edu.cn"}
    MIRROR=${MIRROR//\//\\\/}
    sed -i "s@http://.*archive.ubuntu.com@https://${MIRROR}@g" /etc/apt/sources.list
    sed -i "s@http://.*security.ubuntu.com@https://${MIRROR}@g" /etc/apt/sources.list
}

apt_install()
{
    # basic packages
    apt-get update
    for i in {man-db,vim,ca-certificates}; do apt-get install $i -y; done

    # mass installation
    apt-get install git tmux zsh curl wget dialog net-tools dnsutils netcat traceroute sudo python3 python3-pip cron inetutils-ping openssh-client openssh-server htop gcc g++ cmake make zip less bsdmainutils
    for i in {fzf,ripgrep}; do apt-get install $i -y; done
}

set_timezone()
{
    TIMEZONE=${1:-"Asia/Shanghai"}
    timedatectl set-timezone "$TIMEZONE"
}

router()
{
    case $1 in
        apt-install ) apt_install ;;
        set-mirror  ) set_mirror $2 ;;  
        set-timezone\
        | set-tz    ) set_timezone $2 ;;
        *           ) echo unknown command "$1". available: apt-install, set-mirror, set-timezone;;
    esac
}

router $@
