#!/bin/bash
set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/common.sh"

zsh_hist_file="$HOME/.zsh_history"

do_append()
{
    timestamp=$(date +%s)
    while read -r line; do
        echo ": $timestamp:0;$line" >> "$zsh_hist_file"
    done
}

main()
{
    key=$1
    if [[ -z "$key" ]]; then
        fmt_fatal "missing key"
    fi
    IFS=',' read -r -a keys<<<"$key"
    for k in "${keys[@]}";do
        if [[ -z "$k" ]]; then
            continue
        fi
        curl -fsSL "https://pastebin.com/raw/$k" | do_append
    done
}

main "${GOT_OPTS[@]}"