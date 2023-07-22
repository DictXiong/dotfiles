#!/usr/bin/env bash
set -ex
OPTS='-a -bcl --color --arg1=1 --arg2 2 " 1 2" yes'
TARGET_OPTS='-a -b -c --arg1 1 --arg2 2  1 2 yes'
eval set -- $OPTS

THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/common.sh"

test "${GOT_OPTS[*]}" = "$TARGET_OPTS"
test $# -eq 8
test "$*" = "${OPTS//\"/}"
test "$DFS_LITE" = "1"
is_tty
test -z "$DFS_QUIET"

set +x
echo "test passed, args:"
for i in "${GOT_OPTS[@]}"; do
    echo "$i"
done