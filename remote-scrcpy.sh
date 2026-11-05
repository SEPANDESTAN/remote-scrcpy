#!/usr/bin/env bash
# =============================================================================
# remote-scrcpy — View/control an Android phone over SSH from this computer.
# =============================================================================
# PURPOSE
#   Runs scrcpy locally while an Android phone remains connected by USB to an
#   SSH-accessible remote computer. The remote computer's authorized ADB server
#   is accessed through temporary SSH tunnels; no display server is needed on
#   the remote computer. Each invocation owns and cleans up its SSH resources.
#
# INSTALL ON THE VIEWING COMPUTER
#   1. Install Bash 4.4+, an OpenSSH client, adb, and scrcpy (with a GUI session).
#   2. Copy this script and make it executable:
#        mkdir -p "$HOME/.local/bin"
#        install -m 755 remote-scrcpy.sh "$HOME/.local/bin/remote-scrcpy"
#   3. Ensure ~/.local/bin is on PATH, or call the file as ./remote-scrcpy.sh.
#   On the REMOTE computer, enable SSH forwarding and authorize the Android
#   phone for USB debugging. See the detailed, updatable preparation guide:
#        remote-scrcpy --prerequisites
#
# BASIC USAGE
#        remote-scrcpy --help
#        remote-scrcpy --prerequisites
#        remote-scrcpy                      # choose SSH host, then phone
#        remote-scrcpy alienware            # choose phone on SSH host
#        remote-scrcpy alienware SERIAL     # connect without prompts
#        remote-scrcpy --list-hosts
#        remote-scrcpy --list-devices alienware
#   Enable Bash completion in your interactive shell (optional):
#        source <(remote-scrcpy --completion bash)
#
# CONFIGURATION AND MAINTENANCE
#   CLI flags override REMOTE_SCRCPY_* environment variables; see --help.
#   Internal SETTINGS_* globals hold resolved choices, SESSION_* globals hold
#   owned resources, and DISPLAY_*/DISCOVERED_DEVICE_* hold presentation/data.
#   Internal helpers are _prefixed-kebab-case; `remote-scrcpy` is the sole
#   public function. The single-file executable is assembled from documented
#   source modules by `bash build.sh`; edit those modules when available.
#   No external terminal UI framework or embedded binary payload is required.
# =============================================================================
if (( BASH_VERSINFO[0] < 4 || ( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4 ) )); then
    printf 'remote-scrcpy requires Bash 4.4 or newer.\n' >&2
    exit 2
fi
set -Eeuo pipefail

# ===== core.sh =====
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
    APPLICATION_VERSION=3.0.1
    # Public environment inputs are read once. CLI flags always override them.
    SETTINGS_SSH_HOST=${REMOTE_SCRCPY_HOST:-}
    SETTINGS_DEVICE_SERIAL=${REMOTE_SCRCPY_SERIAL:-}
    SETTINGS_SSH_CONFIG_FILE=${REMOTE_SCRCPY_SSH_CONFIG:-}
    SETTINGS_SSH_DISCOVERY_CONFIG_FILE=${SETTINGS_SSH_CONFIG_FILE:-${HOME:?HOME is not set}/.ssh/config}
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
_sanitize-display-text() {
    # Device descriptions and config aliases must not inject terminal controls.
    local LC_ALL=C value=$1
    printf '%s' "${value//[[:cntrl:]]/?}"
}

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
# Args: executable; prints absolute path or exits with actionable error.
_resolve-executable-path() {
    local result
    if ! result=$(command -v -- "$1") || [[ ! -f $result || ! -x $result ]]; then
        _exit-with-error "Executable not found: $1. Install it or specify its path." 127
    fi
    # An explicit relative path must remain usable by scrcpy and its adb children.
    if [[ $result != /* ]]; then result=$PWD/$result; fi
    printf '%s\n' "$result"
}

# Validate all environment/CLI settings before connecting.
# Checks modes, boolean flags, address, serial, path and ADB port.
_validate-configuration() {
    local flag
    for flag in SETTINGS_VERBOSE SETTINGS_QUIET SETTINGS_NON_INTERACTIVE SETTINGS_ASCII_ONLY; do
        case ${!flag} in 0|1) ;; *) _exit-with-error "${flag#SETTINGS_} environment toggle must be 0 or 1." 2 ;; esac
    done
    case $SETTINGS_COLOR_MODE in
        auto|always|never) ;;
        *) _exit-with-error '--color must be auto, always, or never.' 2 ;;
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
    if [[ ! $SETTINGS_REMOTE_ADB_SERVER_PORT =~ ^[0-9]{1,5}$ ]]; then
        _exit-with-error '--adb-port / ADB_PORT must be an integer from 1 to 65535.' 2
    fi
    SETTINGS_REMOTE_ADB_SERVER_PORT=$((10#$SETTINGS_REMOTE_ADB_SERVER_PORT))
    if (( SETTINGS_REMOTE_ADB_SERVER_PORT < 1 || SETTINGS_REMOTE_ADB_SERVER_PORT > 65535 )); then
        _exit-with-error '--adb-port / ADB_PORT must be an integer from 1 to 65535.' 2
    fi
    if [[ -z $SETTINGS_REMOTE_ADB_EXECUTABLE || $SETTINGS_REMOTE_ADB_EXECUTABLE == *[[:cntrl:]]* ]]; then
        _exit-with-error '--remote-adb must be an executable name or path, not a shell command.' 2
    fi
}

# Check only executables required for the selected operation.
# Resolves SETTINGS_LOCAL_ADB_EXECUTABLE and SETTINGS_LOCAL_SCRCPY_EXECUTABLE; no download or installation.
_check-runtime-dependencies() {
    local tool
    for tool in ssh awk mktemp rm sleep; do
        command -v "$tool" >/dev/null || _exit-with-error "Missing prerequisite: $tool" 127
    done
    SETTINGS_LOCAL_ADB_EXECUTABLE=$(_resolve-executable-path "$SETTINGS_LOCAL_ADB_EXECUTABLE") || exit $?
    if [[ $SETTINGS_OPERATION == connect ]]; then
        SETTINGS_LOCAL_SCRCPY_EXECUTABLE=$(_resolve-executable-path "$SETTINGS_LOCAL_SCRCPY_EXECUTABLE") || exit $?
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

# ===== cli.sh =====
# CLI contract: only parse/validate arguments; never open network connections.
# Positional HOST and SERIAL fill the same state as --host and --serial.
# A standalone -- is the boundary: subsequent arguments go unchanged to scrcpy.

# Command-line parsing is independent of connection setup and menus.

# Print a standalone contract; the long setup procedure is --prerequisites.
# Show CLI syntax, examples, options, precedence and basic setup.
# Prints static text to stdout; must work with no optional binaries.
_print-help() {
    local line
    while IFS= read -r line; do printf '%s\n' "$line"; done <<'END_HELP_TEXT'
remote-scrcpy  |  Interactive Android control over SSH

USAGE
  remote-scrcpy [OPTIONS] [HOST [SERIAL]] [-- SCRCPY_OPTIONS...]

WORKFLOW
  No arguments         Pick an SSH alias, then choose an online Android device.
  HOST                 Skip the host menu; choose a device on that remote.
  HOST SERIAL          Skip both menus and connect directly.
  --serial SERIAL      Choose the host interactively, then use this device.
  --                    Pass the remaining arguments directly to scrcpy.

EXAMPLES
  remote-scrcpy
  remote-scrcpy alienware
  remote-scrcpy alienware A00000K5801C0602948
  remote-scrcpy alienware -- --max-size=1280 --max-fps=30
  remote-scrcpy --list-devices alienware
  remote-scrcpy --non-interactive alienware A00000K5801C0602948

OPTIONS
  --host HOST           SSH alias, hostname, or user@hostname
  --serial SERIAL       Exact device serial from `adb devices -l`
  --list-hosts          List literal aliases from the SSH config (no network)
  --list-devices        List remote devices without launching scrcpy
  --ssh-config FILE     Alternate SSH config for discovery and connection
  --adb PATH            Local adb executable
  --remote-adb PATH     adb executable/path on remote computer
  --adb-port PORT       Remote ADB server port (default 5037)
  --color MODE          auto (default), always, never
  --ascii               Replace decorative Unicode markers with ASCII
  --non-interactive     Never prompt; use SSH BatchMode
  --quiet               Hide banner and progress (errors and prompts remain)
  -v, --verbose         Include SSH and transport details
  --prerequisites       Detailed local, remote, and Android preparation guide
  --completion bash     Output the optional Bash completion definition
  -h, --help            Show this help
  -V, --version         Show the launcher version

CONFIGURATION
  CLI flags override environment variables, which override defaults.
  REMOTE_SCRCPY_HOST, REMOTE_SCRCPY_SERIAL, REMOTE_SCRCPY_SSH_CONFIG,
  REMOTE_SCRCPY_ADB, REMOTE_SCRCPY_REMOTE_ADB, REMOTE_SCRCPY_ADB_PORT,
  REMOTE_SCRCPY_SCRCPY, REMOTE_SCRCPY_COLOR,
  REMOTE_SCRCPY_ASCII, REMOTE_SCRCPY_VERBOSE,
  REMOTE_SCRCPY_QUIET, REMOTE_SCRCPY_NON_INTERACTIVE (toggles: 0 or 1).
  ADB, REMOTE_ADB, ADB_PORT and SCRCPY remain secondary fallbacks.
  NO_COLOR=1 disables color unconditionally.

PREREQUISITES
  Local: Bash 4.4+, OpenSSH client, scrcpy, and an accessible adb client;
  a graphical desktop is needed for mirroring. Remote: SSH server, adb,
  authorized USB debugging, and TCP forwarding. See --prerequisites for
  verification commands and an expandable remote/phone checklist.

COMPLETION
  source <(remote-scrcpy --completion bash)
  Add this to ~/.bashrc for persistent Bash tab completion. Host aliases
  are local; online device serials are queried by SSH on each Tab by default.
  REMOTE_SCRCPY_COMPLETE_DEVICES=0 disables remote device queries.
  REMOTE_SCRCPY_COMPLETION_TIMEOUT=6 is the optional time bound (seconds).

NOTES
  Host listing is a static SSH-config alias inventory; OpenSSH controls the
  actual connection. The launcher owns scrcpy's device/tunnel flags. Do not
  override --serial, --port or --tunnel-port after --. Use `scrcpy --help`
  for supported display, audio, input, and recording options.
END_HELP_TEXT
}

# Apply a named argument exactly once; initial environment defaults are allowed.
# Assign one explicit host or serial while detecting duplicates.
# Args: state variable name, value and label; tracks CLI-set flags.
_assign-unique-argument() {
    local name=$1 value=$2 label=$3
    [[ -n $value ]] || _exit-with-error "$label needs a nonempty value." 2
    if [[ $name == SETTINGS_SSH_HOST ]]; then
        (( CLI_HOST_EXPLICIT == 0 )) || _exit-with-error "$label was supplied more than once." 2
        CLI_HOST_EXPLICIT=1
    else
        (( CLI_SERIAL_EXPLICIT == 0 )) || _exit-with-error "$label was supplied more than once." 2
        CLI_SERIAL_EXPLICIT=1
    fi
    printf -v "$name" '%s' "$value"
}

# Parse options, positional arguments and scrcpy passthrough.
# Args: main argv; outputs SETTINGS_OPERATION/SETTINGS_*; no connection side effects.
_parse-command-line() {
    local key value arg
    CLI_HOST_EXPLICIT=0 CLI_SERIAL_EXPLICIT=0
    while (( $# )); do
        arg=$1
        case $arg in
            --) shift; SETTINGS_SCRCPY_EXTRA_ARGUMENTS=("$@"); break ;;
            -h|--help) _print-help; exit 0 ;;
            --prerequisites|--requirements) SETTINGS_OPERATION=prerequisites; shift ;;
            --completion)
                (( $# >= 2 )) || _exit-with-error '--completion requires bash.' 2
                [[ $2 == bash ]] || _exit-with-error 'Only Bash completion is supported.' 2
                SETTINGS_OPERATION=completion; shift 2 ;;
            -V|--version) printf 'remote-scrcpy %s\n' "$APPLICATION_VERSION"; exit 0 ;;
            -v|--verbose) SETTINGS_VERBOSE=1; shift ;;
            --quiet) SETTINGS_QUIET=1; shift ;;
            --ascii) SETTINGS_ASCII_ONLY=1; shift ;;
            --non-interactive) SETTINGS_NON_INTERACTIVE=1; shift ;;
            --list-hosts|--list-devices|--list)
                [[ $SETTINGS_OPERATION == connect ]] || _exit-with-error 'Choose only one listing mode.' 2
                if [[ $arg == --list-hosts ]]; then SETTINGS_OPERATION=hosts; else SETTINGS_OPERATION=devices; fi
                shift ;;
            --host|--serial|--ssh-config|--adb|--remote-adb|--adb-port|--color|\
            --host=*|--serial=*|--ssh-config=*|--adb=*|--remote-adb=*|--adb-port=*|--color=*)
                key=${arg%%=*}
                if [[ $arg == *=* ]]; then
                    value=${arg#*=}; shift
                else
                    (( $# >= 2 )) || _exit-with-error "$arg needs a value." 2
                    value=$2; shift 2
                fi
                [[ -n $value ]] || _exit-with-error "$key needs a nonempty value." 2
                case $key in
                    --host) _assign-unique-argument SETTINGS_SSH_HOST "$value" --host ;;
                    --serial) _assign-unique-argument SETTINGS_DEVICE_SERIAL "$value" --serial ;;
                    --ssh-config) SETTINGS_SSH_CONFIG_FILE=$value; SETTINGS_SSH_DISCOVERY_CONFIG_FILE=$value ;;
                    --adb) SETTINGS_LOCAL_ADB_EXECUTABLE=$value ;;
                    --remote-adb) SETTINGS_REMOTE_ADB_EXECUTABLE=$value ;;
                    --adb-port) SETTINGS_REMOTE_ADB_SERVER_PORT=$value ;;
                    --color) SETTINGS_COLOR_MODE=$value ;;

                esac ;;
            -*) _exit-with-error "Unknown launcher option: $arg. Put scrcpy options after --." 2 ;;
            *)
                [[ -n $arg ]] || _exit-with-error 'A positional host or serial cannot be empty.' 2
                if (( ! CLI_HOST_EXPLICIT )); then
                    _assign-unique-argument SETTINGS_SSH_HOST "$arg" HOST
                elif (( ! CLI_SERIAL_EXPLICIT )); then
                    _assign-unique-argument SETTINGS_DEVICE_SERIAL "$arg" SERIAL
                else
                    _exit-with-error "Unexpected argument: $arg. Put scrcpy options after --." 2
                fi
                shift ;;
        esac
    done
    if [[ $SETTINGS_OPERATION == hosts ]] && (( CLI_HOST_EXPLICIT || CLI_SERIAL_EXPLICIT )); then
        _exit-with-error '--list-hosts does not take a host or serial.' 2
    fi
    if [[ $SETTINGS_OPERATION == devices ]] && (( CLI_SERIAL_EXPLICIT )); then
        _exit-with-error '--list-devices does not take a serial.' 2
    fi
    if [[ $SETTINGS_OPERATION != connect ]] && (( ${#SETTINGS_SCRCPY_EXTRA_ARGUMENTS[@]} )); then
        _exit-with-error 'Listing modes do not take scrcpy options.' 2
    fi
}

# Reject caller arguments that would conflict with launcher routing.
# Reads SETTINGS_SCRCPY_EXTRA_ARGUMENTS; errors before opening any network connection.
_validate-scrcpy-arguments() {
    local arg key owned
    local -a managed=(
        --serial --select-usb --select-tcpip --tcpip --otg --port
        --tunnel-host --tunnel-port --force-adb-forward --kill-adb-on-close
    )
    for arg in "${SETTINGS_SCRCPY_EXTRA_ARGUMENTS[@]}"; do
        if [[ $arg == --* ]]; then
            key=${arg%%=*}
            [[ $key != -- ]] || _exit-with-error 'A second -- is not a scrcpy option.' 2
            # getopt_long accepts abbreviations; prefixes can override our values too.
            for owned in "${managed[@]}"; do
                [[ $owned != "$key"* ]] || _exit-with-error "The launcher manages $key." 2
            done
        elif [[ $arg == -* && $arg != - ]]; then
            case $arg in
                -[psde]*) _exit-with-error "The launcher manages $arg." 2 ;;
                -[mbr]*|-[[:alnum:]]) ;;
                *) _exit-with-error "Use separate short flags or full long options after --: $arg" 2 ;;
            esac
        fi
    done
}

# ===== ssh-config.sh =====
# SSH config alias inventory (not an SSH configuration interpreter).
# Handles static Host declarations and Include paths, without executing Match
# expressions. OpenSSH itself remains authoritative for actual connections.

# SSH alias discovery for the interactive menu. Requires Bash 4.3+.
# This reads configuration as data: it never executes Match exec, shell
# substitutions, or ssh -G. Actual connection settings remain SSH's job.

# Split one directive's values into the caller's local `words` array.
# OpenSSH-style quoted values and comments are enough for Host and Include;
# malformed quoted lines are rejected instead of inventing a partial alias.
# Tokenize Host/Include directives without shell evaluation.
# Args: directive contents; outputs caller-scope words array.
_split-ssh-configuration-words() {
    local text=$1 char next word= quote= index
    words=()
    for ((index = 0; index < ${#text}; index++)); do
        char=${text:index:1}
        next=${text:index+1:1}
        if [[ $char == '\' && ( $next == '"' || $next == "'" || $next == '\' ) ]]; then
            word+=$next
            ((index += 1))
        elif [[ -n $quote ]]; then
            if [[ $char == "$quote" ]]; then quote=; else word+=$char; fi
        else
            case $char in
                '"'|"'") quote=$char ;;
                '#') break ;;
                ' '|$'\t'|$'\r')
                    if [[ -n $word ]]; then words+=("$word"); word=; fi
                    ;;
                *) word+=$char ;;
            esac
        fi
    done
    [[ -z $quote ]] || return 1
    if [[ -n $word ]]; then words+=("$word"); fi
    return 0
}

# Read each physical file once, including symlink aliases. `visited` and
# home/directory values are local to _discover-ssh-host-aliases and shared by recursion.
# Walk one SSH configuration file and its static Includes.
# Args: path and depth; uses caller-scope visited/path state; prints aliases.
_visit-ssh-configuration-file() {
    local file=$1 depth=$2 previous line key value included pattern
    local line_number=0
    local -a words=() matches=()

    [[ -f $file ]] || return 0
    if [[ ! -r $file ]]; then
        printf 'Skipping unreadable SSH config: %s\n' "$file" >&2
        return 0
    fi
    # The + expansion also supports empty arrays under Bash 4.3's nounset.
    for previous in ${visited[@]+"${visited[@]}"}; do
        [[ $file -ef $previous ]] && return 0
    done
    if ((depth > 32)); then
        printf 'Skipping SSH Include deeper than 32 files: %s\n' "$file" >&2
        return 0
    fi
    visited+=("$file")

    while IFS= read -r line || [[ -n $line ]]; do
        ((line_number += 1))
        [[ $line =~ ^[[:space:]]*([[:alpha:]]+)([[:space:]]*=[[:space:]]*|[[:space:]]+)(.*)$ ]] || continue
        key=${BASH_REMATCH[1],,}
        [[ $key == host || $key == include ]] || continue
        if ! _split-ssh-configuration-words "${BASH_REMATCH[3]}"; then
            printf 'Skipping malformed SSH config line: %s:%s\n' "$file" "$line_number" >&2
            continue
        fi
        for value in ${words[@]+"${words[@]}"}; do
            if [[ $key == host ]]; then
                # Patterns, negations, options and control characters are not
                # concrete selectable destinations. SSH patterns use * and ?.
                [[ $value == '!'* || $value == -* || $value == *'*'* || $value == *'?'* ||
                   $value =~ [[:space:][:cntrl:]] ]] && continue
                printf '%s\n' "$value"
                continue
            fi

            # A static inventory cannot resolve connection-specific tokens or
            # conditions. Expand current-user ~ only, without invoking a shell.
            case $value in
                *'$'*|*'%'*|~[^/]*)
                    printf 'Skipping dynamic SSH Include in %s: %s\n' "$file" "$value" >&2
                    continue ;;
                '~') pattern=$ssh_user_home ;;
                '~/'*) pattern=$ssh_user_home/${value#\~/} ;;
                /*) pattern=$value ;;
                *) pattern=$ssh_directory/$value ;;
            esac
            # Empty IFS keeps quoted spaces intact. Deliberate unquoted
            # expansion performs pathname globbing only, never shell evaluation.
            local IFS=
            # shellcheck disable=SC2206
            matches=( $pattern )
            for included in ${matches[@]+"${matches[@]}"}; do
                _visit-ssh-configuration-file "$included" "$((depth + 1))"
            done
        done
    done < "$file"
}

# Print unique literal aliases in declaration order. Include globs are visited
# in lexical order; relative Includes follow OpenSSH's ~/.ssh rule, even when
# the parent file is elsewhere. Missing files simply yield no aliases.
#
# This is a static candidate inventory: Host/Match conditions on Includes are
# not evaluated. ${VARIABLE}, %-token, and ~otheruser Include paths are skipped
# with a diagnostic; users can always pass a host explicitly.
# The optional second argument injects the user's home directory for tests.
# Enumerate unique literal Host aliases in declaration order.
# Args: optional config/home; subshell isolates parser state and globs.
_discover-ssh-host-aliases() (
    local config=${1:-$HOME/.ssh/config}
    local ssh_user_home=${2:-$HOME}
    local ssh_directory=$ssh_user_home/.ssh
    local -a visited=()
    export LC_ALL=C
    unset GLOBIGNORE
    set +f
    shopt -s nullglob
    shopt -u failglob dotglob nocaseglob extglob
    _visit-ssh-configuration-file "$config" 0 | awk '!seen[$0]++'
)

# ===== presentation.sh =====
# Human-facing colors and Unicode symbols, limited to stderr in a TTY.
# Never add terminal escapes to stdout; listing/completion modes need plain text.
# NO_COLOR overrides --color. --ascii changes decoration independently.

# Small terminal decorations for the numbered UI. No cursor movement, raw input
# mode, external UI program, terminal database, or subprocess is needed for setup.
# Only human-facing stderr is decorated; listing stdout is always plain data.

# Set safe color and decoration variables for human stderr.
# Uses terminal, locale, SETTINGS_COLOR_MODE, SETTINGS_ASCII_ONLY and NO_COLOR.
_initialize-terminal-styles() {
    local terminal=0 locale_name
    DISPLAY_COLOR_RESET= DISPLAY_COLOR_BOLD= DISPLAY_COLOR_MUTED= DISPLAY_COLOR_SECTION= DISPLAY_COLOR_PROMPT=
    DISPLAY_COLOR_SUCCESS= DISPLAY_COLOR_WARNING= DISPLAY_COLOR_ERROR= DISPLAY_COLOR_INFO=
    DISPLAY_SYMBOL_SECTION='>' DISPLAY_SYMBOL_PROMPT='>' DISPLAY_SYMBOL_SUCCESS='+'
    DISPLAY_SYMBOL_WARNING='!' DISPLAY_SYMBOL_ERROR='x' DISPLAY_SYMBOL_INFO='*'
    if [[ -t 2 && -n ${TERM:-} && $TERM != dumb ]]; then terminal=1; fi

    # NO_COLOR takes precedence, including over an explicit --color=always.
    if [[ -z ${NO_COLOR:-} ]] \
        && { [[ $SETTINGS_COLOR_MODE == always ]] || { [[ $SETTINGS_COLOR_MODE == auto ]] && (( terminal )); }; }; then
        DISPLAY_COLOR_RESET=$'\033[0m'
        DISPLAY_COLOR_BOLD=$'\033[1m'
        DISPLAY_COLOR_MUTED=$'\033[2m'
        DISPLAY_COLOR_SECTION=$'\033[1;36m'
        DISPLAY_COLOR_PROMPT=$'\033[1;35m'
        DISPLAY_COLOR_SUCCESS=$'\033[32m'
        DISPLAY_COLOR_WARNING=$'\033[33m'
        DISPLAY_COLOR_ERROR=$'\033[1;31m'
        DISPLAY_COLOR_INFO=$'\033[36m'
    fi

    # Inspect locale settings directly; no locale/tput binary is required.
    # An explicit LC_ALL=C overrides a UTF-8 LANG. Symbols are only decoration.
    locale_name=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
    if (( terminal && ! SETTINGS_ASCII_ONLY )); then
        case ${locale_name,,} in
            *utf-8*|*utf8*)
                DISPLAY_SYMBOL_SECTION='▸' DISPLAY_SYMBOL_PROMPT='›' DISPLAY_SYMBOL_SUCCESS='✓'
                DISPLAY_SYMBOL_ERROR='×' DISPLAY_SYMBOL_INFO='•'
                ;;
        esac
    fi
}

# Print a styled one-line status, warning or error.
# Args: color, marker, message; stderr only.
_print-styled-message() {
    local color=$1 marker=$2 message=$3
    printf '%s%s %s%s\n' "$color" "$marker" "$(_sanitize-display-text "$message")" "$DISPLAY_COLOR_RESET" >&2
}

# Print a warning using the common message formatter.
# Args: warning text; stderr only.
_print-warning() { _print-styled-message "$DISPLAY_COLOR_WARNING" "$DISPLAY_SYMBOL_WARNING" "$*"; }

# Print a visually distinct menu section heading.
# Args: heading; stderr only.
_print-section-heading() {
    printf '%s%s %s%s\n' "$DISPLAY_COLOR_SECTION" "$DISPLAY_SYMBOL_SECTION" \
        "$(_sanitize-display-text "$1")" "$DISPLAY_COLOR_RESET" >&2
}

# Print a numeric menu row with sanitized text.
# Args: index and label; stderr only.
_print-numbered-choice() {
    printf '  %s%s)%s %s\n' "$DISPLAY_COLOR_SECTION" "$1" "$DISPLAY_COLOR_RESET" \
        "$(_sanitize-display-text "$2")" >&2
}

# Print secondary advice without confusing it with menu choices.
# Args: hint; stderr only.
_print-muted-hint() {
    printf '  %s%s%s\n' "$DISPLAY_COLOR_MUTED" "$(_sanitize-display-text "$1")" "$DISPLAY_COLOR_RESET" >&2
}

# ===== ui.sh =====
# Numbered interactive menus and remote ADB device enumeration.
# Menus modify SETTINGS_SSH_HOST and SETTINGS_DEVICE_SERIAL only after valid user selection.
# Device inventory consists of parallel DISCOVERED_DEVICE_* arrays (same indexes).

# Interactive selection and presentation. Menus write to stderr; machine-readable
# listing modes write to stdout. Remote data is parsed once into parallel arrays.

# Choose a literal SSH alias or manually entered destination.
# Writes SETTINGS_SSH_HOST; q cancels; does not connect.
_prompt-for-ssh-host() {
    _require-interactive-terminal 'SSH host' 'Pass HOST or --host HOST.'
    local -a choices=()
    local choice index
    mapfile -t choices < <(_discover-ssh-host-aliases "$SETTINGS_SSH_DISCOVERY_CONFIG_FILE")
    _print-section-heading "Remote hosts from $SETTINGS_SSH_DISCOVERY_CONFIG_FILE:"
    if (( ${#choices[@]} )); then
        for index in "${!choices[@]}"; do
            _print-numbered-choice "$((index + 1))" "${choices[index]}"
        done
    else
        _print-muted-hint 'No literal Host aliases found. You can enter a destination below.'
    fi
    _print-numbered-choice m 'Enter another destination'
    _print-numbered-choice q 'Quit'
    printf '\n' >&2
    while :; do
        _read-user-response 'Remote (number, alias, or m): '
        choice=$INPUT_RESPONSE
        case $choice in
            q|Q) _exit-with-error 'Cancelled.' 130 ;;
            m|M)
                _read-user-response 'SSH destination (alias or user@host): '
                if _is-valid-ssh-destination "$INPUT_RESPONSE"; then
                    SETTINGS_SSH_HOST=$INPUT_RESPONSE
                    return 0
                fi
                _print-warning 'Enter a nonempty SSH destination without whitespace.'
                continue ;;
        esac
        if [[ $choice =~ ^[0-9]+$ ]]; then
            # A huge menu number is invalid, not an implicit numeric hostname.
            if (( ${#choice} <= 6 )); then
                index=$((10#$choice - 1))
                if (( index >= 0 && index < ${#choices[@]} )); then
                    SETTINGS_SSH_HOST=${choices[index]}
                    _is-valid-ssh-destination "$SETTINGS_SSH_HOST" || _exit-with-error 'That alias is not a supported SSH destination.' 2
                    return 0
                fi
            fi
        elif _is-valid-ssh-destination "$choice"; then
            SETTINGS_SSH_HOST=$choice
            return 0
        fi
        _print-warning 'Enter a listed number, a valid SSH destination, or q to quit.'
    done
}

# Query and parse remote `adb devices -l` through the SSH tunnel.
# Updates parallel DISCOVERED_DEVICE_* arrays; errors if discovery fails.
_load-remote-device-list() {
    local output serial state rest word model
    local -a fields=()
    if ! output=$(_run-remote-adb-client devices -l); then
        _exit-with-error "Could not list devices on $SETTINGS_SSH_HOST. Check the SSH connection and remote ADB."
    fi
    DISCOVERED_DEVICE_SERIALS=(); DISCOVERED_DEVICE_STATES=(); DISCOVERED_DEVICE_MODELS=()
    while IFS= read -r rest; do
        rest=${rest%$'\r'}
        [[ -n $rest && $rest != 'List of devices attached'* && $rest != \** ]] || continue
        read -r serial state rest <<< "$rest"
        [[ -n $serial && -n $state ]] || continue
        if [[ $state == no && $rest == permissions* ]]; then state='no permissions'; fi
        model=
        read -r -a fields <<< "$rest"
        for word in "${fields[@]}"; do
            if [[ $word == model:* ]]; then model=${word#model:}; model=${model//_/ }; break; fi
        done
        DISCOVERED_DEVICE_SERIALS+=("$serial")
        DISCOVERED_DEVICE_STATES+=("$state")
        DISCOVERED_DEVICE_MODELS+=("$model")
    done <<< "$output"
}

# Emit machine-readable device data for --list-devices.
# Uses tab-separated stdout; never emits styling.
_print-remote-device-list() {
    local index
    printf 'SERIAL\tSTATE\tMODEL\n'
    for index in "${!DISCOVERED_DEVICE_SERIALS[@]}"; do
        printf '%s\t%s\t%s\n' \
            "$(_sanitize-display-text "${DISCOVERED_DEVICE_SERIALS[index]}")" \
            "$(_sanitize-display-text "${DISCOVERED_DEVICE_STATES[index]}")" \
            "$(_sanitize-display-text "${DISCOVERED_DEVICE_MODELS[index]}")"
    done
}

# Return guidance for offline/unauthorized/unusable device states.
# Args: device state; prints a short explanation.
_explain-device-state() {
    case $1 in
        unauthorized) printf 'Unlock the phone and authorize USB debugging for the remote user.' ;;
        offline) printf 'Reconnect USB and check the phone on the remote computer.' ;;
        'no permissions') printf 'Fix USB/udev access for the SSH user on the remote computer.' ;;
        *) printf 'The device is not available to scrcpy in this state.' ;;
    esac
}

# Ensure requested serial is present and in `device` state.
# Reads SETTINGS_DEVICE_SERIAL and DISCOVERED_DEVICE_* arrays; error on mismatch.
_validate-selected-device() {
    local index state
    for index in "${!DISCOVERED_DEVICE_SERIALS[@]}"; do
        [[ ${DISCOVERED_DEVICE_SERIALS[index]} == "$SETTINGS_DEVICE_SERIAL" ]] || continue
        state=${DISCOVERED_DEVICE_STATES[index]}
        [[ $state == device ]] || _exit-with-error "Device $SETTINGS_DEVICE_SERIAL is $state. $(_explain-device-state "$state")"
        return 0
    done
    _print-remote-device-list >&2
    _exit-with-error "Device $SETTINGS_DEVICE_SERIAL is not listed on $SETTINGS_SSH_HOST. Check the serial and USB connection."
}

# Choose online device by row or exact serial; allow refresh.
# Writes SETTINGS_DEVICE_SERIAL; r re-queries; q cancels.
_prompt-for-device() {
    _require-interactive-terminal 'device serial' 'Pass SERIAL or --serial SERIAL.'
    local index choice selected online exact
    local -a selectable=()
    while :; do
        selectable=(); online=0
        printf '\n' >&2
        _print-section-heading "Android devices on $SETTINGS_SSH_HOST:"
        if (( ! ${#DISCOVERED_DEVICE_SERIALS[@]} )); then
            _print-warning 'No devices found. Connect a phone and enable USB debugging.'
        fi
        for index in "${!DISCOVERED_DEVICE_SERIALS[@]}"; do
            if [[ ${DISCOVERED_DEVICE_STATES[index]} == device ]]; then
                selectable+=("$index"); online=$((online + 1))
                printf '  %s%d)%s %s%s%s %s  %s%s%s  %s[ready]%s\n' \
                    "$DISPLAY_COLOR_SECTION" "$online" "$DISPLAY_COLOR_RESET" \
                    "$DISPLAY_COLOR_SUCCESS" "$DISPLAY_SYMBOL_SUCCESS" "$DISPLAY_COLOR_RESET" \
                    "$(_sanitize-display-text "${DISCOVERED_DEVICE_SERIALS[index]}")" \
                    "$DISPLAY_COLOR_MUTED" "$(_sanitize-display-text "${DISCOVERED_DEVICE_MODELS[index]}")" "$DISPLAY_COLOR_RESET" \
                    "$DISPLAY_COLOR_SUCCESS" "$DISPLAY_COLOR_RESET" >&2
            else
                printf '     %s%s%s %s  %s[%s]%s\n' \
                    "$DISPLAY_COLOR_WARNING" "$DISPLAY_SYMBOL_WARNING" "$DISPLAY_COLOR_RESET" \
                    "$(_sanitize-display-text "${DISCOVERED_DEVICE_SERIALS[index]}")" \
                    "$DISPLAY_COLOR_WARNING" "$(_sanitize-display-text "${DISCOVERED_DEVICE_STATES[index]}")" "$DISPLAY_COLOR_RESET" >&2
                _print-muted-hint "     $(_explain-device-state "${DISCOVERED_DEVICE_STATES[index]}")"
            fi
        done
        _print-numbered-choice s 'Enter an exact serial'
        _print-numbered-choice r 'Refresh devices'
        _print-numbered-choice q 'Quit'
        printf '\n' >&2
        _read-user-response 'Device (number, serial, or s/r/q): '
        choice=$INPUT_RESPONSE
        exact=0
        case $choice in
            q|Q) _exit-with-error 'Cancelled.' 130 ;;
            r|R) _load-remote-device-list; continue ;;
            s|S) _read-user-response 'Exact device serial: '; choice=$INPUT_RESPONSE; exact=1 ;;
        esac
        selected=
        # A displayed menu number always means that row. The explicit serial
        # entry path also supports short numeric serials that overlap menu numbers.
        if (( ! exact )) && [[ $choice =~ ^[0-9]{1,6}$ ]]; then
            index=$((10#$choice - 1))
            if (( index >= 0 && index < ${#selectable[@]} )); then selected=${selectable[index]}; fi
        fi
        if [[ -z $selected ]]; then
            for index in "${selectable[@]}"; do
                if [[ ${DISCOVERED_DEVICE_SERIALS[index]} == "$choice" ]]; then selected=$index; break; fi
            done
        fi
        if [[ -n $selected ]]; then
            SETTINGS_DEVICE_SERIAL=${DISCOVERED_DEVICE_SERIALS[selected]}
            return 0
        fi
        _print-warning 'Choose an online device, refresh with r, or quit with q.'
    done
}

# ===== transport.sh =====
# SSH/ADB/scrcpy connection lifetime and resource ownership.
# SESSION_* variables belong exclusively to this module, including SSH mux
# socket, forwarding ports, ADB reservation, and scrcpy PID. The EXIT trap
# must run _cleanup-remote-connection on every post-connect failure.

# SSH/ADB transport. Sourced by the launcher; no work happens at source time.
# Configuration: SETTINGS_SSH_HOST, SETTINGS_DEVICE_SERIAL, SETTINGS_SSH_CONFIG_FILE, SETTINGS_LOCAL_ADB_EXECUTABLE, SETTINGS_REMOTE_ADB_EXECUTABLE,
# SETTINGS_REMOTE_ADB_SERVER_PORT, SETTINGS_LOCAL_SCRCPY_EXECUTABLE, SETTINGS_SCRCPY_EXTRA_ARGUMENTS, SETTINGS_NON_INTERACTIVE, SETTINGS_VERBOSE.
# Common helpers: _exit-with-error/log/debug.
# Owned session state is always prefixed SESSION_. All are initialized to
# empty/inactive, then assigned by _open-remote-connection and
# _reserve-device-forwarding-port. _cleanup-remote-connection may run after
# partial setup, so it MUST tolerate unset/incomplete resources.
#
#   SESSION_WORK_DIRECTORY       Private temporary directory for socket/errors.
#   SESSION_SSH_CONTROL_SOCKET   Private SSH master control socket path.
#   SESSION_SSH_CONTROL_COMMAND  Array invoking that master; no shell eval.
#   SESSION_LOCAL_ADB_TUNNEL_PORT  Local listener -> remote ADB server port.
#   SESSION_LOCAL_MEDIA_TUNNEL_PORT  Local listener -> scrcpy media port.
#   SESSION_REMOTE_MEDIA_PORT    Remote ADB-allocated scrcpy media port.
#   SESSION_ADB_PORT_RESERVATION Unique ADB forwarding target used for cleanup.
#   SESSION_LOCAL_ADB_PROTOCOL   Protocol version expected by local ADB client.
#   SESSION_REMOTE_ADB_PROTOCOL  Protocol returned by remote ADB server probe.
#   SESSION_ADB_PROBE_ERROR      Diagnostic from the last protocol probe.
#   SESSION_NEW_FORWARD_PORT    Most recently allocated local tunnel port.
#   SESSION_SCRCPY_PROCESS_ID   Child process ID while scrcpy is running.
#   SESSION_STOPPING            Guard against repeated shutdown signals.

SESSION_WORK_DIRECTORY=''
SESSION_SSH_CONTROL_SOCKET=''
SESSION_LOCAL_ADB_TUNNEL_PORT=''
SESSION_LOCAL_MEDIA_TUNNEL_PORT=''
SESSION_REMOTE_MEDIA_PORT=''
SESSION_ADB_PORT_RESERVATION=''
SESSION_LOCAL_ADB_PROTOCOL=''
SESSION_REMOTE_ADB_PROTOCOL=''
SESSION_ADB_PROBE_ERROR=''
SESSION_NEW_FORWARD_PORT=''
SESSION_SCRCPY_PROCESS_ID=''
SESSION_STOPPING=0
SESSION_SSH_CONTROL_COMMAND=()

# POSIX-quote one argument for SSH remote login shell.
# Args: untrusted path/value; stdout; never uses eval locally.
_quote-remote-shell-argument() {
    # SSH sends a command string to the remote login shell, not an argv array.
    # POSIX single quotes also work when that shell is not Bash.
    local value=${1//\'/\'\\\'\'}
    printf "'%s'" "$value"
}

# Send control operations to this invocation’s SSH mux.
# Args: SSH -O subcommand/forwards; appends exact SETTINGS_SSH_HOST.
_run-ssh-master-command() {
    "${SESSION_SSH_CONTROL_COMMAND[@]}" "$@" -- "$SETTINGS_SSH_HOST"
}

# Execute a quoted command using the existing SSH master.
# Args: remote command string built only from quoted fields.
_run-remote-shell-command() {
    "${SESSION_SSH_CONTROL_COMMAND[@]}" -- "$SETTINGS_SSH_HOST" "$1"
}

# Reserve an unused local loopback port through SSH.
# Args: remote port; writes SESSION_NEW_FORWARD_PORT; retries bind collisions.
_create-local-ssh-forward() {
    # The SSH bind is the reservation. A failed candidate is safe to retry.
    local remote_port=$1 candidate attempt
    for ((attempt = 0; attempt < 20; attempt++)); do
        candidate=$((20000 + ((RANDOM << 1) ^ RANDOM) % 40000))
        if _run-ssh-master-command -O forward \
            -L "127.0.0.1:$candidate:127.0.0.1:$remote_port" \
            > /dev/null 2> "$SESSION_WORK_DIRECTORY/forward.err"; then
            SESSION_NEW_FORWARD_PORT=$candidate
            _log-debug "Forward: local 127.0.0.1:$candidate -> remote 127.0.0.1:$remote_port"
            return 0
        fi
        _run-ssh-master-command -O check > /dev/null 2>&1 || break
    done
    [[ ! -s $SESSION_WORK_DIRECTORY/forward.err ]] || cat "$SESSION_WORK_DIRECTORY/forward.err" >&2
    _exit-with-error 'Could not allocate an SSH forwarding port. Check the SSH connection and TCP forwarding permissions.'
}

# Probe adb host:version directly, avoiding adb client restarts.
# Reads the SSH-mapped ADB socket in a subshell; prints protocol number.
_read-adb-server-protocol() (
    # A plain adb command may kill a server with a different protocol version.
    # This read-only request does not run an adb client. A subshell owns the FD
    # so EOF, errors and SIGPIPE cannot leak it into the interactive launcher.
    local fd status='' size='' payload='' result length
    if ! { exec {fd}<>"/dev/tcp/127.0.0.1/$SESSION_LOCAL_ADB_TUNNEL_PORT"; } 2>/dev/null; then
        return 2
    fi
    printf '000chost:version' >&"$fd" || return 2
    if IFS= read -r -N 4 -t 5 status <&"$fd"; then
        :
    else
        result=$?
        if [[ -z $status && $result == 1 ]]; then
            return 2  # SSH accepted locally, but no remote daemon answered.
        fi
        printf '%s\n' 'ADB version response timed out or ended before its status was complete.' >&2
        return 1
    fi
    if [[ $status != OKAY && $status != FAIL ]]; then
        printf '%s\n' 'The remote ADB port returned an invalid protocol status.' >&2
        return 1
    fi
    if ! IFS= read -r -N 4 -t 5 size <&"$fd" || [[ ! $size =~ ^[[:xdigit:]]{4}$ ]]; then
        printf '%s\n' 'The remote ADB server returned a truncated or invalid response length.' >&2
        return 1
    fi
    length=$((16#$size))
    if ((length < 1 || length > 4096)); then
        printf '%s\n' 'The remote ADB server returned an invalid version payload length.' >&2
        return 1
    fi
    if ! IFS= read -r -N "$length" -t 5 payload <&"$fd"; then
        printf '%s\n' 'The remote ADB server returned an incomplete version payload.' >&2
        return 1
    fi
    if [[ $status == FAIL ]]; then
        printf '%s\n' 'The remote ADB server rejected its version query.' >&2
        return 1
    fi
    if [[ ! $payload =~ ^[[:xdigit:]]{1,8}$ ]]; then
        printf '%s\n' 'The remote ADB server returned an invalid protocol version.' >&2
        return 1
    fi
    printf '%d\n' "$((16#$payload))"
)

# Set SESSION_REMOTE_ADB_PROTOCOL without restarting shared ADB.
# Status 0=success, 2=absent, 1=malformed/other; sets error details.
_probe-adb-server() {
    local result
    SESSION_ADB_PROBE_ERROR=''
    if SESSION_REMOTE_ADB_PROTOCOL=$(_read-adb-server-protocol 2> "$SESSION_WORK_DIRECTORY/probe.err"); then
        return 0
    else
        result=$?
        SESSION_ADB_PROBE_ERROR=$(< "$SESSION_WORK_DIRECTORY/probe.err")
        # SIGPIPE also means the connection closed before the request completed.
        [[ $result != 141 ]] || result=2
        return "$result"
    fi
}

# Open private SSH mux and verify remote ADB startup/protocol.
# Allocates SESSION_WORK_DIRECTORY/SESSION_LOCAL_ADB_TUNNEL_PORT; EXIT trap must already be installed.
_open-remote-connection() {
    local version command result
    local -a master=(ssh -fMNT)
    SESSION_WORK_DIRECTORY=$(mktemp -d /tmp/remote-scrcpy.XXXXXXXX) || _exit-with-error 'Could not create a private temporary directory.'
    SESSION_SSH_CONTROL_SOCKET=$SESSION_WORK_DIRECTORY/ssh
    SESSION_SSH_CONTROL_COMMAND=(ssh -F /dev/null -S "$SESSION_SSH_CONTROL_SOCKET" -T -n
        -o ControlMaster=no -o BatchMode=yes -o ProxyCommand=false)
    [[ -z $SETTINGS_SSH_CONFIG_FILE ]] || master+=(-F "$SETTINGS_SSH_CONFIG_FILE")
    ((SETTINGS_NON_INTERACTIVE == 0)) || master+=(-o BatchMode=yes)
    ((SETTINGS_VERBOSE == 0)) || master+=(-v)
    master+=(-S "$SESSION_SSH_CONTROL_SOCKET"
        -o ControlPersist=no -o ClearAllForwardings=yes
        -o ExitOnForwardFailure=yes -o RemoteCommand=none
        -o PermitLocalCommand=no -o ForwardX11=no -o ForwardAgent=no
        -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ConnectTimeout=15)
    _log-status "Connecting to $SETTINGS_SSH_HOST..."
    "${master[@]}" -- "$SETTINGS_SSH_HOST" || _exit-with-error 'SSH connection failed; see the SSH error above.'
    _run-ssh-master-command -O check > /dev/null 2>&1 || _exit-with-error 'The SSH control connection could not be established.'
    _create-local-ssh-forward "$SETTINGS_REMOTE_ADB_SERVER_PORT"
    SESSION_LOCAL_ADB_TUNNEL_PORT=$SESSION_NEW_FORWARD_PORT

    version=$("$SETTINGS_LOCAL_ADB_EXECUTABLE" version) || _exit-with-error 'Could not read the local ADB version.'
    if [[ $version =~ Android\ Debug\ Bridge\ version\ 1\.0\.([0-9]+) ]]; then
        SESSION_LOCAL_ADB_PROTOCOL=$((10#${BASH_REMATCH[1]}))
    else
        _exit-with-error 'Could not determine the local ADB protocol version. Check the configured ADB executable.'
    fi
    _log-status "Checking ADB on $SETTINGS_SSH_HOST..."
    if _probe-adb-server; then
        :
    else
        result=$?
        if ((result != 2)); then
            _exit-with-error "${SESSION_ADB_PROBE_ERROR:-Could not query the remote ADB server.} Check SSH TCP forwarding and the remote ADB port."
        fi
        # Hostless tcp:PORT permits a local daemon start on the SSH host.
        # tcp:127.0.0.1:PORT is treated as remote by ADB's startup logic.
        command="exec env $(_quote-remote-shell-argument "ADB_SERVER_SOCKET=tcp:$SETTINGS_REMOTE_ADB_SERVER_PORT") $(_quote-remote-shell-argument "$SETTINGS_REMOTE_ADB_EXECUTABLE") start-server"
        _log-status "Starting ADB on $SETTINGS_SSH_HOST..."
        _run-remote-shell-command "$command" >&2 || _exit-with-error 'Could not start ADB on the remote host. Check its ADB installation, executable path and USB permissions.'
        if ! _probe-adb-server; then
            _exit-with-error "${SESSION_ADB_PROBE_ERROR:-ADB is still unreachable through SSH.} Check SSH TCP forwarding and the remote ADB port."
        fi
    fi
    if [[ $SESSION_REMOTE_ADB_PROTOCOL != "$SESSION_LOCAL_ADB_PROTOCOL" ]]; then
        _exit-with-error "ADB protocol mismatch: local client $SESSION_LOCAL_ADB_PROTOCOL, remote server $SESSION_REMOTE_ADB_PROTOCOL. Install compatible Platform Tools on the viewing computer. The remote server was not restarted."
    fi
    _log-debug "ADB protocol $SESSION_LOCAL_ADB_PROTOCOL matches the remote server."
}

# Call local adb against the tunneled remote ADB server.
# Args: adb arguments; clears conflicting inherited ADB environment.
_run-remote-adb-client() {
    env -u ANDROID_SERIAL -u ANDROID_ADB_SERVER_ADDRESS -u ANDROID_ADB_SERVER_PORT \
        "ADB_SERVER_SOCKET=tcp:127.0.0.1:$SESSION_LOCAL_ADB_TUNNEL_PORT" "$SETTINGS_LOCAL_ADB_EXECUTABLE" "$@"
}

# Atomically allocate remote scrcpy TCP port via adb tcp:0.
# Sets reservation token and SESSION_REMOTE_MEDIA_PORT/SESSION_LOCAL_MEDIA_TUNNEL_PORT.
_reserve-device-forwarding-port() {
    local port
    SESSION_ADB_PORT_RESERVATION="localabstract:remote_scrcpy_${SESSION_WORK_DIRECTORY##*/}_$RANDOM"
    # tcp:0 atomically chooses and holds an unused port on the remote host.
    # scrcpy will rebind this placeholder to its own device socket.
    port=$(_run-remote-adb-client -s "$SETTINGS_DEVICE_SERIAL" forward tcp:0 "$SESSION_ADB_PORT_RESERVATION") \
        || _exit-with-error 'Could not reserve a remote forwarding port for the selected device.'
    if [[ ! $port =~ ^[0-9]{1,5}$ ]] || ((10#$port < 1 || 10#$port > 65535)); then
        _exit-with-error 'ADB did not return a valid allocated TCP port.'
    fi
    SESSION_REMOTE_MEDIA_PORT=$((10#$port))
    _create-local-ssh-forward "$SESSION_REMOTE_MEDIA_PORT"
    SESSION_LOCAL_MEDIA_TUNNEL_PORT=$SESSION_NEW_FORWARD_PORT
}

# Check whether this session’s scrcpy process still exists.
# Reads SESSION_SCRCPY_PROCESS_ID; status is Boolean.
_is-scrcpy-process-alive() {
    [[ -n $SESSION_SCRCPY_PROCESS_ID ]] && kill -0 "$SESSION_SCRCPY_PROCESS_ID" 2>/dev/null
}

# Bounded poll while allowing scrcpy to shut down gracefully.
# Args: number of 0.1-second intervals; does not force signal.
_wait-for-scrcpy-exit() {
    local attempts=$1
    while ((attempts-- > 0)) && _is-scrcpy-process-alive; do
        sleep 0.1
    done
    ! _is-scrcpy-process-alive
}

# Signal only the owned scrcpy process group, then reap it.
# Args: INT/TERM/HUP; idempotent, used by traps.
_stop-scrcpy-process() {
    # Called by the main INT/TERM/HUP handler before it exits. The player has a
    # separate process group, so a terminal signal is forwarded exactly once.
    local signal=${1:-INT}
    ((SESSION_STOPPING == 0)) || return 0
    SESSION_STOPPING=1
    if _is-scrcpy-process-alive; then
        kill -s "$signal" "$SESSION_SCRCPY_PROCESS_ID" 2>/dev/null || true
        if ! _wait-for-scrcpy-exit 50; then
            kill -TERM -- "-$SESSION_SCRCPY_PROCESS_ID" 2>/dev/null || true
            if ! _wait-for-scrcpy-exit 20; then
                kill -KILL -- "-$SESSION_SCRCPY_PROCESS_ID" 2>/dev/null || true
            fi
        fi
        wait "$SESSION_SCRCPY_PROCESS_ID" 2>/dev/null || true
    fi
    SESSION_SCRCPY_PROCESS_ID=''
    SESSION_STOPPING=0
    return 0
}

# Start local scrcpy with the exact owned forwarding ports.
# Forwards SETTINGS_SCRCPY_EXTRA_ARGUMENTS; propagates scrcpy exit status.
_launch-scrcpy() {
    local result monitor_was_enabled=0
    [[ $- != *m* ]] || monitor_was_enabled=1
    # Bash job control isolates the GUI's process group without adding setsid
    # or Python as a runtime dependency. The GUI does not read terminal stdin.
    set -m
    (
        trap - INT QUIT TERM HUP
        exec env -u ANDROID_SERIAL -u ANDROID_ADB_SERVER_ADDRESS -u ANDROID_ADB_SERVER_PORT \
            "ADB=$SETTINGS_LOCAL_ADB_EXECUTABLE" "ADB_SERVER_SOCKET=tcp:127.0.0.1:$SESSION_LOCAL_ADB_TUNNEL_PORT" \
            "$SETTINGS_LOCAL_SCRCPY_EXECUTABLE" "--serial=$SETTINGS_DEVICE_SERIAL" --force-adb-forward \
            "--port=$SESSION_REMOTE_MEDIA_PORT" --tunnel-host=127.0.0.1 \
            "--tunnel-port=$SESSION_LOCAL_MEDIA_TUNNEL_PORT" "${SETTINGS_SCRCPY_EXTRA_ARGUMENTS[@]}"
    ) < /dev/null &
    SESSION_SCRCPY_PROCESS_ID=$!
    ((monitor_was_enabled != 0)) || set +m
    if wait "$SESSION_SCRCPY_PROCESS_ID"; then result=0; else result=$?; fi
    SESSION_SCRCPY_PROCESS_ID=''
    return "$result"
}

# Release owned ADB reservation, SSH mux and temp directory.
# Safe after partial setup; never terminates shared remote adb.
_cleanup-remote-connection() {
    local serial endpoint target extra listing directory
    [[ -n $SESSION_WORK_DIRECTORY ]] || return 0
    _stop-scrcpy-process INT
    if [[ -n $SESSION_ADB_PORT_RESERVATION && -n $SESSION_LOCAL_ADB_TUNNEL_PORT ]] \
        && _probe-adb-server && [[ $SESSION_REMOTE_ADB_PROTOCOL == "$SESSION_LOCAL_ADB_PROTOCOL" ]]; then
        if listing=$(_run-remote-adb-client forward --list 2>/dev/null); then
            while read -r serial endpoint target extra; do
                if [[ $serial == "$SETTINGS_DEVICE_SERIAL" && $target == "$SESSION_ADB_PORT_RESERVATION" \
                    && $endpoint =~ ^tcp:[0-9]+$ && -z $extra ]]; then
                    # Do not remove scrcpy's replacement, or a port now reused
                    # by another session. Only an unused unique token matches.
                    _run-remote-adb-client -s "$serial" forward --remove "$endpoint" > /dev/null 2>&1 || true
                fi
            done <<< "$listing"
        fi
    fi
    _run-ssh-master-command -O exit > /dev/null 2>&1 || true
    directory=$SESSION_WORK_DIRECTORY
    SESSION_WORK_DIRECTORY=''
    SESSION_SSH_CONTROL_SOCKET=''
    SESSION_ADB_PORT_RESERVATION=''
    rm -rf -- "$directory" || true
    return 0
}

# ===== prerequisites.sh =====
# Extended, self-contained setup guide. Intentionally contains only established
# prerequisites; site-specific policies are left as explicit placeholders until
# the maintainer supplies exact remote-server and phone preparation steps.
# No commands are executed in this mode.
# Show detailed local/remote/phone preparation checklist.
# Static stdout; includes TODOs awaiting user’s site-specific instructions.
_print-prerequisites() {
    local line
    while IFS= read -r line; do printf '%s\n' "$line"; done <<'GUIDE'
REMOTE SCRCPY — PREREQUISITES & PREPARATION
==========================================

1. VIEWING COMPUTER (the machine running remote-scrcpy)
   - Linux or another TESTED Unix-like environment with Bash >= 4.4.
   - OpenSSH client (`ssh`) with multiplexing and local TCP forwarding.
   - `scrcpy` installed and a usable `adb` client available. Some scrcpy
     packages depend on or bundle adb; this launcher still invokes adb itself
     to enumerate devices and configure forwarding. Check `command -v adb`.
   - A graphical desktop with video support for the scrcpy window.
   - Standard tools: awk, mktemp, rm, sleep. No extra terminal UI dependency.

   Check:
     bash --version
     ssh -V
     adb version
     scrcpy --version

2. REMOTE COMPUTER (phone is attached here)
   - Reachable SSH server and credentials/key for the SSH user.
   - `adb` accessible from that user's noninteractive SSH shell, or provide
     `--remote-adb /absolute/path/to/adb`.
   - Permit local TCP forwarding through SSH (sshd policy AllowTcpForwarding).
   - Same or compatible ADB client/server protocol as the viewing computer.
   - Authorized USB access for the remote user. Verify:
       ssh HOST 'adb start-server && adb devices -l'

   IMPORTANT: The launcher reuses remote ADB and does not deliberately stop
   an existing remote ADB server. ADB authorization is specific to the host
   user/configuration; do not run it under a different user unexpectedly.

3. ANDROID PHONE(S)
   - Enable Developer options and USB debugging through Android settings.
   - Plug the phone into the REMOTE computer using a data-capable cable.
   - Unlock the phone and approve the remote computer's RSA debugging prompt.
   - Confirm `adb devices -l` on the remote reports the state `device`.
   - `unauthorized`: confirm the on-phone authorization prompt.
   - `offline`: reconnect/restart ADB and inspect USB connectivity.
   - `no permissions`: correct the remote Linux user/udev USB permissions.

4. SSH ALIASES AND FIREWALL
   Optionally add a readable SSH alias in ~/.ssh/config, for example:

     Host alienware
         HostName 192.0.2.10
         User myuser

   Replace the example address and username. The launcher shows literal Host
   aliases; you can also enter any valid SSH destination manually.
   Only SSH needs to be accessible over the network; forwarding ports bind
   on loopback and are routed through the authenticated SSH session.

5. SITE-SPECIFIC SETUP (TO BE PROVIDED BY THE MAINTAINER)
   [TODO: Add remote server provisioning steps, packages, service setup,
    SSH hardening decisions, USB permissions, ADB startup procedures, and
    any site-specific reconnect or recovery steps.]

   [TODO: Add phone-specific instructions for each Android version/model,
    charging/USB restrictions, authorization lifecycle, and any security
    guidance relevant to the phones being used.]

   Please supply exact OS, device model, installation and authorization
   procedures before turning these TODOs into prescriptive instructions.

6. TROUBLESHOOTING
   - `remote-scrcpy --list-hosts` lists aliases locally, without SSH.
   - `remote-scrcpy --list-devices HOST` checks remote discovery without GUI.
   - `remote-scrcpy --verbose HOST SERIAL` prints SSH/ADB diagnostics.
   - `ADB server mismatch`: align Android Platform Tools versions; the
     launcher does not forcibly restart an incompatible shared server.
   - scrcpy SDL/display errors: run on the viewer's graphical desktop,
     not from an ordinary SSH shell on the remote computer.
   - Review scrcpy's own documentation for platform-specific requirements.

Security: USB debugging and SSH access give powerful control of the phone.
Only authorize computers and accounts you trust. Keep forwarding local.
GUIDE
}

# ===== completion.sh =====
# Bash completion is emitted as shell text; it is not installed automatically.
# Host suggestions come from the SSH config. Device suggestions are live SSH
# queries by default. Completion never prompts for passwords: it uses BatchMode.
# REMOTE_SCRCPY_COMPLETE_DEVICES=0 disables network queries from Tab completion.
# REMOTE_SCRCPY_COMPLETION_TIMEOUT controls the optional `timeout` wrapper
# (default 6 seconds). A failed/offline host simply yields zero suggestions.
#
# Install for the current Bash shell:
#   source <(remote-scrcpy --completion bash)
# Users can add the same line to ~/.bashrc for persistent completion.

# Emit standalone completion code. No network access occurs until Tab is pressed.
_print-bash-completion() {
    while IFS= read -r line; do printf '%s\n' "$line"; done <<'COMPLETION'
# Bash completion for remote-scrcpy; source once per interactive Bash shell.
# Device serials are queried through SSH by default. Set
# REMOTE_SCRCPY_COMPLETE_DEVICES=0 to use host-only, offline completion.
# The source executable is invoked only for --list-hosts.

# Quote a single shell argument for SSH's remote command string.
# This is data escaping, not evaluation. Supports paths containing apostrophes.
_remote-scrcpy-quote-remote-argument() {
    local value=${1//\'/\'\\\'\'}
    printf "'%s'" "$value"
}

# Produce device serials on stdout without changing the remote ADB server's
# lifecycle beyond adb's normal `devices -l` behavior. This is deliberately
# a read-only ADB inventory query, not a scrcpy connection/tunnel setup.
_remote-scrcpy-query-device-serials() {
    local host=$1 config=$2 remote_adb=$3 limit=$4 line serial state
    local -a ssh_command=(ssh -T -o BatchMode=yes -o NumberOfPasswordPrompts=0
        -o ConnectTimeout=3 -o ConnectionAttempts=1
        -o ServerAliveInterval=2 -o ServerAliveCountMax=1)
    [[ -z $config ]] || ssh_command+=(-F "$config")
    ssh_command+=(-- "$host" "$(_remote-scrcpy-quote-remote-argument "$remote_adb") devices -l")
    local -a bounded_command=("${ssh_command[@]}")
    # `timeout` is optional, not a new hard dependency. ssh's own connection
    # and keepalive limits remain in effect if the utility is unavailable.
    if command -v timeout >/dev/null 2>&1; then
        bounded_command=(timeout "${limit}s" "${ssh_command[@]}")
    fi
    while IFS= read -r line; do
        [[ -n $line && $line != 'List of devices attached'* && $line != \** ]] || continue
        read -r serial state _ <<< "$line"
        [[ $state == device && -n $serial ]] && printf '%s\n' "$serial"
    done < <("${bounded_command[@]}" 2>/dev/null)
}

# Entry point used by Bash's programmable completion system.
# Resolves the current argument position, including --host/--serial and
# --key=value forms. Existing option values must not be treated as positionals.
_complete-remote-scrcpy() {
    local current previous word index host='' serial='' ssh_config='' remote_adb=''
    local value complete_host=0 complete_serial=0 explicit_host=0
    local command=${COMP_WORDS[0]}
    local -a positions=()
    local options='--help --version --host --serial --list-hosts --list-devices --list --ssh-config --adb --remote-adb --adb-port --color --ascii --non-interactive --quiet --verbose --prerequisites --completion'
    current=${COMP_WORDS[COMP_CWORD]:-}
    previous=${COMP_WORDS[COMP_CWORD-1]:-}
    ssh_config=${REMOTE_SCRCPY_SSH_CONFIG:-}
    remote_adb=${REMOTE_SCRCPY_REMOTE_ADB:-${REMOTE_ADB:-adb}}
    host=${REMOTE_SCRCPY_HOST:-}

    # Parse only completed words. No evaluation of SSH alias or shell text.
    for ((index=1; index<COMP_CWORD; index++)); do
        word=${COMP_WORDS[index]}
        [[ $word == -- ]] && return 0  # Everything after -- belongs to scrcpy.
        case $word in
            --host|--serial|--ssh-config|--adb|--remote-adb|--adb-port|--color|--completion)
                value=${COMP_WORDS[index+1]:-}
                case $word in
                    --host) host=$value; explicit_host=1 ;;
                    --serial) serial=$value ;;
                    --ssh-config) ssh_config=$value ;;
                    --remote-adb) remote_adb=$value ;;
                esac
                ((index+=1)) ;;
            --host=*) host=${word#*=}; explicit_host=1 ;;
            --serial=*) serial=${word#*=} ;;
            --ssh-config=*) ssh_config=${word#*=} ;;
            --remote-adb=*) remote_adb=${word#*=} ;;
            --*=*|-*) ;;
            *) positions+=("$word") ;;
        esac
    done
    [[ -n $host ]] || host=${positions[0]:-}

    case $previous in
        --host) complete_host=1 ;;
        --serial) complete_serial=1 ;;
        --color) COMPREPLY=( $(compgen -W 'auto always never' -- "$current") ); return ;;
        --completion) COMPREPLY=( $(compgen -W bash -- "$current") ); return ;;
        --ssh-config|--adb|--remote-adb)
            COMPREPLY=( $(compgen -f -- "$current") ); return ;;
        --adb-port) return ;;
    esac

    # Support `--host=...`, `--serial=...` and `--color=...` without
    # replacing the option prefix when Bash inserts a completion candidate.
    case $current in
        --host=*) current=${current#*=}; complete_host=2 ;;
        --serial=*) current=${current#*=}; complete_serial=2 ;;
        --color=*)
            current=${current#*=}
            while IFS= read -r value; do COMPREPLY+=("--color=$value"); done \
                < <(compgen -W 'auto always never' -- "$current")
            return ;;
        --*) COMPREPLY=( $(compgen -W "$options" -- "$current") ); return ;;
    esac

    if (( complete_host == 0 && complete_serial == 0 )); then
        # The first positional is the SSH host unless a --host flag already
        # supplied one. An environment-host similarly makes it a serial.
        if (( explicit_host )) || [[ -n ${REMOTE_SCRCPY_HOST:-} ]]; then
            complete_serial=1
        elif (( ${#positions[@]} )); then
            complete_serial=1
        else
            complete_host=1
        fi
    fi

    if (( complete_host )); then
        local -a host_command=("$command" --list-hosts)
        [[ -z $ssh_config ]] || host_command+=(--ssh-config "$ssh_config")
        while IFS= read -r value; do
            [[ $value == "$current"* ]] || continue
            if (( complete_host == 2 )); then COMPREPLY+=("--host=$value")
            else COMPREPLY+=("$value"); fi
        done < <("${host_command[@]}" 2>/dev/null)
        return
    fi
    if (( complete_serial )) && [[ ${REMOTE_SCRCPY_COMPLETE_DEVICES:-1} != 0 && -n $host ]]; then
        local limit=${REMOTE_SCRCPY_COMPLETION_TIMEOUT:-6}
        [[ $limit =~ ^[1-9][0-9]?$ ]] || limit=6
        while IFS= read -r value; do
            [[ $value == "$current"* ]] || continue
            if (( complete_serial == 2 )); then COMPREPLY+=("--serial=$value")
            else COMPREPLY+=("$value"); fi
        done < <(_remote-scrcpy-query-device-serials "$host" "$ssh_config" "$remote_adb" "$limit")
    fi
}
complete -F _complete-remote-scrcpy remote-scrcpy remote-scrcpy.sh
COMPLETION
}

# ===== main.sh =====
# Application controller. remote-scrcpy is the only public function.
# CLI parsing, selection, transport, GUI and cleanup share one linear lifecycle.

# Entry point: each step fills missing input, without duplicating connection logic.

# Preserve exit status while performing idempotent cleanup.
# Invoked via EXIT trap; never returns.
_handle-process-exit() {
    local status=$?
    trap - EXIT
    trap '' INT TERM HUP
    set +e
    _cleanup-remote-connection
    exit "$status"
}

# Forward signal to owned scrcpy, then exit with signal code.
# Args: signal and exit status; triggers EXIT cleanup.
_handle-termination-signal() {
    local signal=$1 status=$2
    trap '' INT TERM HUP
    _stop-scrcpy-process "$signal"
    exit "$status"
}

# Public application entry point and sole exported command function.
# Args: CLI argv; orchestrates parsing, menus, transport and cleanup.
remote-scrcpy() {
    _initialize-configuration
    _parse-command-line "$@"
    _validate-configuration
    _validate-scrcpy-arguments
    _initialize-terminal-styles

    # Local help modes must not require SSH, adb, scrcpy, or a working network.
    case $SETTINGS_OPERATION in
        prerequisites) _print-prerequisites; return ;;
        completion) _print-bash-completion; return ;;
    esac

    if [[ $SETTINGS_OPERATION == hosts ]]; then
        command -v awk >/dev/null || _exit-with-error 'Missing prerequisite: awk' 127
        _discover-ssh-host-aliases "$SETTINGS_SSH_DISCOVERY_CONFIG_FILE"
        return
    fi
    # Install cleanup before the first prompt. Plain read never changes tty mode.
    trap _handle-process-exit EXIT
    trap '_handle-termination-signal INT 130' INT
    trap '_handle-termination-signal TERM 143' TERM
    trap '_handle-termination-signal HUP 129' HUP
    _print-introduction
    _check-runtime-dependencies
    [[ -n $SETTINGS_SSH_HOST ]] || _prompt-for-ssh-host
    # Validate an absent serial before connecting if the caller cannot answer a menu.
    if [[ $SETTINGS_OPERATION == connect && -z $SETTINGS_DEVICE_SERIAL ]]; then
        _require-interactive-terminal 'device serial' 'Pass SERIAL or --serial SERIAL.'
    fi

    _open-remote-connection
    _load-remote-device-list
    if [[ $SETTINGS_OPERATION == devices ]]; then
        _print-remote-device-list
        return
    fi
    [[ -n $SETTINGS_DEVICE_SERIAL ]] || _prompt-for-device
    _validate-selected-device
    _reserve-device-forwarding-port
    _log-status "Opening $SETTINGS_DEVICE_SERIAL via $SETTINGS_SSH_HOST. Close the window or press Ctrl+C to disconnect."
    _launch-scrcpy
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    remote-scrcpy "$@"
fi
