#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# lib/tui.sh
#
# Единственный низкоуровневый TTY/TUI-модуль.
#
# Ответственность:
#   • /dev/tty
#   • terminal state
#   • stty
#   • alternate screen
#   • cursor
#   • colors
#   • Unicode / ASCII
#   • keyboard events
#   • screen
#   • drawing
#   • dialogs
#   • text input
#   • menus
#   • progress
#
# Не содержит:
#   • installer logic
#   • CONFIG business logic
#   • partition logic
#   • filesystem logic
#   • package logic
#
# Требования:
#   • Bash 4+
#   • /dev/tty
#   • stty
#   • tput
#
#============================================================

if [[ -n "${TUI_SH_LOADED:-}" ]]
then
    return 0
fi

readonly TUI_SH_LOADED=1

#============================================================
# Event constants
#============================================================

readonly EVENT_NONE="NONE"

readonly EVENT_UP="UP"
readonly EVENT_DOWN="DOWN"
readonly EVENT_LEFT="LEFT"
readonly EVENT_RIGHT="RIGHT"

readonly EVENT_SELECT="SELECT"
readonly EVENT_BACK="BACK"

readonly EVENT_HOME="HOME"
readonly EVENT_END="END"

readonly EVENT_PAGE_UP="PAGE_UP"
readonly EVENT_PAGE_DOWN="PAGE_DOWN"

readonly EVENT_SPACE="SPACE"
readonly EVENT_TAB="TAB"
readonly EVENT_TAB_BACK="TAB_BACK"

readonly EVENT_DELETE="DELETE"

readonly EVENT_F1="F1"
readonly EVENT_F2="F2"
readonly EVENT_F3="F3"
readonly EVENT_F4="F4"
readonly EVENT_F5="F5"
readonly EVENT_F6="F6"
readonly EVENT_F7="F7"
readonly EVENT_F8="F8"
readonly EVENT_F9="F9"
readonly EVENT_F10="F10"
readonly EVENT_F11="F11"
readonly EVENT_F12="F12"

readonly EVENT_HELP="HELP"
readonly EVENT_CHAR="CHAR"

#
# Timeout used while reading an escape sequence.
#
# 0.15 sec is safer than 0.08 sec for:
#   • virtual consoles
#   • VMs
#   • slow terminals
#   • remote consoles
#
readonly TUI_ESCAPE_TIMEOUT="0.15"

#============================================================
# Terminal
#============================================================

TUI_TTY="${TUI_TTY:-/dev/tty}"

#
# File descriptor opened by tui_open_terminal().
#
TUI_FD=-1

#============================================================
# State
#============================================================

TUI_INITIALIZED=0
TUI_ACTIVE=0

TUI_STTY_SAVED=0
TUI_STTY_STATE=""

TUI_ALT_SCREEN=0
TUI_CURSOR_HIDDEN=0

TUI_ROWS=0
TUI_COLS=0

TUI_CURSOR_ROW=1
TUI_CURSOR_COL=1

TUI_COLOR_ENABLED=1
TUI_UNICODE_ENABLED=1

TUI_EVENT="$EVENT_NONE"
TUI_EVENT_CHAR=""

TUI_INPUT_RESULT=""

TUI_MENU_RESULT=""
TUI_MENU_VALUE=""

TUI_PROGRESS_ACTIVE=0
TUI_PROGRESS_PERCENT=0
TUI_PROGRESS_ROW=1
TUI_PROGRESS_COL=1
TUI_PROGRESS_WIDTH=40
TUI_PROGRESS_TITLE=""

#============================================================
# Internal logging
#============================================================

tui_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@"
    else
        printf 'TUI ERROR: %s\n' "$*" >&2
    fi
}

tui_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@"
    else
        printf 'TUI WARN: %s\n' "$*" >&2
    fi
}

tui_log_debug()
{
    if declare -F logger_debug >/dev/null 2>&1
    then
        logger_debug "$@"
    fi
}

tui_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@"
    fi
}

#============================================================
# Internal terminal FD
#============================================================

tui_open_terminal()
{
    #
    # Already open.
    #
    if (( TUI_FD >= 0 ))
    then
        return 0
    fi

    #
    # /dev/tty must exist.
    #
    if [[ ! -e "$TUI_TTY" ]]
    then
        tui_log_error \
            "TUI: terminal device not found: $TUI_TTY"

        return 1
    fi

    #
    # Open terminal read/write.
    #
    #
    # Bash supports dynamic file descriptors:
    #
    #   exec {fd}<>/dev/tty
    #
    if ! exec {TUI_FD}<>"$TUI_TTY"
    then
        tui_log_error \
            "TUI: cannot open terminal: $TUI_TTY"

        TUI_FD=-1

        return 1
    fi

    #
    # Verify that the descriptor really behaves as a tty.
    #
    if ! tty <&"$TUI_FD" >/dev/null 2>&1
    then
        tui_log_error \
            "TUI: terminal descriptor is not a TTY"

        exec {TUI_FD}>&- 2>/dev/null || true

        TUI_FD=-1

        return 1
    fi

    return 0
}

tui_close_terminal()
{
    if (( TUI_FD >= 0 ))
    then
        exec {TUI_FD}>&- 2>/dev/null || true
        TUI_FD=-1
    fi

    return 0
}

tui_require_tty()
{
    tui_open_terminal || return 1

    if (( TUI_FD < 0 ))
    then
        tui_log_error \
            "TUI: invalid terminal descriptor"

        return 1
    fi

    return 0
}

#============================================================
# Internal output
#============================================================

tui_print()
{
    if (( TUI_FD < 0 ))
    then
        tui_log_error \
            "TUI: output attempted with invalid terminal FD"

        return 1
    fi

    printf '%s' "${1-}" >&"$TUI_FD"
}

tui_printf()
{
    local format="${1-}"

    shift || true

    if (( TUI_FD < 0 ))
    then
        tui_log_error \
            "TUI: formatted output attempted with invalid terminal FD"

        return 1
    fi

    printf "$format" "$@" >&"$TUI_FD"
}

tui_flush()
{
    #
    # Bash printf writes directly to the descriptor.
    #
    # This function intentionally remains an API no-op.
    #
    return 0
}

#============================================================
# Save terminal state
#============================================================

tui_save_terminal()
{
    if (( TUI_STTY_SAVED ))
    then
        return 0
    fi

    tui_require_tty || return 1

    if ! TUI_STTY_STATE="$(
        stty -g <&"$TUI_FD" 2>/dev/null
    )"
    then
        tui_log_error \
            "TUI: failed to save terminal state"

        return 1
    fi

    if [[ -z "$TUI_STTY_STATE" ]]
    then
        tui_log_error \
            "TUI: saved terminal state is empty"

        return 1
    fi

    TUI_STTY_SAVED=1

    tui_log_debug \
        "TUI: terminal state saved"

    return 0
}

#============================================================
# Restore terminal state
#============================================================

tui_restore_terminal()
{
    local rc=0

    if (( ! TUI_STTY_SAVED ))
    then
        return 0
    fi

    #
    # Reopen terminal if necessary.
    #
    if (( TUI_FD < 0 ))
    then
        if ! tui_open_terminal
        then
            tui_log_error \
                "TUI: cannot reopen terminal for restore"

            return 1
        fi
    fi

    #
    # First attempt: exact original state.
    #
    if stty "$TUI_STTY_STATE" <&"$TUI_FD" 2>/dev/null
    then
        tui_log_debug \
            "TUI: original terminal state restored"

        return 0
    fi

    #
    # Fallback.
    #
    tui_log_warn \
        "TUI: failed to restore saved terminal state"

    if stty sane <&"$TUI_FD" 2>/dev/null
    then
        tui_log_warn \
            "TUI: terminal restored using stty sane"
    else
        tui_log_error \
            "TUI: failed to restore terminal using stty sane"

        rc=1
    fi

    return "$rc"
}

#============================================================
# Terminal capabilities
#============================================================

tui_detect_capabilities()
{
    TUI_COLOR_ENABLED=1
    TUI_UNICODE_ENABLED=1

    #
    # NO_COLOR convention.
    #
    if [[ -n "${NO_COLOR:-}" ]]
    then
        TUI_COLOR_ENABLED=0
    fi

    #
    # Dumb terminal.
    #
    if [[ "${TERM:-}" == "dumb" ]]
    then
        TUI_COLOR_ENABLED=0
        TUI_UNICODE_ENABLED=0
    fi

    #
    # Verify color support.
    #
    if ! tput colors <&"$TUI_FD" >/dev/null 2>&1
    then
        TUI_COLOR_ENABLED=0
    fi

    #
    # C / POSIX locales do not guarantee UTF-8.
    #
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    in
        C|POSIX|C.*|POSIX.*)
            TUI_UNICODE_ENABLED=0
            ;;
    esac
}

#============================================================
# Screen size
#============================================================

tui_update_size()
{
    local rows=""
    local cols=""
    local size=""

    tui_require_tty || return 1

    #
    # Preferred method.
    #
    rows="$(
        tput lines <&"$TUI_FD" 2>/dev/null || true
    )"

    cols="$(
        tput cols <&"$TUI_FD" 2>/dev/null || true
    )"

    #
    # Validate.
    #
    if [[ ! "$rows" =~ ^[0-9]+$ ]]
    then
        rows=""
    fi

    if [[ ! "$cols" =~ ^[0-9]+$ ]]
    then
        cols=""
    fi

    #
    # Fallback.
    #
    if [[ -z "$rows" || -z "$cols" ]]
    then
        size="$(
            stty size <&"$TUI_FD" 2>/dev/null || true
        )"

        if [[ "$size" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]
        then
            rows="${BASH_REMATCH[1]}"
            cols="${BASH_REMATCH[2]}"
        fi
    fi

    #
    # Final validation.
    #
    if [[ ! "$rows" =~ ^[0-9]+$ ||
          ! "$cols" =~ ^[0-9]+$ ]]
    then
        tui_log_error \
            "TUI: cannot determine terminal size"

        TUI_ROWS=0
        TUI_COLS=0

        return 1
    fi

    if (( rows < 1 || cols < 1 ))
    then
        tui_log_error \
            "TUI: invalid terminal size: ${cols}x${rows}"

        TUI_ROWS=0
        TUI_COLS=0

        return 1
    fi

    TUI_ROWS="$rows"
    TUI_COLS="$cols"

    return 0
}

#============================================================
# Initialization
#============================================================

tui_init()
{
    if (( TUI_INITIALIZED ))
    then
        return 0
    fi

    tui_require_tty || return 1

    #
    # Save original terminal state BEFORE modifying it.
    #
    tui_save_terminal || return 1

    #
    # Get initial screen size.
    #
    if ! tui_update_size
    then
        tui_restore_terminal || true

        TUI_STTY_SAVED=0
        TUI_STTY_STATE=""

        return 1
    fi

    tui_detect_capabilities

    TUI_CURSOR_ROW=1
    TUI_CURSOR_COL=1

    TUI_EVENT="$EVENT_NONE"
    TUI_EVENT_CHAR=""

    TUI_INITIALIZED=1

    tui_log_info \
        "TUI initialized: ${TUI_COLS}x${TUI_ROWS}"

    return 0
}

#============================================================
# Activate TUI
#============================================================

tui_start()
{
    if (( TUI_ACTIVE ))
    then
        return 0
    fi

    if (( ! TUI_INITIALIZED ))
    then
        tui_init || return 1
    fi

    #
    # Refresh terminal dimensions.
    #
    tui_update_size || return 1

    #
    # Protect arithmetic expressions.
    #
    if ! [[ "$TUI_ROWS" =~ ^[0-9]+$ &&
            "$TUI_COLS" =~ ^[0-9]+$ ]]
    then
        tui_log_error \
            "TUI: invalid size variables"

        return 1
    fi

    #
    # Minimum usable size.
    #
    if (( TUI_ROWS < 20 || TUI_COLS < 70 ))
    then
        tui_log_error \
            "TUI: terminal too small: ${TUI_COLS}x${TUI_ROWS}; minimum 70x20"

        return 1
    fi

    #
    # Enter alternate screen.
    #
    if ! tui_print $'\033[?1049h'
    then
        tui_log_error \
            "TUI: failed to enter alternate screen"

        return 1
    fi

    TUI_ALT_SCREEN=1

    #
    # Clear alternate screen.
    #
    if ! tui_print $'\033[2J\033[H'
    then
        tui_abort_start
        return 1
    fi

    #
    # Hide cursor.
    #
    if ! tui_print $'\033[?25l'
    then
        tui_abort_start
        return 1
    fi

    TUI_CURSOR_HIDDEN=1

    #
    # Configure keyboard input.
    #
    #
    # Keep signals enabled but disable canonical input,
    # echo and XON/XOFF.
    #
    if ! stty \
        -echo \
        -echonl \
        -icanon \
        -ixon \
        min 1 \
        time 0 \
        <&"$TUI_FD"
    then
        tui_log_error \
            "TUI: failed to configure terminal input"

        tui_abort_start

        return 1
    fi

    TUI_ACTIVE=1

    TUI_CURSOR_ROW=1
    TUI_CURSOR_COL=1

    tui_log_debug \
        "TUI started"

    return 0
}

#============================================================
# Abort incomplete startup
#============================================================

tui_abort_start()
{
    #
    # Show cursor before leaving screen.
    #
    if (( TUI_CURSOR_HIDDEN ))
    then
        tui_print $'\033[?25h' 2>/dev/null || true
        TUI_CURSOR_HIDDEN=0
    fi

    #
    # Leave alternate screen.
    #
    if (( TUI_ALT_SCREEN ))
    then
        tui_print $'\033[?1049l' 2>/dev/null || true
        TUI_ALT_SCREEN=0
    fi

    #
    # Restore original terminal mode.
    #
    if (( TUI_STTY_SAVED ))
    then
        tui_restore_terminal || true
    fi

    TUI_ACTIVE=0

    return 0
}

#============================================================
# Restore TUI
#============================================================

tui_restore()
{
    local failed=0

    #
    # Make sure terminal descriptor exists if possible.
    #
    if (( TUI_FD < 0 )) &&
       (( TUI_STTY_SAVED || TUI_ALT_SCREEN || TUI_CURSOR_HIDDEN ))
    then
        tui_open_terminal || true
    fi

    #
    # Show cursor.
    #
    if (( TUI_CURSOR_HIDDEN ))
    then
        if ! tui_print $'\033[?25h' 2>/dev/null
        then
            failed=1
        fi

        TUI_CURSOR_HIDDEN=0
    fi

    #
    # Reset attributes.
    #
    tui_print $'\033[0m' 2>/dev/null || true

    #
    # Leave alternate screen.
    #
    if (( TUI_ALT_SCREEN ))
    then
        if ! tui_print $'\033[?1049l' 2>/dev/null
        then
            failed=1
        fi

        TUI_ALT_SCREEN=0
    fi

    #
    # Restore original stty state.
    #
    if (( TUI_STTY_SAVED ))
    then
        if ! tui_restore_terminal
        then
            failed=1
        fi
    fi

    #
    # Reset internal state.
    #
    TUI_ACTIVE=0
    TUI_INITIALIZED=0

    TUI_STTY_SAVED=0
    TUI_STTY_STATE=""

    TUI_CURSOR_ROW=1
    TUI_CURSOR_COL=1

    TUI_EVENT="$EVENT_NONE"
    TUI_EVENT_CHAR=""

    TUI_INPUT_RESULT=""

    TUI_MENU_RESULT=""
    TUI_MENU_VALUE=""

    TUI_PROGRESS_ACTIVE=0
    TUI_PROGRESS_PERCENT=0
    TUI_PROGRESS_ROW=1
    TUI_PROGRESS_COL=1
    TUI_PROGRESS_WIDTH=40
    TUI_PROGRESS_TITLE=""

    if (( failed ))
    then
        tui_log_error \
            "TUI restoration completed with errors"

        return 1
    fi

    tui_log_debug \
        "TUI restored"

    return 0
}

#============================================================
# Shutdown
#============================================================

tui_shutdown()
{
    local rc=0

    if ! tui_restore
    then
        rc=1
    fi

    tui_close_terminal

    return "$rc"
}

#============================================================
# Cursor
#============================================================

tui_move()
{
    local row="${1:-}"
    local col="${2:-}"

    if ! [[ "$row" =~ ^[0-9]+$ &&
            "$col" =~ ^[0-9]+$ ]]
    then
        tui_log_error \
            "TUI: invalid cursor position: ${row},${col}"

        return 1
    fi

    if (( row < 1 || col < 1 ))
    then
        return 1
    fi

    #
    # Coordinates beyond the current screen are allowed by the
    # low-level cursor primitive. Drawing functions are responsible
    # for their own geometry.
    #

    tui_printf \
        '\033[%d;%dH' \
        "$row" \
        "$col" || return 1

    TUI_CURSOR_ROW="$row"
    TUI_CURSOR_COL="$col"

    return 0
}

cursor_move()
{
    tui_move "$@"
}

tui_move_to()
{
    tui_move "$@"
}

tui_home()
{
    tui_move 1 1
}

tui_save_cursor()
{
    tui_print $'\033[s'
}

tui_restore_cursor()
{
    tui_print $'\033[u'
}

#============================================================
# Colors
#============================================================

tui_color()
{
    local code="${1:-}"
    local text="${2-}"

    if (( TUI_COLOR_ENABLED ))
    then
        tui_printf \
            '\033[%sm%s\033[0m' \
            "$code" \
            "$text"
    else
        tui_print "$text"
    fi
}

color_error()
{
    tui_color 91 "${1-}"
}

color_success()
{
    tui_color 92 "${1-}"
}

color_warning()
{
    tui_color 93 "${1-}"
}

color_info()
{
    tui_color 96 "${1-}"
}

color_title()
{
    if (( TUI_COLOR_ENABLED ))
    then
        tui_printf \
            '\033[1m%s\033[0m' \
            "${1-}"
    else
        tui_print "${1-}"
    fi
}

color_selected()
{
    if (( TUI_COLOR_ENABLED ))
    then
        tui_printf \
            '\033[7m%s\033[0m' \
            "${1-}"
    else
        tui_print "${1-}"
    fi
}

#============================================================
# Unicode / ASCII
#============================================================

tui_horizontal()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        tui_print '─'
    else
        tui_print '-'
    fi
}

tui_vertical()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        tui_print '│'
    else
        tui_print '|'
    fi
}

tui_top_left()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        tui_print '┌'
    else
        tui_print '+'
    fi
}

tui_top_right()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        tui_print '┐'
    else
        tui_print '+'
    fi
}

tui_bottom_left()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        tui_print '└'
    else
        tui_print '+'
    fi
}

tui_bottom_right()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        tui_print '┘'
    else
        tui_print '+'
    fi
}

tui_arrow_up()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        tui_print '↑'
    else
        tui_print '^'
    fi
}

tui_arrow_down()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        tui_print '↓'
    else
        tui_print 'v'
    fi
}

tui_arrow_right()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        tui_print '→'
    else
        tui_print '>'
    fi
}

#============================================================
# Screen
#============================================================

tui_clear()
{
    tui_print $'\033[2J\033[H' || return 1

    TUI_CURSOR_ROW=1
    TUI_CURSOR_COL=1

    return 0
}

screen_clear()
{
    tui_clear
}

screen_prepare()
{
    tui_update_size || return 1
    tui_clear || return 1

    return 0
}

screen_refresh()
{
    return 0
}

screen_rows()
{
    printf '%s' "$TUI_ROWS"
}

screen_cols()
{
    printf '%s' "$TUI_COLS"
}

#============================================================
# Repeat
#============================================================

tui_repeat()
{
    local char="${1:- }"
    local count="${2:-0}"
    local i

    if ! [[ "$count" =~ ^[0-9]+$ ]]
    then
        tui_log_error \
            "TUI: invalid repeat count: $count"

        return 1
    fi

    if (( count == 0 ))
    then
        return 0
    fi

    for (( i=0; i<count; i++ ))
    do
        tui_print "$char" || return 1
    done

    return 0
}

#============================================================
# Drawing
#============================================================

draw_box()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local width="${3:-10}"
    local height="${4:-3}"
    local y

    if ! [[ "$row" =~ ^[0-9]+$ &&
            "$col" =~ ^[0-9]+$ &&
            "$width" =~ ^[0-9]+$ &&
            "$height" =~ ^[0-9]+$ ]]
    then
        tui_log_error \
            "TUI: invalid box geometry"

        return 1
    fi

    if (( row < 1 ||
          col < 1 ||
          width < 2 ||
          height < 2 ))
    then
        return 1
    fi

    #
    # Horizontal character.
    #
    local horizontal='-'

    if (( TUI_UNICODE_ENABLED ))
    then
        horizontal='─'
    fi

    #
    # Top.
    #
    tui_move "$row" "$col" || return 1

    tui_top_left
    tui_repeat "$horizontal" "$((width - 2))"
    tui_top_right

    #
    # Sides.
    #
    for (( y=1; y<height-1; y++ ))
    do
        tui_move \
            "$((row + y))" \
            "$col" || return 1

        tui_vertical

        tui_move \
            "$((row + y))" \
            "$((col + width - 1))" || return 1

        tui_vertical
    done

    #
    # Bottom.
    #
    tui_move \
        "$((row + height - 1))" \
        "$col" || return 1

    tui_bottom_left
    tui_repeat "$horizontal" "$((width - 2))"
    tui_bottom_right

    return 0
}

widget_box()
{
    draw_box "$@"
}

draw_panel()
{
    local title="${1-}"
    local row="${2:-1}"
    local col="${3:-1}"
    local height="${4:-5}"
    local width="${5:-40}"

    draw_box \
        "$row" \
        "$col" \
        "$width" \
        "$height" || return 1

    if [[ -n "$title" ]]
    then
        tui_move \
            "$row" \
            "$((col + 2))" || return 1

        color_title "$title"
    fi

    return 0
}

titlebar_draw()
{
    local title="${1:-Arch Installer}"

    if (( TUI_COLS < 1 ))
    then
        return 1
    fi

    tui_move 1 1 || return 1

    tui_repeat ' ' "$TUI_COLS" || return 1

    tui_move 1 2 || return 1

    color_title "$title"
}

statusbar_draw()
{
    local text="${1-}"

    if (( TUI_ROWS < 1 || TUI_COLS < 1 ))
    then
        return 1
    fi

    tui_move \
        "$TUI_ROWS" \
        1 || return 1

    tui_repeat ' ' "$TUI_COLS" || return 1

    tui_move \
        "$TUI_ROWS" \
        2 || return 1

    tui_print "$text"
}

tui_text()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local text="${3-}"

    tui_move "$row" "$col" || return 1
    tui_print "$text"
}

#============================================================
# Event parser
#============================================================

event_read_csi()
{
    local seq="["
    local byte=""
    local length

    while true
    do
        if ! IFS= read \
            -rsn1 \
            -t "$TUI_ESCAPE_TIMEOUT" \
            byte \
            <&"$TUI_FD"
        then
            TUI_EVENT="$EVENT_NONE"
            return 0
        fi

        seq+="$byte"

        length="${#seq}"

        #
        # CSI final byte is in the range 0x40..0x7E.
        #
        if [[ "$byte" =~ [@-~] ]]
        then
            break
        fi

        #
        # Protect against malformed sequences.
        #
        if (( length >= 32 ))
        then
            TUI_EVENT="$EVENT_NONE"
            return 0
        fi
    done

    case "$seq"
    in
        #
        # Arrow keys.
        #
        "[A"|"[1A"|"[1;1A")
            TUI_EVENT="$EVENT_UP"
            ;;

        "[B"|"[1B"|"[1;1B")
            TUI_EVENT="$EVENT_DOWN"
            ;;

        "[C"|"[1C"|"[1;1C")
            TUI_EVENT="$EVENT_RIGHT"
            ;;

        "[D"|"[1D"|"[1;1D")
            TUI_EVENT="$EVENT_LEFT"
            ;;

        #
        # Modified arrows.
        #
        "[1;2A"|"[1;3A"|"[1;4A"|"[1;5A"|"[1;6A"|"[1;7A"|"[1;8A")
            TUI_EVENT="$EVENT_UP"
            ;;

        "[1;2B"|"[1;3B"|"[1;4B"|"[1;5B"|"[1;6B"|"[1;7B"|"[1;8B")
            TUI_EVENT="$EVENT_DOWN"
            ;;

        "[1;2C"|"[1;3C"|"[1;4C"|"[1;5C"|"[1;6C"|"[1;7C"|"[1;8C")
            TUI_EVENT="$EVENT_RIGHT"
            ;;

        "[1;2D"|"[1;3D"|"[1;4D"|"[1;5D"|"[1;6D"|"[1;7D"|"[1;8D")
            TUI_EVENT="$EVENT_LEFT"
            ;;

        #
        # Home / End.
        #
        "[H"|"[1~"|"[7~")
            TUI_EVENT="$EVENT_HOME"
            ;;

        "[F"|"[4~"|"[8~")
            TUI_EVENT="$EVENT_END"
            ;;

        #
        # Delete / Page.
        #
        "[3~")
            TUI_EVENT="$EVENT_DELETE"
            ;;

        "[5~")
            TUI_EVENT="$EVENT_PAGE_UP"
            ;;

        "[6~")
            TUI_EVENT="$EVENT_PAGE_DOWN"
            ;;

        #
        # Shift+Tab.
        #
        "[Z")
            TUI_EVENT="$EVENT_TAB_BACK"
            ;;

        #
        # Function keys.
        #
        "[11~")
            TUI_EVENT="$EVENT_F1"
            ;;

        "[12~")
            TUI_EVENT="$EVENT_F2"
            ;;

        "[13~")
            TUI_EVENT="$EVENT_F3"
            ;;

        "[14~")
            TUI_EVENT="$EVENT_F4"
            ;;

        "[15~")
            TUI_EVENT="$EVENT_F5"
            ;;

        "[17~")
            TUI_EVENT="$EVENT_F6"
            ;;

        "[18~")
            TUI_EVENT="$EVENT_F7"
            ;;

        "[19~")
            TUI_EVENT="$EVENT_F8"
            ;;

        "[20~")
            TUI_EVENT="$EVENT_F9"
            ;;

        "[21~")
            TUI_EVENT="$EVENT_F10"
            ;;

        "[23~")
            TUI_EVENT="$EVENT_F11"
            ;;

        "[24~")
            TUI_EVENT="$EVENT_F12"
            ;;

        *)
            TUI_EVENT="$EVENT_NONE"
            ;;
    esac

    return 0
}

#============================================================
# Read event
#============================================================

event_read()
{
    local key=""
    local ss3=""

    TUI_EVENT="$EVENT_NONE"
    TUI_EVENT_CHAR=""

    if (( TUI_FD < 0 ))
    then
        tui_log_error \
            "TUI: event_read called without terminal FD"

        return 1
    fi

    #
    # Read one byte.
    #
    if ! IFS= read \
        -rsn1 \
        key \
        <&"$TUI_FD"
    then
        #
        # EOF / closed terminal.
        #
        TUI_EVENT="$EVENT_BACK"
        return 0
    fi

    case "$key"
    in
        #
        # Escape sequence.
        #
        $'\e')
            #
            # A standalone ESC is BACK.
            #
            if ! IFS= read \
                -rsn1 \
                -t "$TUI_ESCAPE_TIMEOUT" \
                key \
                <&"$TUI_FD"
            then
                TUI_EVENT="$EVENT_BACK"
                return 0
            fi

            case "$key"
            in
                #
                # CSI sequence.
                #
                "[")
                    event_read_csi
                    ;;

                #
                # SS3 sequence.
                #
                "O")
                    if IFS= read \
                        -rsn1 \
                        -t "$TUI_ESCAPE_TIMEOUT" \
                        ss3 \
                        <&"$TUI_FD"
                    then
                        case "$ss3"
                        in
                            A)
                                TUI_EVENT="$EVENT_UP"
                                ;;

                            B)
                                TUI_EVENT="$EVENT_DOWN"
                                ;;

                            C)
                                TUI_EVENT="$EVENT_RIGHT"
                                ;;

                            D)
                                TUI_EVENT="$EVENT_LEFT"
                                ;;

                            H)
                                TUI_EVENT="$EVENT_HOME"
                                ;;

                            F)
                                TUI_EVENT="$EVENT_END"
                                ;;

                            P)
                                TUI_EVENT="$EVENT_F1"
                                ;;

                            Q)
                                TUI_EVENT="$EVENT_F2"
                                ;;

                            R)
                                TUI_EVENT="$EVENT_F3"
                                ;;

                            S)
                                TUI_EVENT="$EVENT_F4"
                                ;;

                            *)
                                TUI_EVENT="$EVENT_NONE"
                                ;;
                        esac
                    else
                        TUI_EVENT="$EVENT_NONE"
                    fi
                    ;;

                #
                # Alt+character / unknown escape.
                #
                *)
                    TUI_EVENT="$EVENT_NONE"
                    ;;
            esac
            ;;

        #
        # Enter.
        #
        "")
            TUI_EVENT="$EVENT_SELECT"
            ;;

        #
        # Space.
        #
        " ")
            TUI_EVENT="$EVENT_SPACE"
            ;;

        #
        # Tab.
        #
        $'\t')
            TUI_EVENT="$EVENT_TAB"
            ;;

        #
        # Backspace / DEL.
        #
        $'\177'|$'\b')
            TUI_EVENT="$EVENT_DELETE"
            ;;

        #
        # Ordinary character.
        #
        *)
            TUI_EVENT="$EVENT_CHAR"
            TUI_EVENT_CHAR="$key"
            ;;
    esac

    return 0
}

event_get()
{
    printf '%s' "$TUI_EVENT"
}

event_get_char()
{
    printf '%s' "$TUI_EVENT_CHAR"
}

#============================================================
# Event predicates
#============================================================

event_is_navigation()
{
    case "${1:-}"
    in
        "$EVENT_UP"|
        "$EVENT_DOWN"|
        "$EVENT_LEFT"|
        "$EVENT_RIGHT"|
        "$EVENT_HOME"|
        "$EVENT_END"|
        "$EVENT_PAGE_UP"|
        "$EVENT_PAGE_DOWN")
            return 0
            ;;

        *)
            return 1
            ;;
    esac
}

event_is_select()
{
    [[ "${1:-}" == "$EVENT_SELECT" ]]
}

event_is_back()
{
    [[ "${1:-}" == "$EVENT_BACK" ]]
}

event_is_space()
{
    [[ "${1:-}" == "$EVENT_SPACE" ]]
}

event_is_char()
{
    [[ "${1:-}" == "$EVENT_CHAR" ]]
}

#============================================================
# Text input
#============================================================

tui_input()
{
    local prompt="${1:-}"
    local initial="${2-}"
    local width="${3:-40}"
    local hidden="${4:-0}"

    local value="$initial"
    local char=""
    local masked=""

    TUI_INPUT_RESULT=""

    if ! [[ "$width" =~ ^[0-9]+$ ]]
    then
        tui_log_error \
            "TUI: invalid input width: $width"

        return 1
    fi

    if (( width < 1 ))
    then
        return 1
    fi

    #
    # Truncate initial value if necessary.
    #
    if (( ${#value} > width ))
    then
        value="${value:0:width}"
    fi

    while true
    do
        tui_clear || return 1

        tui_move 5 5 || return 1
        tui_print "$prompt"

        tui_move 7 5 || return 1

        if (( hidden ))
        then
            masked=""

            if (( ${#value} > 0 ))
            then
                printf -v masked '%*s' "${#value}" ''
                masked="${masked// /*}"
            fi

            tui_print "$masked"
        else
            tui_print "$value"
        fi

        event_read || return 1

        case "$TUI_EVENT"
        in
            "$EVENT_SELECT")
                TUI_INPUT_RESULT="$value"
                return 0
                ;;

            "$EVENT_BACK")
                return 1
                ;;

            "$EVENT_DELETE")
                if [[ -n "$value" ]]
                then
                    value="${value:0:${#value}-1}"
                fi
                ;;

            "$EVENT_SPACE")
                if (( ${#value} < width ))
                then
                    value+=' '
                fi
                ;;

            "$EVENT_CHAR")
                char="$TUI_EVENT_CHAR"

                if (( ${#value} < width ))
                then
                    value+="$char"
                fi
                ;;
        esac
    done
}

input_read_line()
{
    tui_input "$@"
}

input_get_result()
{
    printf '%s' "$TUI_INPUT_RESULT"
}

#============================================================
# Dialog
#============================================================

dialog_message()
{
    local title="${1:-Message}"
    local message="${2-}"
    local box_width
    local box_height=10

    if (( TUI_COLS < 20 ))
    then
        return 1
    fi

    box_width=$((TUI_COLS - 16))

    if (( box_width < 20 ))
    then
        box_width=20
    fi

    tui_clear || return 1

    draw_box \
        5 \
        8 \
        "$box_width" \
        "$box_height" || return 1

    tui_move 6 10 || return 1
    color_title "$title"

    tui_move 8 10 || return 1
    tui_print "$message"

    tui_move 12 10 || return 1
    tui_print 'Enter = OK   Esc = Back'

    while true
    do
        event_read || return 1

        case "$TUI_EVENT"
        in
            "$EVENT_SELECT"|"$EVENT_BACK")
                return 0
                ;;
        esac
    done
}

dialog_info()
{
    dialog_message \
        "${1:-Information}" \
        "${2-}"
}

dialog_warning()
{
    dialog_message \
        "${1:-Warning}" \
        "${2-}"
}

dialog_error()
{
    local message="${1:-Unknown error}"

    tui_log_error "$message"

    dialog_message \
        "Error" \
        "$message"
}

dialog_confirm()
{
    local message="${1:-Continue?}"
    local box_width

    if (( TUI_COLS < 20 ))
    then
        return 1
    fi

    box_width=$((TUI_COLS - 16))

    if (( box_width < 20 ))
    then
        box_width=20
    fi

    tui_clear || return 1

    draw_box \
        6 \
        8 \
        "$box_width" \
        9 || return 1

    tui_move 8 10 || return 1
    tui_print "$message"

    tui_move 11 10 || return 1
    tui_print 'Enter = Yes   Esc = No'

    while true
    do
        event_read || return 1

        case "$TUI_EVENT"
        in
            "$EVENT_SELECT")
                return 0
                ;;

            "$EVENT_BACK")
                return 1
                ;;
        esac
    done
}

#============================================================
# Menu
#============================================================

tui_menu()
{
    local title="${1:-Select}"
    local selected="${2:-0}"

    shift 2

    local items=("$@")
    local count="${#items[@]}"

    local event=""
    local i=0

    local box_height
    local visible_items
    local top=0
    local bottom

    TUI_MENU_RESULT=""
    TUI_MENU_VALUE=""

    if (( count == 0 ))
    then
        tui_log_error \
            "TUI: menu contains no items"

        return 1
    fi

    #
    # Validate initial selection.
    #
    if ! [[ "$selected" =~ ^[0-9]+$ ]]
    then
        selected=0
    fi

    if (( selected >= count ))
    then
        selected=0
    fi

    while true
    do
        tui_clear || return 1

        titlebar_draw "$title" || return 1

        #
        # Reserve:
        #   3 rows top
        #   1 row bottom
        #   menu border
        #
        visible_items=$((TUI_ROWS - 7))

        if (( visible_items < 1 ))
        then
            tui_log_error \
                "TUI: terminal too small for menu"

            return 1
        fi

        if (( visible_items > count ))
        then
            visible_items="$count"
        fi

        box_height=$((visible_items + 4))

        if (( box_height > TUI_ROWS - 3 ))
        then
            box_height=$((TUI_ROWS - 3))
        fi

        if (( box_height < 4 ))
        then
            return 1
        fi

        #
        # Keep selected item visible.
        #
        if (( selected < top ))
        then
            top="$selected"
        fi

        bottom=$((top + visible_items - 1))

        if (( selected > bottom ))
        then
            top=$((selected - visible_items + 1))
        fi

        if (( top < 0 ))
        then
            top=0
        fi

        draw_box \
            3 \
            5 \
            "$((TUI_COLS - 10))" \
            "$box_height" || return 1

        #
        # Draw visible items.
        #
        for (( i=0; i<visible_items; i++ ))
        do
            local index=$((top + i))

            if (( index >= count ))
            then
                break
            fi

            tui_move \
                "$((5 + i))" \
                8 || return 1

            if (( index == selected ))
            then
                color_selected \
                    "> ${items[index]}"
            else
                tui_print \
                    "  ${items[index]}"
            fi
        done

        #
        # Scroll indicators.
        #
        if (( top > 0 ))
        then
            tui_move 4 "$((TUI_COLS - 12))" || return 1
            tui_arrow_up
        fi

        if (( top + visible_items < count ))
        then
            tui_move "$((4 + visible_items))" "$((TUI_COLS - 12))" ||
                return 1

            tui_arrow_down
        fi

        statusbar_draw \
            '↑↓ Navigate   Enter Select   Esc Back' || return 1

        event_read || return 1

        event="$TUI_EVENT"

        case "$event"
        in
            "$EVENT_UP")
                if (( selected > 0 ))
                then
                    selected=$((selected - 1))
                else
                    selected=$((count - 1))
                fi
                ;;

            "$EVENT_DOWN")
                if (( selected < count - 1 ))
                then
                    selected=$((selected + 1))
                else
                    selected=0
                fi
                ;;

            "$EVENT_HOME")
                selected=0
                ;;

            "$EVENT_END")
                selected=$((count - 1))
                ;;

            "$EVENT_PAGE_UP")
                selected=$((selected - visible_items))

                if (( selected < 0 ))
                then
                    selected=0
                fi
                ;;

            "$EVENT_PAGE_DOWN")
                selected=$((selected + visible_items))

                if (( selected >= count ))
                then
                    selected=$((count - 1))
                fi
                ;;

            "$EVENT_SELECT")
                TUI_MENU_RESULT="$selected"
                TUI_MENU_VALUE="${items[selected]}"

                return 0
                ;;

            "$EVENT_BACK")
                return 1
                ;;
        esac
    done
}

dialog_select()
{
    tui_menu "$@"
}

dialog_get_result()
{
    printf '%s' "$TUI_MENU_RESULT"
}

dialog_get_value()
{
    printf '%s' "$TUI_MENU_VALUE"
}

#============================================================
# Progress
#============================================================

tui_progress()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local width="${3:-40}"
    local percent="${4:-0}"

    local filled
    local empty

    if ! [[ "$row" =~ ^[0-9]+$ &&
            "$col" =~ ^[0-9]+$ &&
            "$width" =~ ^[0-9]+$ &&
            "$percent" =~ ^[0-9]+$ ]]
    then
        tui_log_error \
            "TUI: invalid progress parameters"

        return 1
    fi

    if (( row < 1 || col < 1 || width < 1 ))
    then
        return 1
    fi

    if (( percent > 100 ))
    then
        percent=100
    fi

    filled=$((width * percent / 100))
    empty=$((width - filled))

    tui_move \
        "$row" \
        "$col" || return 1

    tui_print '[' || return 1
    tui_repeat '#' "$filled" || return 1
    tui_repeat ' ' "$empty" || return 1
    tui_printf '] %3d%%' "$percent" || return 1

    return 0
}

progress_start()
{
    local title="${1-}"
    local row="${2:-1}"
    local col="${3:-1}"
    local width="${4:-40}"

    if ! [[ "$row" =~ ^[0-9]+$ &&
            "$col" =~ ^[0-9]+$ &&
            "$width" =~ ^[0-9]+$ ]]
    then
        tui_log_error \
            "TUI: invalid progress geometry"

        return 1
    fi

    if (( row < 1 ||
          col < 1 ||
          width < 1 ))
    then
        return 1
    fi

    TUI_PROGRESS_ACTIVE=1
    TUI_PROGRESS_PERCENT=0
    TUI_PROGRESS_ROW="$row"
    TUI_PROGRESS_COL="$col"
    TUI_PROGRESS_WIDTH="$width"
    TUI_PROGRESS_TITLE="$title"

    if [[ -n "$title" ]]
    then
        tui_move "$row" "$col" || return 1
        tui_print "$title" || return 1

        row=$((row + 1))

        TUI_PROGRESS_ROW="$row"
    fi

    tui_progress \
        "$TUI_PROGRESS_ROW" \
        "$TUI_PROGRESS_COL" \
        "$TUI_PROGRESS_WIDTH" \
        0
}

progress_set()
{
    local percent="${1:-0}"

    if ! [[ "$percent" =~ ^[0-9]+$ ]]
    then
        tui_log_error \
            "TUI: invalid progress percentage: $percent"

        return 1
    fi

    if (( percent > 100 ))
    then
        percent=100
    fi

    TUI_PROGRESS_PERCENT="$percent"

    if (( TUI_PROGRESS_ACTIVE ))
    then
        tui_progress \
            "$TUI_PROGRESS_ROW" \
            "$TUI_PROGRESS_COL" \
            "$TUI_PROGRESS_WIDTH" \
            "$TUI_PROGRESS_PERCENT"
    fi

    return 0
}

progress_complete()
{
    progress_set 100 || return 1

    TUI_PROGRESS_ACTIVE=0

    return 0
}

#============================================================
# Terminal title
#============================================================

terminal_title()
{
    local title="${1:-Arch Installer}"

    tui_printf \
        '\033]0;%s\007' \
        "$title"
}

terminal_reset_title()
{
    tui_print $'\033]0;\007'
}

#============================================================
# End
#============================================================
```
