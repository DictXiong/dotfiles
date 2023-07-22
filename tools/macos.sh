#!/usr/bin/env bash
set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/common.sh"

brew_install()
{
    # brew update
    brew install git zsh curl tmux vim util-linux
}

router()
{
    case $1 in
        brew-install ) brew_install ;;
        *            ) echo unknown command \"$1\". available: brew-install;;
    esac
}

router "${GOT_OPTS[@]}"
