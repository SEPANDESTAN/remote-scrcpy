#!/usr/bin/env bash
# Focused regressions for command-line continuation and unambiguous menu input.
set -euo pipefail
# The suite must never see the developer's own launcher configuration: with a
# host exported, an inherited environment once made a check contact it.
unset "${!REMOTE_SCRCPY_@}" ADB REMOTE_ADB ADB_PORT SCRCPY NO_COLOR
# Nor may any child inherit the caller's standard input: docs/testing.md,
# "Environment", has the reason. Not dead code; the maintenance suite checks it.
exec < /dev/null
review_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$review_dir/src/core.sh"
source "$review_dir/src/cli.sh"
source "$review_dir/src/presentation.sh"
source "$review_dir/src/ui.sh"
passed=0
failed=0

expect_output() {
    local label=$1 expected=$2 actual
    shift 2
    if actual=$("$@"); then
        if [[ $actual == "$expected" ]]; then
            passed=$((passed + 1)); return 0
        fi
    fi
    printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$label" "$expected" "$actual" >&2
    failed=$((failed + 1))
}

parse_destinations() (
    _initialize-configuration
    _parse-command-line "$@"
    printf '%s|%s' "$SETTINGS_SSH_HOST" "$SETTINGS_DEVICE_SERIAL"
)

# What a command line makes the launcher do: connect, hosts, devices,
# prerequisites or completion.
parse_operation() (
    _initialize-configuration
    _parse-command-line "$@"
    printf '%s' "$SETTINGS_OPERATION"
)

# The usage error a command line is refused with, or "accepted".
parse_refusal() (
    _initialize-configuration
    local message
    if message=$(_parse-command-line "$@" 2>&1 > /dev/null); then
        printf 'accepted'
    else
        printf '%s' "${message#*remote-scrcpy: }"
    fi
)

# Run a command with a host and a serial that come from the environment only.
with_environment_destination() (
    export REMOTE_SCRCPY_HOST=remote-host REMOTE_SCRCPY_SERIAL=PHONE_A
    "$@"
)

parse_scrcpy_values() (
    _initialize-configuration
    _parse-command-line "$@"
    printf '<%s>' "${SETTINGS_SCRCPY_EXTRA_ARGUMENTS[@]}"
)

# Whether status output would be colored for a color mode and a NO_COLOR value
# (empty for unset). The mode is set directly, or read from the environment
# when written as env:MODE. Styles are decided with standard error detached,
# so the result does not depend on where the suite was started; the price is
# that the terminal half of the auto mode cannot be reached here.
color_state() (
    if [[ $1 == env:* ]]; then export REMOTE_SCRCPY_COLOR=${1#env:}; fi
    _initialize-configuration
    [[ $1 == env:* ]] || SETTINGS_COLOR_MODE=$1
    if [[ -n $2 ]]; then export NO_COLOR=$2; else unset NO_COLOR; fi
    _initialize-terminal-styles 2>/dev/null
    if [[ -n $DISPLAY_COLOR_RESET ]]; then printf on; else printf off; fi
)

parse_presentation() (
    _initialize-configuration
    _parse-command-line "$@"
    printf '%s|%s|%s|%s' "$SETTINGS_COLOR_MODE" "$SETTINGS_ASCII_ONLY" "$SETTINGS_SSH_HOST" "$SETTINGS_DEVICE_SERIAL"
)

validate_configuration() (
    _initialize-configuration
    SETTINGS_REMOTE_ADB_SERVER_PORT=5037
    _parse-command-line "$@"
    _validate-configuration
)

# The message printed when a scrcpy option after -- is refused.
scrcpy_argument_error() {
    ( _initialize-configuration
      _parse-command-line remote-host PHONE_A -- "$@"
      _validate-scrcpy-arguments ) 2>&1 || true
}

exit_status() (
    local result=0
    "$@" >/dev/null 2>&1 || result=$?
    printf '%s' "$result"
)

# Menus use fixture answers without requiring a controlling terminal.
fixture_ui() {
    _require-interactive-terminal() { :; }
    _read-user-response() {
        (( ${#fixture_answers[@]} )) || _exit-with-error 'Unexpected additional test prompt.' 99
        INPUT_RESPONSE=${fixture_answers[0]}
        fixture_answers=("${fixture_answers[@]:1}")
    }
}

choose_numeric_manual_host() (
    _initialize-configuration
    fixture_ui
    local -a fixture_answers=(m 1)
    _discover-ssh-host-aliases() { printf '%s\n' alpha 1; }
    _prompt-for-ssh-host 2>/dev/null
    printf '%s' "$SETTINGS_SSH_HOST"
)

choose_device_by_displayed_number() (
    _initialize-configuration
    fixture_ui
    local -a fixture_answers=(1)
    SETTINGS_SSH_HOST=remote-host
    DISCOVERED_DEVICE_SERIALS=(PHONE_A 1)
    DISCOVERED_DEVICE_STATES=(device device)
    DISCOVERED_DEVICE_MODELS=(First Second)
    _prompt-for-device 2>/dev/null
    printf '%s' "$SETTINGS_DEVICE_SERIAL"
)

reject_huge_host_menu_number() (
    _initialize-configuration
    fixture_ui
    local -a fixture_answers=(999999999999999999999999 1)
    _discover-ssh-host-aliases() { printf '%s\n' alpha beta; }
    _prompt-for-ssh-host 2>/dev/null
    printf '%s' "$SETTINGS_SSH_HOST"
)

choose_exact_numeric_device_serial() (
    _initialize-configuration
    fixture_ui
    local -a fixture_answers=(s 1)
    SETTINGS_SSH_HOST=remote-host
    DISCOVERED_DEVICE_SERIALS=(PHONE_A 1)
    DISCOVERED_DEVICE_STATES=(device device)
    DISCOVERED_DEVICE_MODELS=(First Second)
    _prompt-for-device 2>/dev/null
    printf '%s' "$SETTINGS_DEVICE_SERIAL"
)

expect_output 'No destination arguments preserve both interactive steps' '|' parse_destinations
expect_output 'Positional host skips only the host picker' 'remote-host|' parse_destinations remote-host
expect_output 'Both positionals skip both pickers' 'remote-host|PHONE_A' parse_destinations remote-host PHONE_A
expect_output 'Named host plus positional serial' 'remote-host|PHONE_A' parse_destinations --host remote-host PHONE_A
expect_output 'Named serial plus positional host' 'remote-host|PHONE_A' parse_destinations --serial PHONE_A remote-host
expect_output 'Named serial alone preserves host picker' '|PHONE_A' parse_destinations --serial=PHONE_A
expect_output 'Duplicate host rejected' '2' exit_status parse_destinations remote-host --host other
expect_output 'Duplicate serial rejected' '2' exit_status parse_destinations remote-host PHONE_A --serial other
expect_output 'Extra positional rejected' '2' exit_status parse_destinations remote-host PHONE_A extra
# One mode per run: each mode option alone selects its mode, and any two of
# them, the same one twice included, are refused the same way in either order.
modes=(--list-hosts --list-devices --prerequisites --completion=bash)
operations=(hosts devices prerequisites completion)
for index in "${!modes[@]}"; do
    expect_output "${modes[index]} alone selects its mode" "${operations[index]}" parse_operation "${modes[index]}"
    for second in "${modes[@]}"; do
        expect_output "${modes[index]} then $second is refused" \
            'Choose only one of --list-hosts, --list-devices, --prerequisites and --completion.' \
            parse_refusal "${modes[index]}" "$second"
        expect_output "${modes[index]} then $second exits with status 2" '2' exit_status parse_operation "${modes[index]}" "$second"
    done
done
# The two-word form of --completion is a mode option like the others.
one_mode='Choose only one of --list-hosts, --list-devices, --prerequisites and --completion.'
expect_output '--completion bash alone selects its mode' 'completion' parse_operation --completion bash
for second in --list-hosts --list-devices --prerequisites; do
    expect_output "--completion bash then $second is refused" "$one_mode" parse_refusal --completion bash "$second"
    expect_output "$second then --completion bash is refused" "$one_mode" parse_refusal "$second" --completion bash
done
expect_output 'No mode option means connect' 'connect' parse_operation remote-host
# A host or serial belongs to a connection or to the device list only.
expect_output '--list-devices takes a host' 'devices' parse_operation --list-devices remote-host
expect_output '--list-devices refuses a serial' '--list-devices does not take a serial.' parse_refusal --list-devices remote-host PHONE_A
expect_output '--list-hosts refuses a host' '--list-hosts does not take a host or serial.' parse_refusal remote-host --list-hosts
expect_output '--prerequisites refuses a host' '--prerequisites does not take a host or serial.' parse_refusal remote-host --prerequisites
expect_output '--prerequisites refuses a serial' '--prerequisites does not take a host or serial.' parse_refusal --prerequisites --serial PHONE_A
expect_output '--completion refuses a host' '--completion does not take a host or serial.' parse_refusal --completion bash remote-host
# Only what is typed counts: a host and serial that come from the
# environment, as in a shell set up for daily use, refuse none of these.
expect_output 'An environment destination does not refuse --prerequisites' 'prerequisites' with_environment_destination parse_operation --prerequisites
expect_output 'An environment destination does not refuse --completion' 'completion' with_environment_destination parse_operation --completion bash
expect_output 'An environment destination does not refuse --list-hosts' 'hosts' with_environment_destination parse_operation --list-hosts
expect_output 'An environment serial does not refuse --list-devices' 'devices' with_environment_destination parse_operation --list-devices
# Only a connection starts scrcpy, so only it takes options after --.
for index in "${!modes[@]}"; do
    expect_output "${modes[index]} refuses scrcpy options" "${modes[index]%%=*} does not take scrcpy options." \
        parse_refusal "${modes[index]}" -- --max-size=1024
done
expect_output 'A connection takes scrcpy options' 'connect' parse_operation remote-host -- --max-size=1024
expect_output 'Quoted scrcpy option values survive parsing' '<--record><phone capture.mkv><--max-size=1280>' \
    parse_scrcpy_values remote-host PHONE_A -- --record 'phone capture.mkv' --max-size=1280
expect_output 'Manual numeric SSH destination is not a menu number' '1' choose_numeric_manual_host
expect_output 'A displayed device number always selects that row' 'PHONE_A' choose_device_by_displayed_number
expect_output 'Huge host menu numbers cannot become unintended destinations' 'alpha' reject_huge_host_menu_number
expect_output 'Exact serial entry disambiguates a numeric device serial' '1' choose_exact_numeric_device_serial
expect_output 'Default presentation uses automatic color and symbols' 'auto|0||' parse_presentation
expect_output 'An explicit always colors without a terminal' 'on' color_state always ''
expect_output 'An explicit always overrides NO_COLOR' 'on' color_state always 1
expect_output 'An explicit never stays uncolored' 'off' color_state never ''
expect_output 'Always from the environment overrides NO_COLOR too' 'on' color_state env:always 1
expect_output 'Auto does not color without a terminal' 'off' color_state auto ''
expect_output 'Color option retains host-only continuation' 'never|0|remote-host|' \
    parse_presentation --color never remote-host
expect_output 'Equals color and ASCII options retain explicit device' 'always|1|remote-host|PHONE_A' \
    parse_presentation remote-host PHONE_A --color=always --ascii
expect_output 'A dash-led value is refused with a way out' \
    "x remote-scrcpy: Use separate short flags or full long options after --: -1920 (If it is an option's value, write --option=value.)" \
    scrcpy_argument_error --window-x -1920
expect_output 'A value that looks like a managed flag gets the same hint' \
    "x remote-scrcpy: The launcher manages -demo. (If it is an option's value, write --option=value.)" \
    scrcpy_argument_error --window-title -demo
expect_output 'The same value is accepted in the = form' '' scrcpy_argument_error --window-x=-1920
expect_output 'Removed UI option is rejected' '2' exit_status validate_configuration --ui gum
expect_output 'Unknown interface is rejected' '2' exit_status validate_configuration --ui invalid
expect_output 'Empty interface is rejected' '2' exit_status parse_destinations --ui=
expect_output 'Unknown color policy is rejected' '2' exit_status validate_configuration --color invalid
expect_output 'Empty color policy is rejected' '2' exit_status parse_presentation --color=
expect_output 'Missing color value is rejected' '2' exit_status parse_presentation --color

printf 'CLI/menu review checks: %s passed, %s failed.\n' "$passed" "$failed"
(( failed == 0 ))
