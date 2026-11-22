#!/usr/bin/env bash
# Verify install.sh in a sandbox: a scratch HOME, a PATH of chosen tools and a
# fake curl. No network, and nothing outside the sandbox is written.
set -euo pipefail
# The suite must never see the developer's own launcher configuration: with a
# host exported, an inherited environment once made a check contact it.
unset "${!REMOTE_SCRCPY_@}" ADB REMOTE_ADB ADB_PORT SCRCPY NO_COLOR
# No child may inherit the caller's standard input. Bash started with -c in a
# cleared environment and with a socket there (an agent's tool, a remote
# command) takes itself for a remote shell and reads /etc/bashrc and
# ~/.bashrc. Under the bare PATH used below, a command-not-found handler
# defined there called a missing command from inside itself and forked
# without end.
exec < /dev/null
project=$(cd -- "$(dirname -- "$0")/.." && pwd)
installer=$project/install.sh
bundle=$project/remote-scrcpy.sh
passed=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
check() { "$@" || fail "$*"; passed=$((passed+1)); }
contains() { [[ $1 == *"$2"* ]]; }
lacks() { [[ $1 != *"$2"* ]]; }
equals() { [[ $1 == "$2" ]]; }

sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
home=$sandbox/home
bin=$sandbox/bin            # what the installer itself needs, and the fake curl
tools=$sandbox/tools        # stand-ins for ssh, adb and scrcpy
mkdir "$home" "$bin" "$tools" "$sandbox/work"
real_bash=$(command -v bash)
for tool in bash mkdir mktemp chmod mv rm cp grep; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
done
for tool in ssh adb scrcpy; do
    printf '#!%s\nexit 0\n' "$real_bash" > "$tools/$tool"
    chmod +x "$tools/$tool"
done
# The fake curl records its arguments and writes what the file `curl-serves`
# names to the -o target: the bundle, a script that stops parsing after its
# first command, a script that is not the launcher, or nothing with curl's
# status for an HTTP error.
cat > "$bin/curl" <<CURL
#!$real_bash
printf '%s\n' "\$*" >> '$sandbox/curl.log'
while (( \$# )); do [[ \$1 == -o ]] && output=\$2; shift; done
case \$(< '$sandbox/curl-serves') in
    bundle) cp '$bundle' "\$output" ;;
    garbage) printf ': > %s\nif then\n' '$sandbox/garbage-ran' > "\$output" ;;
    stranger) printf 'echo hello\n' > "\$output" ;;
    *) exit 22 ;;
esac
CURL
chmod +x "$bin/curl"
printf 'bundle\n' > "$sandbox/curl-serves"

# Run the installer with nothing inherited. The first argument is the PATH;
# output and status land in `output` and `result`.
run() {
    local path=$1; shift
    result=0
    output=$(cd "$sandbox/work" && env -i HOME="$home" PATH="$path" "$real_bash" "$@" 2>&1 < /dev/null) || result=$?
}
# The same for an installer that arrives on standard input, as from curl.
run-piped() {
    local path=$1; shift
    result=0
    output=$(cd "$sandbox/work" && env -i HOME="$home" PATH="$path" "$real_bash" -s -- "$@" 2>&1 < "$installer") || result=$?
}
version=$("$real_bash" "$bundle" --version)
main_url=https://raw.githubusercontent.com/SEPANDESTAN/remote-scrcpy/main/remote-scrcpy.sh

# --help explains the script and does nothing else.
run "$bin" "$installer" --help
check equals "$result" 0
check contains "$output" 'Usage: install.sh [--dir DIR] [--ref REF] [--completion]'
# What it cannot use is refused with status 2 before anything is written.
for arguments in '--bogus' 'extra' '--dir' '--dir=' '--ref' '--ref=a b' '--ref=../main' '--ref=-x' '--ref=a..b'; do
    read -r -a words <<< "$arguments"
    [[ $arguments != '--ref=a b' ]] || words=('--ref=a b')
    run "$bin" "$installer" "${words[@]}"
    equals "$result" 2 || fail "status $result instead of 2 for: $arguments"
done
passed=$((passed+1))
check equals "$(ls -A "$home" "$sandbox/work")" "$home:

$sandbox/work:"
[[ ! -e $sandbox/curl.log ]] || fail 'a usage error reached curl'

# From a checkout: the bundle next to the installer, no network, no ~/.bashrc.
run "$bin" "$installer"
check equals "$result" 0
check cmp -s "$bundle" "$home/.local/bin/remote-scrcpy"
check test -x "$home/.local/bin/remote-scrcpy"
check equals "$(ls -A "$home/.local/bin")" 'remote-scrcpy'
check test ! -e "$sandbox/curl.log"
check test ! -e "$home/.bashrc"
check contains "$output" "Installed $version as $home/.local/bin/remote-scrcpy"
# It says what is still missing: the directory on PATH, the three programs,
# and how to get completion.
check contains "$output" "Note: $home/.local/bin is not on PATH."
check contains "$output" 'Note: not found on PATH: ssh adb scrcpy.'
check contains "$output" '  source <(remote-scrcpy --completion bash)'
# With everything in place it says none of that.
run "$bin:$tools:$home/.local/bin" "$installer"
check equals "$result" 0
check lacks "$output" 'Note:'

# --dir, also relative and with a space; an existing file is replaced, and
# only the launcher is left in the directory.
mkdir -p "$sandbox/work/my bin"
printf 'old\n' > "$sandbox/work/my bin/remote-scrcpy"
run "$bin" "$installer" --dir 'my bin'
check equals "$result" 0
check contains "$output" "Installed $version as $sandbox/work/my bin/remote-scrcpy"
check cmp -s "$bundle" "$sandbox/work/my bin/remote-scrcpy"
check equals "$(ls -A "$sandbox/work/my bin")" 'remote-scrcpy'
run "$bin" "$installer" "--dir=$sandbox/other"
check cmp -s "$bundle" "$sandbox/other/remote-scrcpy"
# A directory of that name is not overwritten.
mkdir -p "$sandbox/blocked/remote-scrcpy"
run "$bin" "$installer" --dir "$sandbox/blocked"
check equals "$result" 1
check equals "$(ls -A "$sandbox/blocked")" 'remote-scrcpy'

# --completion adds one marked line to ~/.bashrc, keeps what is there, and
# does not add it twice.
printf 'export EXISTING=1' > "$home/.bashrc"
run "$bin" "$installer" --completion
check equals "$result" 0
check contains "$output" 'Added Tab completion to ~/.bashrc'
check equals "$(grep -c 'added by install.sh' "$home/.bashrc")" 1
check equals "$(sed -n 1p "$home/.bashrc")" 'export EXISTING=1'
run "$bin" "$installer" --completion
check contains "$output" 'Tab completion is already set up'
check equals "$(grep -c 'remote-scrcpy --completion bash' "$home/.bashrc")" 1
# The line registers the completion when the launcher is on PATH and is
# silent when it is not. --norc and the sandbox HOME keep the shell that
# tries it away from the real startup files whatever its standard input is.
# shellcheck disable=SC2016  # scripts for the shell under test; they must expand there
printf 'source "$HOME/.bashrc" && complete -p remote-scrcpy\n' > "$sandbox/try-registered.sh"
# shellcheck disable=SC2016
printf 'source "$HOME/.bashrc"; echo "status $?"\n' > "$sandbox/try-silent.sh"
check equals "$(env -i HOME="$home" PATH="$bin:$home/.local/bin" "$real_bash" --norc "$sandbox/try-registered.sh" 2>&1 < /dev/null)" \
    'complete -F _complete-remote-scrcpy remote-scrcpy'
check equals "$(env -i HOME="$home" PATH="$bin" "$real_bash" --norc "$sandbox/try-silent.sh" 2>&1 < /dev/null)" 'status 0'
# A home without a ~/.bashrc gets one that holds just that line.
home=$sandbox/fresh-home
mkdir "$home"
run "$bin" "$installer" --completion
check equals "$(grep -c '' "$home/.bashrc")" 1
check contains "$(< "$home/.bashrc")" 'source <(remote-scrcpy --completion bash); fi  # remote-scrcpy completion (added by install.sh)'
home=$sandbox/home

# Read from a pipe there is no checkout: it downloads the main branch.
run-piped "$bin" --dir "$sandbox/piped"
check equals "$result" 0
check cmp -s "$bundle" "$sandbox/piped/remote-scrcpy"
check contains "$(< "$sandbox/curl.log")" "$main_url"
# A file named remote-scrcpy.sh where the pipe is run is not taken for one.
cp "$bundle" "$sandbox/work/remote-scrcpy.sh"
: > "$sandbox/curl.log"
run-piped "$bin" --dir "$sandbox/piped"
check contains "$(< "$sandbox/curl.log")" "$main_url"
# So does a copy of the installer that has no bundle next to it.
mkdir "$sandbox/lone"
cp "$installer" "$sandbox/lone/install.sh"
: > "$sandbox/curl.log"
run "$bin" "$sandbox/lone/install.sh" --dir "$sandbox/lone/bin"
check contains "$(< "$sandbox/curl.log")" "$main_url"
check cmp -s "$bundle" "$sandbox/lone/bin/remote-scrcpy"
# --ref names the version and downloads even from a checkout.
: > "$sandbox/curl.log"
run "$bin" "$installer" --ref v3.0.2 --dir "$sandbox/piped"
check equals "$result" 0
check contains "$(< "$sandbox/curl.log")" 'https://raw.githubusercontent.com/SEPANDESTAN/remote-scrcpy/v3.0.2/remote-scrcpy.sh'

# A download that fails, is not Bash, or is not the launcher installs
# nothing: the existing launcher stays and no temporary file is left.
printf 'old\n' > "$sandbox/piped/remote-scrcpy"
for served in missing garbage stranger; do
    printf '%s\n' "$served" > "$sandbox/curl-serves"
    run-piped "$bin" --dir "$sandbox/piped"
    equals "$result" 1 || fail "status $result instead of 1 for a download that is $served"
    equals "$(< "$sandbox/piped/remote-scrcpy")" 'old' || fail "a download that is $served replaced the launcher"
    equals "$(ls -A "$sandbox/piped")" 'remote-scrcpy' || fail "a download that is $served left a file behind"
    passed=$((passed+1))
done
# A file that does not parse is not run at all, not even its first lines.
check test ! -e "$sandbox/garbage-ran"
# Without curl it says so with the status for a missing program.
rm "$bin/curl"
run-piped "$bin" --dir "$sandbox/piped"
check equals "$result" 127
check contains "$output" 'curl is needed'
check equals "$(ls -A "$sandbox/piped")" 'remote-scrcpy'

printf 'Install checks: %d passed.\n' "$passed"
