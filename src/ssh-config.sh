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
            if [[ -z $ssh_user_home && $value != /* ]]; then
                # ~ and relative Includes are resolved against the home
                # directory; without one they would point at the root.
                printf 'Skipping SSH Include that needs a home directory in %s: %s\n' "$file" "$value" >&2
                continue
            fi
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
    local config=${1:-${HOME:+$HOME/.ssh/config}}
    local ssh_user_home=${2:-${HOME:-}}
    local ssh_directory=$ssh_user_home/.ssh
    local -a visited=()
    export LC_ALL=C
    unset GLOBIGNORE
    set +f
    shopt -s nullglob
    shopt -u failglob dotglob nocaseglob extglob
    _visit-ssh-configuration-file "$config" 0 | awk '!seen[$0]++'
)
