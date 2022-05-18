#!/bin/bash

declare -A install_commands
install_commands=(\
    [git]="apt update && apt install git" \
    [fzf]="git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf &&  ~/.fzf/install" \
    [acme.sh]="curl https://get.acme.sh | sh -s email=${EMAIL:-me@beardic.cn}" \
    [oh-my-zsh]='sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' \
)

install()
{
    echo ${install_commands[$1]}
}

install $1
