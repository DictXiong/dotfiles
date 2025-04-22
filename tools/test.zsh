#!/bin/false "This script should be sourced in zsh, not executed directly"

set -ex
trap "dfs beacon gh.ci.fail" ERR

# fix for macos
dfs cd
if [[ $(./tools/common.sh get_os_type) == "macos" ]]; then
    export PATH="/usr/local/opt/coreutils/libexec/gnubin:/opt/homebrew/opt/coreutils/libexec/gnubin:${PATH}"
fi

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
diff -q ./.eid/authorized_certificates ~/.eid/authorized_certificates
grep -q ".zshrc2" ~/.zshrc
if [[ -x $(command -v crontab) ]]; then
    crontab -l | grep -qxF "0 * * * * ${DOTFILES}/update.sh"
fi

# check scripts and functions
dfs version
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
test "$(DFS_TRUST=1 riot time@is.impt:2222/yes@you-r.right/you@are.really.recht./ibd./try@it,another@host scp /tmp/ ./tmp -D 2>/dev/null)" = 'scp -P 12022 -o RequestTTY=yes -o PermitLocalCommand=yes -o ControlMaster=auto -o ControlPath=~/.ssh/master-socket/%C -o ProxyJump=time@is.impt:2222,yes@you-r.right:12022,you@are.really.recht:12022,root@ibd:12022 -r try@it.dxng.net:/tmp/ ./tmp
scp -P 12022 -o RequestTTY=yes -o PermitLocalCommand=yes -o ControlMaster=auto -o ControlPath=~/.ssh/master-socket/%C -o ForwardX11=yes -o ForwardAgent=yes -r another@host.dxng.net:/tmp/ ./tmp'

# check alias
alias p114
alias cbds
which riot
sagt
test -f ~/.ssh/agent-$(whoami)
gbes || which gbes

# check update
DFS_VERSION=`dfs version`
dfs update
dfs version
test `git rev-parse HEAD` = `curl -fsSL https://api.beardic.cn/get-var/dfs-commit-id`

# clean
git reset --hard $DFS_VERSION

# then check install.sh
./install.sh -dx DFS_CI=1 -H e153a2eL,f8At3iFw
grep -qE "testhist 1$" ~/.zsh_history
grep -qE "testhist 4$" ~/.zsh_history
grep -qx "DFS_CI=1" ~/.config/dotfiles/env
./install.sh -l
dfs version
test `git rev-parse HEAD` = `curl -fsSL https://api.beardic.cn/get-var/dfs-commit-id`

# clean
git reset --hard $DFS_VERSION

set +x
