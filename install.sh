#!/bin/bash

THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/tools/common.sh"

home_slashes=${HOME//\//\\\/}
if [[ ! $DOTFILES == ${home_slashes}* ]]; then 
    fmt_fatal "\"$DOTFILES\" is not under \"$HOME\". aborting ..."
fi
dotfile_home_path=${DOTFILES/${home_slashes}/\~}
dotfile_relative_path=${DOTFILES#${home_slashes}\/}
crontab_job="0 * * * * ${DOTFILES}/update.sh"

insert_if_not_exist()
{
    filename=$1
    line=$2
    fmt_note "installing \"$line\" into \"$filename\" ..."
    mkdir -p $(dirname "$filename")
    if [ ! -f "$filename" ]; then
        touch $filename
    fi
    grep -qxF -- "$line" "$filename" || echo "$line" >> "$filename"
}

delete_if_exist()
{
    filename=$1
    line=$2
    fmt_note "removing \"$line\" from \"$filename\" ..."
    if [ -f "$filename" ]; then
        grep -vxF -- "$line" "$filename" | tee "$filename"
    fi
}

create_symlink()
{
    src=$1
    dest=$2
    fmt_note "creating symlink \"$dest\" --> \"$src\" ..."
    if [ ! -f "$src" ]; then
        fmt_error "\"$src\" does not exist! aborting this job ..."
        return 1
    fi
    mkdir -p $(dirname "$dest")
    if [ -f "$dest" ]; then
        if [ "$(readlink $dest)" -ef "$src" ]; then
            return 0
        fi
        fmt_warning "\"$dest\" already exists! stat output:"
        echo ----------
        stat $dest
        echo ----------
        ask_for_yN "would you like to replace ${dest}?"
        if [ $? -eq 1 ]; then 
            rm $dest
        else
            fmt_error "\"$dest\" already exists! aborting this job ..."
            return 1
        fi
    fi
    ln -s $src $dest
    return $?
}

delete_link_if_match()
{
    src=$1
    dest=$2
    if [ "$(readlink $dest)" -ef "$src" ]; then
        fmt_note "removing symlink \"$dest\" ..."
        echo ----------
        stat $dest
        echo ----------
        rm $dest
    fi
}

install_crontab(){
    fmt_note "installing \"$crontab_job\" to crontab ..."
    ( crontab -l | grep -vxF "${crontab_job}" | grep -v "no crontab for"; echo "$crontab_job" ) | crontab -
}

uninstall_crontab(){
    fmt_note "removing \"$crontab_job\" from crontab ..."
    ( crontab -l | grep -vxF "$crontab_job" ) | crontab - 
}

install_tmux_tpm(){
    TMUX_TPM="$HOME/.tmux/plugins/tpm"
    if [[ -x $(command -v tmux) && ! -d "$TMUX_TPM" ]]; then
        fmt_note "installing tmux tpm ..."
        git clone https://gitee.com/dictxiong/tpm "$TMUX_TPM"
        if [[ -x $(command -v g++) && -x $(command -v cmake) && -x $(command -v make) ]]; then
            fmt_note "initializing tmux plugins ..."
            if [[ -z "$DFS_NO_COMPILE" ]]; then
                ~/.tmux/plugins/tpm/bin/install_plugins
            fi
        else
            fmt_warning "pls install g++,cmake,make and then init tmux plugins by <prefix + I> or ~/.tmux/plugins/tpm/bin/install_plugins"
        fi
    fi
}

install_vim_vundle(){
    VIM_VUNDLE="$HOME/.vim/bundle/Vundle.vim"
    if [[ -x $(command -v vim) && ! -d "$VIM_VUNDLE" ]]; then
        fmt_note "installing vim vundle ..."
        git clone https://gitee.com/dictxiong/Vundle.vim "$VIM_VUNDLE"
        fmt_note "initializing vim plugins ..."
        if [[ -z "$DFS_NO_COMPLIE" ]]; then
            vim +PluginInstall +qall
        fi
    fi
}

install_update(){
    fmt_note "installing update.sh ..."
    cp "${DOTFILES}/.update.sh" "${DOTFILES}/update.sh"
    chmod +x "${DOTFILES}/update.sh"
    if [[ -z "$DFS_NO_UPDATE" ]]; then
        fmt_note "running update.sh ..."
        ${DOTFILES}/update.sh
    fi
}

uninstall_update(){
    fmt_note "removing update.sh ..."
    rm "${DOTFILES}/update.sh"
}

install(){
    install_update
    install_crontab
    insert_if_not_exist "${HOME}/.zshrc" "source ${dotfile_home_path}/.zshrc2"
    insert_if_not_exist "${HOME}/.tmux.conf" "source-file ${dotfile_home_path}/.tmux.conf2"
    insert_if_not_exist "${HOME}/.vimrc" "source ${dotfile_home_path}/.vimrc2"
    insert_if_not_exist "${HOME}/.gitconfig" "[include] path = \"${dotfile_home_path}/.gitconfig2\""
    create_symlink "${DOTFILES}/.ssh/authorized_keys2" "${HOME}/.ssh/authorized_keys2"
    # those that won't be uninstalled in the future
    install_tmux_tpm
    install_vim_vundle
    fmt_note "done installing!"
}

uninstall(){
    ask_for_yN "do you really want to uninstall?"
    if [[ $? == 1 ]]; then
        uninstall_update
        uninstall_crontab
        delete_if_exist "${HOME}/.zshrc" "source ${dotfile_home_path}/.zshrc2"
        delete_if_exist "${HOME}/.tmux.conf" "source-file ${dotfile_home_path}/.tmux.conf2"
        delete_if_exist "${HOME}/.vimrc" "source ${dotfile_home_path}/.vimrc2"
        delete_if_exist "${HOME}/.gitconfig" "[include] path = \"${dotfile_home_path}/.gitconfig2\""
        delete_link_if_match "${DOTFILES}/.ssh/authorized_keys2" "${HOME}/.ssh/authorized_keys2"
        fmt_note "done uninstalling!"
    fi
}


case $1 in
    ""|-i ) install ;;
    -r    ) uninstall ;;
    *     ) fmt_warning "unknown command \"$1\". available: -i, -r" ;;
esac
