#!/usr/bin/env bash
# Fast dependency-free maintenance regressions. No remote SSH/ADB required.
set -euo pipefail
# The suite must never see the developer's own launcher configuration: with a
# host exported, an inherited environment once made a check contact it.
unset "${!REMOTE_SCRCPY_@}" ADB REMOTE_ADB ADB_PORT SCRCPY NO_COLOR
project=$(cd -- "$(dirname -- "$0")/.." && pwd)
script=$project/remote-scrcpy.sh
passed=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
check() { "$@" || fail "$*"; passed=$((passed+1)); }
contains() { [[ $1 == *"$2"* ]]; }
equals() { [[ $1 == "$2" ]]; }
status() { local wanted=$1; shift; local result=0; "$@" >/dev/null 2>&1 || result=$?; [[ $result == "$wanted" ]]; }

check bash -n "$script"
check contains "$("$script" --version)" '3.0.2'
check contains "$(env -u PATH "$script" --help)" 'USAGE'
check contains "$(env PATH=/nonexistent "$BASH" "$script" --prerequisites)" 'SITE-SPECIFIC SETUP'
check contains "$(env PATH=/nonexistent "$BASH" "$script" --completion bash)" '_complete-remote-scrcpy()'
check contains "$("$script" --help)" 'REMOTE_SCRCPY_HOST'
check contains "$("$script" --help)" 'EXIT STATUS'
# Errors name every place a rejected value can come from, not an internal
# name and not the option alone. No command here names a host: all stop at
# validation.
check contains "$(REMOTE_SCRCPY_ASCII=maybe "$script" --list-hosts 2>&1 || true)" 'REMOTE_SCRCPY_ASCII must be 0 or 1'
check contains "$(ADB_PORT=70000 "$script" --non-interactive --list-devices 2>&1 || true)" '(--adb-port, REMOTE_SCRCPY_ADB_PORT, or the fallback ADB_PORT)'
check contains "$(REMOTE_SCRCPY_COLOR=sometimes "$script" --list-hosts 2>&1 || true)" '(--color or REMOTE_SCRCPY_COLOR)'
check contains "$(REMOTE_ADB=$'two\nlines' "$script" --non-interactive --list-devices 2>&1 || true)" '(--remote-adb, REMOTE_SCRCPY_REMOTE_ADB, or the fallback REMOTE_ADB)'

# Every utility the launcher calls is looked for before it connects, so a
# missing one is reported at the start. The directory holds empty stand-ins:
# the check only asks whether each name resolves, and stand-ins keep the test
# independent of which real tools this machine has.
tools=$(mktemp -d)
for missing in cat env; do
    mkdir "$tools/without-$missing"
    for tool in ssh awk cat env mktemp rm sleep; do
        [[ $tool == "$missing" ]] || { : > "$tools/without-$missing/$tool"; chmod +x "$tools/without-$missing/$tool"; }
    done
    check contains "$(PATH=$tools/without-$missing "$BASH" "$script" --non-interactive --list-devices 2>&1 || true)" "Missing prerequisite: $missing"
    check status 127 env PATH="$tools/without-$missing" "$BASH" "$script" --non-interactive --list-devices
done
check contains "$(head -n 45 "$script")" 'INSTALL ON THE VIEWING COMPUTER'
check contains "$(head -n 45 "$script")" 'remote-scrcpy --help'
check contains "$(head -n 45 "$script")" 'remote-scrcpy --prerequisites'
check contains "$(head -n 45 "$script")" 'source <(remote-scrcpy --completion bash)'
check contains "$(head -n 90 "$script")" 'SETTINGS_SSH_HOST'
check contains "$(head -n 90 "$script")" 'SESSION_*'
# Regression guard: the old opaque RS_* prefix was replaced with SETTINGS_*/SESSION_*/etc.
if grep -Eq '\bRS_[[:upper:]_]+\b' "$script"; then fail 'Obsolete internal variable prefix found'; fi
passed=$((passed+1))
check status 2 "$script" --color wrong
check status 2 "$script" --ui plain
check status 2 env REMOTE_SCRCPY_ASCII=maybe "$script" --list-hosts
check status 2 "$script" --host a --host b --list-devices
check status 2 "$script" --serial a --serial b --list-devices
check status 2 "$script" --serial a --list-devices
check status 2 "$script" --host host --serial serial --list-hosts
check status 2 "$script" --bogus

# Source into isolated subshells; public application entry remains unused.
check equals "$(bash -c 'source "$1"; shift; _initialize-configuration; _parse-command-line "$@"; printf "%s|%s" "$SETTINGS_SSH_HOST" "$SETTINGS_DEVICE_SERIAL"' -- "$script" remote-host PHONE)" 'remote-host|PHONE'
check equals "$(bash -c 'source "$1"; shift; _initialize-configuration; _parse-command-line "$@"; printf "%s|%s" "$SETTINGS_SSH_HOST" "$SETTINGS_DEVICE_SERIAL"' -- "$script" --serial PHONE remote-host)" 'remote-host|PHONE'
check equals "$(REMOTE_SCRCPY_HOST=fromenv REMOTE_SCRCPY_SERIAL=one bash -c 'source "$1"; shift; _initialize-configuration; _parse-command-line "$@"; printf "%s|%s" "$SETTINGS_SSH_HOST" "$SETTINGS_DEVICE_SERIAL"' -- "$script" --host cli --serial two)" 'cli|two'
check equals "$(REMOTE_SCRCPY_HOST=fromenv bash -c 'source "$1"; shift; _initialize-configuration; _parse-command-line "$@"; printf "%s" "$SETTINGS_SSH_HOST"' -- "$script")" 'fromenv'
check equals "$(REMOTE_SCRCPY_COLOR=never bash -c 'source "$1"; shift; _initialize-configuration; _parse-command-line --color always; printf "%s" "$SETTINGS_COLOR_MODE"' -- "$script")" 'always'

# Host completion is local; device completion queries SSH unless disabled.
config=$(mktemp)
trap 'rm -f "$config"; rm -rf "${tools:-}"' EXIT
printf 'Host alpha beta\nHost gamma\n' > "$config"
check contains "$(REMOTE_SCRCPY_SSH_CONFIG=$config "$script" --list-hosts)" 'gamma'
# None of the local modes needs HOME.
check contains "$(env -u HOME "$script" --version)" '3.0.2'
check contains "$(env -u HOME "$script" --help)" 'USAGE'
check contains "$(env -u HOME "$script" --prerequisites)" 'SITE-SPECIFIC SETUP'
check contains "$(env -u HOME "$script" --completion bash)" '_complete-remote-scrcpy()'
check contains "$(env -u HOME "$script" --list-hosts --ssh-config "$config")" 'gamma'
# With HOME unset the default SSH config is found through the password
# database, as OpenSSH finds it. A home directory of "/" is a home like any
# other. Only an empty HOME leaves no default: listing hosts then prints
# nothing and succeeds. The resolved path is inspected instead of listed, so
# the suite never reads the configuration of whoever runs it.
# shellcheck disable=SC2016  # a script for another shell; it must expand there, not here
print_discovery_path='source "$1"; _initialize-configuration; printf "[%s]" "$SETTINGS_SSH_DISCOVERY_CONFIG_FILE"'
database_home=$(env -u HOME bash -c 'printf %s ~')
check equals "$(env -u HOME bash -c "$print_discovery_path" -- "$script")" "[$database_home/.ssh/config]"
check equals "$(env HOME=/ bash -c "$print_discovery_path" -- "$script")" '[//.ssh/config]'
check equals "$(env HOME= bash -c "$print_discovery_path" -- "$script")" '[]'
check equals "$(env HOME= "$script" --list-hosts; echo "rc=$?")" 'rc=0'
check bash -n <("$script" --completion bash)
# Explicitly exercise the emitted completion function with a prefixed SSH alias.
source <("$script" --completion bash)
COMP_WORDS=("$script" 'al') COMP_CWORD=1
REMOTE_SCRCPY_SSH_CONFIG=$config
_complete-remote-scrcpy
check equals "${COMPREPLY[*]}" 'alpha'
COMP_WORDS=("$script" --color a) COMP_CWORD=2
_complete-remote-scrcpy
check equals "${COMPREPLY[*]}" 'auto always'

# Regression guard: every fast suite clears the launcher's public environment
# as its first command after `set -euo pipefail`, so nothing in it can run
# with the developer's real host configured. Comments and blank lines aside,
# the scrub has to be the second line of the file.
for suite in "$project"/tests/test-*.sh; do
    # shellcheck disable=SC2016  # the literal text of the line is compared, nothing should expand
    [[ $(grep -vE '^[[:space:]]*(#|$)' "$suite" | sed -n 2p) == 'unset "${!REMOTE_SCRCPY_@}" ADB REMOTE_ADB ADB_PORT SCRCPY NO_COLOR' ]] \
        || fail "$(basename -- "$suite") does not clear the launcher environment first"
done
passed=$((passed+1))

# Regression guard: reject prior approaches that were deliberately rejected —
# a TUI framework dependency (gum), a --ui flag, and any base64-encoded
# embedded payload. The bundle must stay a plain Bash script.
if grep -Eiq '(^|[^[:alpha:]])gum([^[:alpha:]]|$)|future-ui|base64 --decode|--ui=' "$script"; then fail 'Removed dependency or option is still present in release'; fi
passed=$((passed+1))

printf 'Maintenance checks: %s passed.\n' "$passed"
