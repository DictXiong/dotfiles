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
dfs beacon gh.ci $GITHUB_SHA
z ~
test ~ -ef "$(pwd)"
dogo
doll
dfs cd
tools/test-getopts.sh
tools/common.sh get_os_name
test $(echo y | tools/common.sh ask_for_yN "test") = "1"
test $(echo n | tools/common.sh ask_for_yN "test") = "0"
test $(echo | tools/common.sh ask_for_yN "test") = "0"
test $(echo | tools/common.sh ask_for_Yn "test") = "1"
test $(DFS_QUIET=1 tools/common.sh ask_for_Yn "test") = "1"

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
./install.sh -dx DFS_CI=1
grep -q "DFS_CI=1" ~/.config/dotfiles/env
./install.sh -l -x DFS_CI=1
dfs version
test `git rev-parse HEAD` = `curl -fsSL https://api.beardic.cn/get-var/dfs-commit-id`

# clean
git reset --hard $DFS_VERSION

set +x