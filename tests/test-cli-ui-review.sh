#!/usr/bin/env bash
# Focused regressions for command-line continuation and unambiguous menu input.
set -euo pipefail
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

parse_scrcpy_values() (
    _initialize-configuration
    _parse-command-line "$@"
    printf '<%s>' "${SETTINGS_SCRCPY_EXTRA_ARGUMENTS[@]}"
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
    SETTINGS_SSH_HOST=alienware
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
    SETTINGS_SSH_HOST=alienware
    DISCOVERED_DEVICE_SERIALS=(PHONE_A 1)
    DISCOVERED_DEVICE_STATES=(device device)
    DISCOVERED_DEVICE_MODELS=(First Second)
    _prompt-for-device 2>/dev/null
    printf '%s' "$SETTINGS_DEVICE_SERIAL"
)

expect_output 'No destination arguments preserve both interactive steps' '|' parse_destinations
expect_output 'Positional host skips only the host picker' 'alienware|' parse_destinations alienware
expect_output 'Both positionals skip both pickers' 'alienware|PHONE_A' parse_destinations alienware PHONE_A
expect_output 'Named host plus positional serial' 'alienware|PHONE_A' parse_destinations --host alienware PHONE_A
expect_output 'Named serial plus positional host' 'alienware|PHONE_A' parse_destinations --serial PHONE_A alienware
expect_output 'Named serial alone preserves host picker' '|PHONE_A' parse_destinations --serial=PHONE_A
expect_output 'Duplicate host rejected' '2' exit_status parse_destinations alienware --host other
expect_output 'Duplicate serial rejected' '2' exit_status parse_destinations alienware PHONE_A --serial other
expect_output 'Extra positional rejected' '2' exit_status parse_destinations alienware PHONE_A extra
expect_output 'Quoted scrcpy option values survive parsing' '<--record><phone capture.mkv><--max-size=1280>' \
    parse_scrcpy_values alienware PHONE_A -- --record 'phone capture.mkv' --max-size=1280
expect_output 'Manual numeric SSH destination is not a menu number' '1' choose_numeric_manual_host
expect_output 'A displayed device number always selects that row' 'PHONE_A' choose_device_by_displayed_number
expect_output 'Huge host menu numbers cannot become unintended destinations' 'alpha' reject_huge_host_menu_number
expect_output 'Exact serial entry disambiguates a numeric device serial' '1' choose_exact_numeric_device_serial
expect_output 'Default presentation uses automatic color and symbols' 'auto|0||' parse_presentation
expect_output 'Color option retains host-only continuation' 'never|0|alienware|' \
    parse_presentation --color never alienware
expect_output 'Equals color and ASCII options retain explicit device' 'always|1|alienware|PHONE_A' \
    parse_presentation alienware PHONE_A --color=always --ascii
expect_output 'Removed UI option is rejected' '2' exit_status validate_configuration --ui gum
expect_output 'Unknown interface is rejected' '2' exit_status validate_configuration --ui invalid
expect_output 'Empty interface is rejected' '2' exit_status parse_destinations --ui=
expect_output 'Unknown color policy is rejected' '2' exit_status validate_configuration --color invalid
expect_output 'Empty color policy is rejected' '2' exit_status parse_presentation --color=
expect_output 'Missing color value is rejected' '2' exit_status parse_presentation --color

printf 'CLI/menu review checks: %s passed, %s failed.\n' "$passed" "$failed"
(( failed == 0 ))
