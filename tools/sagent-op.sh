#!/usr/bin/env bash
set -e

op=$(command -v op || command -v op.exe || true)
if [[ ! -x $op ]]; then
    echo "1password cli not found" > /dev/stderr
    exit -1
fi
"$op" read "op://Personal/id25519-passphrase/$(hostname)"
