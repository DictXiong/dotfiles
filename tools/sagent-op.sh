#!/usr/bin/env bash
set -e

op=$(command -v op || command -v op.exe)
if [[ ! -x $op ]]; then
    echo "1password cli not found"
    exit -1
fi
"$op" read "op://Personal/id25519-passphrase/$(hostname)"
