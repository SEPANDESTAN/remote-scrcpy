# Numbered interactive menus and remote ADB device enumeration.
# Menus write to stderr and change SETTINGS_SSH_HOST and SETTINGS_DEVICE_SERIAL
# only after a valid selection; the listing modes write plain data to stdout.
# Remote data is parsed once into the parallel DISCOVERED_DEVICE_* arrays,
# where one index describes one device.

# Choose a literal SSH alias or manually entered destination.
# Writes SETTINGS_SSH_HOST; q cancels; does not connect.
_prompt-for-ssh-host() {
    _require-interactive-terminal 'SSH host' 'Pass HOST or --host HOST.'
    local -a choices=()
    local choice index
    mapfile -t choices < <(_discover-ssh-host-aliases "$SETTINGS_SSH_DISCOVERY_CONFIG_FILE")
    _print-section-heading "Remote hosts from ${SETTINGS_SSH_DISCOVERY_CONFIG_FILE:-the SSH config (none: no home directory)}:"
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
        if [[ $choice =~ ^[0123456789]+$ ]]; then
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
        if (( ! exact )) && [[ $choice =~ ^[0123456789]{1,6}$ ]]; then
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
