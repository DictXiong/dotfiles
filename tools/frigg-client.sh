#!/bin/bash

set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/common.sh"

if [[ "$DFS_ORPHAN" == "1" ]]; then
    exit 0
fi

if [[ -n "$DFS_HOSTNAME" ]]; then
    hostname=$DFS_HOSTNAME
elif [[ -x $(command -v hostname) ]]; then
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

handle_resp()
{
    local resp="$1"
    if grep -q "200" <<< "$resp"; then
        echo $resp
    elif grep -q "403" <<< "$resp"; then
        echo $resp >&2
        fmt_error "error accessing api: authentification failed"
        fmt_info "try to register you hostname and uuid"
        fmt_info "hostname: $hostname"
        fmt_info "uuid: $uuid"
    else
        echo $resp >&2
        fmt_fatal "server returned an error"
        # here return 1 because this is not expected
    fi
}

post_beacon()
{
    local beacon_type=$1
    local meta=$2
    if [[ -n "$CI" && "$beacon_type" != "gh.ci" && "$beacon_type" != "dfs.invalid-commit" && "$beacon_type" != "dfs.dirty" ]]; then
        return
    fi
    if [[ -z "$beacon_type" ]]; then
        fmt_fatal "beacon type is required"
    fi
    resp=$(curl -m 10 -sSL -X POST -H "Content-Type: text/plain" -d "$meta" "https://api.beardic.cn/post-beacon?hostname=$hostname&beacon=$beacon_type")
    handle_resp "$resp"
}

post_log()
{
    local log_content=$1
    if [[ -z "$log_content" ]]; then
        fmt_fatal "log content is required"
    fi
    init_uuid
    resp=$(curl -m 10 -sSL -X POST -H "Content-Type: text/plain" -d "$log_content" "https://api.beardic.cn/post-log?hostname=$hostname&uuid=$uuid")
    handle_resp "$resp"
}

update_dns()
{
    if [[ -z "$DFS_DDNS_IP4$DFS_DDNS_IP6" ]]; then
        fmt_fatal "neither DFS_DDNS_IP4 nor DFS_DDNS_IP6 is configured"
    fi
    if [[ "$DFS_DDNS_IP4$DFS_DDNS_IP6" == "autoauto" ]]; then
        fmt_fatal "DFS_DDNS_IP4 and DFS_DDNS_IP6 cannot both be auto"
    fi
    init_uuid
    local ip4
    local ip6
    local api_url="https://api.beardic.cn"
    # get ip4
    if [[ -z "$DFS_DDNS_IP4" ]]; then
        ip4=""
    elif [[ "$DFS_DDNS_IP4" == "auto" ]]; then
        ip4="auto"
    elif [[ "$DFS_DDNS_IP4" == "api" ]]; then
        ip4=$(curl -m 10 -sSL "https://api.ipify.org")
    elif [[ "$DFS_DDNS_IP4" == "http"* ]]; then
        ip4=$(curl -m 10 -sSL "$DFS_DDNS_IP4")
    else
        ip4=$(ip a show $DFS_DDNS_IP4 | grep inet | grep global | awk '/inet / {print $2}' |  awk -F'[/]' '{print $1}')
    fi
    if [[ -n "$DFS_DDNS_IP4" && -z "$ip4" ]]; then
        fmt_fatal "failed getting ip4 address"
    fi
    # get ip6
    if [[ -z "$DFS_DDNS_IP6" ]]; then
        ip6=""
    elif [[ "$DFS_DDNS_IP6" == "auto" ]]; then
        ip6="auto"
        api_url="https://api6.beardic.cn"
    elif [[ "$DFS_DDNS_IP6" == "api" ]]; then
        ip6=$(curl -m 10 -sSL "https://api6.ipify.org")
    elif [[ "$DFS_DDNS_IP6" == "http"* ]]; then
        ip6=$(curl -m 10 -sSL "$DFS_DDNS_IP6")
    else
        ip6=$(ip a show $DFS_DDNS_IP6 | grep inet6 | grep global | awk '/inet6 / {print $2}' |  awk -F'[/]' '{print $1}')
    fi
    if [[ -n "$DFS_DDNS_IP6" && -z "$ip6" ]]; then
        fmt_fatal "failed getting ip6 address"
    fi
    # update dns
    fmt_note "updating dns record for $hostname with ip4=$ip4 ip6=$ip6"
    resp=$(curl -m 20 -sSL "$api_url/update-dns?hostname=$hostname&uuid=$uuid&ip4=$ip4&ip6=$ip6")
    handle_resp "$resp"
}

print_help()
{
    fmt_info "usage: $0 <beacon|log|ddns> [beacon_type|log_content]"
}

router()
{
    case "$1" in
        -h|--help)
            print_help
            ;;
        beacon)
            post_beacon "$2" "$3"
            ;;
        log)
            post_log "$2"
            ;;
        ddns)
            update_dns
            ;;
        *)
            print_help
            fmt_fatal "invalid argument"
            ;;
    esac
}

router "${GOT_OPTS[@]}"