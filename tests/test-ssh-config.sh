#!/usr/bin/env bash
# Focused data-only discovery tests; no SSH server or network is needed.
set -euo pipefail
# The suite must never see the developer's own launcher configuration: with a
# host exported, an inherited environment once made a check contact it.
unset "${!REMOTE_SCRCPY_@}" ADB REMOTE_ADB ADB_PORT SCRCPY NO_COLOR
# Nor may any child inherit the caller's standard input: docs/testing.md,
# "Environment", has the reason. Not dead code; the maintenance suite checks it.
exec < /dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/../src/ssh-config.sh"

fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# Inject the discovery home without modifying the process's HOME.
discover_fixture() { _discover-ssh-host-aliases "$1" "$fixture/home"; }
# Every check says what was expected when it fails; a bare test or a bare
# run of the discovery under `set -e` would end the suite without a word.
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_discovery() {
    local expected=$1 config=$2 actual
    actual=$(discover_fixture "$config") || fail "the discovery of $config ended with status $?"
    if [[ $actual != "$expected" ]]; then
        printf 'FAIL: the aliases found differ.\nExpected aliases:\n%s\nActual aliases:\n%s\n' "$expected" "$actual" >&2
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
actual=$(cd -- "$fixture" && discover_fixture "$config" 2> "$fixture/warnings") \
    || fail "the discovery ended with status $?: $(< "$fixture/warnings")"
[[ $actual == *valid-after-malformed ]] || fail 'a host declared after a malformed line is still listed'
[[ ! -e $fixture/SHOULD_NOT_EXIST ]] || fail 'nothing written in a config is executed'
[[ $(< "$fixture/warnings") == *'Skipping dynamic SSH Include'* ]] || fail 'a dynamic Include ($, % or ~user) is skipped with a message'
[[ $(< "$fixture/warnings") == *'Skipping malformed SSH config line'* ]] || fail 'a malformed line is skipped with a message'

# A missing config is a normal empty inventory.
assert_discovery '' "$fixture/missing"

# Without a home directory (an empty HOME here), an Include that needs one is
# skipped with a diagnostic instead of being resolved against the root
# directory; hosts and absolute Includes still work, and an Include the scan
# cannot follow anyway keeps its own diagnostic.
printf 'Host absolute-include\n' > "$fixture/elsewhere/absolute"
# shellcheck disable=SC2016  # ${NOPE} is literal text of the config under test
printf 'Host homeless\nInclude ~/parts/10.conf parts/20.conf %s "${NOPE}/x"\n' "$fixture/elsewhere/absolute" > "$config"
actual=$(HOME=; _discover-ssh-host-aliases "$config" 2> "$fixture/warnings") \
    || fail "the discovery with an empty HOME ended with status $?: $(< "$fixture/warnings")"
[[ $actual == $'homeless\nabsolute-include' ]] || fail 'without a home directory, the hosts of the config and of an absolute Include are listed, and nothing else'
[[ $(grep -c 'needs a home directory' "$fixture/warnings") == 2 ]] || fail 'without a home directory, each of the two Includes that need one is skipped with a message'
[[ $(grep -c 'Skipping dynamic SSH Include' "$fixture/warnings") == 1 ]] || fail 'without a home directory, a dynamic Include still gets its own message, once'

# With HOME unset the scan takes the home directory from the password
# database, as the launcher does for the default config, so an Include under
# ~ is followed, not skipped. The name is one that does not exist: nothing is
# read from the home of whoever runs the suite.
printf 'Host database-home\nInclude ~/.remote-scrcpy-test-no-such-file\n' > "$config"
actual=$(unset HOME; _discover-ssh-host-aliases "$config" 2> "$fixture/warnings") \
    || fail "the discovery with HOME unset ended with status $?: $(< "$fixture/warnings")"
[[ $actual == database-home ]] || fail 'with HOME unset, the host is listed'
[[ $(grep -c 'needs a home directory' "$fixture/warnings") == 0 ]] || fail 'with HOME unset, an Include under ~ is followed and not skipped'

# State and caller glob settings do not leak across separate discoveries.
# The discovery is called directly here, not inside a command substitution,
# so that the caller whose settings must survive is this suite itself.
printf 'Host second-call\n' > "$config"
shopt -s failglob dotglob nocaseglob
set -f
_discover-ssh-host-aliases "$config" "$fixture/home" > "$fixture/aliases" \
    || fail "a discovery called directly ended with status $?"
[[ $(< "$fixture/aliases") == second-call ]] || fail 'a second discovery lists only its own host'
[[ $- == *f* ]] || fail "the caller's noglob setting survives a discovery"
shopt -q failglob dotglob nocaseglob || fail "the caller's glob options survive a discovery"

printf 'SSH config discovery checks passed.\n'
