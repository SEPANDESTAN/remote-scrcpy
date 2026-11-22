# SSH/ADB/scrcpy connection lifetime and resource ownership. No work happens
# when the module is loaded.
# Reads: SETTINGS_SSH_HOST, SETTINGS_DEVICE_SERIAL, SETTINGS_SSH_CONFIG_FILE,
# SETTINGS_LOCAL_ADB_EXECUTABLE, SETTINGS_REMOTE_ADB_EXECUTABLE,
# SETTINGS_REMOTE_ADB_SERVER_PORT, SETTINGS_LOCAL_SCRCPY_EXECUTABLE,
# SETTINGS_SCRCPY_EXTRA_ARGUMENTS, SETTINGS_NON_INTERACTIVE, SETTINGS_VERBOSE.
# Owns: the SESSION_* variables below, which no other module touches. They
# start empty or inactive, and each is assigned by the function that creates
# the resource it names. The EXIT trap must run _cleanup-remote-connection on
# every failure after connecting, and that function may run after partial
# setup, so it MUST tolerate unset or incomplete resources.
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
    local fd status='' size='' payload='' result length version
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
    # The two hex fields come from the remote. printf converts them without
    # evaluating anything: handed something that is not a number it fails,
    # where shell arithmetic would run a command substitution inside it. The
    # checks in front say which field was wrong; the conversion does not
    # depend on them for its safety.
    if ! IFS= read -r -N 4 -t 5 size <&"$fd" || [[ ! $size =~ ^[[:xdigit:]]{4}$ ]] \
        || ! printf -v length '%d' "0x$size" 2>/dev/null; then
        printf '%s\n' 'The remote ADB server returned a truncated or invalid response length.' >&2
        return 1
    fi
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
    if [[ ! $payload =~ ^[[:xdigit:]]{1,8}$ ]] || ! printf -v version '%d' "0x$payload" 2>/dev/null; then
        printf '%s\n' 'The remote ADB server returned an invalid protocol version.' >&2
        return 1
    fi
    printf '%s\n' "$version"
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
            _exit-with-error "${SESSION_ADB_PROBE_ERROR:-ADB is still unreachable through SSH.} Check SSH TCP forwarding, the remote ADB port, and that this Bash supports /dev/tcp."
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
# Args: INT or TERM; idempotent, used by traps.
_stop-scrcpy-process() {
    # Called by the main signal handler before it exits, which passes a
    # received HUP on as TERM. The player has a separate process group, so a
    # terminal signal is forwarded exactly once.
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
                    # Only this session's own, still unused reservation
                    # matches. A forward that scrcpy has rebound to its own
                    # socket is deliberately left alone, even if scrcpy died
                    # before removing it: by then the port may belong to
                    # another session, and the two cannot be told apart.
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
