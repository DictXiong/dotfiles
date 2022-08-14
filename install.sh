#!/bin/bash

# Color settings
# Source: https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
if [ -t 1 ]; then
    is_tty() {
        true
    }
else
    is_tty() {
        false
    }
fi

supports_truecolor() {
    case "$COLORTERM" in
    truecolor|24bit) return 0 ;;
    esac

    case "$TERM" in
    iterm           |\
    tmux-truecolor  |\
    linux-truecolor |\
    xterm-truecolor |\
    screen-truecolor) return 0 ;;
    esac

    return 1
}

fmt_fatal() {
    printf '%sfatal: %s%s\n' "${FMT_BOLD}${FMT_RED}" "$*" "$FMT_RESET" >&2
    exit
}

fmt_error() {
    printf '%serror: %s%s\n' "${FMT_RED}" "$*" "$FMT_RESET" >&2
}

fmt_warning() {
    echo "${FMT_YELLOW}warning: $1 ${FMT_RESET}" 
}

fmt_note() {
    echo "${FMT_GREEN}$1 ${FMT_RESET}"
}

setup_color() {
    # Only use colors if connected to a terminal
    if ! is_tty; then
        FMT_RAINBOW=""
        FMT_RED=""
        FMT_GREEN=""
        FMT_YELLOW=""
        FMT_BLUE=""
        FMT_BOLD=""
        FMT_RESET=""
    return
    fi

    if supports_truecolor; then
    FMT_RAINBOW="
        $(printf '\033[38;2;255;0;0m')
        $(printf '\033[38;2;255;97;0m')
        $(printf '\033[38;2;247;255;0m')
        $(printf '\033[38;2;0;255;30m')
        $(printf '\033[38;2;77;0;255m')
        $(printf '\033[38;2;168;0;255m')
        $(printf '\033[38;2;245;0;172m')
    "
    else
    FMT_RAINBOW="
        $(printf '\033[38;5;196m')
        $(printf '\033[38;5;202m')
        $(printf '\033[38;5;226m')
        $(printf '\033[38;5;082m')
        $(printf '\033[38;5;021m')
        $(printf '\033[38;5;093m')
        $(printf '\033[38;5;163m')
    "
    fi

    FMT_RED=$(printf '\033[31m')
    FMT_GREEN=$(printf '\033[32m')
    FMT_YELLOW=$(printf '\033[33m')
    FMT_BLUE=$(printf '\033[34m')
    FMT_BOLD=$(printf '\033[1m')
    FMT_RESET=$(printf '\033[0m')
}
# END of color settings

dotfile_path=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
home_slashes=${HOME//\//\\\/}
if [[ ! $dotfile_path == ${home_slashes}* ]]; then 
    fmt_fatal "\"$dotfile_path\" is not under \"$HOME\". aborting ..."
fi
dotfile_home_path=${dotfile_path/${home_slashes}/\~}
dotfile_relative_path=${dotfile_path#${home_slashes}\/}
crontab_job="0 * * * * ${dotfile_path}/update.sh"

ask_for_yN()
{
    while true; do
        read -p "${FMT_YELLOW}$1${FMT_RESET} [yN]: " yn
        case $yn in
            [Yy]* ) return 1;;
            [Nn]* ) return 0;;
            * ) return 0;;
        esac
    done
}

insert_if_not_exist()
{
    filename=$1
    line=$2
    fmt_note "installing \"$line\" into \"$filename\" ..."
    mkdir -p $(dirname "$filename")
    if [ ! -f "$filename" ]; then
        touch $filename
    fi
    grep -qxF -- "$line" "$filename" || echo "$line" >> "$filename"
}

delete_if_exist()
{
    filename=$1
    line=$2
    fmt_note "removing \"$line\" from \"$filename\" ..."
    if [ -f "$filename" ]; then
        grep -vxF -- "$line" "$filename" | tee "$filename"
    fi
}

create_symlink()
{
    src=$1
    dest=$2
    fmt_note "creating symlink \"$dest\" --> \"$src\" ..."
    if [ ! -f "$src" ]; then
        fmt_error "\"$src\" does not exist! aborting this job ..."
        return 1
    fi
    mkdir -p $(dirname "$dest")
    if [ -f "$dest" ]; then
        if [ "$(readlink $dest)" -ef "$src" ]; then
            return 0
        fi
        fmt_warning "\"$dest\" already exists! stat output:"
        echo ----------
        stat $dest
        echo ----------
        ask_for_yN "would you like to replace ${dest}?"
        if [ $? -eq 1 ]; then 
            rm $dest
        else
            fmt_error "\"$dest\" already exists! aborting this job ..."
            return 1
        fi
    fi
    ln -s $src $dest
    return $?
}

delete_link_if_match()
{
    src=$1
    dest=$2
    if [ "$(readlink $dest)" -ef "$src" ]; then
        fmt_note "removing symlink \"$dest\" ..."
        echo ----------
        stat $dest
        echo ----------
        rm $dest
    fi
}

install_crontab(){
    fmt_note "installing \"$crontab_job\" to crontab ..."
    ( crontab -l | grep -vxF "${crontab_job}" | grep -v "no crontab for"; echo "$crontab_job" ) | crontab -
}

uninstall_crontab(){
    fmt_note "removing \"$crontab_job\" from crontab ..."
    ( crontab -l | grep -vxF "$crontab_job" ) | crontab - 
}

install_tmux_tpm(){
    TMUX_TPM="$HOME/.tmux/plugins/tpm"
    if [[ -x $(command -v tmux) && ! -d "$TMUX_TPM" ]]; then
        fmt_note "installing tmux tpm ..."
        git clone https://gitee.com/dictxiong/tpm "$TMUX_TPM"
        if [[ -x $(command -v g++) && -x $(command -v cmake) && -x $(command -v make) ]]; then
            fmt_note "initializing tmux plugins ..."
            ~/.tmux/plugins/tpm/bin/install_plugins
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
        vim +PluginInstall +qall
    fi
}

install_update(){
    fmt_note "installing update.sh ..."
    cp "${dotfile_path}/.update.sh" "${dotfile_path}/update.sh"
    chmod +x "${dotfile_path}/update.sh"
    fmt_note "running update.sh ..."
    ${dotfile_path}/update.sh
}

uninstall_update(){
    fmt_note "removing update.sh ..."
    rm "${dotfile_path}/update.sh"
}

install(){
    install_update
    install_crontab
    insert_if_not_exist "${HOME}/.zshrc" "source ${dotfile_home_path}/.zshrc2"
    insert_if_not_exist "${HOME}/.tmux.conf" "source-file ${dotfile_home_path}/.tmux.conf2"
    insert_if_not_exist "${HOME}/.vimrc" "source ${dotfile_home_path}/.vimrc2"
    insert_if_not_exist "${HOME}/.gitconfig" "[include] path = \"${dotfile_home_path}/.gitconfig2\""
    create_symlink "${dotfile_path}/.ssh/authorized_keys2" "${HOME}/.ssh/authorized_keys2"
    # those that won't be uninstalled in the future
    install_tmux_tpm
    install_vim_vundle
    fmt_note "done installing!"
}

uninstall(){
    ask_for_yN "do you really want to uninstall?"
    if [[ $? == 1 ]]; then
        uninstall_update
        uninstall_crontab
        delete_if_exist "${HOME}/.zshrc" "source ${dotfile_home_path}/.zshrc2"
        delete_if_exist "${HOME}/.tmux.conf" "source-file ${dotfile_home_path}/.tmux.conf2"
        delete_if_exist "${HOME}/.vimrc" "source ${dotfile_home_path}/.vimrc2"
        delete_if_exist "${HOME}/.gitconfig" "[include] path = \"${dotfile_home_path}/.gitconfig2\""
        delete_link_if_match "${dotfile_path}/.ssh/authorized_keys2" "${HOME}/.ssh/authorized_keys2"
        fmt_note "done uninstalling!"
    fi
}

setup_color
case $1 in
    ""|-i ) install ;;
    -r    ) uninstall ;;
    *     ) fmt_warning "unknown command \"$1\". available: -i, -r" ;;
esac
