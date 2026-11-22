# CLI contract: only parse and validate arguments; never open a connection or
# a menu. Positional HOST and SERIAL fill the same state as --host and
# --serial. A standalone -- is the boundary: what follows goes to scrcpy.

# Print the syntax, examples, options, precedence and basic setup; the long
# setup procedure is --prerequisites.
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
  remote-scrcpy remote-host
  remote-scrcpy remote-host DEVICE1234567890
  remote-scrcpy remote-host -- --max-size=1280 --max-fps=30
  remote-scrcpy --list-devices remote-host
  remote-scrcpy --non-interactive remote-host DEVICE1234567890

OPTIONS
  An option that takes a value also accepts it as --option=VALUE.
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
  NO_COLOR=1 disables color unless --color=always or
  REMOTE_SCRCPY_COLOR=always asks for it.

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
  REMOTE_SCRCPY_COMPLETION_TIMEOUT=6 bounds a lookup, in seconds from 1 to
  99, where a `timeout` program is installed; other values mean 6.

NOTES
  Host listing is a static SSH-config alias inventory; OpenSSH controls the
  actual connection. The launcher owns scrcpy's device, tunnel and adb
  lifecycle options and rejects them after --: --serial, --select-usb,
  --select-tcpip, --tcpip, --otg, --port, --tunnel-host, --tunnel-port,
  --force-adb-forward, --kill-adb-on-close and their abbreviations, and the
  short flags -s -d -e -p. Other short flags are passed on one per word;
  only -m, -b and -r may carry their value in the same word, so write
  -V debug, not -Vdebug. A second -- is refused. Write an option's value as
  --option=value when it starts with a dash. Use `scrcpy --help` for
  supported display, audio, input, and recording options.

EXIT STATUS
  Listing and help modes exit 0. Otherwise, from the launcher itself,
  before scrcpy is started:
    1    runtime failure (SSH, ADB, forwarding, protocol mismatch)
    2    usage or configuration error; nothing was connected
    127  a required executable is missing
  From a signal or a prompt, at any time:
    129  the terminal was closed (SIGHUP)
    130  cancelled at a prompt, or interrupted (SIGINT)
    143  terminated (SIGTERM)
  Once scrcpy runs, its own exit status is passed on unchanged: 0 when it
  quits normally, and scrcpy uses 1 and 2 for failures of its own.
END_HELP_TEXT
}

# Assign a host or serial given on the command line, once: a second one is an
# error, while a value that only came from the environment may be replaced.
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

# Choose the one thing a run does instead of connecting. A second mode
# option is a usage error, whichever two they are and in whichever order.
# Args: operation (hosts, devices, prerequisites or completion); sets
# SETTINGS_OPERATION; exits with status 2 when a mode was already chosen.
_select-operation() {
    [[ $SETTINGS_OPERATION == connect ]] \
        || _exit-with-error 'Choose only one of --list-hosts, --list-devices, --prerequisites and --completion.' 2
    SETTINGS_OPERATION=$1
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
            --prerequisites) _select-operation prerequisites; shift ;;
            --completion|--completion=*)
                if [[ $arg == *=* ]]; then
                    value=${arg#*=}; shift
                else
                    (( $# >= 2 )) || _exit-with-error '--completion requires bash.' 2
                    value=$2; shift 2
                fi
                [[ $value == bash ]] || _exit-with-error 'Only Bash completion is supported.' 2
                _select-operation completion ;;
            -V|--version) printf 'remote-scrcpy %s\n' "$APPLICATION_VERSION"; exit 0 ;;
            -v|--verbose) SETTINGS_VERBOSE=1; shift ;;
            --quiet) SETTINGS_QUIET=1; shift ;;
            --ascii) SETTINGS_ASCII_ONLY=1; shift ;;
            --non-interactive) SETTINGS_NON_INTERACTIVE=1; shift ;;
            --list-hosts) _select-operation hosts; shift ;;
            --list-devices) _select-operation devices; shift ;;
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
    # Only a connection and the device list are about a host, and only a
    # connection starts scrcpy. A host, a serial or a scrcpy option next to
    # a mode that has no use for it is a mistake, not something to ignore.
    case $SETTINGS_OPERATION in
        hosts) key=--list-hosts ;;
        devices) key=--list-devices ;;
        prerequisites) key=--prerequisites ;;
        completion) key=--completion ;;
        *) return 0 ;;
    esac
    if [[ $key == --list-devices ]]; then
        (( ! CLI_SERIAL_EXPLICIT )) || _exit-with-error '--list-devices does not take a serial.' 2
    elif (( CLI_HOST_EXPLICIT || CLI_SERIAL_EXPLICIT )); then
        _exit-with-error "$key does not take a host or serial." 2
    fi
    if (( ${#SETTINGS_SCRCPY_EXTRA_ARGUMENTS[@]} )); then
        _exit-with-error "$key does not take scrcpy options." 2
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
                -[psde]*) _exit-with-error "The launcher manages $arg. (If it is an option's value, write --option=value.)" 2 ;;
                -[mbr]*|-[[:alnum:]]) ;;
                *) _exit-with-error "Use separate short flags or full long options after --: $arg (If it is an option's value, write --option=value.)" 2 ;;
            esac
        fi
    done
}
