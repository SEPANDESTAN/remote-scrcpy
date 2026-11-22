#!/usr/bin/env bash
# Focused data-only discovery tests; no SSH server or network is needed.
set -euo pipefail
# The suite must never see the developer's own launcher configuration: with a
# host exported, an inherited environment once made a check contact it.
unset "${!REMOTE_SCRCPY_@}" ADB REMOTE_ADB ADB_PORT SCRCPY NO_COLOR
source "$(dirname -- "${BASH_SOURCE[0]}")/../src/ssh-config.sh"

fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# Inject the discovery home without modifying the process's HOME.
discover_fixture() { _discover-ssh-host-aliases "$1" "$fixture/home"; }
assert_discovery() {
    local expected=$1 config=$2 actual
    actual=$(discover_fixture "$config")
    if [[ $actual != "$expected" ]]; then
        printf 'Expected aliases:\n%s\nActual aliases:\n%s\n' "$expected" "$actual" >&2
        exit 1
    fi
}

mkdir -p "$fixture/home/.ssh/parts" "$fixture/home/.ssh/quoted dir" "$fixture/elsewhere"
config=$fixture/home/.ssh/config

# Declaration order, multiple aliases, comments, quoting, =, negations,
# wildcard patterns, deduplication, and an unterminated final physical line.
cat > "$config" <<'CONFIG'
# Host comment
Host remote-host first-alias # Host ghost
hoST="quoted" equals
Host = spaced-equals
Host first-alias *.example !except ?wild *
Hostname not-an-alias
Host "#literal" 'single-quoted'
Host -option
CONFIG
printf 'Host last-no-newline' >> "$config"
assert_discovery $'remote-host\nfirst-alias\nquoted\nequals\nspaced-equals\n#literal\nsingle-quoted\nlast-no-newline' "$config"

# Includes are lexical, recurse in place, preserve quoted paths, and resolve
# relative names against ~/.ssh rather than the including file's directory.
cat > "$fixture/elsewhere/config" <<'CONFIG'
Host before
Include parts/*.conf "quoted dir/with space" ~/elsewhere-absent
Host after
CONFIG
cat > "$fixture/home/.ssh/parts/20.conf" <<'CONFIG'
Host twenty
Include parts/10.conf
CONFIG
cat > "$fixture/home/.ssh/parts/10.conf" <<'CONFIG'
Host ten
Include parts/cycle
CONFIG
ln -s 10.conf "$fixture/home/.ssh/parts/cycle"
printf 'Host from-space\r\n' > "$fixture/home/.ssh/quoted dir/with space"
assert_discovery $'before\nten\ntwenty\nfrom-space\nafter' "$fixture/elsewhere/config"

# Treat executable-looking text as data, never launch Match exec, and warn
# about unsupported dynamic Includes without misreading partial paths.
cat > "$config" <<'CONFIG'
Match exec "touch SHOULD_NOT_EXIST"
    Include parts/20.conf
Include "${HOME}/.ssh/config" "%d/.ssh/config" "~otheruser/.ssh/config"
Include "$(touch SHOULD_NOT_EXIST)"
Host "$(touch\tSHOULD_NOT_EXIST)"
Host "unterminated
Host valid-after-malformed
CONFIG
# Run from inside the fixture so that a command executed by mistake would
# leave its marker there, not in the caller's directory.
actual=$(cd -- "$fixture" && discover_fixture "$config" 2> "$fixture/warnings")
[[ $actual == *valid-after-malformed ]]
[[ ! -e $fixture/SHOULD_NOT_EXIST ]]
[[ $(< "$fixture/warnings") == *'Skipping dynamic SSH Include'* ]]
[[ $(< "$fixture/warnings") == *'Skipping malformed SSH config line'* ]]

# A missing config is a normal empty inventory.
assert_discovery '' "$fixture/missing"

# Without a home directory, an Include that needs one is skipped with a
# diagnostic instead of being resolved against the root directory; hosts and
# absolute Includes still work.
printf 'Host absolute-include\n' > "$fixture/elsewhere/absolute"
printf 'Host homeless\nInclude ~/parts/10.conf parts/20.conf %s\n' "$fixture/elsewhere/absolute" > "$config"
actual=$(unset HOME; _discover-ssh-host-aliases "$config" 2> "$fixture/warnings")
[[ $actual == $'homeless\nabsolute-include' ]]
[[ $(grep -c 'needs a home directory' "$fixture/warnings") == 2 ]]

# State and caller glob settings do not leak across separate discoveries.
printf 'Host second-call\n' > "$config"
shopt -s failglob dotglob nocaseglob
set -f
assert_discovery second-call "$config"
[[ $- == *f* ]]
shopt -q failglob dotglob nocaseglob

printf 'SSH config discovery checks passed.\n'
