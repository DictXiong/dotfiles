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
        brew_install ) brew_install ;;
        *            ) echo unknown command "$1". available: brew_install;;
    esac
}

router $@
