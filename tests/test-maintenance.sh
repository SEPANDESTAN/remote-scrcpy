#!/usr/bin/env bash
# Fast dependency-free maintenance regressions. No remote SSH/ADB required.
set -euo pipefail
project=$(cd -- "$(dirname -- "$0")/.." && pwd)
script=$project/remote-scrcpy.sh
passed=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
check() { "$@" || fail "$*"; passed=$((passed+1)); }
contains() { [[ $1 == *"$2"* ]]; }
equals() { [[ $1 == "$2" ]]; }
status() { local wanted=$1; shift; local result=0; "$@" >/dev/null 2>&1 || result=$?; [[ $result == "$wanted" ]]; }

check bash -n "$script"
check contains "$("$script" --version)" '3.0.1'
check contains "$(env -u PATH "$script" --help)" 'USAGE'
check contains "$(env PATH=/nonexistent /bin/bash "$script" --prerequisites)" 'SITE-SPECIFIC SETUP'
check contains "$(env PATH=/nonexistent /bin/bash "$script" --completion bash)" '_complete-remote-scrcpy()'
check contains "$("$script" --help)" 'REMOTE_SCRCPY_HOST'
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
check equals "$(bash -c 'source "$1"; shift; _initialize-configuration; _parse-command-line "$@"; printf "%s|%s" "$SETTINGS_SSH_HOST" "$SETTINGS_DEVICE_SERIAL"' -- "$script" alienware PHONE)" 'alienware|PHONE'
check equals "$(bash -c 'source "$1"; shift; _initialize-configuration; _parse-command-line "$@"; printf "%s|%s" "$SETTINGS_SSH_HOST" "$SETTINGS_DEVICE_SERIAL"' -- "$script" --serial PHONE alienware)" 'alienware|PHONE'
check equals "$(REMOTE_SCRCPY_HOST=fromenv REMOTE_SCRCPY_SERIAL=one bash -c 'source "$1"; shift; _initialize-configuration; _parse-command-line "$@"; printf "%s|%s" "$SETTINGS_SSH_HOST" "$SETTINGS_DEVICE_SERIAL"' -- "$script" --host cli --serial two)" 'cli|two'
check equals "$(REMOTE_SCRCPY_HOST=fromenv bash -c 'source "$1"; shift; _initialize-configuration; _parse-command-line "$@"; printf "%s" "$SETTINGS_SSH_HOST"' -- "$script")" 'fromenv'
check equals "$(REMOTE_SCRCPY_COLOR=never bash -c 'source "$1"; shift; _initialize-configuration; _parse-command-line --color always; printf "%s" "$SETTINGS_COLOR_MODE"' -- "$script")" 'always'

# Host completion is local; device completion queries SSH unless disabled.
config=$(mktemp)
trap 'rm -f "$config"' EXIT
printf 'Host alpha beta\nHost gamma\n' > "$config"
check contains "$(REMOTE_SCRCPY_SSH_CONFIG=$config "$script" --list-hosts)" 'gamma'
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

# Regression guard: reject prior approaches that were deliberately rejected —
# a TUI framework dependency (gum), a --ui flag, and any base64-encoded
# embedded payload. The bundle must stay a plain Bash script.
if grep -Eiq '(^|[^[:alpha:]])gum([^[:alpha:]]|$)|future-ui|base64 --decode|--ui=' "$script"; then fail 'Removed dependency or option is still present in release'; fi
passed=$((passed+1))

printf 'Maintenance checks: %s passed.\n' "$passed"
