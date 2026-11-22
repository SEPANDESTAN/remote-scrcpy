#!/usr/bin/env bash
# Verify both local SSH-alias and live remote device completion without network.
set -euo pipefail
# The suite must never see the developer's own launcher configuration: with a
# host exported, an inherited environment once made a check contact it.
unset "${!REMOTE_SCRCPY_@}" ADB REMOTE_ADB ADB_PORT SCRCPY NO_COLOR
# Nor may any child inherit the caller's standard input: docs/testing.md,
# "Environment", has the reason. Not dead code; the maintenance suite checks it.
exec < /dev/null
project=$(cd -- "$(dirname -- "$0")/.." && pwd)
script=$project/remote-scrcpy.sh
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
mkdir "$sandbox/bin"
cat > "$sandbox/config" <<'CONFIG'
Host remote-host
Host remote-backup beta
CONFIG
cat > "$sandbox/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SSH_COMPLETION_CALLS"
# A real ssh reads its standard input and forwards it; record what this one
# could have taken.
if IFS= read -r -t 1 taken; then printf '%s\n' "$taken" >> "$SSH_COMPLETION_STDIN"; fi
cat <<'DEVICES'
List of devices attached
DEVICE1234567890 device product:test model:Test_Phone_A
OFFLINE offline
Z99999 device product:other model:Another
UNAUTH unauthorized
192.0.2.10:5555 device product:test model:Network_Phone
DEVICES
SSH
chmod +x "$sandbox/bin/ssh"
# Keep timeout out of PATH intentionally: SSH options should still bound connects.
# Where available, GNU timeout is allowed, and delegates to our fake ssh.
export PATH="$sandbox/bin:$PATH"
export SSH_COMPLETION_CALLS="$sandbox/calls"
export SSH_COMPLETION_STDIN="$sandbox/stdin"
export REMOTE_SCRCPY_SSH_CONFIG="$sandbox/config"
source <("$script" --completion bash) || { printf 'FAIL sourcing the completion script ended with status %s\n' "$?" >&2; exit 1; }
passed=0
assert_eq() {
    local label=$1 expected=$2 actual=$3
    [[ $expected == "$actual" ]] || { printf 'FAIL %s expected %q actual %q\n' "$label" "$expected" "$actual" >&2; exit 1; }
    ((passed+=1))
}
# Hand the function the command line the way an interactive Bash does: split
# at the COMP_WORDBREAKS characters '=', '@' and ':' as well as at spaces.
# Observed with Bash 5.3: `--serial=D` arrives as `--serial`, `=`, `D`, and
# `--serial=` leaves COMP_CWORD on the `=`. Whole words are a shape a shell
# never delivers for such input, and checks built on them proved nothing.
default_wordbreaks=$' \t\n"\'@><=;|&(:'
complete_words() {
    local word
    COMP_WORDBREAKS=$default_wordbreaks
    COMP_WORDS=("$script")
    for word in "$@"; do
        [[ -n $word ]] || COMP_WORDS+=('')
        while [[ $word =~ ^([^=@:]+|[=@:]+)(.*)$ ]]; do
            COMP_WORDS+=("${BASH_REMATCH[1]}"); word=${BASH_REMATCH[2]}
        done
    done
    COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
    COMPREPLY=()
    calls_before=$(ssh_calls)
    _complete-remote-scrcpy || { printf 'FAIL the completion function ended with status %s for: %s\n' "$?" "$*" >&2; exit 1; }
}
ssh_calls() { wc -l < "$SSH_COMPLETION_CALLS"; }
# The host the last complete_words asked ssh for. A lookup left over from an
# earlier check does not count.
queried_host() {
    if (( $(ssh_calls) == calls_before )); then printf '(no lookup)'; return; fi
    tail -1 "$SSH_COMPLETION_CALLS" | sed -E 's/.* -- ([^ ]+) .*/\1/'
}
: > "$SSH_COMPLETION_CALLS"

complete_words r
assert_eq 'SSH aliases' 'remote-host remote-backup' "${COMPREPLY[*]}"
assert_eq 'host completion stays local' '0' "$(ssh_calls)"
complete_words remote-host D
assert_eq 'serial positional' 'DEVICE1234567890' "${COMPREPLY[*]}"
# Keys typed while a lookup runs stay with the shell: ssh gets no input.
: > "$SSH_COMPLETION_STDIN"
complete_words remote-host D <<< 'typed ahead'
assert_eq 'a lookup reads nothing from the terminal' '' "$(< "$SSH_COMPLETION_STDIN")"
complete_words --host remote-host D
assert_eq 'serial after named host' 'DEVICE1234567890' "${COMPREPLY[*]}"
complete_words --host remote-host --serial Z
assert_eq 'serial with flag' 'Z99999' "${COMPREPLY[*]}"

# Bash replaces only the text after the last break character, so a candidate
# for `--host=remote-h` is the host alone.
complete_words --host=remote-h
assert_eq 'host equals' 'remote-host' "${COMPREPLY[*]}"
complete_words remote-host --serial=D
assert_eq 'serial equals' 'DEVICE1234567890' "${COMPREPLY[*]}"
complete_words remote-host --serial=
assert_eq 'serial equals, nothing typed' 'DEVICE1234567890 Z99999 192.0.2.10:5555' "${COMPREPLY[*]}"
complete_words --color=a
assert_eq 'color equals' 'auto always' "${COMPREPLY[*]}"
complete_words --completion=
assert_eq 'completion equals' 'bash' "${COMPREPLY[*]}"
complete_words --list
assert_eq 'only the documented listing options are offered' '--list-hosts --list-devices' "${COMPREPLY[*]}"
# A word that starts with one dash offers the options, short and long, and
# is never taken for a host or serial to look up.
all_options='--help --version --host --serial --list-hosts --list-devices --ssh-config --adb --remote-adb --adb-port --color --ascii --non-interactive --quiet --verbose --prerequisites --completion -h -v -l -L -p -q -n -V'
complete_words -
assert_eq 'a single dash offers every option' "$all_options" "${COMPREPLY[*]}"
complete_words -l
assert_eq 'a short option completes to itself' '-l' "${COMPREPLY[*]}"
complete_words remote-host -
assert_eq 'a dash after a host offers the options' "$all_options" "${COMPREPLY[*]}"
assert_eq 'a dash after a host starts no lookup' '(no lookup)' "$(queried_host)"
# A short option before the host is not counted as the host.
complete_words -l remote-host D
assert_eq 'a short option does not shift the positions' 'remote-host' "$(queried_host)"
complete_words remote-host 192.0.2.10:5
assert_eq 'serial with a colon' '5555' "${COMPREPLY[*]}"
# With two break characters in the word, the cut is at the last one.
complete_words remote-host --serial=192.0.2.10:5
assert_eq 'serial with a colon after --serial=' '5555' "${COMPREPLY[*]}"
# Bash keeps a leading '@' in the text it replaces, so the candidate keeps it.
mkdir "$sandbox/at@home"; : > "$sandbox/at@home/config-file"
complete_words --ssh-config "$sandbox/at@home/con"
assert_eq 'file name behind an @' '@home/config-file' "${COMPREPLY[*]}"

# Pieces of one word must not be read as separate arguments: a serial, a port
# or a user name would otherwise be taken for the host and contacted.
complete_words myuser@remote-host D
assert_eq 'user@host is one word' 'DEVICE1234567890' "${COMPREPLY[*]}"
assert_eq 'user@host is the host queried' 'myuser@remote-host' "$(queried_host)"
complete_words --adb-port=5038 remote-host D
assert_eq 'an option value is not the host' 'remote-host' "$(queried_host)"
count=$(ssh_calls)
complete_words --serial=DEVICE1234567890 r
assert_eq 'a serial given with = leaves the host position free' 'remote-host remote-backup' "${COMPREPLY[*]}"
assert_eq 'a serial given with = is never contacted' "$count" "$(ssh_calls)"

# Where '=' was removed from COMP_WORDBREAKS the word arrives whole and Bash
# replaces it whole, so the candidate keeps the option.
COMP_WORDBREAKS=$' \t\n'; COMP_WORDS=("$script" --host=remote-h); COMP_CWORD=1; COMPREPLY=()
_complete-remote-scrcpy || { printf 'FAIL the completion function ended with status %s for: --host=remote-h\n' "$?" >&2; exit 1; }
assert_eq 'host equals when = does not break words' '--host=remote-host' "${COMPREPLY[*]}"

count=$(ssh_calls)
REMOTE_SCRCPY_COMPLETE_DEVICES=0
complete_words remote-host D
assert_eq 'disabled network serial' '' "${COMPREPLY[*]}"
assert_eq 'disabled network query count' "$count" "$(ssh_calls)"
unset REMOTE_SCRCPY_COMPLETE_DEVICES

# With REMOTE_SCRCPY_HOST set, positions keep the meaning the launcher's parser
# gives them: the first positional is still the host, and it replaces the
# environment host for the device query. Only --serial and --host change that.
export REMOTE_SCRCPY_HOST=remote-backup
count=$(ssh_calls)
complete_words r
assert_eq 'environment host: first positional completes hosts' 'remote-host remote-backup' "${COMPREPLY[*]}"
assert_eq 'environment host: host completion stays local' "$count" "$(ssh_calls)"
complete_words remote-host D
assert_eq 'environment host: serial after a positional host' 'DEVICE1234567890' "${COMPREPLY[*]}"
assert_eq 'environment host: positional host is the one queried' 'remote-host' "$(queried_host)"
complete_words --serial D
assert_eq 'environment host: --serial completes without a positional' 'DEVICE1234567890' "${COMPREPLY[*]}"
assert_eq 'environment host: --serial queries the environment host' 'remote-backup' "$(queried_host)"
complete_words --serial=D
assert_eq 'environment host: --serial= completes without a positional' 'DEVICE1234567890' "${COMPREPLY[*]}"
assert_eq 'environment host: --serial= queries the environment host' 'remote-backup' "$(queried_host)"
complete_words --host remote-host D
assert_eq 'environment host: --host wins for the query' 'remote-host' "$(queried_host)"
complete_words --host remote-host X D
assert_eq 'environment host: a positional never replaces --host' 'remote-host' "$(queried_host)"
complete_words --host=remote-host D
assert_eq 'environment host: --host= wins for the query' 'remote-host' "$(queried_host)"
unset REMOTE_SCRCPY_HOST
printf 'Completion checks: %d passed.\n' "$passed"
