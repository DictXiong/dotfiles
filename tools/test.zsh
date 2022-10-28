#!/bin/false "This script should be sourced in a shell, not executed directly"

set -ex

# check files
cd /
dfs cd
pwd
test -f .zshrc2
diff -q ./.ssh/authorized_keys2 ~/.ssh/authorized_keys2
grep -q ".zshrc2" ~/.zshrc
l ~

# check scripts and functions
dfs version
dfs log 1
l
z
dogo
tools/common.sh get_os_type
tools/common.sh get_linux_dist

# check alias
alias p114 > /dev/null

# check update
DFS_VERSION=`dfs version`
dfs update
dfs version
test `git rev-parse HEAD` = `curl -fsSL https://api.beardic.cn/get-var/dfs-commit-id`

# clean
dfs cd
git reset --hard $DFS_VERSION
set +x