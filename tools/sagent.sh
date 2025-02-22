#!/usr/bin/env bash
set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
export DFS_COLOR=1
source "$THIS_DIR/common.sh"


SO_PATHS=(
    "/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so"  # ubuntu 22.04
    "/run/current-system/sw/lib/opensc-pkcs11.so"  # nixos 23.05
    "/Library/OpenSC/lib/opensc-pkcs11.so"  # macos 13.4
)

find_so_file()
{
    local SO_FILE
    for SO_FILE in ${SO_PATHS[*]}; do
        if [[ -f "$SO_FILE" ]]; then
            echo "$SO_FILE"
            return
        fi
    done
}

create_agent()
{
    local IFS=","
    ssh-agent -P "${SO_PATHS[*]},/nix/store/*"
}

kill_agent()
{
    if pgrep -x ssh-agent > /dev/null; then
        fmt_note "killing existing agent"
        pkill -9 -x ssh-agent
    fi
}

add_piv()
{
    local SO_FILE=$(find_so_file)
    if [[ -n "$SO_FILE" ]]; then
        echo ssh-add -s \"$SO_FILE\"
    else
        fmt_error "opensc-pkcs11.so not found"
    fi
    list
}

add_id25519_with_op()
{
    SSH_ASKPASS_REQUIRE=force SSH_ASKPASS="$THIS_DIR/sagent-op.sh" timeout 30s ssh-add ~/.ssh/id_ed25519 || fmt_fatal "timed out when adding the key. probably the passphrase is wrong"
    list
}

list()
{
    echo echo "available keys:"
    echo ssh-add -l
}

reset()
{
    kill_agent
    all
}

all()
{
    test -d ~/.ssh || mkdir ~/.ssh
    local agent_file=~/.ssh/agent-$(whoami)
    if [[ -f $agent_file ]]; then
        source $agent_file > /dev/null
    else
        touch $agent_file
        chmod 600 $agent_file
    fi
    if ! ps -p "$SSH_AGENT_PID" 1>/dev/null 2>&1; then
        kill_agent
        fmt_note "launching a new agent"
        create_agent | tee $agent_file
    else
        fmt_note "using existing agent: $SSH_AGENT_PID"
        cat $agent_file
    fi
}

route()
{
    os_type="$(get_os_type)"
    if [[ "$os_type" == "msys" || "$os_type" == "cygwin" ]]; then
        fmt_fatal "unsupported platform: $os_type. you may use WinCryptSSHAgent."
    fi
    if [[ $# -eq 0 ]]; then
        all
        return
    fi
    case $1 in
        kill)
            kill_agent
            ;;
        piv)
            add_piv
            ;;
        op)
            add_id25519_with_op
            ;;
        reset)
            reset
            ;;
        list|ls)
            list
            ;;
        *)
            fmt_error "unknown command: $1"
            ;;
    esac
}

route "$@"
