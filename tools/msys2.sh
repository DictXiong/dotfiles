#!/bin/bash
set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/common.sh"

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
    # lite
    pacman -S tmux git zsh bash curl vim
    # full
    if [[ -z "$DFS_LITE" || "$DFS_LITE" == "0" ]]; then
        pacman -S wget base-devel mingw-w64-x86_64-toolchain make cmake gcc zip unzip python3 python3-pip man-pages-posix
    fi
}

router()
{
    case $1 in
        pacman-S    ) pacman_S ;;
        set-mirror  ) set_mirror $2 ;;  
        *           ) echo unknown command "$1". available: pacman-S, set-mirror ;;
    esac
}

router $@
