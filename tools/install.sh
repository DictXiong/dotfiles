#!/bin/bash

declare -A install_commands
install_commands=(\
    [git]="apt update && apt install git" \
    [fzf]="git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf &&  ~/.fzf/install" \
    [acme.sh]="curl https://get.acme.sh | sh -s email=${EMAIL:-me@beardic.cn}" \
    [oh-my-zsh]='sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' \
    [oh-my-tuna]='wget https://tuna.moe/oh-my-tuna/oh-my-tuna.py && sudo python oh-my-tuna.py --global' \
    [v2ray]="bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) #--remove" \
    [zerotier-one]='curl -s https://install.zerotier.com | sudo bash' \
    [docker-ce]='curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh #--mirror Aliyun #--dry-run' \
)

install()
{
    echo -e ${install_commands[$1]}
}

install $1
