#!/bin/false

# remotes
nasp.remote() {
    remote=nasp.fit
    RET_PORT=${RET_PORT:-36022}
    RET_USERNAME=${RET_USERNAME:-root}
    RET_TRUST_SERVER=1
}

# domains
.domain() {
    RET_USERNAME=${RET_USERNAME:-root}
    RET_PORT=${RET_PORT:-12022}
    RET_HOSTNAME=${remote%.}
}

dxng.domain() {
    RET_HOSTNAME=$host.dxng.net
    RET_PORT=${RET_PORT:-12022}
    RET_USERNAME=${RET_USERNAME:-root}
    RET_TRUST_SERVER=1
}

i.domain() {
    RET_HOSTNAME=$host.ibd.ink
    RET_PORT=${RET_PORT:-12022}
    RET_USERNAME=${RET_USERNAME:-root}
    RET_TRUST_SERVER=1
}

42.domain() {
    RET_HOSTNAME=$host.i.bd.dn42
    RET_PORT=${RET_PORT:-12022}
    RET_USERNAME=${RET_USERNAME:-root}
    RET_TRUST_SERVER=1
}

nasp.domain() {
    RET_HOSTNAME=$host
    RET_PORT=${RET_PORT:-12022}
    RET_USERNAME=${RET_USERNAME:-root}
    RET_JUMP_SERVER="ssh@nasp.fit:36022"
    RET_TRUST_SERVER=1
}

default.domain() {
    dxng.domain
}
