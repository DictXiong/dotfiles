#!/bin/bash

if [[ $USER != "root" ]]; then
    echo "must run as root!"
    exit 1
fi

set_mirror()
{
    # MIRROR=${1:-"mirrors.tuna.tsinghua.edu.cn"}
    # MIRROR=${MIRROR//\//\\\/}
    # sed -i 's/(archive|security).ubuntu.com/${MIRROR}/g' /etc/apt/sources.list
    echo "to do ..."
}

pacman_S()
{
    pacman -Syu
    pacman -S tmux git zsh curl vim wget base-devel mingw-w64-x86_64-toolchain make cmake gcc zip
}

router()
{
    case $1 in
        pacman-S ) pacman_S ;;
        set-mirror  ) set_mirror $2 ;;  
        *           ) echo unknown command "$1". available: pacman-S, set-mirror ;;
    esac
}

router $@
