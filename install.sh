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

dotfile_path=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
home_slashes=${HOME//\//\\\/}
if [[ ! $dotfile_path == ${home_slashes}* ]]; then 
    fmt_fatal "\"$dotfile_path\" is not under \"$HOME\". aborting ..."
fi
dotfile_home_path=${dotfile_path/${home_slashes}/\~}
dotfile_relative_path=${dotfile_path#${home_slashes}\/}
crontab_job="0 * * * * cd ${dotfile_path} && env git pull"

ask_for_yN()
{
    while true; do
        read -p "$1 [yN]: " yn
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
    if [ ! -f "$filename" ]; then
        touch $filename
    fi
    grep -qxF -- "$line" "$filename" || echo "$line" >> "$filename"
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
    if [ -f "$dest" ]; then
        fmt_warning "\"$dest\" already exists! stat output:"
        echo ----------
        env stat $dest
        echo ----------
        ask_for_yN "${FMT_YELLOW}would you like to replace ${dest}?${FMT_RESET}"
        if [ $? -eq 1 ]; then 
            rm $dest
        else
            fmt_error "\"$dest\" already exists! aborting this job ..."
            return 1
        fi
    fi
    ln -s $src $dest
}

install_crontab(){
    fmt_note "installing \"$crontab_job\" to crontab ..."
    ( crontab -l | grep -v "${crontab_job//\*/\\\*}" | grep -v "no crontab for"; echo "$crontab_job" ) | crontab -
}

uninstall_crontab(){
    fmt_note uninstalling "\"$crontab_job\"" from crontab ...
    ( crontab -l | grep -v"$crontab_job" ) | crontab - 
}

install(){
    install_crontab
    insert_if_not_exist "${HOME}/.zshrc" "source ${dotfile_home_path}/.zshrc2"
    create_symlink "${dotfile_path}/.ssh/authorized_keys2" "${HOME}/.ssh/authorized_keys2"
    fmt_note "job done!"
}

setup_color
install
