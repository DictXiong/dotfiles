#!/bin/false "This script should be sourced in zsh, not executed directly"

set -ex

# check files
cd /
l
cd ~
l
dfs cd
l
pwd
test -f .zshrc2
diff -q ./.ssh/authorized_keys2 ~/.ssh/authorized_keys2
grep -q ".zshrc2" ~/.zshrc

# check scripts and functions
dfs version
dfs log 1
dfs beacon gh.ci
z ~
test ~ -ef "$(pwd)"
dogo
doll
dfs cd
./tools/test-getopts.sh
tools/common.sh get_os_type
tools/common.sh get_linux_dist

# check alias
alias p114
which riot
piv-agent || which piv-agent
gbes || which gbes

# check update
DFS_VERSION=`dfs version`
dfs update
dfs version
test `git rev-parse HEAD` = `curl -fsSL https://api.beardic.cn/get-var/dfs-commit-id`

# clean
git reset --hard $DFS_VERSION

# then check install.sh
./install.sh -l -x DFS_CI=1
dfs version
test `git rev-parse HEAD` = `curl -fsSL https://api.beardic.cn/get-var/dfs-commit-id`
grep -q "DFS_CI=1" ~/.config/dotfiles/env

# clean
git reset --hard $DFS_VERSION

set +x