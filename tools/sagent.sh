#!/bin/bash
set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
export DFS_COLOR=1
source "$THIS_DIR/common.sh"


find_so_file()
{
    local SO_PATHS=( "/usr/lib64/opensc-pkcs11.so" "/usr/local/lib/opensc-pkcs11.so" )
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
    local SO_FILE=$(find_so_file)
    if [[ -n "$SO_FILE" ]]; then
        fmt_note "opensc-pkcs11.so found"
        SO_FILE="-P $SO_FILE"
    fi
    ssh-agent $SO_FILE
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
    local agent_file="/tmp/piv-agent-$(whoami)"
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