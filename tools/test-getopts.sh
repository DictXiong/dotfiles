#!/bin/bash
set -ex
OPTS="-a -bcl --color --arg1=1 --arg2 2 yes"
TARGET_OPTS="-a -b -c --arg1 1 --arg2 2 yes"
set -- $OPTS

THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
source "$THIS_DIR/common.sh"

test "${GOT_OPTS[*]}" = "$TARGET_OPTS"
test "$*" = "$OPTS"
test "$DFS_LITE" = "1"
is_tty
test -z "$DFS_QUIET"