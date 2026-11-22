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

# Decide what the last of the given whole words completes to.
# Args: the command line as whole words, command first, the word being
# completed last. Sets COMPREPLY to whole-word candidates, so `--host=re`
# yields `--host=remote-host`. Resolves the argument position, including
# --host/--serial and --key=value forms; an option's value is never a positional.
_remote-scrcpy-complete-words() {
    local -a words=("$@")
    local last=$(( $# - 1 ))
    local current=${words[last]} previous='' word index host='' serial='' ssh_config='' remote_adb=''
    local value complete_host=0 complete_serial=0 explicit_host=0
    local command=${words[0]}
    local -a positions=()
    local options='--help --version --host --serial --list-hosts --list-devices --list --ssh-config --adb --remote-adb --adb-port --color --ascii --non-interactive --quiet --verbose --prerequisites --completion'
    if (( last >= 1 )); then previous=${words[last-1]}; fi
    ssh_config=${REMOTE_SCRCPY_SSH_CONFIG:-}
    remote_adb=${REMOTE_SCRCPY_REMOTE_ADB:-${REMOTE_ADB:-adb}}
    host=${REMOTE_SCRCPY_HOST:-}

    # Parse only completed words. No evaluation of SSH alias or shell text.
    for ((index=1; index<last; index++)); do
        word=${words[index]}
        [[ $word == -- ]] && return 0  # Everything after -- belongs to scrcpy.
        case $word in
            --host|--serial|--ssh-config|--adb|--remote-adb|--adb-port|--color|--completion)
                value=${words[index+1]:-}
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
    # A positional host replaces REMOTE_SCRCPY_HOST, as it does in the
    # launcher's parser; only --host takes the first positional's place.
    if (( ! explicit_host && ${#positions[@]} )); then host=${positions[0]}; fi

    case $previous in
        --host) complete_host=1 ;;
        --serial) complete_serial=1 ;;
        --color) COMPREPLY=( $(compgen -W 'auto always never' -- "$current") ); return ;;
        --completion) COMPREPLY=( $(compgen -W bash -- "$current") ); return ;;
        --ssh-config|--adb|--remote-adb)
            COMPREPLY=( $(compgen -f -- "$current") ); return ;;
        --adb-port) return ;;
    esac

    # `--host=...`, `--serial=...` and `--color=...`: complete the value and
    # keep the option in front of each candidate.
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
        # Same rule as the launcher's parser: the first positional is the SSH
        # host unless --host supplied one. REMOTE_SCRCPY_HOST does not change
        # what a position means; it only fills in a host that was not given.
        if (( explicit_host || ${#positions[@]} )); then
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

# Entry point used by Bash's programmable completion system.
# Bash hands a completion function the line already split at the characters in
# COMP_WORDBREAKS, which by default include '=', '@' and ':'. `--serial=D`
# arrives as `--serial`, `=`, `D`, and `myuser@192.0.2.10` as three words too.
# Read piecewise, a serial, a port or a user name would be taken for the host
# and contacted. So the pieces are joined back into the words that were typed
# before they are interpreted, and each candidate is then cut down to what
# Bash replaces: the text after the last '=' or ':', or from the last '@' on,
# since Bash keeps a leading '@' in the text it replaces.
#
# COMP_WORDS does not say whether two pieces were adjacent. A word that begins
# with one of these characters (the host `::1`), or one typed apart from its
# neighbours (`--host = z`), is therefore joined to the word before it.
_complete-remote-scrcpy() {
    local -a words=()
    local word index glue=0 current char
    COMPREPLY=()
    for ((index = 0; index <= COMP_CWORD; index++)); do
        word=${COMP_WORDS[index]:-}
        # A piece made only of break characters belongs to the word before it,
        # and so does the piece that follows.
        if (( index > 0 )) && { (( glue )) || [[ $word =~ ^[=@:]+$ ]]; }; then
            words[${#words[@]}-1]+=$word
        else
            words+=("$word")
        fi
        if [[ $word =~ ^[=@:]+$ ]]; then glue=1; else glue=0; fi
    done
    _remote-scrcpy-complete-words "${words[@]}"
    (( ${#COMPREPLY[@]} )) || return 0
    # Only characters still in COMP_WORDBREAKS split words; where one was
    # removed, Bash replaces the whole word and the candidate stays whole.
    current=${words[${#words[@]}-1]}
    for ((index = ${#current} - 1; index >= 0; index--)); do
        char=${current:index:1}
        if [[ $char == [=@:] && ${COMP_WORDBREAKS-} == *"$char"* ]]; then
            [[ $char == @ ]] || ((index += 1))
            COMPREPLY=("${COMPREPLY[@]#"${current:0:index}"}")
            break
        fi
    done
}
complete -F _complete-remote-scrcpy remote-scrcpy remote-scrcpy.sh
COMPLETION
}
