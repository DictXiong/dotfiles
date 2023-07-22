#!/usr/bin/env bash

declare -A INSTALL_COMMANDS
INSTALL_COMMANDS=(\
    [git]="apt update && apt install git" \
    [fzf]="git clone --depth 1 https://gitee.com/dictxiong/fzf.git ~/.fzf &&  ~/.fzf/install" \
    [acme.sh]="curl https://get.acme.sh | sh -s email=${EMAIL:-me@beardic.cn}" \
    [oh-my-zsh]='sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' \
    [oh-my-tuna]='wget https://tuna.moe/oh-my-tuna/oh-my-tuna.py && sudo python oh-my-tuna.py --global' \
    [v2fly]="bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) #--remove" \
    [zerotier-one]='curl -s https://install.zerotier.com | sudo bash' \
    [docker-ce]='curl -fsSL https://get.docker.com | sudo bash -s - --mirror Aliyun #--dry-run' \
    [lemonbench]='curl -fsSL https://ilemonra.in/LemonBenchIntl | bash -s fast # or full' \
)

install()
{
    echo -e ${INSTALL_COMMANDS[$1]}
}

install $1
