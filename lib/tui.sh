#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# lib/tui.sh
#
# Низкоуровневый TTY/TUI-модуль.
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
#============================================================

#============================================================
# Include guard
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

# Интервал ожидания продолжения ESC-последовательности.
readonly TUI_ESCAPE_TIMEOUT="0.15"

#============================================================
# Terminal
#============================================================

TUI_TTY="${TUI_TTY:-/dev/tty}"
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

TUI_MENU_FIRST=0
TUI_MENU_VISIBLE=0

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
# Numeric validation
#============================================================

tui_is_uint()
{
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

#============================================================
# Internal terminal FD
#============================================================

tui_open_terminal()
{
    if (( TUI_FD >= 0 ))
    then
        return 0
    fi

    if [[ ! -e "$TUI_TTY" ]]
    then
        tui_log_error \
            "TUI: terminal device not found: $TUI_TTY"

        return 1
    fi

    if [[ ! -r "$TUI_TTY" || ! -w "$TUI_TTY" ]]
    then
        tui_log_error \
            "TUI: terminal is not readable/writable: $TUI_TTY"

        return 1
    fi

    if ! exec {TUI_FD}<>"$TUI_TTY"
    then
        tui_log_error \
            "TUI: cannot open terminal: $TUI_TTY"

        TUI_FD=-1
        return 1
    fi

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

#============================================================
# Close terminal
#============================================================

tui_close_terminal()
{
    if (( TUI_FD >= 0 ))
    then
        exec {TUI_FD}>&- 2>/dev/null || true
        TUI_FD=-1
    fi
}

#============================================================
# Require terminal
#============================================================

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
    tui_require_tty || return 1

    printf '%s' "${1-}" >&"$TUI_FD"
}

tui_printf()
{
    tui_require_tty || return 1

    local format="${1-}"
    shift || true

    printf "$format" "$@" >&"$TUI_FD"
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

    if ! TUI_STTY_STATE="$(stty -g <&"$TUI_FD" 2>/dev/null)"
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
    if (( ! TUI_STTY_SAVED ))
    then
        return 0
    fi

    if (( TUI_FD < 0 ))
    then
        tui_open_terminal || return 1
    fi

    if (( TUI_FD < 0 ))
    then
        tui_log_error \
            "TUI: invalid terminal descriptor during restore"

        return 1
    fi

    if [[ -z "$TUI_STTY_STATE" ]]
    then
        tui_log_error \
            "TUI: saved terminal state is empty"

        return 1
    fi

    if stty "$TUI_STTY_STATE" <&"$TUI_FD" 2>/dev/null
    then
        tui_log_debug \
            "TUI: original terminal state restored"

        return 0
    fi

    tui_log_warn \
        "TUI: failed to restore saved terminal state"

    if stty sane <&"$TUI_FD" 2>/dev/null
    then
        tui_log_warn \
            "TUI: terminal restored using stty sane"

        return 0
    fi

    tui_log_error \
        "TUI: failed to restore terminal using stty sane"

    return 1
}

#============================================================
# Terminal capabilities
#============================================================

tui_detect_capabilities()
{
    TUI_COLOR_ENABLED=1
    TUI_UNICODE_ENABLED=1

    if [[ -n "${NO_COLOR:-}" ]]
    then
        TUI_COLOR_ENABLED=0
    fi

    if [[ "${TERM:-}" == "dumb" ]]
    then
        TUI_COLOR_ENABLED=0
        TUI_UNICODE_ENABLED=0
    fi

    if ! tput colors <&"$TUI_FD" >/dev/null 2>&1
    then
        TUI_COLOR_ENABLED=0
    fi

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

    rows="$(
        tput lines <&"$TUI_FD" 2>/dev/null || true
    )"

    cols="$(
        tput cols <&"$TUI_FD" 2>/dev/null || true
    )"

    if ! tui_is_uint "$rows"
    then
        rows=""
    fi

    if ! tui_is_uint "$cols"
    then
        cols=""
    fi

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

    if ! tui_is_uint "$rows" || ! tui_is_uint "$cols"
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

    tui_save_terminal || return 1

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
# Configure raw-ish input
#============================================================

tui_enable_input()
{
    tui_require_tty || return 1

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

        return 1
    fi

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

    tui_update_size || return 1

    if ! tui_is_uint "$TUI_ROWS" ||
       ! tui_is_uint "$TUI_COLS"
    then
        tui_log_error \
            "TUI: invalid terminal size"

        return 1
    fi

    if (( TUI_ROWS < 18 || TUI_COLS < 60 ))
    then
        tui_log_error \
            "TUI: terminal too small: ${TUI_COLS}x${TUI_ROWS}; minimum 60x18"

        return 1
    fi

    if ! tui_enable_input
    then
        tui_restore_terminal || true
        return 1
    fi

    if ! tui_print $'\033[?1049h'
    then
        tui_restore_terminal || true
        return 1
    fi

    TUI_ALT_SCREEN=1

    if ! tui_print $'\033[2J\033[H'
    then
        tui_abort_start
        return 1
    fi

    if ! tui_print $'\033[?25l'
    then
        tui_abort_start
        return 1
    fi

    TUI_CURSOR_HIDDEN=1

    if ! tui_print $'\033[0m'
    then
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
    if (( TUI_CURSOR_HIDDEN ))
    then
        tui_print $'\033[?25h' 2>/dev/null || true
        TUI_CURSOR_HIDDEN=0
    fi

    if (( TUI_ALT_SCREEN ))
    then
        tui_print $'\033[0m' 2>/dev/null || true
        tui_print $'\033[?1049l' 2>/dev/null || true
        TUI_ALT_SCREEN=0
    fi

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

    if (( ! TUI_INITIALIZED &&
          ! TUI_ACTIVE &&
          ! TUI_ALT_SCREEN &&
          ! TUI_CURSOR_HIDDEN &&
          ! TUI_STTY_SAVED ))
    then
        return 0
    fi

    tui_open_terminal || true

    if (( TUI_CURSOR_HIDDEN ))
    then
        if ! tui_print $'\033[?25h' 2>/dev/null
        then
            failed=1
        fi

        TUI_CURSOR_HIDDEN=0
    fi

    tui_print $'\033[0m' 2>/dev/null || true

    if (( TUI_ALT_SCREEN ))
    then
        if ! tui_print $'\033[?1049l' 2>/dev/null
        then
            failed=1
        fi

        TUI_ALT_SCREEN=0
    fi

    if (( TUI_STTY_SAVED ))
    then
        if ! tui_restore_terminal
        then
            failed=1
        fi
    fi

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
    TUI_MENU_FIRST=0
    TUI_MENU_VISIBLE=0

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
    tui_restore
}

#============================================================
# Cursor
#============================================================

tui_move()
{
    local row="${1:-}"
    local col="${2:-}"

    if ! tui_is_uint "$row" ||
       ! tui_is_uint "$col"
    then
        tui_log_error \
            "TUI: invalid cursor position: ${row},${col}"

        return 1
    fi

    if (( row < 1 || col < 1 ))
    then
        return 1
    fi

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

    if [[ -z "$code" ]]
    then
        tui_log_error \
            "TUI: empty color code"

        return 1
    fi

    if (( TUI_COLOR_ENABLED ))
    then
        tui_printf \
            '\033[%sm%s\033[0m' \
            "$code" \
            "$text" || return 1
    else
        tui_print "$text" || return 1
    fi

    return 0
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
    tui_clear
}

screen_refresh()
{
    return 0
}

tui_flush()
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

    if ! tui_is_uint "$count"
    then
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
    local horizontal

    if ! tui_is_uint "$row" ||
       ! tui_is_uint "$col" ||
       ! tui_is_uint "$width" ||
       ! tui_is_uint "$height"
    then
        return 1
    fi

    if (( row < 1 ||
          col < 1 ||
          width < 2 ||
          height < 2 ))
    then
        return 1
    fi

    if (( TUI_COLS > 0 &&
          col + width - 1 > TUI_COLS ))
    then
        return 1
    fi

    if (( TUI_ROWS > 0 &&
          row + height - 1 > TUI_ROWS ))
    then
        return 1
    fi

    if (( TUI_UNICODE_ENABLED ))
    then
        horizontal='─'
    else
        horizontal='-'
    fi

    tui_move "$row" "$col" || return 1

    tui_top_left || return 1
    tui_repeat "$horizontal" "$((width - 2))" || return 1
    tui_top_right || return 1

    for (( y=1; y<height-1; y++ ))
    do
        tui_move \
            "$((row + y))" \
            "$col" || return 1

        tui_vertical || return 1

        tui_move \
            "$((row + y))" \
            "$((col + width - 1))" || return 1

        tui_vertical || return 1
    done

    tui_move \
        "$((row + height - 1))" \
        "$col" || return 1

    tui_bottom_left || return 1
    tui_repeat "$horizontal" "$((width - 2))" || return 1
    tui_bottom_right || return 1

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

        color_title "$title" || return 1
    fi

    return 0
}

titlebar_draw()
{
    local title="${1:-Arch Installer}"

    tui_move 1 1 || return 1

    tui_repeat ' ' "$TUI_COLS" || return 1

    tui_move 1 2 || return 1

    color_title "$title"
}

statusbar_draw()
{
    local text="${1-}"
    local max_width
    local output

    if (( TUI_ROWS < 1 || TUI_COLS < 1 ))
    then
        return 1
    fi

    max_width=$((TUI_COLS - 2))

    if (( max_width < 0 ))
    then
        max_width=0
    fi

    output="$text"

    if (( ${#output} > max_width ))
    then
        output="${output:0:max_width}"
    fi

    tui_move \
        "$TUI_ROWS" \
        1 || return 1

    tui_repeat ' ' "$TUI_COLS" || return 1

    tui_move \
        "$TUI_ROWS" \
        2 || return 1

    tui_print "$output"
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

        case "$byte"
        in
            A|B|C|D|H|F|Z|~)
                break
                ;;
        esac

        if (( ${#seq} >= 32 ))
        then
            TUI_EVENT="$EVENT_NONE"
            return 0
        fi
    done

    case "$seq"
    in
        "[A")
            TUI_EVENT="$EVENT_UP"
            ;;

        "[B")
            TUI_EVENT="$EVENT_DOWN"
            ;;

        "[C")
            TUI_EVENT="$EVENT_RIGHT"
            ;;

        "[D")
            TUI_EVENT="$EVENT_LEFT"
            ;;

        "[H"|"[1~"|"[7~")
            TUI_EVENT="$EVENT_HOME"
            ;;

        "[F"|"[4~"|"[8~")
            TUI_EVENT="$EVENT_END"
            ;;

        "[3~")
            TUI_EVENT="$EVENT_DELETE"
            ;;

        "[5~")
            TUI_EVENT="$EVENT_PAGE_UP"
            ;;

        "[6~")
            TUI_EVENT="$EVENT_PAGE_DOWN"
            ;;

        "[Z")
            TUI_EVENT="$EVENT_TAB_BACK"
            ;;

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

        "[1;2A"|"[1;3A"|"[1;4A"|"[1;5A")
            TUI_EVENT="$EVENT_UP"
            ;;

        "[1;2B"|"[1;3B"|"[1;4B"|"[1;5B")
            TUI_EVENT="$EVENT_DOWN"
            ;;

        "[1;2C"|"[1;3C"|"[1;4C"|"[1;5C")
            TUI_EVENT="$EVENT_RIGHT"
            ;;

        "[1;2D"|"[1;3D"|"[1;4D"|"[1;5D")
            TUI_EVENT="$EVENT_LEFT"
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

    tui_require_tty || return 1

    if ! IFS= read \
        -rsn1 \
        key \
        <&"$TUI_FD"
    then
        return 1
    fi

    case "$key"
    in
        $'\e')
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
                "[")
                    event_read_csi
                    ;;

                "O")
                    if IFS= read \
                        -rsn1 \
                        -t "$TUI_ESCAPE_TIMEOUT" \
                        ss3 \
                        <&"$TUI_FD"
                    then
                        case "$ss3"
                        in
                            A) TUI_EVENT="$EVENT_UP" ;;
                            B) TUI_EVENT="$EVENT_DOWN" ;;
                            C) TUI_EVENT="$EVENT_RIGHT" ;;
                            D) TUI_EVENT="$EVENT_LEFT" ;;
                            H) TUI_EVENT="$EVENT_HOME" ;;
                            F) TUI_EVENT="$EVENT_END" ;;
                            P) TUI_EVENT="$EVENT_F1" ;;
                            Q) TUI_EVENT="$EVENT_F2" ;;
                            R) TUI_EVENT="$EVENT_F3" ;;
                            S) TUI_EVENT="$EVENT_F4" ;;
                            *) TUI_EVENT="$EVENT_NONE" ;;
                        esac
                    else
                        TUI_EVENT="$EVENT_NONE"
                    fi
                    ;;

                *)
                    TUI_EVENT="$EVENT_NONE"
                    ;;
            esac
            ;;

        "")
            TUI_EVENT="$EVENT_SELECT"
            ;;

        " ")
            TUI_EVENT="$EVENT_SPACE"
            ;;

        $'\t')
            TUI_EVENT="$EVENT_TAB"
            ;;

        $'\177'|$'\b')
            TUI_EVENT="$EVENT_DELETE"
            ;;

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

    if ! tui_is_uint "$width"
    then
        tui_log_error \
            "TUI: invalid input width: $width"

        return 1
    fi

    if (( width < 1 ))
    then
        return 1
    fi

    while true
    do
        tui_clear || return 1

        tui_move 5 5 || return 1
        tui_print "$prompt" || return 1

        tui_move 7 5 || return 1

        if (( hidden ))
        then
            masked=""

            if [[ -n "$value" ]]
            then
                printf -v masked '%*s' "${#value}" ''
                masked="${masked// /*}"
            fi

            tui_print "$masked" || return 1
        else
            tui_print "$value" || return 1
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

    if (( TUI_COLS > 16 ))
    then
        box_width=$((TUI_COLS - 16))
    else
        box_width=40
    fi

    if (( box_width > TUI_COLS - 2 ))
    then
        box_width=$((TUI_COLS - 2))
    fi

    tui_clear || return 1

    draw_box \
        5 \
        8 \
        "$box_width" \
        10 || return 1

    tui_move 6 10 || return 1
    color_title "$title" || return 1

    tui_move 8 10 || return 1
    tui_print "$message" || return 1

    tui_move 12 10 || return 1
    tui_print 'Enter = OK   Esc = Back' || return 1

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

    if (( TUI_COLS > 16 ))
    then
        box_width=$((TUI_COLS - 16))
    else
        box_width=40
    fi

    if (( box_width > TUI_COLS - 2 ))
    then
        box_width=$((TUI_COLS - 2))
    fi

    tui_clear || return 1

    draw_box \
        6 \
        8 \
        "$box_width" \
        9 || return 1

    tui_move 8 10 || return 1
    tui_print "$message" || return 1

    tui_move 11 10 || return 1
    tui_print 'Enter = Yes   Esc = No' || return 1

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
    local i
    local box_height
    local first
    local visible
    local last
    local row
    local menu_width

    TUI_MENU_RESULT=""
    TUI_MENU_VALUE=""
    TUI_MENU_FIRST=0
    TUI_MENU_VISIBLE=0

    if (( count == 0 ))
    then
        return 1
    fi

    if ! tui_is_uint "$selected"
    then
        selected=0
    fi

    if (( selected >= count ))
    then
        selected=$((count - 1))
    fi

    visible=$((TUI_ROWS - 8))

    if (( visible < 1 ))
    then
        return 1
    fi

    menu_width=$((TUI_COLS - 10))

    if (( menu_width < 10 ))
    then
        return 1
    fi

    while true
    do
        tui_clear || return 1

        titlebar_draw "$title" || return 1

        box_height=$((visible + 4))

        if (( box_height > TUI_ROWS - 3 ))
        then
            box_height=$((TUI_ROWS - 3))
        fi

        if (( box_height < 4 ))
        then
            return 1
        fi

        first="$TUI_MENU_FIRST"

        if (( selected < first ))
        then
            first="$selected"
        fi

        if (( selected >= first + visible ))
        then
            first=$((selected - visible + 1))
        fi

        if (( first < 0 ))
        then
            first=0
        fi

        if (( first > count - 1 ))
        then
            first=$((count - 1))
        fi

        TUI_MENU_FIRST="$first"

        last=$((first + visible - 1))

        if (( last >= count ))
        then
            last=$((count - 1))
        fi

        TUI_MENU_VISIBLE=$((last - first + 1))

        draw_box \
            3 \
            5 \
            "$menu_width" \
            "$box_height" || return 1

        row=5

        for (( i=first; i<=last; i++ ))
        do
            tui_move \
                "$row" \
                8 || return 1

            if (( i == selected ))
            then
                color_selected \
                    "> ${items[i]}" || return 1
            else
                tui_print \
                    "  ${items[i]}" || return 1
            fi

            ((row++))
        done

        if (( first > 0 ))
        then
            tui_move \
                4 \
                "$((TUI_COLS - 10))" || return 1

            tui_arrow_up || return 1
        fi

        if (( last < count - 1 ))
        then
            tui_move \
                "$((3 + box_height - 1))" \
                "$((TUI_COLS - 10))" || return 1

            tui_arrow_down || return 1
        fi

        statusbar_draw \
            '↑↓ Navigate   Home/End   PgUp/PgDn   Enter Select   Esc Back' \
            || return 1

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
                selected=$((selected - visible))

                if (( selected < 0 ))
                then
                    selected=0
                fi
                ;;

            "$EVENT_PAGE_DOWN")
                selected=$((selected + visible))

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

    if ! tui_is_uint "$row" ||
       ! tui_is_uint "$col" ||
       ! tui_is_uint "$width" ||
       ! tui_is_uint "$percent"
    then
        return 1
    fi

    if (( row < 1 ||
          col < 1 ||
          width < 1 ))
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

    tui_printf '] %3d%%' "$percent"
}

progress_start()
{
    local title="${1-}"
    local row="${2:-1}"
    local col="${3:-1}"
    local width="${4:-40}"

    if ! tui_is_uint "$row" ||
       ! tui_is_uint "$col" ||
       ! tui_is_uint "$width"
    then
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

    if ! tui_is_uint "$percent"
    then
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
