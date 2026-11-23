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

# Everything the options without a value can set:
# operation|verbose|quiet|non-interactive|ascii|color mode.
parse_flags() (
    _initialize-configuration
    _parse-command-line "$@"
    printf '%s|%s|%s|%s|%s|%s' "$SETTINGS_OPERATION" "$SETTINGS_VERBOSE" "$SETTINGS_QUIET" \
        "$SETTINGS_NON_INTERACTIVE" "$SETTINGS_ASCII_ONLY" "$SETTINGS_COLOR_MODE"
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

# Put a terminal on standard error, or take it away, for the styles: the
# launcher asks one function, and the suite answers for it. The result then
# does not depend on where the suite was started. Args: `terminal` or
# anything else; TERM, or `unset` for none (default xterm).
pretend_stderr() {
    if [[ $1 == terminal ]]; then _stderr-is-terminal() { return 0; }
    else _stderr-is-terminal() { return 1; }; fi
    if [[ ${2:-xterm} == unset ]]; then unset TERM; else TERM=${2:-xterm}; fi
}

# Whether status output would be colored. Args: the color mode, set directly
# or read from the environment when written as env:MODE; NO_COLOR ('' for
# unset, `empty` for set to nothing); then what pretend_stderr takes.
color_state() (
    if [[ $1 == env:* ]]; then export REMOTE_SCRCPY_COLOR=${1#env:}; fi
    _initialize-configuration
    [[ $1 == env:* ]] || SETTINGS_COLOR_MODE=$1
    case $2 in
        '') unset NO_COLOR ;;
        empty) export NO_COLOR= ;;
        *) export NO_COLOR=$2 ;;
    esac
    pretend_stderr "${3:-}" "${4:-}"
    _initialize-terminal-styles 2>/dev/null
    if [[ -n $DISPLAY_COLOR_RESET ]]; then printf on; else printf off; fi
)

# The mark in front of a success message. Args: what pretend_stderr takes
# first, 1 for --ascii, then the locale as NAME=value words for LC_ALL,
# LC_CTYPE and LANG; a variable not given is unset. The launcher reads the
# locale's name only, so the locale need not be installed.
success_symbol() (
    local assignment
    _initialize-configuration
    SETTINGS_ASCII_ONLY=$2
    pretend_stderr "$1"
    shift 2
    {
        unset LC_ALL LC_CTYPE LANG
        for assignment in "$@"; do export "${assignment?}"; done
    } 2>/dev/null
    _initialize-terminal-styles 2>/dev/null
    printf '%s' "$DISPLAY_SYMBOL_SUCCESS"
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

# What the display sanitizer prints for a text, together with anything it
# writes to standard error, under a locale name. Args: LC_ALL, the text.
sanitized_under() (
    { export LC_ALL=$1; } 2>/dev/null
    _sanitize-display-text "$2" 2>&1
)

# The caller's locale after the sanitizer was called directly, not in a
# command substitution.
locale_after_sanitizing() (
    { LC_ALL=C.UTF-8; } 2>/dev/null
    _sanitize-display-text text > /dev/null
    printf '%s' "$LC_ALL"
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

# A menu answer written in the digits of another script, in a locale where the
# range 0-9 would match them. `wide_locale` and `other_digit` are set below.
answer_host_menu_in_other_digits() (
    LC_ALL=$wide_locale
    _initialize-configuration
    fixture_ui
    local -a fixture_answers=("$other_digit" q)
    _discover-ssh-host-aliases() { printf '%s\n' alpha beta gamma; }
    _prompt-for-ssh-host 2>/dev/null
    printf '%s' "$SETTINGS_SSH_HOST"
)

answer_device_menu_in_other_digits() (
    LC_ALL=$wide_locale
    _initialize-configuration
    fixture_ui
    local -a fixture_answers=("$other_digit" 2)
    SETTINGS_SSH_HOST=remote-host
    DISCOVERED_DEVICE_SERIALS=(PHONE_A PHONE_B PHONE_C)
    DISCOVERED_DEVICE_STATES=(device device device)
    DISCOVERED_DEVICE_MODELS=(First Second Third)
    _prompt-for-device 2>/dev/null
    printf '%s' "$SETTINGS_DEVICE_SERIAL"
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
expect_output 'Scrcpy options next to a mode exit with status 2' '2' exit_status parse_operation --prerequisites -- --max-size=1024
# Each one-letter option does what its long name does, and nothing else.
expect_output 'No option leaves every flag off' 'connect|0|0|0|0|auto' parse_flags
short_forms=('-l --list-devices devices|0|0|0|0|auto' '-L --list-hosts hosts|0|0|0|0|auto'
    '-p --prerequisites prerequisites|0|0|0|0|auto' '-q --quiet connect|0|1|0|0|auto'
    '-n --non-interactive connect|0|0|1|0|auto' '-V --verbose connect|1|0|0|0|auto')
for form in "${short_forms[@]}"; do
    read -r short long flags <<< "$form"
    expect_output "$long sets what it should" "$flags" parse_flags "$long"
    expect_output "$short is $long" "$flags" parse_flags "$short"
done
# -v is the version and stops there; -V, which used to be the version, is not.
expect_output '--version prints the version' "remote-scrcpy $(_initialize-configuration; printf '%s' "$APPLICATION_VERSION")" parse_flags --version
expect_output '-v is --version' "$(parse_flags --version)" parse_flags -v
expect_output '-v exits with status 0' '0' exit_status parse_flags -v
# The mode rule and the host rule hold for the short forms too.
expect_output '-l then -L is refused' "$one_mode" parse_refusal -l -L
expect_output '-p then --completion bash is refused' "$one_mode" parse_refusal -p --completion bash
expect_output '-p refuses a host' '--prerequisites does not take a host or serial.' parse_refusal remote-host -p 27183
expect_output '-L refuses a host' '--list-hosts does not take a host or serial.' parse_refusal -L remote-host
expect_output '-l takes a host' 'devices|0|0|0|0|auto' parse_flags -l remote-host
# One letter per word: letters are not bundled.
expect_output 'Bundled short options are refused' 'Unknown launcher option: -ql. Put scrcpy options after --.' parse_refusal -ql
expect_output 'Separate short options combine' 'devices|0|1|1|0|auto' parse_flags -q -n -l remote-host
expect_output 'Quoted scrcpy option values survive parsing' '<--record><phone capture.mkv><--max-size=1280>' \
    parse_scrcpy_values remote-host PHONE_A -- --record 'phone capture.mkv' --max-size=1280
expect_output 'Manual numeric SSH destination is not a menu number' '1' choose_numeric_manual_host
expect_output 'A displayed device number always selects that row' 'PHONE_A' choose_device_by_displayed_number
expect_output 'Huge host menu numbers cannot become unintended destinations' 'alpha' reject_huge_host_menu_number
expect_output 'Exact serial entry disambiguates a numeric device serial' '1' choose_exact_numeric_device_serial
# Only the ten ASCII digits make a menu number. In some locales the range 0-9
# in a pattern also matches the digits of other scripts, and an answer in
# those went on into arithmetic and ended the launcher with a Bash error.
# These checks need such a locale, or they could not fail.
other_digit=$'\xd9\xa3'   # ARABIC-INDIC DIGIT THREE
wide_locale=''
for candidate in en_US.UTF-8 en_GB.UTF-8 de_DE.UTF-8; do
    # C first: a locale that cannot be set then leaves the probe in C, where
    # the range is plain, and not in whatever locale the suite was started in.
    if (LC_ALL=C; LC_ALL=$candidate; [[ $other_digit =~ ^[0-9]$ ]]) 2>/dev/null; then wide_locale=$candidate; break; fi
done
if [[ -n $wide_locale ]]; then
    expect_output 'A host menu answer in other digits is a destination name, not row 3' "$other_digit" answer_host_menu_in_other_digits
    expect_output 'A device menu answer in other digits is not a row; the menu asks again' 'PHONE_B' answer_device_menu_in_other_digits
else
    printf 'note: no installed locale widens the digit range; the menu checks in such a locale were not run.\n' >&2
fi
# Text from the phone or the remote is cleaned before it is shown.
expect_output 'Control characters in display text become question marks' 'a?[31mb?c' sanitized_under C $'a\033[31mb\007c'
# The sample has letters whose encoding holds a byte from 0x80 to 0x9F (the
# first of the Cyrillic word, the last letter), which a cruder rule would hit.
expect_output 'Text in other scripts passes unchanged' 'né 中 س Привет À' sanitized_under C.UTF-8 'né 中 س Привет À'
# The sanitizer works in the C locale and must leave no trace of that: no
# warning from Bash where the caller's locale is not installed, and the
# caller's locale as it was. The first of the two can fail only where Bash
# is told that the locale is missing; some C libraries accept any name.
if [[ -n $( (LC_ALL=xx_XX.UTF-8) 2>&1) ]]; then
    expect_output 'A locale that is not installed adds no warning to display text' 'a?b' sanitized_under xx_XX.UTF-8 $'a\033b'
else
    printf 'note: this C library accepts a locale name that is not installed; the warning check was not run.\n' >&2
fi
expect_output 'The sanitizer leaves the caller its locale' 'C.UTF-8' locale_after_sanitizing
expect_output 'Default presentation uses automatic color and symbols' 'auto|0||' parse_presentation
expect_output 'An explicit always colors without a terminal' 'on' color_state always ''
expect_output 'An explicit always overrides NO_COLOR' 'on' color_state always 1
expect_output 'An explicit never stays uncolored' 'off' color_state never ''
expect_output 'Always from the environment overrides NO_COLOR too' 'on' color_state env:always 1
expect_output 'Auto does not color without a terminal' 'off' color_state auto ''
# The automatic mode on a terminal: it colors, unless NO_COLOR has a value or
# the terminal cannot show it.
expect_output 'Auto colors on a terminal' 'on' color_state auto '' terminal
expect_output 'Auto from the environment colors on a terminal' 'on' color_state env:auto '' terminal
expect_output 'Auto on a terminal obeys NO_COLOR' 'off' color_state auto 1 terminal
expect_output 'An empty NO_COLOR counts as not set' 'on' color_state auto empty terminal
expect_output 'Auto does not color a dumb terminal' 'off' color_state auto '' terminal dumb
expect_output 'Auto does not color without TERM' 'off' color_state auto '' terminal unset
expect_output 'Never stays uncolored on a terminal' 'off' color_state never '' terminal
expect_output 'Always colors a dumb terminal too' 'on' color_state always '' terminal dumb
# The symbols need a terminal and a UTF-8 locale, and --ascii turns them off.
expect_output 'A terminal in a UTF-8 locale gets the Unicode marks' '✓' success_symbol terminal 0 LC_ALL=C.UTF-8
expect_output 'A locale that is not UTF-8 gets the ASCII marks' '+' success_symbol terminal 0 LC_ALL=C
expect_output 'No locale at all gets the ASCII marks' '+' success_symbol terminal 0
expect_output '--ascii gets the ASCII marks on any terminal' '+' success_symbol terminal 1 LC_ALL=C.UTF-8
expect_output 'Without a terminal the marks are ASCII' '+' success_symbol none 0 LC_ALL=C.UTF-8
# The locale is read as the C library reads it: LC_ALL, then LC_CTYPE, then LANG.
expect_output 'LC_CTYPE alone names the locale' '✓' success_symbol terminal 0 LC_CTYPE=C.UTF-8
expect_output 'LANG alone names the locale' '✓' success_symbol terminal 0 LANG=C.UTF-8
expect_output 'LC_ALL comes before LC_CTYPE and LANG' '+' success_symbol terminal 0 LC_ALL=C LC_CTYPE=C.UTF-8 LANG=C.UTF-8
expect_output 'LC_CTYPE comes before LANG' '+' success_symbol terminal 0 LC_CTYPE=C LANG=C.UTF-8
expect_output 'LC_CTYPE comes before LANG, the other way round' '✓' success_symbol terminal 0 LC_CTYPE=C.UTF-8 LANG=C
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
