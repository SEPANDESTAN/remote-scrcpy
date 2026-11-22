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

# Stop the owned scrcpy for a received signal, then exit with its code.
# Args: signal and exit status; triggers EXIT cleanup.
_handle-termination-signal() {
    local signal=$1 status=$2
    trap '' INT TERM HUP
    # scrcpy shuts down cleanly on INT and TERM only; nothing in it handles
    # HUP, which would kill it before its own shutdown: finishing a recording,
    # stopping the server and, during startup, removing its adb forward. A
    # closed terminal therefore reaches it as TERM. The exit status still
    # says HUP.
    [[ $signal != HUP ]] || signal=TERM
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
