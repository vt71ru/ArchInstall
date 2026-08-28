```bash
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
#   • terminal lifecycle
#   • stty
#   • cursor
#   • colors
#   • Unicode/ASCII
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

TUI_STTY_STATE=""

TUI_ROWS=0
TUI_COLS=0

TUI_CURSOR_ROW=1
TUI_CURSOR_COL=1

TUI_COLOR_ENABLED=1
TUI_UNICODE_ENABLED=1

TUI_EVENT_CHAR=""

#============================================================
# Initialization
#============================================================

tui_init()
{
    if (( TUI_INITIALIZED ))
    then
        return 0
    fi

    if [[ ! -t 0 || ! -t 1 ]]
    then
        logger_error \
            "TUI requires stdin/stdout TTY"

        return 1
    fi

    TUI_STTY_STATE="$(
        stty -g 2>/dev/null
    )" || {
        logger_error \
            "Cannot read terminal state"

        return 1
    }

    [[ -n "$TUI_STTY_STATE" ]] || {
        logger_error \
            "Terminal state is empty"

        return 1
    }

    tui_update_size || \
        return 1

    tui_detect_capabilities

    TUI_INITIALIZED=1

    logger_info \
        "TUI initialized: ${TUI_COLS}x${TUI_ROWS}"

    return 0
}

#============================================================
# Capability detection
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

    if [[ "${LC_ALL:-}" == "C" ||
          "${LC_ALL:-}" == "POSIX" ||
          "${LC_CTYPE:-}" == "C" ||
          "${LC_CTYPE:-}" == "POSIX" ||
          "${LANG:-}" == "C" ||
          "${LANG:-}" == "POSIX" ]]
    then
        TUI_UNICODE_ENABLED=0
    fi
}

#============================================================
# Start
#============================================================

tui_start()
{
    if (( TUI_ACTIVE ))
    then
        return 0
    fi

    (( TUI_INITIALIZED )) || \
        tui_init

    tui_update_size || \
        return 1

    if (( TUI_ROWS < 20 || TUI_COLS < 70 ))
    then
        logger_error \
            "Terminal too small: ${TUI_COLS}x${TUI_ROWS}; minimum 70x20"

        return 1
    fi

    printf '\033[?1049h'
    printf '\033[2J\033[H'
    printf '\033[?25l'

    if ! stty \
        -echo \
        -echonl \
        -icanon \
        -ixon \
        min 1 \
        time 0
    then
        printf '\033[?25h'
        printf '\033[?1049l'

        logger_error \
            "Failed to configure terminal input"

        return 1
    fi

    TUI_ACTIVE=1

    tui_clear

    logger_debug \
        "TUI started"

    return 0
}

#============================================================
# Restore
#============================================================

tui_restore()
{
    if (( ! TUI_ACTIVE ))
    then
        return 0
    fi

    if [[ -n "$TUI_STTY_STATE" ]]
    then
        stty \
            "$TUI_STTY_STATE" \
            2>/dev/null \
            || stty sane 2>/dev/null \
            || true
    else
        stty sane 2>/dev/null || true
    fi

    printf '\033[?25h'
    printf '\033[?1049l'
    printf '\033[0m'

    TUI_ACTIVE=0
    TUI_INITIALIZED=0

    TUI_CURSOR_ROW=1
    TUI_CURSOR_COL=1

    logger_debug \
        "TUI restored"
}

#============================================================
# Size
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
          ! "$cols" =~ ^[0-9]+$ ||
          "$rows" == "0" ||
          "$cols" == "0" ]]
    then
        logger_error \
            "Cannot determine terminal size"

        return 1
    fi

    TUI_ROWS="$rows"
    TUI_COLS="$cols"

    return 0
}

tui_rows()
{
    printf '%s' "$TUI_ROWS"
}

tui_cols()
{
    printf '%s' "$TUI_COLS"
}

#============================================================
# Cursor
#============================================================

tui_move()
{
    local row="${1:-1}"
    local col="${2:-1}"

    [[ "$row" =~ ^[0-9]+$ ]] || return 1
    [[ "$col" =~ ^[0-9]+$ ]] || return 1

    (( row >= 1 && col >= 1 )) || return 1

    printf \
        '\033[%d;%dH' \
        "$row" \
        "$col"

    TUI_CURSOR_ROW="$row"
    TUI_CURSOR_COL="$col"
}

tui_move_to()
{
    tui_move "$@"
}

cursor_move()
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
# Symbols
#============================================================

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

#============================================================
# Repeat
#============================================================

tui_repeat()
{
    local char="${1:- }"
    local count="${2:-0}"
    local i

    [[ "$count" =~ ^[0-9]+$ ]] || return 1

    for (( i=0; i<count; i++ ))
    do
        printf '%s' "$char"
    done
}

#============================================================
# Draw box
#============================================================

draw_box()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local width="${3:-10}"
    local height="${4:-3}"
    local y

    (( width >= 2 && height >= 2 )) || \
        return 1

    tui_move "$row" "$col"

    tui_top_left
    tui_repeat "$(tui_horizontal)" "$((width - 2))"
    tui_top_right

    for (( y=1; y<height-1; y++ ))
    do
        tui_move "$((row + y))" "$col"

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

#============================================================
# Panel
#============================================================

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

#============================================================
# Title bar
#============================================================

titlebar_draw()
{
    local title="${1:-Arch Installer}"

    tui_move 1 1

    tui_repeat ' ' "$TUI_COLS"

    tui_move 1 2

    color_title \
        "$title"
}

#============================================================
# Status bar
#============================================================

statusbar_draw()
{
    local text="${1-}"

    tui_move \
        "$TUI_ROWS" \
        1

    tui_repeat ' ' "$TUI_COLS"

    tui_move \
        "$TUI_ROWS" \
        2

    printf '%s' \
        "$text"
}

#============================================================
# Text
#============================================================

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

readonly TUI_EVENT_NONE="NONE"
readonly TUI_EVENT_UP="UP"
readonly TUI_EVENT_DOWN="DOWN"
readonly TUI_EVENT_LEFT="LEFT"
readonly TUI_EVENT_RIGHT="RIGHT"
readonly TUI_EVENT_SELECT="SELECT"
readonly TUI_EVENT_BACK="BACK"
readonly TUI_EVENT_HOME="HOME"
readonly TUI_EVENT_END="END"
readonly TUI_EVENT_PAGE_UP="PAGE_UP"
readonly TUI_EVENT_PAGE_DOWN="PAGE_DOWN"
readonly TUI_EVENT_SPACE="SPACE"
readonly TUI_EVENT_TAB="TAB"
readonly TUI_EVENT_TAB_BACK="TAB_BACK"
readonly TUI_EVENT_DELETE="DELETE"
readonly TUI_EVENT_CHAR="CHAR"

EVENT_NONE="$TUI_EVENT_NONE"
EVENT_UP="$TUI_EVENT_UP"
EVENT_DOWN="$TUI_EVENT_DOWN"
EVENT_LEFT="$TUI_EVENT_LEFT"
EVENT_RIGHT="$TUI_EVENT_RIGHT"
EVENT_SELECT="$TUI_EVENT_SELECT"
EVENT_BACK="$TUI_EVENT_BACK"
EVENT_HOME="$TUI_EVENT_HOME"
EVENT_END="$TUI_EVENT_END"
EVENT_PAGE_UP="$TUI_EVENT_PAGE_UP"
EVENT_PAGE_DOWN="$TUI_EVENT_PAGE_DOWN"
EVENT_SPACE="$TUI_EVENT_SPACE"
EVENT_TAB="$TUI_EVENT_TAB"
EVENT_TAB_BACK="$TUI_EVENT_TAB_BACK"
EVENT_DELETE="$TUI_EVENT_DELETE"
EVENT_CHAR="$TUI_EVENT_CHAR"

readonly TUI_ESCAPE_TIMEOUT=0.08

event_get_char()
{
    printf '%s' \
        "$TUI_EVENT_CHAR"
}

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

        "[Z")
            printf '%s' "$EVENT_TAB_BACK"
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

        *)
            printf '%s' "$EVENT_NONE"
            ;;
    esac
}

event_read()
{
    local key=""
    local seq=""

    TUI_EVENT_CHAR=""

    if ! IFS= read \
        -rsn1 \
        key
    then
        printf '%s' \
            "$EVENT_BACK"

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
                printf '%s' \
                    "$EVENT_BACK"

                return 0
            fi

            case "$key"
            in
                "[")
                    event_read_csi
                    ;;

                "O")
                    local ss3=""

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
                            P) printf '%s' "F1" ;;
                            Q) printf '%s' "F2" ;;
                            R) printf '%s' "F3" ;;
                            S) printf '%s' "F4" ;;
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

#============================================================
# Predicates
#============================================================

event_is_navigation()
{
    case "${1:-}"
    in
        "$EVENT_UP"|"$EVENT_DOWN"|"$EVENT_LEFT"|"$EVENT_RIGHT"|\
        "$EVENT_HOME"|"$EVENT_END"|"$EVENT_PAGE_UP"|"$EVENT_PAGE_DOWN")
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
# Input
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

    while true
    do
        tui_move \
            "$TUI_CURSOR_ROW" \
            "$TUI_CURSOR_COL"

        if [[ -n "$prompt" ]]
        then
            printf '%s' \
                "$prompt"
        fi

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

        tui_repeat \
            ' ' \
            "$((width - ${#value}))"

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
                value+=' '
                ;;

            "$EVENT_CHAR")
                char="$TUI_EVENT_CHAR"
                value+="$char"
                ;;
        esac
    done
}

TUI_INPUT_RESULT=""

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

    local lines=()
    local line
    local row
    local height

    while IFS= read -r line ||
          [[ -n "$line" ]]
    do
        lines+=("$line")
    done < <(
        printf '%s\n' "$message"
    )

    height=$(( ${#lines[@]} + 5 ))

    if (( height > TUI_ROWS - 2 ))
    then
        height=$((TUI_ROWS - 2))
    fi

    row=$(( (TUI_ROWS - height) / 2 + 1 ))

    if (( row < 2 ))
    then
        row=2
    fi

    local width=60
    local col

    (( width > TUI_COLS - 4 )) && \
        width=$((TUI_COLS - 4))

    col=$(( (TUI_COLS - width) / 2 + 1 ))

    draw_box \
        "$row" \
        "$col" \
        "$width" \
        "$height"

    tui_move \
        "$row" \
        "$((col + 2))"

    color_title \
        "$title"

    local i

    for (( i=0; i<${#lines[@]}; i++ ))
    do
        (( i >= height - 4 )) && break

        tui_move \
            "$((row + 2 + i))" \
            "$((col + 2))"

        printf '%s' \
            "${lines[i]:0:$((width - 4))}"
    done

    tui_move \
        "$((row + height - 2))" \
        "$((col + 2))"

    printf 'Enter = OK'

    tui_flush

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
    logger_error \
        "${1:-Unknown error}"

    dialog_message \
        "Error" \
        "${1:-Unknown error}"
}

dialog_confirm()
{
    local message="${1:-Continue?}"
    local event

    tui_clear

    draw_box \
        6 \
        10 \
        60 \
        8

    tui_move \
        8 \
        12

    printf '%s' \
        "$message"

    tui_move \
        11 \
        12

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

    (( count > 0 )) || \
        return 1

    while true
    do
        tui_clear
        titlebar_draw "$title"

        draw_box \
            3 \
            5 \
            70 \
            "$((count + 4))"

        for i in "${!items[@]}"
        do
            tui_move \
                "$((5 + i))" \
                8

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
            "↑↓ Navigate  Enter Select  Esc Back"

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

TUI_MENU_RESULT=""
TUI_MENU_VALUE=""

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

    (( percent < 0 )) && percent=0
    (( percent > 100 )) && percent=100

    filled=$((width * percent / 100))
    empty=$((width - filled))

    tui_move \
        "$row" \
        "$col"

    printf '['

    tui_repeat '#' "$filled"
    tui_repeat ' ' "$empty"

    printf '] %3d%%' \
        "$percent"
}

progress_start()
{
    TUI_PROGRESS_ACTIVE=1
    TUI_PROGRESS_PERCENT=0
    TUI_PROGRESS_ROW="${2:-1}"
    TUI_PROGRESS_COL="${3:-1}"
    TUI_PROGRESS_WIDTH="${4:-40}"
    TUI_PROGRESS_TITLE="${1-}"

    if [[ -n "$TUI_PROGRESS_TITLE" ]]
    then
        tui_move \
            "$TUI_PROGRESS_ROW" \
            "$TUI_PROGRESS_COL"

        printf '%s' \
            "$TUI_PROGRESS_TITLE"
    fi
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

TUI_PROGRESS_ACTIVE=0
TUI_PROGRESS_PERCENT=0
TUI_PROGRESS_ROW=1
TUI_PROGRESS_COL=1
TUI_PROGRESS_WIDTH=40
TUI_PROGRESS_TITLE=""

#============================================================
# End
#============================================================
