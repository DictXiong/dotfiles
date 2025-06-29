#!/usr/bin/env bash
set -e
THIS_DIR_COMMON_SH=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
export DOTFILES=$( cd "$THIS_DIR_COMMON_SH/.." && pwd )
if [[ -f ~/.config/dotfiles/env ]]; then set -a; source ~/.config/dotfiles/env; set +a; fi
if [[ "$DFS_DEV" == "1" ]]; then set -x; fi
DFS_CURL_OPTIONS="--retry 2 --max-time 20"

# parse args and set env, when it is sourced
# todo: make this skipable
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    ORIGIN_ARGS=("$@")
    ARG=""
    GOT_OPTS=()
    while [[ $# > 0 || -n "$ARG" ]]; do
        if [[ -z "$ARG" ]]; then
            if [[ "$1" == "--" ]]; then GOT_OPTS+=("$@"); break; fi
            ARG="$1"; shift;
        fi
        case $ARG in
            -q*|--quite ) export DFS_QUIET=1 ;;
            -l*|--lite ) export DFS_LITE=1 ;;
            -d*|--dev ) export DFS_DEV=1; set -x ;;
            -D*|--dry-run ) export DFS_DRY_RUN=1 ;;
            --color ) export DFS_COLOR=1 ;;
            --*=* ) GOT_OPTS+=("${ARG%%=*}" "${ARG#*=}") ;;
            --* ) GOT_OPTS+=("$ARG") ;;
            -* ) GOT_OPTS+=("${ARG:0:2}") ;;
            *  ) GOT_OPTS+=("$ARG") ;;
        esac
        if [[ "$ARG" == "--"* || ! "$ARG" == "-"* || ${#ARG} -le 2 ]]; then
            ARG=""
        else
            ARG=-${ARG:2}
        fi
    done
    set -- "${ORIGIN_ARGS[@]}"
    unset ARG
    # outputs: GOT_OPTS and ORIGIN_ARGS
fi

# Color settings
# Source: https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
if [[ -t 1 || "$DFS_COLOR" == "1" ]]; then
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
    printf '%sinfo: %s\n' "${FMT_RESET}" "$*" >&2
}

fmt_note() {
    printf '%s%s%s\n' "${FMT_GREEN}" "$*" "${FMT_RESET}" >&2
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
SUDOE=''
if [[ "$EUID" != "0" && -x $(command -v sudo) ]]; then
    SUDO='sudo'
    SUDOE='sudo -E'
fi

ask_for_yN()
{
    if [[ "$DFS_QUIET" == "1" ]]; then
        echo 0
    else
        read -p "${FMT_YELLOW}$1${FMT_RESET} [yN]: " yn
        case $yn in
            [Yy]* ) echo 1;;
            * ) echo 0;;
        esac
    fi
}

ask_for_Yn()
{
    if [[ "$DFS_QUIET" == "1" ]]; then
        echo 1
    else
        read -p "${FMT_YELLOW}$1${FMT_RESET} [Yn]: " yn
        case $yn in
            [Nn]* ) echo 0;;
            * ) echo 1;;
        esac
    fi
}

post_beacon()
{
    if [[ $# < 1 || -z "$1" ]]; then
        fmt_fatal "usage: post_beacon <beacon>"
    fi
    "${DOTFILES}/tools/frigg-client.sh" "beacon" "$1" "$2"
}

apost_beacon()
{
    post_beacon "$@" 1>/dev/null &
}

get_os_type()
{
    test -z "$DFS_OS_TYPE" || { echo "$DFS_OS_TYPE"; return; }
    local ans="unknown"
    case "$(uname -s)" in
        Darwin*)    ans="MacOS";;
        CYGWIN*)    ans="Cygwin";;
        MSYS*  )    ans="MSYS";;
        Linux* )    ans="Linux";;
        *)          ans="unknown";;
    esac
    export DFS_OS_TYPE="$ans"
    echo $ans | tr '[:upper:]' '[:lower:]'
}

get_linux_dist()
{
    test -z "$DFS_LINUX_DIST" || { echo "$DFS_LINUX_DIST"; return; }
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
    export DFS_LINUX_DIST="$ans"
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

is_port_free() {
    ( echo $1 | grep -qxE "[1-9][0-9]{0,4}" ) || false
    local cmd
    case $(get_os_type) in
        macos ) cmd="netstat -van | grep -q \".$1\"" ;;
        cygwin|msys ) cmd="netstat -ano | grep -q \":$1\"" ;;
        *) cmd="netstat -tuanp | grep -q \":$1\"" ;;
    esac
    if eval $cmd; then
        return 2
    else
        return 0
    fi
}

get_free_port() {
    while
        local port=$(shuf -n 1 -i 49152-65535)
        ! is_port_free $port
    do
        continue
    done
    echo $port
}

is_function() {
    test "$(type -t "$1")" = "function"
}

# if bash-ed, else source-d
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    $1 "${@:2}"
else
    setup_color
fi

unset THIS_DIR_COMMON_SH
