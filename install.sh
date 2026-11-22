#!/usr/bin/env bash
# Install remote-scrcpy: put the single-file launcher into a directory on PATH.
#
#   curl -fsSL https://raw.githubusercontent.com/SEPANDESTAN/remote-scrcpy/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/SEPANDESTAN/remote-scrcpy/main/install.sh | bash -s -- --completion
#   bash install.sh --dir ~/bin      # in a checkout: installs its own bundle, no network
#
# It writes one file and, when asked, one line in ~/.bashrc. It never uses
# sudo and never installs ssh, adb or scrcpy. All work happens in main, which
# is called from a brace group on the last line: cut short at any byte, that
# line is an unfinished command, so a partial download installs nothing.
set -euo pipefail

INSTALL_TEMPORARY_FILE=''

# Print the usage text to stdout.
usage() {
    printf '%s\n' \
        'Usage: install.sh [--dir DIR] [--ref REF] [--completion]' \
        '' \
        'Install remote-scrcpy, a single Bash file, as DIR/remote-scrcpy.' \
        '' \
        '  --dir DIR      where to install (default: ~/.local/bin)' \
        '  --ref REF      branch or tag to download (default: main)' \
        '  --completion   also add Bash completion to ~/.bashrc: one marked' \
        '                 line, added once' \
        '  -h, --help     show this help' \
        '' \
        'Run as a file in a checkout and without --ref, it installs the' \
        "checkout's own remote-scrcpy.sh and uses no network. Otherwise it" \
        'downloads that file with curl. It never uses sudo and installs nothing' \
        'else: ssh, adb and scrcpy are yours to provide, see' \
        'remote-scrcpy --prerequisites.'
}

# Print a message to stderr.
say() { printf '%s\n' "$*" >&2; }

# Print an error and exit. Args: message, optional status (default 1).
die() { say "install.sh: $1"; exit "${2:-1}"; }

# Install the launcher. Args: the path of this file ('' when it is read from
# a pipe), then the command line. Exits 2 for usage errors, 127 when curl is
# needed and missing, 1 when nothing could be installed.
main() {
    local self=$1; shift
    local dir='' ref='' completion=0 bundle='' target version tool missing='' line
    local url=https://raw.githubusercontent.com/SEPANDESTAN/remote-scrcpy
    local marker='# remote-scrcpy completion (added by install.sh)'
    while (( $# )); do
        case $1 in
            -h|--help) usage; return 0 ;;
            --completion) completion=1 ;;
            --dir|--ref)
                (( $# > 1 )) || die "$1 needs a value" 2
                set -- "$1=$2" "${@:3}"
                continue ;;
            --dir=?*) dir=${1#*=} ;;
            --ref=?*) ref=${1#*=} ;;
            *) say "install.sh: cannot use this argument: $1"; usage >&2; exit 2 ;;
        esac
        shift
    done
    if [[ -n $ref ]] && { [[ ! $ref =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || [[ $ref == *..* ]]; }; then
        die "not a branch or tag name: $ref" 2
    fi
    # The shell expands ~ in "--dir ~/bin" but not in "--dir=~/bin".
    # shellcheck disable=SC2088  # a literal ~ is what is being matched
    case $dir in
        '~'|'~/'*)
            [[ -n ${HOME:-} ]] || die 'HOME is not set, so ~ in --dir has no meaning' 2
            dir=$HOME${dir#'~'} ;;
    esac
    if [[ -z $dir ]]; then
        [[ -n ${HOME:-} ]] || die 'HOME is not set; say where to install with --dir DIR' 2
        dir=$HOME/.local/bin
    fi
    if (( completion )) && [[ -z ${HOME:-} ]]; then
        die 'HOME is not set, so there is no ~/.bashrc for --completion' 2
    fi

    # A checkout carries the bundle next to this file. A --ref asks for a
    # particular version, so it always downloads.
    if [[ -z $ref && -n $self ]]; then
        bundle=./remote-scrcpy.sh
        [[ $self != */* ]] || bundle=${self%/*}/remote-scrcpy.sh
        [[ -f $bundle ]] || bundle=''
    fi
    url=$url/${ref:-main}/remote-scrcpy.sh

    mkdir -p -- "$dir" && dir=$(cd -- "$dir" && pwd) || die "cannot use the directory $dir"
    target=$dir/remote-scrcpy
    [[ ! -d $target ]] || die "$target is a directory"
    # The new file is checked next to its destination and then renamed over
    # it, so a failed install leaves an existing launcher as it was.
    INSTALL_TEMPORARY_FILE=$(mktemp "$dir/.remote-scrcpy.XXXXXX") || die "cannot write to $dir"
    trap 'rm -f -- "$INSTALL_TEMPORARY_FILE"' EXIT
    if [[ -n $bundle ]]; then
        cp -- "$bundle" "$INSTALL_TEMPORARY_FILE" || die "cannot copy $bundle"
    else
        command -v curl > /dev/null 2>&1 || die 'curl is needed to download remote-scrcpy' 127
        curl -fsSL -o "$INSTALL_TEMPORARY_FILE" "$url" || die "download failed: $url"
    fi
    bash -n "$INSTALL_TEMPORARY_FILE" 2> /dev/null && version=$(bash "$INSTALL_TEMPORARY_FILE" --version) \
        && [[ $version == 'remote-scrcpy '* ]] \
        || die "${bundle:-$url} did not run as remote-scrcpy; nothing was installed"
    chmod 755 "$INSTALL_TEMPORARY_FILE" && mv -f -- "$INSTALL_TEMPORARY_FILE" "$target" \
        || die "cannot write $target"
    say "Installed $version as $target"

    case ":${PATH:-}:" in
        *":$dir:"*) ;;
        *) say "Note: $dir is not on PATH. Add it in ~/.bashrc: export PATH=\"$dir:\$PATH\"" ;;
    esac
    for tool in ssh adb scrcpy; do
        command -v "$tool" > /dev/null 2>&1 || missing+=" $tool"
    done
    [[ -z $missing ]] || say "Note: not found on PATH:$missing. See: remote-scrcpy --prerequisites"

    # The line names the installed file, not the command: a login shell may
    # read ~/.bashrc before the directory is put on PATH.
    line=$(printf '%q' "$target")
    line="if [[ -x $line ]]; then source <($line --completion bash); fi  $marker"
    if (( ! completion )); then
        say 'For Tab completion, run this installer with --completion, or add to ~/.bashrc:'
        say '  source <(remote-scrcpy --completion bash)'
    elif grep -Fqsx -- "$line" "$HOME/.bashrc"; then
        say 'Tab completion is already set up in ~/.bashrc.'
    elif grep -Fqs -e "$marker" -e 'remote-scrcpy --completion bash' "$HOME/.bashrc"; then
        # shellcheck disable=SC2088  # message text
        say '~/.bashrc already loads a remote-scrcpy completion that was not written for'
        say 'this location; it was left unchanged. To load it from here, replace it with:'
        say "  $line"
    else
        # On a line of its own, whatever the file ends with.
        {
            [[ ! -s $HOME/.bashrc ]] || printf '\n'
            printf '%s\n' "$line"
        } >> "$HOME/.bashrc" || die 'cannot write ~/.bashrc'
        say 'Added Tab completion to ~/.bashrc; it applies to new shells.'
    fi
}

{ main "${BASH_SOURCE[0]:-}" "$@"; }
