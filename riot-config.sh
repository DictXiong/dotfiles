#!/bin/false

# remotes
j.remote() {
    remote=sir0.ibd.ink
    RET_PORT=${RET_PORT:-36122}
    RET_USERNAME=${RET_USERNAME:-root}
    RET_TRUST_SERVER=1
}

# domains
i.domain() {
    RET_HOSTNAME=$host.ibd.ink
    RET_PORT=${RET_PORT:-12022}
    RET_USERNAME=${RET_USERNAME:-root}
    RET_TRUST_SERVER=1
}

x.domain() {
    RET_HOSTNAME=ssh.beardic.cn
    local tmp=$(sha256sum <<< "$host" | tr -cd "[:digit:]")
    tmp=${tmp:0:4}
    RET_PORT=$((10#$tmp+36000))
    RET_USERNAME=root
    RET_TRUST_SERVER=1
}

nasp.domain() {
    RET_HOSTNAME=$host
    RET_PORT=${RET_PORT:-12022}
    RET_USERNAME=${RET_USERNAME:-dictxiong}
    RET_JUMP_SERVER="ssh@nasp.ob.ac.cn:36022"
    RET_TRUST_SERVER=1
}

default.domain() {
    i.domain
}
