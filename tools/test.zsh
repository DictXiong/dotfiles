#!/bin/false "This script should be sourced in a shell, not executed directly"

set -ex

# check files
cd /
dfs cd
pwd
test -f .zshrc2
diff -q ./.ssh/authorized_keys2 ~/.ssh/authorized_keys2
grep -q ".zshrc2" ~/.zshrc

# check scripts and functions
antigen list
dfs version
dfs log 1
l
l ~
dogo
tools/common.sh get_os_type
tools/common.sh get_linux_dist

# check alias
alias p114 > /dev/null

# check update
dfs update
dfs version
test `git rev-parse HEAD` = `curl -fsSL https://api.beardic.cn/get-var/dfs-commit-id`
