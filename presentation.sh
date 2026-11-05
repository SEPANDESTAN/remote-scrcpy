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
