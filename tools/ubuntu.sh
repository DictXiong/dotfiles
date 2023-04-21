#!/bin/bash
set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/common.sh"

set_mirror()
{
    MIRROR=${1:-"mirrors.tuna.tsinghua.edu.cn"}
    sed -i "s@http://.*archive.ubuntu.com@https://${MIRROR}@g" /etc/apt/sources.list
    sed -i "s@http://.*security.ubuntu.com@https://${MIRROR}@g" /etc/apt/sources.list
}

apt_install()
{
    apt-get update -y
    # lite
    apt-get install -y git zsh bash tmux vim curl inetutils-ping less bsdmainutils
    # full
    if [[ -z "$DFS_LITE" || "$DFS_LITE" == "0" ]]; then
        apt-get install -y wget dialog net-tools dnsutils netcat traceroute sudo python3 python3-pip cron openssh-client openssh-server htop gcc g++ cmake make zip
        for i in {fzf,ripgrep,man-db}; do apt-get install -y $i; done
    fi
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
        *           ) echo unknown command \"$1\". available: apt-install, set-mirror, set-timezone;;
    esac
}

router "${GOT_OPTS[@]}"
