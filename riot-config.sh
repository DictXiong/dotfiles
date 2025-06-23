#!/bin/false

# batches
nasps.batch() {
    remotes+=(
        g1.nasp
        g2.nasp
        g3.nasp
        g4.nasp
        g5.nasp
        g6.nasp
        g7.nasp
        g8.nasp
        g9.nasp
        g10.nasp
        g11.nasp
        g12.nasp
        g13.nasp
        g14.nasp
        dictxiong@g15.nasp
        dictxiong@g16.nasp
        g17.nasp
    )
}

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
    if [[ "$host" =~ ^sed([0-9]{1,2})$ ]]; then
        RET_HOSTNAME=192.168.98.$((100+BASH_REMATCH[1]))
    else
        RET_HOSTNAME=$host.dxng.net
    fi
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
