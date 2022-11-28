#!/bin/bash

set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/common.sh"

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
    local raw_uuid
    if [[ -f /var/lib/dbus/machine-id ]]; then
        raw_uuid=$(cat /var/lib/dbus/machine-id)
    elif [[ -f /etc/machine-id ]]; then
        raw_uuid=$(cat /etc/machine-id)
    elif [[ -f ~/.config/dotfiles/uuid ]]; then
        raw_uuid=$(cat ~/.config/dotfiles/uuid)
    else
        mkdir -p ~/.config/dotfiles
        raw_uuid=$(uuidgen)
        echo "$raw_uuid" > ~/.config/dotfiles/uuid
    fi
    uuid=$(uuidgen -n "cc23b903-1993-44eb-9c90-48bd841eeac3" -s -N "$raw_uuid")
}

post_beacon()
{
    local beacon_type=$1
    if [[ -z "$beacon_type" ]]; then
        fmt_fatal "beacon type is required"
    fi
    resp=$(curl -sSL -X POST "https://api.beardic.cn/post-beacon?hostname=$hostname&beacon=$beacon_type")
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
    resp=$(curl -sSL -X POST -H "Content-Type: text/plain" -d "$1" "https://api.beardic.cn/post-log?hostname=$hostname&uuid=$uuid")
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

if [[ $# != 2 ]]; then
    print_help >&2
    exit 1
fi

case "$1" in
    -h|--help)
        fmt_info "usage: $0 <beacon|log> <beacon_type|log_content>"
        ;;
    beacon)
        post_beacon "$2"
        ;;
    log)
        post_log "$2"
        ;;
    *)
        fmt_fatal "invalid argument"
        ;;
esac
