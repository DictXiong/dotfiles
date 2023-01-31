#!/bin/bash

set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/common.sh"

if [[ "$DFS_ORPHAN" == "1" ]]; then
    exit 0
fi

if [[ -x $(command -v hostname) ]]; then
    hostname=$(hostname)
elif [[ -x $(command -v uname) ]]; then
    hostname=$(uname -n)
elif [[ -x $(command -v hostnamectl) ]]; then
    hostname=$(hostnamectl --static)
elif [[ -n "$HOSTNAME" ]]; then
    hostname=$HOSTNAME
elif [[ -f /proc/sys/kernel/hostname ]]; then
    hostname=$(cat /proc/sys/kernel/hostname)
elif [[ -f /etc/hostname ]]; then
    hostname=$(cat /etc/hostname)
else
    fmt_fatal "unable to get hostname"
fi

init_uuid()
{
    if  [[ -f ~/.config/dotfiles/uuid ]]; then
        uuid=$(cat ~/.config/dotfiles/uuid)
    else
        if [[ -x $(command -v uuidgen) ]]; then
            uuid=$(uuidgen)
        elif [[ -f /proc/sys/kernel/random/uuid ]]; then
            uuid=$(cat /proc/sys/kernel/random/uuid)
        else
            fmt_fatal "unable to generate uuid"
        fi
        mkdir -p ~/.config/dotfiles
        echo "$uuid" > ~/.config/dotfiles/uuid
    fi
}

post_beacon()
{
    local beacon_type=$1
    local meta=$2
    if [[ -z "$beacon_type" ]]; then
        fmt_fatal "beacon type is required"
    fi
    resp=$(curl -sSL -X POST -H "Content-Type: text/plain" -d "$meta" "https://api.beardic.cn/post-beacon?hostname=$hostname&beacon=$beacon_type")
    if grep -q "200" <<< "$resp"; then
        echo $resp
    else
        echo $resp >&2
        fmt_fatal "error posting beacon"
    fi
}

post_log()
{
    local log_content=$1
    if [[ -z "$log_content" ]]; then
        fmt_fatal "log content is required"
    fi
    init_uuid
    resp=$(curl -sSL -X POST -H "Content-Type: text/plain" -d "$log_content" "https://api.beardic.cn/post-log?hostname=$hostname&uuid=$uuid")
    if grep -q "200" <<< "$resp"; then
        echo $resp
    elif grep -q "403" <<< "$resp"; then
        echo $resp >&2
        fmt_error "error posting log: authentification failed"
        fmt_info "try to register you hostname and uuid"
        fmt_info "hostname: $hostname"
        fmt_info "uuid: $uuid"
    else
        echo $resp >&2
        fmt_fatal "error posting log"
    fi
}

print_help()
{
    fmt_info "usage: $0 <beacon|log> <beacon_type|log_content>"
}

router()
{
    if [[ $# < 2 ]]; then
        print_help >&2
        exit 1
    fi

    case "$1" in
        -h|--help)
            fmt_info "usage: $0 <beacon|log> <beacon_type|log_content>"
            ;;
        beacon)
            post_beacon "$2" "$3"
            ;;
        log)
            post_log "$2"
            ;;
        *)
            fmt_fatal "invalid argument"
            ;;
    esac
}

router "${GOT_OPTS[@]}"