# Application configuration, validation, and common presentation helpers.
# The public entry point is remote-scrcpy; all helpers are prefixed with _.
# Configuration precedence: command line > REMOTE_SCRCPY_* environment > defaults.
#
# Shared state glossary (Bash has no modules, so these globals are intentional):
#   APPLICATION_VERSION              Program version; shown by --version.
#   SETTINGS_*                       Resolved configuration/CLI choices. These are
#                                    not themselves exported environment variables.
#   SETTINGS_SSH_HOST                SSH destination selected by the user.
#   SETTINGS_DEVICE_SERIAL           Exact ADB serial selected by the user.
#   SETTINGS_SSH_CONFIG_FILE         Optional alternate SSH client configuration.
#   SETTINGS_SSH_DISCOVERY_CONFIG_FILE  Config file scanned for Host menu aliases.
#   SETTINGS_LOCAL_ADB_EXECUTABLE    Viewer-side adb command; resolved to a path.
#   SETTINGS_REMOTE_ADB_EXECUTABLE   Remote-side adb command/path, quoted for SSH.
#   SETTINGS_REMOTE_ADB_SERVER_PORT  Port of remote ADB daemon (default 5037).
#   SETTINGS_LOCAL_SCRCPY_EXECUTABLE Viewer-side scrcpy binary.
#   SETTINGS_OPERATION              connect | hosts | devices | prerequisites | completion.
#   SETTINGS_SCRCPY_EXTRA_ARGUMENTS  Arguments after --, kept as a Bash array.
#   DISCOVERED_DEVICE_*              Parallel arrays of serial, state, model.
#   CLI_*_EXPLICIT                   Whether an argument appeared on the CLI.
#   INPUT_RESPONSE                   Latest ordinary line-input response.
#   DISPLAY_COLOR_* / DISPLAY_SYMBOL_*  Terminal styling; no output parsing relies on it.
#   SESSION_*                        Owned SSH/ADB/scrcpy resources; see transport.sh.
#
# Keep external environment names (REMOTE_SCRCPY_*) distinct from internal
# globals. Helpers update explicitly documented globals; do not export these
# variables or interpret untrusted data with eval. No network I/O occurs here.

# Initialize configuration and clear UI selections before processing arguments.
# Outputs: SETTINGS_*, DISCOVERED_DEVICE_*, INPUT/display variables; no I/O.
_initialize-configuration() {
    APPLICATION_VERSION=3.1.0
    # Public environment inputs are read once. CLI flags always override them.
    SETTINGS_SSH_HOST=${REMOTE_SCRCPY_HOST:-}
    SETTINGS_DEVICE_SERIAL=${REMOTE_SCRCPY_SERIAL:-}
    SETTINGS_SSH_CONFIG_FILE=${REMOTE_SCRCPY_SSH_CONFIG:-}
    # The default SSH config sits in the home directory. With HOME unset, ~
    # comes from the password database, which is where OpenSSH looks too. An
    # empty HOME is no home: then there is no default config, and nothing
    # else needs one.
    local home=${HOME-~}
    [[ $home == /* ]] || home=''
    SETTINGS_SSH_DISCOVERY_CONFIG_FILE=${SETTINGS_SSH_CONFIG_FILE:-${home:+$home/.ssh/config}}
    SETTINGS_LOCAL_ADB_EXECUTABLE=${REMOTE_SCRCPY_ADB:-${ADB:-adb}}
    SETTINGS_REMOTE_ADB_EXECUTABLE=${REMOTE_SCRCPY_REMOTE_ADB:-${REMOTE_ADB:-adb}}
    SETTINGS_REMOTE_ADB_SERVER_PORT=${REMOTE_SCRCPY_ADB_PORT:-${ADB_PORT:-5037}}
    SETTINGS_LOCAL_SCRCPY_EXECUTABLE=${REMOTE_SCRCPY_SCRCPY:-${SCRCPY:-scrcpy}}
    SETTINGS_VERBOSE=${REMOTE_SCRCPY_VERBOSE:-0}
    SETTINGS_QUIET=${REMOTE_SCRCPY_QUIET:-0}
    SETTINGS_NON_INTERACTIVE=${REMOTE_SCRCPY_NON_INTERACTIVE:-0}
    SETTINGS_COLOR_MODE=${REMOTE_SCRCPY_COLOR:-auto}
    SETTINGS_ASCII_ONLY=${REMOTE_SCRCPY_ASCII:-0}
    # Errors may occur before style setup. Never inherit terminal control text.
    DISPLAY_COLOR_RESET= DISPLAY_COLOR_BOLD= DISPLAY_COLOR_MUTED= DISPLAY_COLOR_SECTION= DISPLAY_COLOR_PROMPT=
    DISPLAY_COLOR_SUCCESS= DISPLAY_COLOR_WARNING= DISPLAY_COLOR_ERROR= DISPLAY_COLOR_INFO=
    DISPLAY_SYMBOL_SECTION='>' DISPLAY_SYMBOL_PROMPT='>' DISPLAY_SYMBOL_SUCCESS='+'
    DISPLAY_SYMBOL_WARNING='!' DISPLAY_SYMBOL_ERROR='x' DISPLAY_SYMBOL_INFO='*'
    # connect | hosts | devices | prerequisites | completion; only connect opens scrcpy.
    SETTINGS_OPERATION=connect
    # Passed exactly to scrcpy after the command-line `--` separator.
    SETTINGS_SCRCPY_EXTRA_ARGUMENTS=()
    # Parallel arrays: index i always describes the same Android device.
    DISCOVERED_DEVICE_SERIALS=()
    DISCOVERED_DEVICE_STATES=()
    DISCOVERED_DEVICE_MODELS=()
}

# Display a contextual error/cancellation and terminate.
# Args: message, optional exit status; may trigger EXIT cleanup trap.
_exit-with-error() {
    if [[ ${2:-1} == 130 ]]; then
        _print-styled-message "$DISPLAY_COLOR_MUTED" "$DISPLAY_SYMBOL_INFO" "remote-scrcpy: $1"
    else
        _print-styled-message "$DISPLAY_COLOR_ERROR" "$DISPLAY_SYMBOL_ERROR" "remote-scrcpy: $1"
    fi
    exit "${2:-1}"
}

# Print normal progress unless quiet mode is enabled.
# Args: message words; stderr only.
_log-status() {
    if (( ! SETTINGS_QUIET )); then
        _print-styled-message "$DISPLAY_COLOR_INFO" "$DISPLAY_SYMBOL_INFO" "remote-scrcpy: $*"
    fi
    return 0
}

# Print verbose details when enabled.
# Args: message words; stderr only.
_log-debug() {
    if (( SETTINGS_VERBOSE )); then _print-styled-message "$DISPLAY_COLOR_MUTED" "$DISPLAY_SYMBOL_INFO" "remote-scrcpy [debug]: $*"; fi
    return 0
}

# Strip control characters from untrusted displayed metadata.
# Args: one string; prints sanitized representation to stdout.
_sanitize-display-text() (
    # Device descriptions and config aliases must not inject terminal controls.
    # The body is a subshell, so the locale set here ends with it. A local
    # variable would be put back on return, and Bash prints a warning when
    # the value it puts back names a locale that is not installed.
    #
    # Two rules, both byte by byte in the C locale, so that the result is
    # the same whatever the caller's locale is. The controls of ASCII. And
    # the eight-bit controls, U+0080 to U+009F, as UTF-8 writes them: the
    # byte 0xC2 and one from 0x80 to 0x9F. U+009B opens a control sequence
    # like ESC [ does, and a terminal in UTF-8 mode obeys it (VTE does).
    # Only that pair is taken: after another lead byte the same bytes are
    # parts of letters, so text in UTF-8 passes whole. The range is a byte
    # range, which the C locale makes it. What this leaves, and why, is in
    # docs/decisions.md.
    LC_ALL=C
    local value=${1//[[:cntrl:]]/?}
    printf '%s' "${value//$'\xc2'[$'\x80'-$'\x9f']/?}"
)

# Validate one argv-safe SSH destination string.
# Args: destination; status 0=valid, 1=invalid. SSH does actual resolution.
_is-valid-ssh-destination() {
    # SSH owns alias/address syntax, including non-ASCII aliases and IPv6.
    # Keep one unambiguous argv element; it is never evaluated by this script.
    [[ -n $1 && $1 != -* && $1 != *[[:space:][:cntrl:]]* ]]
}

# Reject a missing input in noninteractive contexts.
# Args: missing-field name and corrective guidance; may exit.
_require-interactive-terminal() {
    if (( SETTINGS_NON_INTERACTIVE )) || [[ ! -t 0 ]]; then
        _exit-with-error "Missing $1. $2 (Interactive selection requires terminal input.)" 2
    fi
}

# Read one ordinary line from stdin, without raw terminal mode.
# Args: prompt text; sets INPUT_RESPONSE; EOF cancels.
_read-user-response() {
    printf '%s%s %s%s' "$DISPLAY_COLOR_PROMPT" "$DISPLAY_SYMBOL_PROMPT" "$1" "$DISPLAY_COLOR_RESET" >&2
    if ! IFS= read -r INPUT_RESPONSE; then
        printf '\n' >&2
        _exit-with-error 'Input closed; cancelled.' 130
    fi
    INPUT_RESPONSE=${INPUT_RESPONSE%$'\r'}
}

# Resolve a command or path without executing it.
# Args: executable, then the ways its path can be given, for the error;
# prints the absolute path, or exits with status 127 and a message that
# says how to point at the program.
_resolve-executable-path() {
    local result
    if ! result=$(command -v -- "$1") || [[ ! -f $result || ! -x $result ]]; then
        _exit-with-error "Executable not found: $1. Install it, or give its path with $2." 127
    fi
    # An explicit relative path must remain usable by scrcpy and its adb children.
    if [[ $result != /* ]]; then result=$PWD/$result; fi
    printf '%s\n' "$result"
}

# Validate all environment/CLI settings before connecting.
# Checks modes, boolean flags, address, serial, path and ADB port.
_validate-configuration() {
    local flag variable
    for flag in SETTINGS_VERBOSE SETTINGS_QUIET SETTINGS_NON_INTERACTIVE SETTINGS_ASCII_ONLY; do
        # Name the variable the user set: REMOTE_SCRCPY_ASCII for ASCII_ONLY.
        variable=REMOTE_SCRCPY_${flag#SETTINGS_}; variable=${variable%_ONLY}
        case ${!flag} in 0|1) ;; *) _exit-with-error "$variable must be 0 or 1." 2 ;; esac
    done
    case $SETTINGS_COLOR_MODE in
        auto|always|never) ;;
        *) _exit-with-error 'The color mode must be auto, always, or never (--color or REMOTE_SCRCPY_COLOR).' 2 ;;
    esac
    if [[ -n $SETTINGS_SSH_CONFIG_FILE && ( ! -f $SETTINGS_SSH_CONFIG_FILE || ! -r $SETTINGS_SSH_CONFIG_FILE ) ]]; then
        _exit-with-error "Cannot read SSH config: $SETTINGS_SSH_CONFIG_FILE" 2
    fi
    # An offline alias inventory does not depend on any ADB configuration.
    [[ $SETTINGS_OPERATION == connect || $SETTINGS_OPERATION == devices ]] || return 0
    if [[ -n $SETTINGS_SSH_HOST ]] && ! _is-valid-ssh-destination "$SETTINGS_SSH_HOST"; then
        _exit-with-error 'Invalid SSH destination. Use an SSH alias, hostname, IP, or user@host.' 2
    fi
    if [[ $SETTINGS_DEVICE_SERIAL == *[[:space:][:cntrl:]]* ]]; then
        _exit-with-error 'A device serial cannot contain whitespace or control characters.' 2
    fi
    if [[ ! $SETTINGS_REMOTE_ADB_SERVER_PORT =~ ^[0123456789]{1,5}$ ]]; then
        _exit-with-error 'The remote ADB port must be an integer from 1 to 65535 (--adb-port, REMOTE_SCRCPY_ADB_PORT, or the fallback ADB_PORT).' 2
    fi
    SETTINGS_REMOTE_ADB_SERVER_PORT=$((10#$SETTINGS_REMOTE_ADB_SERVER_PORT))
    if (( SETTINGS_REMOTE_ADB_SERVER_PORT < 1 || SETTINGS_REMOTE_ADB_SERVER_PORT > 65535 )); then
        _exit-with-error 'The remote ADB port must be an integer from 1 to 65535 (--adb-port, REMOTE_SCRCPY_ADB_PORT, or the fallback ADB_PORT).' 2
    fi
    if [[ -z $SETTINGS_REMOTE_ADB_EXECUTABLE || $SETTINGS_REMOTE_ADB_EXECUTABLE == *[[:cntrl:]]* ]]; then
        _exit-with-error 'The remote adb must be an executable name or path, not a shell command (--remote-adb, REMOTE_SCRCPY_REMOTE_ADB, or the fallback REMOTE_ADB).' 2
    fi
}

# Check only executables required for the selected operation.
# Resolves SETTINGS_LOCAL_ADB_EXECUTABLE and SETTINGS_LOCAL_SCRCPY_EXECUTABLE; no download or installation.
_check-runtime-dependencies() {
    local tool
    for tool in ssh awk cat env mktemp rm sleep; do
        command -v "$tool" >/dev/null || _exit-with-error "Missing prerequisite: $tool" 127
    done
    SETTINGS_LOCAL_ADB_EXECUTABLE=$(_resolve-executable-path "$SETTINGS_LOCAL_ADB_EXECUTABLE" \
        '--adb, REMOTE_SCRCPY_ADB, or the fallback ADB') || exit $?
    if [[ $SETTINGS_OPERATION == connect ]]; then
        SETTINGS_LOCAL_SCRCPY_EXECUTABLE=$(_resolve-executable-path "$SETTINGS_LOCAL_SCRCPY_EXECUTABLE" \
            'REMOTE_SCRCPY_SCRCPY or the fallback SCRCPY') || exit $?
    fi
}

# Explain purpose and prerequisites before an interactive operation.
# Stderr; omitted with --quiet.
_print-introduction() {
    (( ! SETTINGS_QUIET )) || return 0
    printf '%s%s Remote scrcpy %s%s\n' "$DISPLAY_COLOR_SECTION" "$DISPLAY_SYMBOL_SECTION" "$APPLICATION_VERSION" "$DISPLAY_COLOR_RESET" >&2
    printf '  Control an Android phone attached to another computer over SSH.\n\n' >&2
    printf '  %sHere%s    Bash 4.4+, OpenSSH, adb, scrcpy, and a desktop for viewing.\n' "$DISPLAY_COLOR_BOLD" "$DISPLAY_COLOR_RESET" >&2
    printf '  %sRemote%s  SSH with TCP forwarding, adb, and authorized USB debugging.\n' "$DISPLAY_COLOR_BOLD" "$DISPLAY_COLOR_RESET" >&2
    printf '  Local and remote ADB must use a compatible protocol.\n' >&2
    printf '  The window opens here; the phone stays connected to the remote.\n\n' >&2
}
