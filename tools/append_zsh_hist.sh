#!/usr/bin/env bash
set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/common.sh"

zsh_hist_file="$HOME/.zsh_history"

do_append()
{
    timestamp=$(date +%s)
    while read -r line; do
        if [[ -n "$line" ]]; then
            echo ": $timestamp:0;$line" >> "$zsh_hist_file"
        fi
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
        (curl -fsSL "https://pastebin.com/raw/$k" && echo) | sed 's/\r//' | do_append
    done
}

main "${GOT_OPTS[@]}"