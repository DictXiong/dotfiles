#!/usr/bin/env bash
set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/tools/common.sh"


if [[ ! "$DOTFILES" == "${HOME}"* ]]; then 
    fmt_fatal "\"$DOTFILES\" is not under \"$HOME\". aborting ..."
fi
DOTFILE_TILDE=${DOTFILES/"$HOME"/\~}

CRON_JOB="0 * * * * ${DOTFILES}/update.sh"
declare -a DFS_CONFIGS
declare -a HOME_FILES_PATH
declare -a HOME_FILES_CONTENT
HOME_FILES_PATH[0]=".zshrc"
HOME_FILES_CONTENT[0]="source ${DOTFILE_TILDE}/.zshrc2"
HOME_FILES_PATH[1]=".tmux.conf"
HOME_FILES_CONTENT[1]="source-file ${DOTFILE_TILDE}/.tmux.conf2"
HOME_FILES_PATH[2]=".vimrc"
HOME_FILES_CONTENT[2]="source ${DOTFILE_TILDE}/.vimrc2"
HOME_FILES_PATH[3]=".gitconfig"
HOME_FILES_CONTENT[3]="[include] path = \"${DOTFILE_TILDE}/.gitconfig2\""

declare -a HOME_SYMLINKS_SRC
declare -a HOME_SYMLINKS_DST
HOME_SYMLINKS_SRC[0]=".ssh/authorized_keys2"
HOME_SYMLINKS_DST[0]=".ssh/authorized_keys2"
HOME_SYMLINKS_SRC[1]=".eid/authorized_certificates"
HOME_SYMLINKS_DST[1]=".eid/authorized_certificates"

install_dependencies()
{
    local ret=0
    fmt_note "installing dependencies ..."
    set +e
    case $(get_os_name) in
        "ubuntu"|"debian" )
            $SUDOE "$DOTFILES/tools/ubuntu.sh" apt-install
            ret=$?
            ;;
        "alpine" )
            $SUDOE "$DOTFILES/tools/alpine.sh" apk-add
            ret=$?
            ;;
        "macos" )
            "$DOTFILES/tools/macos.sh" brew-install
            ret=$?
            ;;
        "msys" )
            "$DOTFILES/tools/msys2.sh" pacman-S
            ret=$?
            ;;
        * ) fmt_error "dfs auto-install is not implemented on OS: $(get_os_name). skipping ..."
    esac
    set -e
    if [[ "$ret" != "0" ]]; then
        fmt_error "failed to install dependencies."
    fi
}

preinstall_check()
{
    fmt_note "checking requirements ..."
    local mandatory_commands=( "git" "zsh" "curl" "grep" "cat" "cp" "bash" "mkdir" )
    local optional_commands=( "vim" "tmux" "ping" )
    for i in "${mandatory_commands[@]}"; do
        if ! command -v $i 1>/dev/null; then
            fmt_info "all this utils are required: ${mandatory_commands[@]}"
            fmt_info "install them manually or check scripts in tools/"
            fmt_fatal "\"$i\" not found. aborting ..."
        fi
    done
    for i in "${optional_commands[@]}"; do
        if ! command -v $i 1>/dev/null; then
            fmt_warning "\"$i\" not found"
            yn=$(ask_for_Yn "continue anyway?")
            if [[ "$yn" == "0" ]]; then
                fmt_info "all this utils are suggested: ${optional_commands[@]}"
                fmt_info "install them manually or check scripts in tools/"
                fmt_fatal "aborting ..."
            fi
        fi
    done
}

prepare_config()
{
    local remote=$(cd "$DOTFILES" && git remote get-url origin)
    if [[ -z "$DFS_NO_WALL" && $remote == *github* ]]; then
        DFS_CONFIGS+=("DFS_NO_WALL=1")
    fi
    if [[ ${#DFS_CONFIGS[@]} == 0 ]]; then
        return
    fi
    fmt_note "preparing dotfiles configurations ..."
    local key value assignment
    for i in "${DFS_CONFIGS[@]}"; do
        if [[ "$i" == *"="* ]]; then
            key=${i%%=*}
            value=${i#*=}
        else
            key=$i
        fi
        [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || fmt_fatal "invalid configuration key \"$key\""
        if [[ "$i" != *"="* ]]; then value=${!key}; fi
        printf -v assignment '%s=%q' "$key" "$value"
        HOME_FILES_PATH+=(".config/dotfiles/env")
        HOME_FILES_CONTENT+=("$assignment")
        printf '%s ' "$assignment"
        export "$key=$value"
    done
    echo
}

append_hist()
{
    fmt_note "appending zsh history ..."
    "$DOTFILES/tools/append_zsh_hist.sh" "$@"
}

config_file_target()
{
    local filename=$1 target links=0
    while [[ -L "$filename" ]]; do
        ((links+=1))
        [[ $links -le 40 ]] || fmt_fatal "too many symlinks resolving \"$1\""
        target=$(readlink "$filename") || return
        if [[ "$target" == /* ]]; then
            filename=$target
        else
            filename="$(dirname "$filename")/$target"
        fi
    done
    printf '%s\n' "$filename"
}

rewrite_config_file()
(
    local filename=$1 content=$2 action=$3
    local temporary line ending link_count backup="" write_pending=0
    filename=$(config_file_target "$filename") || exit 1
    temporary=$(mktemp "${filename}.XXXXXXXX")
    cleanup_config_write()
    {
        local status=$?
        trap - EXIT
        trap '' HUP INT TERM
        if [[ "$write_pending" == 1 ]]; then
            if cat "$backup" > "$filename"; then
                write_pending=0
            else
                fmt_error "could not restore \"$filename\"; original content remains in \"$backup\""
            fi
        fi
        if [[ "$write_pending" == 0 && -n "$backup" ]]; then rm -f -- "$backup"; fi
        rm -f -- "$temporary"
        exit "$status"
    }
    trap cleanup_config_write EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    cp -p -- "$filename" "$temporary"
    # Read each complete or partial line so unrelated content keeps its original
    # final newline, permissions, and symlink target.
    while true; do
        ending=$'\n'
        if ! IFS= read -r line; then
            ending=""
            [[ -n "$line" ]] || break
        fi
        if [[ "$action" != append && "$line" == "$content" ]]; then continue; fi
        printf '%s%s' "$line" "$ending"
    done < "$filename" > "$temporary"
    if [[ "$action" != uninstall ]]; then
        if [[ -s "$temporary" && -n "$(tail -c 1 "$temporary")" ]]; then
            printf '\n' >> "$temporary"
        fi
        printf '%s\n' "$content" >> "$temporary"
    fi
    if cmp -s -- "$temporary" "$filename"; then return 0; fi
    link_count=$(stat -c '%h' "$filename" 2>/dev/null) || link_count=$(stat -f '%l' "$filename")
    [[ "$link_count" =~ ^[1-9][0-9]*$ ]] || fmt_fatal "cannot determine hard-link count for \"$filename\""
    if (( link_count > 1 )); then
        # Replacing the inode would split existing hard links. Keep a complete
        # backup until the in-place write has succeeded or been restored.
        backup=$(mktemp "${filename}.backup.XXXXXXXX")
        cp -p -- "$filename" "$backup"
        write_pending=1
        cat "$temporary" > "$filename"
        write_pending=0
    else
        mv -f -- "$temporary" "$filename"
    fi
)

install_file_content()
{
    fmt_note "installing file content ..."
    for ((i=0; i<${#HOME_FILES_PATH[@]}; i++)); do
        local filename="$HOME/${HOME_FILES_PATH[$i]}"
        local content="${HOME_FILES_CONTENT[$i]}"
        fmt_info "installing \"$content\" into \"$filename\" ..."
        mkdir -p "$(dirname "$filename")"
        if [ ! -f "$filename" ]; then
            touch "$filename"
        fi
        if [[ "${HOME_FILES_PATH[$i]}" == .config/dotfiles/env ]]; then
            # The env file can contain multiline values and arbitrary shell
            # blocks. Appending lets the requested value win without parsing or
            # removing existing shell code, including a repeated older value.
            rewrite_config_file "$filename" "$content" append
        elif ! grep -qxF -- "$content" "$filename"; then
            rewrite_config_file "$filename" "$content" install
        fi
    done
}

uninstall_file_content()
{
    fmt_note "uninstalling file content ..."
    for ((i=0; i<${#HOME_FILES_PATH[@]}; i++)); do
        local filename="$HOME/${HOME_FILES_PATH[$i]}"
        local content=${HOME_FILES_CONTENT[$i]}
        fmt_info "removing \"$content\" from \"$filename\" ..."
        if [ -f "$filename" ]; then
            rewrite_config_file "$filename" "$content" uninstall
        fi
    done
}

install_symlink()
{
    fmt_note "installing symlinks ..."
    for ((i=0; i<${#HOME_SYMLINKS_SRC[@]}; i++)); do
        if [[ -z "${HOME_SYMLINKS_SRC[$i]}" ]]; then
            continue
        fi
        local src="$DOTFILES/${HOME_SYMLINKS_SRC[$i]}"
        local dst="$HOME/${HOME_SYMLINKS_DST[$i]}"
        fmt_info "creating symlink \"$dst\" --> \"$src\" ..."
        if [ ! -f "$src" ]; then
            fmt_error "\"$src\" does not exist! aborting this job ..."
            continue
        fi
        mkdir -p "$(dirname "$dst")"
        if [[ -e "$dst" || -L "$dst" ]]; then
            if [[ -L "$dst" && "$dst" -ef "$src" ]]; then
                continue
            fi
            fmt_warning "\"$dst\" already exists! stat output:"
            echo ----------
            stat "$dst"
            echo ----------
            yn=$(ask_for_yN "would you like to replace ${dst}?")
            if [[ "$yn" == "1" ]]; then
                rm "$dst"
            else
                fmt_error "aborting this job ..."
                continue
            fi
        fi
        ln -s "$src" "$dst"
    done
}

uninstall_symlink()
{
    fmt_note "uninstalling symlinks ..."
    local i src dst
    for i in "${!HOME_SYMLINKS_SRC[@]}"; do
        src="$DOTFILES/${HOME_SYMLINKS_SRC[$i]}"
        dst="$HOME/${HOME_SYMLINKS_DST[$i]}"
        if [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" || "$dst" -ef "$src" ]]; then
            fmt_info "removing symlink \"$dst\" ..."
            echo ----------
            stat "$dst"
            echo ----------
            rm "$dst"
        fi
    done
}

install_crontab()
{
    if [[ -x $(command -v crontab) ]]; then
        fmt_note "installing \"$CRON_JOB\" to crontab ..."
        if [[ -z "$(crontab -l 2>/dev/null || true)" ]]; then
            echo "$CRON_JOB" | crontab -
        elif !( crontab -l | grep -qxF "${CRON_JOB}"); then
            ( crontab -l; echo "$CRON_JOB" ) | crontab -
        fi
    else
        fmt_warning "crontab does not exist. skipping ..."
    fi
}

uninstall_crontab()
{
    local existing
    if [[ -x $(command -v crontab) ]]; then
        fmt_note "removing \"$CRON_JOB\" from crontab ..."
        existing=$(crontab -l 2>/dev/null) || return 0
        printf '%s\n' "$existing" | grep -vxF "$CRON_JOB" | crontab -
    else
        fmt_note "crontab does not exist. skipping ..."
    fi
}

install_tmux_tpm()
{
    TMUX_TPM="$HOME/.tmux/plugins/tpm"
    if [[ -x $(command -v tmux) && ! -d "$TMUX_TPM" ]]; then
        fmt_note "installing tmux tpm ..."
        git clone https://gitee.com/dictxiong/tpm "$TMUX_TPM"
        if [[ -x $(command -v g++) && -x $(command -v cmake) && -x $(command -v make) ]]; then
            if [[ -z "$DFS_LITE" || "$DFS_LITE" == "0" ]]; then
                fmt_note "initializing tmux plugins ..."
                ~/.tmux/plugins/tpm/bin/install_plugins
            else
                fmt_warning "in lite mode, tmux plugins are downloaded but not complied"
                fmt_info "try <prefix + I> or ~/.tmux/plugins/tpm/bin/install_plugins to complie manually"
            fi
        else
            fmt_warning "pls install g++,cmake,make and then init tmux plugins by <prefix + I> or ~/.tmux/plugins/tpm/bin/install_plugins"
        fi
    fi
}

install_vim_vundle()
{
    VIM_VUNDLE="$HOME/.vim/bundle/Vundle.vim"
    if [[ -x $(command -v vim) && ! -d "$VIM_VUNDLE" ]]; then
        fmt_note "installing vim vundle ..."
        git clone https://gitee.com/dictxiong/Vundle.vim "$VIM_VUNDLE"
        fmt_note "initializing vim plugins ..."
        echo | vim +PluginInstall +qall
    fi
}

install_update()
{
    fmt_note "installing update.sh ..."
    cp "${DOTFILES}/.update.sh" "${DOTFILES}/update.sh"
    chmod +x "${DOTFILES}/update.sh"
    local ignore_commit_sign=${DFS_IGNORE_COMMIT_SIGN:-0}
    if [[ "$ignore_commit_sign" != 1 ]] && ! command -v gpg >/dev/null; then
        fmt_warning "gpg not found. Updating without signature checks for this installation."
        fmt_warning "For future updates, install GnuPG or set DFS_IGNORE_COMMIT_SIGN=1 in ~/.config/dotfiles/env."
        ignore_commit_sign=1
    fi
    fmt_note "running update.sh ..."
    set +e
    DFS_IGNORE_COMMIT_SIGN="$ignore_commit_sign" DFS_UPDATED_RET=85 "${DOTFILES}/update.sh"
    RET=$?
    if [[ $RET == 85 ]]; then
        fmt_note "dfs updated. re-running install.sh ..."
        "${DOTFILES}/install.sh" "${ORIGIN_ARGS[@]}" && exit
    elif [[ $RET != 0 ]]; then
        fmt_fatal "update.sh failed with exit code $RET"
    fi
    set -e
}

uninstall_update()
{
    fmt_note "removing update.sh ..."
    rm -f "${DOTFILES}/update.sh"
}

install()
{
    if [[ "$INSTALL_DEP" == "1" ]]; then install_dependencies; fi
    prepare_config
    install_update
    preinstall_check
    install_crontab
    install_file_content
    install_symlink
    apost_beacon "dfs.installed"
    # those that won't be uninstalled in the future
    install_tmux_tpm
    install_vim_vundle
    if [[ -n "$DFS_HIST" ]]; then append_hist "$DFS_HIST"; fi
    fmt_note "done installing!"
}

uninstall()
{
    yn=$(ask_for_yN "do you really want to uninstall?")
    if [[ "$yn" != "1" ]]; then
        fmt_fatal "aborting this job ..."
    fi
    uninstall_update
    uninstall_crontab
    uninstall_file_content
    uninstall_symlink
    apost_beacon "dfs.uninstalled"
    fmt_note "done uninstalling!"
}

echo "this is the dotfiles installer, version $(cd "$DOTFILES" && git describe --tags --always --dirty)"
echo "install options:" "${GOT_OPTS[@]}"
FUNC=install
INSTALL_DEP=0
store_config=0
store_hist=0
for i in "${GOT_OPTS[@]}"; do
    if [[ "$store_config" == "1" ]]; then
        store_config=0
        DFS_CONFIGS+=("$i")
        continue
    fi
    if [[ "$store_hist" == "1" ]]; then
        store_hist=0
        DFS_HIST=$i
        continue
    fi
    case $i in
        -i ) FUNC=install ;;
        -r ) FUNC=uninstall ;;
        -a|--auto ) INSTALL_DEP=1 ;;
        -H|--hist|--history ) store_hist=1 ;;
        -x ) store_config=1 ;;
        --no-auth-info ) HOME_SYMLINKS_SRC=(); HOME_SYMLINKS_DST=() ;;
        * ) fmt_fatal "unknown option \"$i\"" ;;
    esac
done
[[ "$store_config" == 0 ]] || fmt_fatal "option -x requires a configuration key or KEY=VALUE"
[[ "$store_hist" == 0 ]] || fmt_fatal "option -H requires a history key"
if [[ "$DFS_DRY_RUN" == 1 ]]; then
    if [[ "$FUNC" == install ]]; then prepare_config; fi
    fmt_note "dry run: $FUNC dotfiles"
    if [[ "$FUNC" == install && "$INSTALL_DEP" == 1 ]]; then fmt_info "would install dependencies"; fi
    fmt_info "would $FUNC ${DOTFILES}/update.sh and crontab entry $CRON_JOB"
    for i in "${!HOME_FILES_PATH[@]}"; do
        fmt_info "would $FUNC ${HOME_FILES_CONTENT[$i]} in $HOME/${HOME_FILES_PATH[$i]}"
    done
    for i in "${!HOME_SYMLINKS_SRC[@]}"; do
        fmt_info "would $FUNC link $HOME/${HOME_SYMLINKS_DST[$i]} to $DOTFILES/${HOME_SYMLINKS_SRC[$i]}"
    done
    if [[ "$FUNC" == install ]]; then fmt_info "would install tmux/Vim plugins and import requested history"; fi
    exit 0
fi
$FUNC
