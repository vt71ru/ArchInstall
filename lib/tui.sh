#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# tui.sh
#
# Единый TUI-модуль Arch Installer.
#
# Ответственность:
#   • Сохранение / восстановление terminal state
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
#   • progress
#
# Не содержит:
#   • Installer logic
#   • CONFIG business logic
#============================================================

if [[ -n "${TUI_SH_LOADED:-}" ]]
then
    return 0
fi

readonly TUI_SH_LOADED=1

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

readonly TUI_ESCAPE_TIMEOUT="0.08"

#============================================================
# Internal: terminal TTY check
#============================================================

tui_require_tty()
{
    if [[ ! -t 0 ]]
    then
        logger_error \
            "TUI: stdin is not a TTY"

        return 1
    fi

    if [[ ! -t 1 ]]
    then
        logger_error \
            "TUI: stdout is not a TTY"

        return 1
    fi

    if [[ ! -t 2 ]]
    then
        logger_error \
            "TUI: stderr is not a TTY"

        return 1
    fi

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

    tui_require_tty || \
        return 1

    if ! TUI_STTY_STATE="$(
        stty -g
    )"
    then
        logger_error \
            "TUI: failed to save terminal state"

        return 1
    fi

    if [[ -z "$TUI_STTY_STATE" ]]
    then
        logger_error \
            "TUI: saved terminal state is empty"

        return 1
    fi

    TUI_STTY_SAVED=1

    logger_debug \
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

    if stty \
        "$TUI_STTY_STATE" \
        2>/dev/null
    then
        logger_debug \
            "TUI: original terminal state restored"
    else
        logger_warn \
            "TUI: failed to restore saved terminal state"

        if stty sane 2>/dev/null
        then
            logger_warn \
                "TUI: terminal restored using stty sane"
        else
            logger_error \
                "TUI: failed to restore terminal using stty sane"

            rc=1
        fi
    fi

    return "$rc"
}

#============================================================
# Detect terminal capabilities
#============================================================

tui_detect_capabilities()
{
    TUI_COLOR_ENABLED=1
    TUI_UNICODE_ENABLED=1

    if [[ -n "${NO_COLOR:-}" ||
          "${TERM:-}" == "dumb" ]]
    then
        TUI_COLOR_ENABLED=0
    fi

    if ! tput colors >/dev/null 2>&1
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
# Get screen size
#============================================================

tui_update_size()
{
    local rows
    local cols

    rows="$(
        tput lines 2>/dev/null ||
        printf '0'
    )"

    cols="$(
        tput cols 2>/dev/null ||
        printf '0'
    )"

    if [[ ! "$rows" =~ ^[0-9]+$ ||
          ! "$cols" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "TUI: invalid terminal size: ${cols}x${rows}"

        return 1
    fi

    if (( rows <= 0 || cols <= 0 ))
    then
        logger_error \
            "TUI: terminal size is ${cols}x${rows}"

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

    tui_require_tty || \
        return 1

    tui_save_terminal || \
        return 1

    tui_update_size || {
        TUI_STTY_SAVED=0
        TUI_STTY_STATE=""
        return 1
    }

    tui_detect_capabilities

    TUI_CURSOR_ROW=1
    TUI_CURSOR_COL=1

    TUI_INITIALIZED=1

    logger_info \
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
        tui_init || \
            return 1
    fi

    if (( TUI_ROWS < 20 || TUI_COLS < 70 ))
    then
        logger_error \
            "TUI: terminal too small: ${TUI_COLS}x${TUI_ROWS}; minimum 70x20"

        return 1
    fi

    #
    # Enter alternate screen.
    #
    printf '\033[?1049h'

    if [[ $? -ne 0 ]]
    then
        tui_abort_start
        return 1
    fi

    TUI_ALT_SCREEN=1

    #
    # Clear alternate screen.
    #
    printf '\033[2J\033[H'

    #
    # Hide cursor.
    #
    printf '\033[?25l'

    if [[ $? -ne 0 ]]
    then
        tui_abort_start
        return 1
    fi

    TUI_CURSOR_HIDDEN=1

    #
    # Enable interactive TUI input mode.
    #
    if ! stty \
        -echo \
        -echonl \
        -icanon \
        -ixon \
        min 1 \
        time 0
    then
        logger_error \
            "TUI: failed to configure terminal input"

        tui_abort_start

        return 1
    fi

    #
    # IMPORTANT:
    # From this point terminal settings were changed.
    #
    TUI_ACTIVE=1

    TUI_CURSOR_ROW=1
    TUI_CURSOR_COL=1

    logger_debug \
        "TUI started"

    return 0
}

#============================================================
# Abort incomplete startup
#============================================================

tui_abort_start()
{
    #
    # Restore stty first.
    #
    if (( TUI_STTY_SAVED ))
    then
        tui_restore_terminal || true
    fi

    #
    # Show cursor.
    #
    if (( TUI_CURSOR_HIDDEN ))
    then
        printf '\033[?25h'
        TUI_CURSOR_HIDDEN=0
    fi

    #
    # Leave alternate screen.
    #
    if (( TUI_ALT_SCREEN ))
    then
        printf '\033[?1049l'
        TUI_ALT_SCREEN=0
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
    # Restore stty regardless of TUI_ACTIVE.
    #
    # This is critical when an error happens halfway through
    # startup.
    #
    if (( TUI_STTY_SAVED ))
    then
        if ! tui_restore_terminal
        then
            failed=1
        fi
    fi

    #
    # Show cursor.
    #
    if (( TUI_CURSOR_HIDDEN ))
    then
        printf '\033[?25h' || true
        TUI_CURSOR_HIDDEN=0
    fi

    #
    # Leave alternate screen.
    #
    if (( TUI_ALT_SCREEN ))
    then
        printf '\033[?1049l' || true
        TUI_ALT_SCREEN=0
    fi

    #
    # Reset terminal attributes.
    #
    printf '\033[0m' || true

    TUI_ACTIVE=0
    TUI_INITIALIZED=0

    TUI_STTY_SAVED=0
    TUI_STTY_STATE=""

    TUI_CURSOR_ROW=1
    TUI_CURSOR_COL=1

    if (( failed ))
    then
        logger_error \
            "TUI restoration completed with errors"

        return 1
    fi

    logger_debug \
        "TUI restored"

    return 0
}

#============================================================
# Exit TUI
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

    if [[ ! "$row" =~ ^[0-9]+$ ||
          ! "$col" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "TUI: invalid cursor position: ${row},${col}"

        return 1
    fi

    if (( row < 1 || col < 1 ))
    then
        return 1
    fi

    printf \
        '\033[%d;%dH' \
        "$row" \
        "$col"

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
    printf '\033[s'
}

tui_restore_cursor()
{
    printf '\033[u'
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
        printf \
            '\033[%sm%s\033[0m' \
            "$code" \
            "$text"
    else
        printf '%s' \
            "$text"
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
        printf \
            '\033[1m%s\033[0m' \
            "${1-}"
    else
        printf '%s' \
            "${1-}"
    fi
}

color_selected()
{
    if (( TUI_COLOR_ENABLED ))
    then
        printf \
            '\033[7m%s\033[0m' \
            "${1-}"
    else
        printf '%s' \
            "${1-}"
    fi
}

#============================================================
# Unicode / ASCII
#============================================================

tui_horizontal()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        printf '─'
    else
        printf '-'
    fi
}

tui_vertical()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        printf '│'
    else
        printf '|'
    fi
}

tui_top_left()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        printf '┌'
    else
        printf '+'
    fi
}

tui_top_right()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        printf '┐'
    else
        printf '+'
    fi
}

tui_bottom_left()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        printf '└'
    else
        printf '+'
    fi
}

tui_bottom_right()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        printf '┘'
    else
        printf '+'
    fi
}

tui_arrow_up()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        printf '↑'
    else
        printf '^'
    fi
}

tui_arrow_down()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        printf '↓'
    else
        printf 'v'
    fi
}

tui_arrow_right()
{
    if (( TUI_UNICODE_ENABLED ))
    then
        printf '→'
    else
        printf '>'
    fi
}

#============================================================
# Screen
#============================================================

tui_clear()
{
    printf '\033[2J\033[H'

    TUI_CURSOR_ROW=1
    TUI_CURSOR_COL=1
}

screen_clear()
{
    tui_clear
}

screen_prepare()
{
    tui_update_size || \
        return 1

    tui_clear
}

screen_refresh()
{
    printf ''
}

tui_flush()
{
    printf ''
}

screen_rows()
{
    printf '%s' \
        "$TUI_ROWS"
}

screen_cols()
{
    printf '%s' \
        "$TUI_COLS"
}

#============================================================
# Repeat
#============================================================

tui_repeat()
{
    local char="${1:- }"
    local count="${2:-0}"
    local i

    if [[ ! "$count" =~ ^[0-9]+$ ]]
    then
        return 1
    fi

    for (( i=0; i<count; i++ ))
    do
        printf '%s' \
            "$char"
    done
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

    if (( width < 2 || height < 2 ))
    then
        return 1
    fi

    tui_move "$row" "$col"

    tui_top_left
    tui_repeat "$(tui_horizontal)" "$((width - 2))"
    tui_top_right

    for (( y=1; y<height-1; y++ ))
    do
        tui_move \
            "$((row + y))" \
            "$col"

        tui_vertical

        tui_move \
            "$((row + y))" \
            "$((col + width - 1))"

        tui_vertical
    done

    tui_move \
        "$((row + height - 1))" \
        "$col"

    tui_bottom_left
    tui_repeat "$(tui_horizontal)" "$((width - 2))"
    tui_bottom_right
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
        "$height" || \
        return 1

    if [[ -n "$title" ]]
    then
        tui_move \
            "$row" \
            "$((col + 2))"

        color_title \
            "$title"
    fi
}

titlebar_draw()
{
    local title="${1:-Arch Installer}"

    tui_move 1 1

    tui_repeat \
        ' ' \
        "$TUI_COLS"

    tui_move 1 2

    color_title \
        "$title"
}

statusbar_draw()
{
    local text="${1-}"

    tui_move \
        "$TUI_ROWS" \
        1

    tui_repeat \
        ' ' \
        "$TUI_COLS"

    tui_move \
        "$TUI_ROWS" \
        2

    printf '%s' \
        "$text"
}

tui_text()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local text="${3-}"

    tui_move \
        "$row" \
        "$col"

    printf '%s' \
        "$text"
}

#============================================================
# Events
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
            byte
        then
            printf '%s' \
                "$EVENT_NONE"

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
            printf '%s' \
                "$EVENT_NONE"

            return 0
        fi
    done

    case "$seq"
    in
        "[A")
            printf '%s' "$EVENT_UP"
            ;;

        "[B")
            printf '%s' "$EVENT_DOWN"
            ;;

        "[C")
            printf '%s' "$EVENT_RIGHT"
            ;;

        "[D")
            printf '%s' "$EVENT_LEFT"
            ;;

        "[H"|"[1~"|"[7~")
            printf '%s' "$EVENT_HOME"
            ;;

        "[F"|"[4~"|"[8~")
            printf '%s' "$EVENT_END"
            ;;

        "[3~")
            printf '%s' "$EVENT_DELETE"
            ;;

        "[5~")
            printf '%s' "$EVENT_PAGE_UP"
            ;;

        "[6~")
            printf '%s' "$EVENT_PAGE_DOWN"
            ;;

        "[Z")
            printf '%s' "$EVENT_TAB_BACK"
            ;;

        "[11~")
            printf '%s' "$EVENT_F1"
            ;;

        "[12~")
            printf '%s' "$EVENT_F2"
            ;;

        "[13~")
            printf '%s' "$EVENT_F3"
            ;;

        "[14~")
            printf '%s' "$EVENT_F4"
            ;;

        "[15~")
            printf '%s' "$EVENT_F5"
            ;;

        "[17~")
            printf '%s' "$EVENT_F6"
            ;;

        "[18~")
            printf '%s' "$EVENT_F7"
            ;;

        "[19~")
            printf '%s' "$EVENT_F8"
            ;;

        "[20~")
            printf '%s' "$EVENT_F9"
            ;;

        "[21~")
            printf '%s' "$EVENT_F10"
            ;;

        "[23~")
            printf '%s' "$EVENT_F11"
            ;;

        "[24~")
            printf '%s' "$EVENT_F12"
            ;;

        "[1;2A"|"[1;3A"|"[1;4A"|"[1;5A")
            printf '%s' "$EVENT_UP"
            ;;

        "[1;2B"|"[1;3B"|"[1;4B"|"[1;5B")
            printf '%s' "$EVENT_DOWN"
            ;;

        "[1;2C"|"[1;3C"|"[1;4C"|"[1;5C")
            printf '%s' "$EVENT_RIGHT"
            ;;

        "[1;2D"|"[1;3D"|"[1;4D"|"[1;5D")
            printf '%s' "$EVENT_LEFT"
            ;;

        *)
            printf '%s' "$EVENT_NONE"
            ;;
    esac
}

event_read()
{
    local key=""
    local ss3=""

    TUI_EVENT_CHAR=""

    if ! IFS= read \
        -rsn1 \
        key
    then
        printf '%s' "$EVENT_BACK"
        return 0
    fi

    case "$key"
    in
        $'\e')
            if ! IFS= read \
                -rsn1 \
                -t "$TUI_ESCAPE_TIMEOUT" \
                key
            then
                printf '%s' "$EVENT_BACK"
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
                        ss3
                    then
                        case "$ss3"
                        in
                            A) printf '%s' "$EVENT_UP" ;;
                            B) printf '%s' "$EVENT_DOWN" ;;
                            C) printf '%s' "$EVENT_RIGHT" ;;
                            D) printf '%s' "$EVENT_LEFT" ;;
                            H) printf '%s' "$EVENT_HOME" ;;
                            F) printf '%s' "$EVENT_END" ;;
                            P) printf '%s' "$EVENT_F1" ;;
                            Q) printf '%s' "$EVENT_F2" ;;
                            R) printf '%s' "$EVENT_F3" ;;
                            S) printf '%s' "$EVENT_F4" ;;
                            *) printf '%s' "$EVENT_NONE" ;;
                        esac
                    else
                        printf '%s' "$EVENT_NONE"
                    fi
                    ;;

                *)
                    printf '%s' "$EVENT_NONE"
                    ;;
            esac
            ;;

        "")
            printf '%s' "$EVENT_SELECT"
            ;;

        " ")
            printf '%s' "$EVENT_SPACE"
            ;;

        $'\t')
            printf '%s' "$EVENT_TAB"
            ;;

        $'\177'|$'\b')
            printf '%s' "$EVENT_DELETE"
            ;;

        *)
            TUI_EVENT_CHAR="$key"
            printf '%s' "$EVENT_CHAR"
            ;;
    esac
}

event_get_char()
{
    printf '%s' \
        "$TUI_EVENT_CHAR"
}

event_is_navigation()
{
    case "${1:-}"
    in
        "$EVENT_UP"|"$EVENT_DOWN"|"$EVENT_LEFT"|"$EVENT_RIGHT"|"$EVENT_HOME"|"$EVENT_END"|"$EVENT_PAGE_UP"|"$EVENT_PAGE_DOWN")
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
    local event
    local char

    TUI_INPUT_RESULT=""

    if ! [[ "$width" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "TUI: invalid input width: ${width}"

        return 1
    fi

    while true
    do
        tui_clear

        tui_move \
            5 \
            5

        printf '%s' \
            "$prompt"

        tui_move \
            7 \
            5

        if (( hidden ))
        then
            printf '%*s' \
                "${#value}" \
                '' |
                tr ' ' '*'
        else
            printf '%s' \
                "$value"
        fi

        event="$(
            event_read
        )"

        case "$event"
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
    printf '%s' \
        "$TUI_INPUT_RESULT"
}

#============================================================
# Dialog
#============================================================

dialog_message()
{
    local title="${1:-Message}"
    local message="${2-}"

    tui_clear

    draw_box \
        5 \
        8 \
        "$((TUI_COLS - 16))" \
        10 || \
        return 1

    tui_move \
        6 \
        10

    color_title \
        "$title"

    tui_move \
        8 \
        10

    printf '%s' \
        "$message"

    tui_move \
        12 \
        10

    printf \
        'Enter = OK   Esc = Back'

    while true
    do
        case "$(
            event_read
        )"
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

    logger_error \
        "$message"

    dialog_message \
        "Error" \
        "$message"
}

dialog_confirm()
{
    local message="${1:-Continue?}"
    local event

    tui_clear

    draw_box \
        6 \
        8 \
        "$((TUI_COLS - 16))" \
        9 || \
        return 1

    tui_move \
        8 \
        10

    printf '%s' \
        "$message"

    tui_move \
        11 \
        10

    printf \
        'Enter = Yes   Esc = No'

    while true
    do
        event="$(
            event_read
        )"

        case "$event"
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
    local event
    local i

    if (( count == 0 ))
    then
        return 1
    fi

    if ! [[ "$selected" =~ ^[0-9]+$ ]] ||
       (( selected >= count ))
    then
        selected=0
    fi

    while true
    do
        tui_clear

        titlebar_draw \
            "$title"

        draw_box \
            3 \
            5 \
            "$((TUI_COLS - 10))" \
            "$((count + 4))" || \
            return 1

        for i in "${!items[@]}"
        do
            tui_move \
                "$((5 + i))" \
                8 || \
                return 1

            if (( i == selected ))
            then
                color_selected \
                    "> ${items[i]}"
            else
                printf \
                    '  %s' \
                    "${items[i]}"
            fi
        done

        statusbar_draw \
            "↑↓ Navigate   Enter Select   Esc Back"

        event="$(
            event_read
        )"

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
    printf '%s' \
        "$TUI_MENU_RESULT"
}

dialog_get_value()
{
    printf '%s' \
        "$TUI_MENU_VALUE"
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

    [[ "$width" =~ ^[0-9]+$ ]] || return 1
    [[ "$percent" =~ ^[0-9]+$ ]] || return 1

    (( percent > 100 )) && percent=100

    filled=$((width * percent / 100))
    empty=$((width - filled))

    tui_move \
        "$row" \
        "$col" || \
        return 1

    printf '['

    tui_repeat '#' "$filled"
    tui_repeat ' ' "$empty"

    printf '] %3d%%' \
        "$percent"

    return 0
}

progress_start()
{
    local title="${1-}"
    local row="${2:-1}"
    local col="${3:-1}"
    local width="${4:-40}"

    TUI_PROGRESS_ACTIVE=1
    TUI_PROGRESS_PERCENT=0
    TUI_PROGRESS_ROW="$row"
    TUI_PROGRESS_COL="$col"
    TUI_PROGRESS_WIDTH="$width"
    TUI_PROGRESS_TITLE="$title"

    if [[ -n "$title" ]]
    then
        tui_move \
            "$row" \
            "$col"

        printf '%s' \
            "$title"
    fi

    return 0
}

progress_set()
{
    local percent="${1:-0}"

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
    progress_set 100

    TUI_PROGRESS_ACTIVE=0
}

#============================================================
# Window / title
#============================================================

terminal_title()
{
    local title="${1:-Arch Installer}"

    printf \
        '\033]0;%s\007' \
        "$title"
}

terminal_reset_title()
{
    printf \
        '\033]0;\007'
}

#============================================================
# End
#============================================================
