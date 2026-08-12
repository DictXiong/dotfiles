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
    return 1
}

create_agent()
{
    local IFS=","
    ssh-agent -P "${SO_PATHS[*]},/nix/store/*"
}

kill_agent()
{
    local status
    if pgrep -u "$EUID" -x ssh-agent > /dev/null; then
        fmt_note "stopping existing ssh-agent"
        if pkill -TERM -u "$EUID" -x ssh-agent; then
            :
        else
            status=$?
            [[ $status -eq 1 ]] || return "$status"
        fi
    fi
    if command -v gpgconf > /dev/null 2>&1; then
        fmt_note "stopping gpg-agent if running"
        gpgconf --kill gpg-agent
    fi
    unset SSH_AUTH_SOCK SSH_AGENT_PID
    echo unset SSH_AUTH_SOCK SSH_AGENT_PID
}

add_piv()
{
    local SO_FILE
    if ! SO_FILE=$(find_so_file); then
        fmt_error "opensc-pkcs11.so not found"
        return 1
    fi
    printf 'ssh-add -s %q\n' "$SO_FILE"
    list
}

add_id25519_with_op()
{
    local status
    if SSH_ASKPASS_REQUIRE=force SSH_ASKPASS="$THIS_DIR/sagent-op.sh" timeout 60s ssh-add "$HOME/.ssh/id_ed25519"; then
        list
        return
    else
        status=$?
    fi

    if [[ $status -eq 124 ]]; then
        fmt_fatal "timed out when adding the key"
    else
        fmt_fatal "failed to add the key (ssh-add exit $status); check the key, agent, and 1Password CLI"
    fi
}

list()
{
    echo echo "available keys:"
    echo ssh-add -l
}

configured_pinentry()
{
    local agent_conf
    local agent_confs=()
    for agent_conf in "$@"; do
        [[ -f "$agent_conf" ]] && agent_confs+=("$agent_conf")
    done
    [[ ${#agent_confs[@]} -gt 0 ]] || return 1

    awk '
        /^[[:space:]]*#/ { next }
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            if (line ~ /^pinentry-program([[:space:]]|=)/) {
                sub(/^pinentry-program[[:space:]=]*/, "", line)
                sub(/[[:space:]]*$/, "", line)
                pinentry = line
            }
        }
        END {
            if (pinentry == "") exit 1
            print pinentry
        }
    ' "${agent_confs[@]}"
}

check_pinentry()
{
    local gnupg_home
    local gpg_sysconfdir
    local agent_conf
    local system_agent_conf
    local pinentry
    local gpg_bindir
    local candidate

    gnupg_home=$(gpgconf --list-dirs homedir)
    gpg_sysconfdir=$(gpgconf --list-dirs sysconfdir)
    agent_conf="$gnupg_home/gpg-agent.conf"
    system_agent_conf="$gpg_sysconfdir/gpg-agent.conf"
    if pinentry=$(configured_pinentry "$system_agent_conf" "$agent_conf"); then
        if [[ "$pinentry" == "~/"* ]]; then
            pinentry="$HOME/${pinentry#\~/}"
        fi
        if [[ -x "$pinentry" ]]; then
            return
        fi
        fmt_warning "configured pinentry is not executable: $pinentry"
    else
        gpg_bindir=$(gpgconf --list-dirs bindir)
        if [[ -x "$gpg_bindir/pinentry" || -x "$gpg_bindir/pinentry-basic" ]]; then
            return
        fi
    fi

    for candidate in \
        "$(command -v pinentry-curses 2>/dev/null || true)" \
        "$(command -v pinentry 2>/dev/null || true)" \
        "$(command -v pinentry-tty 2>/dev/null || true)"; do
        [[ -n "$candidate" && -x "$candidate" ]] && break
        candidate=""
    done

    if [[ -n "$candidate" ]]; then
        fmt_warning "gpg-agent has no usable pinentry; add 'pinentry-program $candidate' to $agent_conf"
    else
        fmt_warning "gpg-agent has no usable pinentry; install one and configure pinentry-program in $agent_conf"
    fi
}

use_gpg_agent()
{
    command -v gpgconf > /dev/null 2>&1 || fmt_fatal "gpgconf not found"
    command -v gpg-connect-agent > /dev/null 2>&1 || fmt_fatal "gpg-connect-agent not found"

    check_pinentry

    local current_tty
    current_tty=$(tty) || fmt_fatal "unable to determine the current TTY"
    export GPG_TTY="$current_tty"

    gpgconf --launch gpg-agent
    gpg-connect-agent updatestartuptty /bye > /dev/null

    local agent_socket
    agent_socket=$(gpgconf --list-dirs agent-ssh-socket)
    if [[ -z "$agent_socket" || ! -S "$agent_socket" ]]; then
        fmt_fatal "gpg-agent SSH socket not found; add 'enable-ssh-support' to ~/.gnupg/gpg-agent.conf and restart gpg-agent"
    fi

    fmt_note "using gpg-agent: $agent_socket"
    echo unset SSH_AGENT_PID
    printf 'export GPG_TTY=%q\n' "$current_tty"
    printf 'export SSH_AUTH_SOCK=%q\n' "$agent_socket"
}

read_agent_file()
{
    local agent_file="$1"
    local line
    local agent_socket=""
    local agent_pid=""

    while IFS= read -r line; do
        case "$line" in
            SSH_AUTH_SOCK=*)
                agent_socket=${line#SSH_AUTH_SOCK=}
                agent_socket=${agent_socket%%;*}
                ;;
            SSH_AGENT_PID=*)
                agent_pid=${line#SSH_AGENT_PID=}
                agent_pid=${agent_pid%%;*}
                ;;
        esac
    done < "$agent_file"

    [[ -n "$agent_socket" && "$agent_pid" =~ ^[1-9][0-9]*$ ]] || return 1
    export SSH_AUTH_SOCK="$agent_socket"
    export SSH_AGENT_PID="$agent_pid"
}

agent_is_usable()
{
    [[ -S "$SSH_AUTH_SOCK" ]] || return 1
    ps -p "$SSH_AGENT_PID" -o uid= -o comm= 2>/dev/null |
        awk -v uid="$EUID" '$1 == uid && $2 ~ /(^|\/)ssh-agent$/ { found=1 } END { exit !found }' || return 1

    local status
    if ssh-add -l > /dev/null 2>&1; then
        status=0
    else
        status=$?
    fi
    [[ $status -eq 0 || $status -eq 1 ]]
}

print_agent_env()
{
    printf 'export SSH_AUTH_SOCK=%q\n' "$SSH_AUTH_SOCK"
    printf 'export SSH_AGENT_PID=%q\n' "$SSH_AGENT_PID"
}

reset()
{
    kill_agent
    all already-killed
}

all()
{
    local mode="${1:-}"
    mkdir -p "$HOME/.ssh"
    local agent_file="$HOME/.ssh/agent-$(whoami)"
    [[ ! -L "$agent_file" ]] || fmt_fatal "refusing to use symlink as agent file: $agent_file"
    unset SSH_AUTH_SOCK SSH_AGENT_PID

    if [[ "$mode" != "already-killed" && -f "$agent_file" ]]; then
        chmod 600 "$agent_file"
        read_agent_file "$agent_file" || true
    else
        touch "$agent_file"
        chmod 600 "$agent_file"
    fi

    if ! agent_is_usable; then
        if [[ "$mode" != "already-killed" ]]; then
            kill_agent
        fi
        fmt_note "launching a new agent"
        local agent_output
        if ! agent_output=$(create_agent); then
            fmt_fatal "failed to launch ssh-agent"
        fi
        printf '%s\n' "$agent_output" > "$agent_file"
        chmod 600 "$agent_file"
        read_agent_file "$agent_file" || fmt_fatal "ssh-agent returned invalid environment data"
        agent_is_usable || fmt_fatal "new ssh-agent is not usable"
    else
        fmt_note "using existing agent: $SSH_AGENT_PID"
    fi
    print_agent_env
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
        gpg)
            use_gpg_agent
            ;;
        reset)
            reset
            ;;
        list|ls)
            list
            ;;
        *)
            fmt_error "unknown command: $1"
            return 1
            ;;
    esac
}

route "$@"
