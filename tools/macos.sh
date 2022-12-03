#!/bin/bash

set -e

brew_install()
{
    brew update
    brew install git zsh curl tmux vim util-linux
}

router()
{
    case $1 in
        brew-install ) brew_install ;;
        *            ) echo unknown command "$1". available: brew-install;;
    esac
}

router $@
