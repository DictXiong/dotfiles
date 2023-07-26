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
    local key value
    for i in "${DFS_CONFIGS[@]}"; do
        if [[ "$i" == *"="* ]]; then
            key=${i%%=*}
            value=${i#*=}
        else
            key=$i
            value=$(eval echo \$$key)
        fi
        HOME_FILES_PATH+=(".config/dotfiles/env")
        HOME_FILES_CONTENT+=("$key=$value")
        echo -n "$key=$value "
        export $key=$value
    done
    echo
}

append_hist()
{
    fmt_note "appending zsh history ..."
    "$DOTFILES/tools/append_zsh_hist.sh" "$@"
}

install_file_content()
{
    fmt_note "installing file content ..."
    for ((i=0; i<${#HOME_FILES_PATH[@]}; i++)); do
        local filename="$HOME/${HOME_FILES_PATH[$i]}"
        local content="${HOME_FILES_CONTENT[$i]}"
        fmt_info "installing \"$content\" into \"$filename\" ..."
        mkdir -p $(dirname "$filename")
        if [ ! -f "$filename" ]; then
            touch $filename
        fi
        grep -qxF -- "$content" "$filename" || echo "$content" >> "$filename"
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
            grep -vxF -- "$content" "$filename" | tee "$filename"
        fi
    done
}

install_symlink()
{
    fmt_note "installing symlinks ..."
    for ((i=0; i<${#HOME_SYMLINKS_SRC[@]}; i++)); do
        local src="$DOTFILES/${HOME_SYMLINKS_SRC[$i]}"
        local dst="$HOME/${HOME_SYMLINKS_DST[$i]}"
        fmt_info "creating symlink \"$dst\" --> \"$src\" ..."
        if [ ! -f "$src" ]; then
            fmt_error "\"$src\" does not exist! aborting this job ..."
            continue
        fi
        mkdir -p $(dirname "$dst")
        if [ -f "$dst" ]; then
            if [ "$(readlink $dst)" -ef "$src" ]; then
                continue
            fi
            fmt_warning "\"$dst\" already exists! stat output:"
            echo ----------
            stat $dst
            echo ----------
            yn=$(ask_for_yN "would you like to replace ${dst}?")
            if [[ "$yn" == "1" ]]; then
                rm $dst
            else
                fmt_error "aborting this job ..."
                continue
            fi
        fi
        ln -s $src $dst
    done
}

uninstall_symlink()
{
    fmt_note "uninstalling symlinks ..."
    local src
    for src in "${!HOME_SYMLINKS[@]}"; do
        local dst=${HOME_SYMLINKS[$src]}
        src="$DOTFILES/$src"
        dst="$HOME/$dst"
        if [ "$(readlink $dst)" -ef "$src" ]; then
            fmt_info "removing symlink \"$dst\" ..."
            echo ----------
            stat $dst
            echo ----------
            rm $dst
        fi
    done
}

install_crontab()
{
    if [[ -x $(command -v crontab) ]]; then
        fmt_note "installing \"$CRON_JOB\" to crontab ..."
        if ! crontab -l 1>/dev/null 2>&1; then
            echo -n | crontab -
        fi
        ( crontab -l | grep -vxF "${CRON_JOB}" | grep -v "no crontab for"; echo "$CRON_JOB" ) | crontab -
    else
        fmt_warning "crontab does not exist. skipping ..."
    fi
}

uninstall_crontab()
{
    if [[ -x $(command -v crontab) ]]; then
        fmt_note "removing \"$CRON_JOB\" from crontab ..."
        ( crontab -l | grep -vxF "$CRON_JOB" ) | crontab -
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
    fmt_note "running update.sh ..."
    set +e
    DFS_UPDATED_RET=85 ${DOTFILES}/update.sh
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
    rm "${DOTFILES}/update.sh"
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
for i in ${GOT_OPTS[@]}; do
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
        * ) fmt_fatal "unknown option \"$i\"" ;;
    esac
done
$FUNC
