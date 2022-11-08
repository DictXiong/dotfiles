#!/bin/bash

THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/tools/common.sh"


if [[ ! "$DOTFILES" == "${HOME}"* ]]; then 
    fmt_fatal "\"$DOTFILES\" is not under \"$HOME\". aborting ..."
fi
DOTFILE_TILDE=${DOTFILES/"$HOME"/\~}

CRON_JOB="0 * * * * ${DOTFILES}/update.sh"
declare -a HOME_FILES_PATH
declare -a HOME_FILES_CONTENT
HOME_FILES_PATH[0]=".zshrc"
HOME_FILES_CONTENT[0]="source ${DOTFILE_TILDE}/.zshrc2"
HOME_FILES_PATH[1]=".tmux.conf"
HOME_FILES_CONTENT[1]="source-file ${DOTFILE_TILDE}/.tmux.conf2"
HOME_FILES_PATH[2]=".vimrc"
HOME_FILES_CONTENT[2]="source ${DOTFILE_TILDE}/.vimrc2"
HOME_FILES_PATH[3]=".gitconfig"
HOME_FILES_CONTENT[3]="[include] path = \"${DOTFILE_TILDE}/.gitconfig2\""

declare -a HOME_SYMLINKS_SRC
declare -a HOME_SYMLINKS_DST
HOME_SYMLINKS_SRC[0]=".ssh/authorized_keys2"
HOME_SYMLINKS_DST[0]=".ssh/authorized_keys2"

install_dependencies()
{
    fmt_info "installing dependencies ..."
    case $(get_os_type) in
        "linux" )
            case $(get_linux_dist) in
                "ubuntu"|"debian" )
                    $SUDO apt-get update
                    $SUDO apt-get install -y git zsh bash tmux vim python3 python3-pip curl inetutils-ping
                    ;;
                "alpine" )
                    $SUDO apk update
                    $SUDO apk add zsh bash git tmux vim curl python3 py3-pip fzf iputils coreutils
                    ;;
                * ) fmt_error "dfs auto-install is not implemented on linux distribution: $(get_linux_dist)"
            esac
            ;;
        "macos" )
            $SUDO brew update
            $SUDO brew install git python3 zsh curl tmux vim
            ;;
        "msys" )
            pacman -Syu
            pacman -S tmux git zsh bash curl vim python3 python3-pip
            SUDO=""
            ;;
        * ) fmt_error "dfs auto-install is not implemented on OS: $(get_os_type)"
    esac

    if [[ -x $(command -v pip3) ]]; then
        $SUDO pip3 install requests
    elif [[ -x $(command -v pip) ]]; then
        $SUDO pip install requests
    else
        fmt_error "pip3 and pip not found. is pip correctly installed?"
    fi
}

preinstall_check()
{
    mandatory_commands=( "git" "zsh" "curl" "ping" )
    optional_commands=( "python3" "vim" "tmux" )
    for i in "${mandatory_commands[@]}"; do
        if [[ ! -x "$(command -v $i)" ]]; then
            fmt_info "all this utils are required: ${mandatory_commands[@]}"
            fmt_info "install them manually or check scripts in tools/"
            fmt_fatal "\"$i\" not found. aborting ..."
        fi
    done
    for i in "${optional_commands[@]}"; do
        if [[ ! -x "$(command -v $i)" ]]; then
            fmt_warning "\"$i\" not found"
            ask_for_Yn "continue anyway?"
            if [[ "$?" == "0" ]]; then
                fmt_info "all this utils are suggested: ${optional_commands[@]}"
                fmt_info "install them manually or check scripts in tools/"
                fmt_fatal "aborting ..."
            fi
        fi
    done
}

install_file_content()
{
    for ((i=0; i<${#HOME_FILES_PATH[@]}; i++)); do
        local filename="$HOME/${HOME_FILES_PATH[$i]}"
        local content=${HOME_FILES_CONTENT[$i]}
        fmt_note "installing \"$content\" into \"$filename\" ..."
        mkdir -p $(dirname "$filename")
        if [ ! -f "$filename" ]; then
            touch $filename
        fi
        grep -qxF -- "$content" "$filename" || echo "$content" >> "$filename"
    done
}

uninstall_file_content()
{
    for ((i=0; i<${#HOME_FILES_PATH[@]}; i++)); do
        local filename="$HOME/${HOME_FILES_PATH[$i]}"
        local content=${HOME_FILES_CONTENT[$i]}
        fmt_note "removing \"$content\" from \"$filename\" ..."
        if [ -f "$filename" ]; then
            grep -vxF -- "$content" "$filename" | tee "$filename"
        fi
    done
}

install_symlink()
{
    for ((i=0; i<${#HOME_SYMLINKS_SRC[@]}; i++)); do
        local src="$DOTFILES/${HOME_SYMLINKS_SRC[$i]}"
        local dst="$HOME/${HOME_SYMLINKS_DST[$i]}"
        fmt_note "creating symlink \"$dst\" --> \"$src\" ..."
        if [ ! -f "$src" ]; then
            fmt_error "\"$src\" does not exist! aborting this job ..."
            continue
        fi
        mkdir -p $(dirname "$dst")
        if [ -f "$dst" ]; then
            if [ "$(readlink $dst)" -ef "$src" ]; then
                continue
            fi
            fmt_warning "\"$dst\" already exists! stat output:"
            echo ----------
            stat $dst
            echo ----------
            ask_for_yN "would you like to replace ${dst}?"
            if [ $? -eq 1 ]; then 
                rm $dst
            else
                fmt_error "aborting this job ..."
                continue
            fi
        fi
        ln -s $src $dst
    done
}

uninstall_symlink()
{
    local src
    for src in "${!HOME_SYMLINKS[@]}"; do
        local dst=${HOME_SYMLINKS[$src]}
        src="$DOTFILES/$src"
        dst="$HOME/$dst"
        if [ "$(readlink $dst)" -ef "$src" ]; then
            fmt_note "removing symlink \"$dst\" ..."
            echo ----------
            stat $dst
            echo ----------
            rm $dst
        fi
    done
}

install_crontab(){
    if [[ -x $(command -v crontab) ]]; then
        fmt_note "installing \"$CRON_JOB\" to crontab ..."
        ( crontab -l | grep -vxF "${CRON_JOB}" | grep -v "no crontab for"; echo "$CRON_JOB" ) | crontab -
    else
        fmt_warning "crontab does not exist. skipping ..."
    fi
}

uninstall_crontab(){
    if [[ -x $(command -v crontab) ]]; then
        fmt_note "removing \"$CRON_JOB\" from crontab ..."
        ( crontab -l | grep -vxF "$CRON_JOB" ) | crontab -
    else
        fmt_note "crontab does not exist. skipping ..."
    fi
}

install_tmux_tpm(){
    TMUX_TPM="$HOME/.tmux/plugins/tpm"
    if [[ -x $(command -v tmux) && ! -d "$TMUX_TPM" ]]; then
        fmt_note "installing tmux tpm ..."
        git clone https://gitee.com/dictxiong/tpm "$TMUX_TPM"
        if [[ -x $(command -v g++) && -x $(command -v cmake) && -x $(command -v make) ]]; then
            fmt_note "initializing tmux plugins ..."
            if [[ -z "$DFS_NO_COMPILE" ]]; then
                ~/.tmux/plugins/tpm/bin/install_plugins
            fi
        else
            fmt_warning "pls install g++,cmake,make and then init tmux plugins by <prefix + I> or ~/.tmux/plugins/tpm/bin/install_plugins"
        fi
    fi
}

install_vim_vundle(){
    VIM_VUNDLE="$HOME/.vim/bundle/Vundle.vim"
    if [[ -x $(command -v vim) && ! -d "$VIM_VUNDLE" ]]; then
        fmt_note "installing vim vundle ..."
        git clone https://gitee.com/dictxiong/Vundle.vim "$VIM_VUNDLE"
        fmt_note "initializing vim plugins ..."
        echo | vim +PluginInstall +qall
    fi
}

install_update(){
    fmt_note "installing update.sh ..."
    cp "${DOTFILES}/.update.sh" "${DOTFILES}/update.sh"
    chmod +x "${DOTFILES}/update.sh"
    fmt_note "running update.sh ..."
    ${DOTFILES}/update.sh
}

uninstall_update(){
    fmt_note "removing update.sh ..."
    rm "${DOTFILES}/update.sh"
}

install(){
    preinstall_check
    install_update
    install_crontab
    install_file_content
    install_symlink
    # those that won't be uninstalled in the future
    install_tmux_tpm
    install_vim_vundle
    fmt_note "done installing!"
}

uninstall(){
    ask_for_yN "do you really want to uninstall?"
    if [[ $? != 1 ]]; then
        fmt_error "aborting this job ..."
        return
    fi
    uninstall_update
    uninstall_crontab
    uninstall_file_content
    uninstall_symlink
    fmt_note "done uninstalling!"
}

BIN=install
while [[ $# > 0 ]]; do
    case $1 in
        -i ) BIN=install ;;
        -r ) BIN=uninstall ;;
        -q ) export DFS_QUIET=1 ;;
        -d ) export DFS_DEV=1 ;;
        -a|--auto ) install_dependencies ;;
        *  ) fmt_warning "unknown command \"$1\". available: -i, -r, -q, -d"; exit 1 ;;
    esac
    shift
done
$BIN