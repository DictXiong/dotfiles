#!/bin/bash
set -e
THIS_DIR_COMMON_SH=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
export DOTFILES=$( cd "$THIS_DIR_COMMON_SH/.." && pwd )
if [[ -f ~/.config/dotfiles/env ]]; then set -a; source ~/.config/dotfiles/env; set +a; fi

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
    printf '%sfatal: %s%s\n' "${FMT_BOLD}${FMT_RED}" "$*" "${FMT_RESET}" >&2
    exit 1
}

fmt_error() {
    printf '%serror: %s%s\n' "${FMT_RED}" "$*" "${FMT_RESET}" >&2
}

fmt_warning() {
    printf '%swarning: %s%s\n' "${FMT_YELLOW}" "$*" "${FMT_RESET}" >&2
}

fmt_info() {
    printf '%sinfo: %s\n' "${FMT_RESET}" "$*" >&1
}

fmt_note() {
    printf '%s%s%s\n' "${FMT_GREEN}" "$*" "${FMT_RESET}" >&1
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

SUDO=''
if [[ "$EUID" != "0" && -x $(command -v sudo) ]]; then
    SUDO='sudo'
fi

parse_arg()
{
    local ARG=""
    PARSE_ARG_RET=()
    while [[ $# > 0 || -n "$ARG" ]]; do
        if [[ -z "$ARG" ]]; then ARG=$1; shift; fi
        case $ARG in
            -q*|--quite ) export DFS_QUIET=1 ;;
            --* ) PARSE_ARG_RET+=("$ARG") ;;
            -* ) PARSE_ARG_RET+=("${ARG:0:2}") ;;
            *  ) PARSE_ARG_RET+=("$ARG") ;;
        esac
        if [[ "$ARG" == "--"* || ! "$ARG" == "-"* || ${#ARG} -le 2 ]]; then
            ARG=""
        else
            ARG=-${ARG:2}
        fi
    done
}

ask_for_yN()
{
    while [[ -z "$DFS_QUIET" || "$DFS_QUIET" == "0" ]]; do
        read -p "${FMT_YELLOW}$1${FMT_RESET} [yN]: " yn
        case $yn in
            [Yy]* ) return 1;;
            * ) return 0;;
        esac
    done
    return 0
}

ask_for_Yn()
{
    while [[ -z "$DFS_QUIET" || "$DFS_QUIET" == "0" ]]; do
        read -p "${FMT_YELLOW}$1${FMT_RESET} [Yn]: " yn
        case $yn in
            [Nn]* ) return 0;;
            * ) return 1;;
        esac
    done
    return 1
}

post_log()
{
    if [[ $# != 3 || -z "$1" || -z "$2" || -z "$3" ]]; then
        fmt_fatal "usage: post_log <level> <section> <content>"
    fi
    "${DOTFILES}/tools/logger.sh" "log" "[$1][$2] $3"
}

apost_log()
{
    post_log "$@" 1>/dev/null &
}

post_beacon()
{
    if [[ $# != 1 || -z "$1" ]]; then
        fmt_fatal "usage: post_beacon <beacon>"
    fi
    "${DOTFILES}/tools/logger.sh" "beacon" "$1"
}

apost_beacon()
{
    post_beacon "$@" 1>/dev/null &
}

get_os_type()
{
    local ans="unknown"
    case "$(uname -s)" in
        Darwin*)    ans="MacOS";;
        CYGWIN*)    ans="Cygwin";;
        MSYS*  )    ans="MSYS";;
        Linux* )    ans="Linux";;
        *)          ans="unknown";;
    esac
    echo $ans | tr '[:upper:]' '[:lower:]'
}

get_linux_dist()
{
    local ans="unknown"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        ans="$ID"
    elif type lsb_release >/dev/null 2>&1; then
        ans="$(lsb_release -si)"
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        ans="$DISTRIB_ID"
    elif [ -f /etc/debian_version ]; then
        ans="Debian"
    elif [ -f /etc/SuSe-release ]; then
        ans="SUSE"
    elif [ -f /etc/redhat-release ]; then
        ans="RedHat"
    else
        ans="unknown"
    fi
    echo $ans | tr '[:upper:]' '[:lower:]'
}

get_os_name()
{
    local ans=$(get_os_type)
    if [[ "$ans" == "linux" ]]; then
        ans=$(get_linux_dist)
    fi
    echo $ans
}

# if bash-ed, else source-d
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    $1 "${@:2}"
else
    setup_color
fi

unset THIS_DIR_COMMON_SH
