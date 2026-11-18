#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scf="$source_dir/scripts/scf"
fixture=$(mktemp -d /tmp/scf.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
mock_bin="$fixture/bin"
data_dir="$fixture/data"
unit_dir="$fixture/units"
mkdir -p "$mock_bin" "$data_dir" "$unit_dir"

export MOCK_UNIT_DIR="$unit_dir" MOCK_SYSTEMCTL_LOG="$fixture/systemctl.log"
MOCK_VIRTUAL_GUARD=""
MOCK_PROBE_ROOT=""
MOCK_PROBE_LOG=""
REAL_GREP=$(command -v grep)
REAL_HEAD=$(command -v head)

cat > "$mock_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_SYSTEMCTL_LOG"
unit=${@: -1}
cat "$MOCK_UNIT_DIR/$unit"
EOF
chmod +x "$mock_bin/systemctl"

write_unit() {
    local name=$1 executable=$2 argument
    shift 2
    {
        printf '{ path=%s ; argv[]=%s' "$executable" "$executable"
        for argument in "$@"; do
            argument=${argument//\\/\\\\}
            argument=${argument//\"/\\\"}
            printf ' "%s"' "$argument"
        done
        printf ' ; }\n'
    } > "$unit_dir/$name.service"
}

run_scf() {
    env -i HOME="$fixture" PATH="$mock_bin:$PATH" \
        MOCK_UNIT_DIR="$unit_dir" MOCK_SYSTEMCTL_LOG="$MOCK_SYSTEMCTL_LOG" \
        MOCK_VIRTUAL_GUARD="$MOCK_VIRTUAL_GUARD" \
        MOCK_PROBE_ROOT="$MOCK_PROBE_ROOT" MOCK_PROBE_LOG="$MOCK_PROBE_LOG" \
        REAL_GREP="$REAL_GREP" REAL_HEAD="$REAL_HEAD" \
        SCF_MAX_CANDIDATES="${SCF_MAX_CANDIDATES-20}" \
        SCF_MAX_DEPTH="${SCF_MAX_DEPTH-3}" SCF_MAX_SCAN="${SCF_MAX_SCAN-256}" \
        SCF_MAX_BYTES="${SCF_MAX_BYTES-1048576}" \
        "$scf" "$@" 2> "$fixture/stderr"
}

expect_file() {
    local expected=$1
    shift
    if ! run_scf "$@" > "$fixture/stdout"; then
        cat "$fixture/stderr" >&2
        echo "expected scf to select $expected for $*" >&2
        exit 1
    fi
    cmp "$expected" "$fixture/stdout"
}

expect_failure() {
    local message=$1
    shift
    if run_scf "$@" > "$fixture/stdout"; then
        echo "expected scf to fail for $*" >&2
        exit 1
    fi
    grep -Fq -- "$message" "$fixture/stderr"
}

binary="$data_dir/program"
main="$data_dir/main.yaml"
child="$data_dir/child.conf"
note="$data_dir/notes.unknown"
plain="$data_dir/extensionless"
empty="$data_dir/empty"
script="$data_dir/runner"
other_script="$data_dir/other.cjs"
execution_marker="$fixture/script-was-executed"
printf '\177ELF\000binary payload\n' > "$binary"
printf 'main file\ninclude %s\n' "$child" > "$main"
printf 'child file\n' > "$child"
printf 'unknown suffix text\n' > "$note"
printf 'extensionless text without a shebang\n' > "$plain"
: > "$empty"
printf '#!/bin/sh\n# startup script\ntouch %s\n' "$execution_marker" > "$script"
printf '// executable text without a shebang\n' > "$other_script"
chmod +x "$script"
chmod 644 "$other_script"
ln -s "$script" "$data_dir/script-link"

# Direct text arguments retain argv order, independent of suffix or shebang.
# Recursive references are listed after the direct arguments.
write_unit demo "$binary" "$main" "$note"
expect_file "$main" demo
grep -Fq -- '--property=ExecStart --value -- demo.service' "$MOCK_SYSTEMCTL_LOG"
expect_file "$note" -n 2 demo
expect_file "$child" -r -n 3 demo
write_unit arbitrary "$binary" "$note" "$main" "$plain" "$empty"
expect_file "$note" arbitrary
expect_file "$main" -n 2 arbitrary
expect_file "$plain" -n 3 arbitrary
expect_file "$empty" -n 4 arbitrary
expect_failure 'out of range (1-4)' -n 5 arbitrary

# Text executable entry points follow direct arguments. Executable bits and
# script suffixes do not determine whether readable text can be selected.
write_unit script "$script" "$note"
expect_file "$note" script
expect_file "$script" -n 2 script
write_unit plain-script "$other_script"
expect_file "$other_script" plain-script
write_unit linked-script "$data_dir/script-link"
expect_file "$script" linked-script
test ! -e "$execution_marker"

# A relative executable name must not cause the first absolute argument to be
# discarded. Every ExecStart entry in a oneshot unit contributes candidates.
write_unit relative systemd-tmpfiles "$main"
expect_file "$main" relative
write_unit first "$script"
write_unit second "$binary" "$note"
write_unit third "$other_script"
cat "$unit_dir/first.service" "$unit_dir/second.service" "$unit_dir/third.service" \
    > "$unit_dir/multiple.service"
expect_file "$note" multiple
expect_file "$script" -n 2 multiple
expect_file "$other_script" -n 3 multiple
expect_failure 'out of range (1-3)' -n 4 multiple
write_unit role-first "$other_script" "$script"
write_unit role-second "$script"
cat "$unit_dir/role-first.service" "$unit_dir/role-second.service" > "$unit_dir/roles.service"
expect_file "$script" roles
expect_file "$other_script" -n 2 roles
expect_failure 'out of range (1-2)' -n 3 roles
write_unit binary "$binary" "$binary"
if run_scf binary > "$fixture/stdout"; then
    echo 'expected binary-only service to have no text candidate' >&2
    exit 1
fi
test ! -s "$fixture/stdout"
printf 'ASCII prefix line\n\022non-text payload\n' > "$data_dir/control-payload"
write_unit control-payload "$binary" "$data_dir/control-payload"
if run_scf control-payload > "$fixture/stdout"; then
    echo 'expected a control-byte payload to be excluded without a NUL byte' >&2
    exit 1
fi
test ! -s "$fixture/stdout"
printf '\344\270\255\346\226\207 UTF-8 text\n' > "$data_dir/utf8"
write_unit utf8-empty "$binary" "$data_dir/utf8" "$empty"
expect_file "$data_dir/utf8" utf8-empty
expect_file "$empty" -n 2 utf8-empty

# Literal ANSI escape sequences are valid text in both scripts and logs.
printf '#!/bin/sh\nprintf "\033[31mred\033[0m\\n"\ntouch %s\n' \
    "$execution_marker" > "$data_dir/ansi-script"
bash -n "$data_dir/ansi-script"
printf '\033[32mservice started\033[0m\n' > "$data_dir/ansi-log"
write_unit ansi-script "$data_dir/ansi-script"
write_unit ansi-log "$binary" "$data_dir/ansi-log"
expect_file "$data_dir/ansi-script" ansi-script
expect_file "$data_dir/ansi-log" ansi-log
test ! -e "$execution_marker"

# systemctl leaves shell -c commands unquoted. Internal semicolons and shell
# assignments must survive until the actual ExecStart metadata boundary.
printf '{ path=%s ; argv[]=%s -c true; pid=0; status=ready; flags=on; cat "%s" ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0 ; }\n' \
    "$binary" "$binary" "$note" > "$unit_dir/shell-semicolons.service"
expect_file "$note" shell-semicolons
printf '{ path=%s ; argv[]=%s -c f() { true; }; cat "%s" ; }\n' \
    "$binary" "$binary" "$note" > "$unit_dir/shell-braces.service"
expect_file "$note" shell-braces
printf '{ path=%s ; argv[]=%s -c f() { true; ignore_errors=no ; }; cat "%s" ; }\n' \
    "$binary" "$binary" "$note" > "$unit_dir/shell-field-name.service"
expect_file "$note" shell-field-name

# Preserve semicolons in quoted filenames, indexed argv fields, and multiple
# ExecStart records on a single line without merging their executable roles.
semicolon="$data_dir/semicolon ; ignore_errors=no ; }"
printf 'semicolon filename\n' > "$semicolon"
write_unit semicolon "$binary" "$semicolon"
expect_file "$semicolon" semicolon
printf '{ path=%s ; argv[0]=%s ; argv[1]=-c ; argv[2]=true; cat "%s" ; }\n' \
    "$binary" "$binary" "$note" > "$unit_dir/indexed-argv.service"
expect_file "$note" indexed-argv
printf '{ path=%s ; argv[]=%s -c true; cat "%s" ; } { path=%s ; argv[]=%s "%s" ; }\n' \
    "$binary" "$binary" "$note" "$script" "$script" "$plain" \
    > "$unit_dir/inline-records.service"
expect_file "$note" inline-records
expect_file "$plain" -n 2 inline-records
expect_file "$script" -n 3 inline-records
expect_failure 'out of range (1-3)' -n 4 inline-records

# Decoded newlines can produce blank path records. They must not become empty
# associative-array subscripts or prevent a later real file from being found.
printf '%s\n' 'pattern = "/\n"' "'/\\n'" "$note" > "$data_dir/escaped-references"
write_unit escaped-references "$binary" "$data_dir/escaped-references"
# Three probes cover the binary, input text, and real reference. Any incidental
# root-directory task is deferred beyond that budget instead of being scanned.
SCF_MAX_SCAN=3 expect_file "$note" -r -n 2 escaped-references

# Preserve quoted paths and common systemd/shell encodings, including literal
# quotes and backslashes in existing names.
mkdir "$data_dir/space dir"
spaced="$data_dir/space dir/plain file"
quoted="$data_dir/quoted \"file\""
backslash="$data_dir/literal\\space"
printf 'spaced text\n' > "$spaced"
printf 'quoted text\n' > "$quoted"
printf 'backslash text\n' > "$backslash"
write_unit spaced "$binary" "$spaced"
write_unit quoted "$binary" "$quoted"
write_unit backslash "$binary" "$backslash"
expect_file "$spaced" spaced
expect_file "$quoted" quoted
expect_file "$backslash" backslash
for encoding in hex octal shell; do
    case $encoding in
        hex) encoded=${spaced// /\\x20} ;;
        octal) encoded=${spaced// /\\040} ;;
        shell) encoded=${spaced// /\\ } ;;
    esac
    printf '{ path=%s ; argv[]=%s --file %s ; }\n' "$binary" "$binary" "$encoded" \
        > "$unit_dir/$encoding.service"
    expect_file "$spaced" "$encoding"
done

# All directory text entries are eligible, in C filename order. Explicit
# recursive file references outrank entries found by scanning a directory.
directory="$data_dir/items"
mkdir "$directory"
printf 'unknown directory text\n' > "$directory/10.notes"
printf 'extensionless directory text\n' > "$directory/20-plain"
: > "$directory/30-empty"
printf 'PEM-shaped text\n' > "$directory/40.pem"
cp "$binary" "$directory/50.binary"
printf '#!/bin/sh\n# directory script\n' > "$directory/60-runner"
printf 'table inet unit_test {}\n' > "$directory/70.nft"
printf 'alloy text\n' > "$directory/80.alloy"
write_unit directory "$binary" "$directory"
index=1
for expected in "$directory/10.notes" "$directory/20-plain" "$directory/30-empty" \
    "$directory/40.pem" "$directory/60-runner" "$directory/70.nft" "$directory/80.alloy"; do
    expect_file "$expected" -r -n "$index" directory
    index=$((index + 1))
done
expect_failure 'out of range (1-7)' -r -n 8 directory
if run_scf directory > "$fixture/stdout"; then
    echo 'expected directories to require recursive mode' >&2
    exit 1
fi
wrapper="$data_dir/wrapper"
explicit="$data_dir/explicit.unusual"
printf 'direct argument without references\n' > "$data_dir/direct"
printf 'explicit recursive text\n' > "$explicit"
printf '#!/bin/sh\n%s\n%s\n' "$directory" "$explicit" > "$wrapper"
write_unit ranked "$wrapper" "$data_dir/direct"
expect_file "$data_dir/direct" -r ranked
expect_file "$wrapper" -r -n 2 ranked
expect_file "$explicit" -r -n 3 ranked
expect_file "$directory/10.notes" -r -n 4 ranked
mkdir "$data_dir/weak-directory"
printf 'external directory reference\n' > "$data_dir/directory-child.unknown"
printf 'directory document\n%s\n' "$data_dir/directory-child.unknown" > "$data_dir/weak-directory/entry"
write_unit weak-source "$binary" "$data_dir/weak-directory"
expect_file "$data_dir/weak-directory/entry" -r weak-source
expect_file "$data_dir/directory-child.unknown" -r -n 2 weak-source
expect_failure 'out of range (1-2)' -r -n 3 weak-source

# References are ordered by depth before discovery order and cycles terminate.
chain="$data_dir/chain"
middle="$data_dir/middle"
deep="$data_dir/deep.odd"
printf '#!/bin/sh\n%s\n' "$middle" > "$chain"
printf 'middle text\n%s\n' "$deep" > "$middle"
printf 'deep text\n' > "$deep"
write_unit chain "$chain"
expect_file "$chain" -r chain
expect_file "$middle" -r -n 2 chain
expect_file "$deep" -r -n 3 chain
SCF_MAX_DEPTH=1 expect_failure 'out of range (1-2)' -r -n 3 chain
printf 'sibling text\n' > "$data_dir/sibling"
printf '#!/bin/sh\n%s\n%s\n' "$middle" "$data_dir/sibling" > "$data_dir/branching"
write_unit branching "$data_dir/branching"
expect_file "$middle" -r -n 2 branching
expect_file "$data_dir/sibling" -r -n 3 branching
expect_file "$deep" -r -n 4 branching
printf '\n%s\n' "$chain" >> "$deep"
expect_failure 'out of range (1-3)' -r -n 4 chain
SCF_MAX_DEPTH=0 expect_failure 'out of range (1-1)' -r -n 2 chain

# A directory can expose a known file at a shallower traversal depth even
# though the earlier explicit reference retains its stronger display rank.
promotion="$data_dir/promotion"
mkdir -p "$promotion/jobs"
printf '#!/bin/sh\n%s\n%s\n' "$promotion/first" "$promotion/jobs" > "$promotion/entry"
printf 'first reference\n%s\n' "$promotion/jobs/target" > "$promotion/first"
printf 'target text\n%s\n' "$promotion/child" > "$promotion/jobs/target"
printf 'child reached through a shallower directory entry\n' > "$promotion/child"
write_unit promotion "$promotion/entry"
SCF_MAX_DEPTH=2 expect_file "$promotion/child" -r -n 4 promotion
SCF_MAX_DEPTH=2 expect_failure 'out of range (1-4)' -r -n 5 promotion

# Recursive parsing has a byte budget independent of candidate eligibility.
# A partial final path must be discarded even when its prefix names a file.
byte_entry="$data_dir/byte-entry"
byte_large="$data_dir/byte-large"
byte_prefix="$data_dir/byte-tail"
byte_tail="$data_dir/byte-tail-suffix"
large_first_line='large text remains selectable'
printf '#!/bin/sh\n%s\n' "$byte_large" > "$byte_entry"
printf '%s\n%s\n' "$large_first_line" "$byte_tail" > "$byte_large"
printf 'truncated path prefix must not be selected\n' > "$byte_prefix"
printf 'tail file beyond the small byte budget\n' > "$byte_tail"
byte_limit=$(( $(wc -c < "$byte_entry") + ${#large_first_line} + 1 + ${#byte_prefix} ))
write_unit byte-budget "$byte_entry"
SCF_MAX_BYTES="$byte_limit" expect_file "$byte_large" -r -n 2 byte-budget
test "$(grep -cF 'SCF_MAX_BYTES' "$fixture/stderr")" -eq 1
SCF_MAX_BYTES="$byte_limit" expect_failure 'out of range (1-2)' -r -n 3 byte-budget
test "$(grep -cF 'SCF_MAX_BYTES' "$fixture/stderr")" -eq 1
SCF_MAX_BYTES=4096 SCF_MAX_SCAN=3 expect_file "$byte_tail" -r -n 3 byte-budget
SCF_MAX_BYTES=0 expect_failure 'SCF_MAX_BYTES' byte-budget
SCF_MAX_BYTES=invalid expect_failure 'SCF_MAX_BYTES' byte-budget

# A shallower symlink discovery can rescan a file's references. Reuse its
# parsed references so the total budget is charged once per canonical file.
byte_cache="$data_dir/byte-cache"
mkdir -p "$byte_cache/jobs"
printf '#!/bin/sh\n%s\n%s\n' "$byte_cache/first" "$byte_cache/jobs" > "$byte_cache/entry"
printf 'first text\n%s\n' "$byte_cache/target" > "$byte_cache/first"
printf 'target text\n%s\n' "$byte_cache/child" > "$byte_cache/target"
printf 'child text\n%s\n' "$byte_cache/grandchild" > "$byte_cache/child"
printf 'grandchild reached using cached references\n' > "$byte_cache/grandchild"
ln -s "$byte_cache/target" "$byte_cache/jobs/target"
byte_cache_limit=0
for file in entry first target child; do
    byte_cache_limit=$((byte_cache_limit + $(wc -c < "$byte_cache/$file")))
done
write_unit byte-cache "$byte_cache/entry"
SCF_MAX_DEPTH=3 SCF_MAX_BYTES="$byte_cache_limit" \
    expect_file "$byte_cache/grandchild" -r -n 5 byte-cache
if grep -Fq 'SCF_MAX_BYTES' "$fixture/stderr"; then
    echo 'expected canonical reference-cache hits not to consume parsing bytes' >&2
    exit 1
fi

# Canonical physical paths deduplicate aliases without changing source order.
ln -s "$note" "$data_dir/note-link"
ln -s "$data_dir/note-link" "$data_dir/second-link"
write_unit aliases "$binary" "$note" "$data_dir/note-link" "$data_dir/second-link" "$plain"
expect_file "$note" aliases
expect_file "$plain" -n 2 aliases
expect_failure 'out of range (1-2)' -n 3 aliases
SCF_MAX_SCAN=3 expect_file "$plain" -n 2 aliases
if grep -Fq 'SCF_MAX_SCAN' "$fixture/stderr"; then
    echo 'expected aliases to share the physical scan budget' >&2
    exit 1
fi
printf '#!/bin/sh\n%s\n%s\n%s\n%s\n' "$note" "$data_dir/note-link" \
    "$data_dir/second-link" "$plain" > "$data_dir/alias-wrapper"
write_unit alias-wrapper "$data_dir/alias-wrapper"
SCF_MAX_SCAN=3 expect_file "$plain" -r -n 3 alias-wrapper
if grep -Fq 'SCF_MAX_SCAN' "$fixture/stderr"; then
    echo 'expected recursive aliases not to truncate physical discovery' >&2
    exit 1
fi

# Search-path assignments in wrappers do not recursively enumerate packages.
# An explicitly referenced file and an ordinary directory named bin still do.
runtime="$data_dir/runtime"
ordinary_bin="$data_dir/ordinary/bin"
mkdir -p "$runtime/bin" "$runtime/site-packages" "$ordinary_bin"
printf 'wrapped program text\n' > "$runtime/bin/wrapped"
printf 'unrelated tool text\n' > "$runtime/bin/zzz-tool"
printf 'Python library text\n' > "$runtime/site-packages/module.py"
printf 'ordinary bin text\n' > "$ordinary_bin/item"
runtime_wrapper="$data_dir/runtime-wrapper"
printf '#!/bin/sh\nexport PATH=%s; %s\nPYTHONPATH=%s\n%s\n' \
    "$runtime/bin" "$runtime/bin/wrapped" "$runtime/site-packages" "$ordinary_bin" > "$runtime_wrapper"
write_unit runtime "$runtime_wrapper"
expect_file "$runtime_wrapper" -r runtime
expect_file "$runtime/bin/wrapped" -r -n 2 runtime
expect_file "$ordinary_bin/item" -r -n 3 runtime
expect_failure 'out of range (1-3)' -r -n 4 runtime
write_unit explicit-bin "$binary" "$runtime/bin"
expect_file "$runtime/bin/wrapped" -r explicit-bin
expect_file "$runtime/bin/zzz-tool" -r -n 2 explicit-bin

# A directory assignment is not necessarily a runtime search path. Comments
# and command-prefix assignments also must not hide later ordinary references.
assets="$data_dir/assets"
mkdir "$assets"
printf 'ordinary asset directory text\n' > "$assets/item"
printf '#!/bin/sh\nCONFIG_PATH=%s\n' "$assets" > "$data_dir/config-path-wrapper"
printf "#!/bin/sh\nexport PATH=%s # user's tools\n%s\n" \
    "$runtime/bin" "$assets" > "$data_dir/comment-wrapper"
printf '#!/bin/sh\nPATH=%s exec app --assets %s\n' \
    "$runtime/bin" "$assets" > "$data_dir/prefix-wrapper"
for name in config-path comment prefix; do
    write_unit "$name" "$data_dir/$name-wrapper"
    expect_file "$assets/item" -r -n 2 "$name"
    expect_failure 'out of range (1-2)' -r -n 3 "$name"
done
printf 'import sys\nsys.path = [\n    "%s",\n    "%s",\n]\nassets = "%s"\n' \
    "$runtime/bin" "$runtime/site-packages" "$assets" > "$data_dir/python-list"
write_unit python-list "$data_dir/python-list"
expect_file "$assets/item" -r -n 2 python-list
expect_failure 'out of range (1-2)' -r -n 3 python-list
for method in insert append; do
    if [[ $method == insert ]]; then
        call="insert(0, \"$runtime/bin\")"
    else
        call="append(\"$runtime/site-packages\")"
    fi
    printf 'import sys\nsys.path.%s; assets = "%s"\n' "$call" "$assets" > "$data_dir/python-$method"
    write_unit "python-$method" "$data_dir/python-$method"
    expect_file "$assets/item" -r -n 2 "python-$method"
    expect_failure 'out of range (1-2)' -r -n 3 "python-$method"
done
printf '#!/bin/sh\nPATH=\n%s\n' "$assets" > "$data_dir/empty-path-wrapper"
write_unit empty-path "$data_dir/empty-path-wrapper"
expect_file "$assets/item" -r -n 2 empty-path
expect_failure 'out of range (1-2)' -r -n 3 empty-path

# Escaped unit names and option boundaries are accepted, malformed names fail
# before systemctl is called.
write_unit 'unit-escaped\x2dname' "$binary" "$note"
expect_file "$note" 'unit-escaped\x2dname'
write_unit -example "$binary" "$note"
expect_file "$note" -- -example.service
grep -Fq -- '--value -- -example.service' "$MOCK_SYSTEMCTL_LOG"
before=$(wc -l < "$MOCK_SYSTEMCTL_LOG")
for invalid in 'bad\xZZ.service' 'bad\x2.service' 'bad\name.service' 'demo; touch /tmp/unexpected'; do
    expect_failure 'invalid service name' "$invalid"
done
test "$(wc -l < "$MOCK_SYSTEMCTL_LOG")" -eq "$before"
SCF_MAX_CANDIDATES=08 SCF_MAX_DEPTH=08 SCF_MAX_SCAN=08 expect_file "$main" demo
expect_failure 'out of range' -n 08 demo

# Guard probes into virtual filesystems so a regression cannot read a device
# or its own output pipe. Redirecting stdout to a regular file exercises the
# /dev/stdout -f edge case, including ordinary-looking symlink aliases.
virtual_file="$data_dir/output-alias"
virtual_dir="$data_dir/kernel-alias"
ln -s /dev/stdout "$virtual_file"
ln -s /proc "$virtual_dir"
MOCK_VIRTUAL_GUARD="$fixture/virtual-guard"
virtual_probes="$fixture/virtual-probes"
printf 'for argument in "$@"; do\n    case "$argument" in\n' > "$MOCK_VIRTUAL_GUARD"
printf '        /dev|/dev/*|/proc|/proc/*|/sys|/sys/*|"%s"|"%s"|"%s"/*)\n' \
    "$virtual_file" "$virtual_dir" "$virtual_dir" >> "$MOCK_VIRTUAL_GUARD"
printf '            printf "%%s\\n" "$argument" >> "%s"\n            exit 99 ;;\n    esac\ndone\n' \
    "$virtual_probes" >> "$MOCK_VIRTUAL_GUARD"
for command in head grep; do
    cat > "$mock_bin/$command" <<'EOF'
#!/usr/bin/env bash
if [[ -n "$MOCK_VIRTUAL_GUARD" ]]; then source "$MOCK_VIRTUAL_GUARD" "$@"; fi
if [[ -n "$MOCK_PROBE_ROOT" ]]; then
    for argument in "$@"; do
        if [[ $argument == "$MOCK_PROBE_ROOT/"* && -f $argument ]]; then
            readlink -f -- "$argument" >> "$MOCK_PROBE_LOG"
        fi
    done
fi
if [[ ${0##*/} == grep ]]; then exec "$REAL_GREP" "$@"; fi
exec "$REAL_HEAD" "$@"
EOF
    chmod +x "$mock_bin/$command"
done
virtual_wrapper="$data_dir/virtual-runner"
printf '#!/bin/sh\n%s\n' "$note" > "$virtual_wrapper"
printf '%s\n' /dev/stdout /proc/version /sys/kernel/kexec_loaded /dev /proc /sys \
    "$virtual_file" "$virtual_dir" >> "$virtual_wrapper"
write_unit virtual "$virtual_wrapper"
expect_file "$virtual_wrapper" -r virtual
expect_file "$note" -r -n 2 virtual
expect_failure 'out of range (1-2)' -r -n 3 virtual
for executable in /dev/stdout "$virtual_file"; do
    write_unit virtual-entry "$executable" "$note"
    expect_file "$note" virtual-entry
done
test ! -e "$virtual_probes"

# Candidate display limits do not restrict discovery through a wrapper chain.
# A separate scan budget bounds unique physical probes and reports truncation.
MOCK_PROBE_ROOT="$data_dir"
MOCK_PROBE_LOG="$fixture/probes"
: > "$MOCK_PROBE_LOG"
SCF_MAX_CANDIDATES=1 expect_file "$chain" -r chain
grep -Fq 'SCF_MAX_CANDIDATES' "$fixture/stderr"
grep -Fxq "$deep" "$MOCK_PROBE_LOG"
mkdir "$data_dir/many"
for ((i=1; i<=60; i++)); do
    printf 'directory entry %s\n' "$i" > "$data_dir/many/job-$i"
done
probe_wrapper="$data_dir/probe-wrapper"
printf '#!/bin/sh\n%s\n' "$data_dir/many" > "$probe_wrapper"
write_unit probes "$probe_wrapper"
: > "$MOCK_PROBE_LOG"
SCF_MAX_CANDIDATES=128 expect_file "$probe_wrapper" -r probes
single_reads=$(wc -l < "$MOCK_PROBE_LOG")
printf '%s\n%s\n' "$data_dir/many" "$data_dir/many" >> "$probe_wrapper"
: > "$MOCK_PROBE_LOG"
SCF_MAX_CANDIDATES=128 expect_file "$probe_wrapper" -r probes
test "$(wc -l < "$MOCK_PROBE_LOG")" -eq "$single_reads"
: > "$MOCK_PROBE_LOG"
SCF_MAX_SCAN=6 SCF_MAX_CANDIDATES=128 expect_file "$probe_wrapper" -r probes
grep -Fq 'SCF_MAX_SCAN' "$fixture/stderr"
test "$(sort -u "$MOCK_PROBE_LOG" | wc -l)" -le 6
write_unit argument-budget "$probe_wrapper" "$data_dir/many" "$note"
SCF_MAX_SCAN=2 expect_file "$note" -r argument-budget
grep -Fq 'SCF_MAX_SCAN' "$fixture/stderr"
test ! -e "$execution_marker"

echo 'scf tests passed'
