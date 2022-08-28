
set -ex

l ~
l ~/.ssh
cat ~/.zshrc
cd /
dfs
dfs cd
pwd
dfs version
dfs log 1
l
dogo
tools/common.sh get_os_type
tools/common.sh get_linux_dist
bash -x tools/common.sh post_log 1 2 3

dfs update
dfs version

# ..?
p114 -c 4

