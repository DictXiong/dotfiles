#!/usr/bin/env bash
set -e

op=$(command -v op || command -v op.exe || true)
if [[ -z "$op" || ! -x "$op" ]]; then
    echo "1Password CLI not found" >&2
    exit 1
fi
exec "$op" read "op://Personal/id25519-passphrase/$(hostname)"
