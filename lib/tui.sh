```bash
#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  lib/tui.sh
#
#  Terminal User Interface
#
#  Ответственность:
#   • управление терминалом
#   • alternate screen
#   • cursor
#   • colors
#   • keyboard events
#   • menus
#   • dialogs
#   • progress
#
#============================================================

if [[ -n "${TUI_SH_LOADED:-}" ]]
then
    return 0
fi

TUI_SH_LOADED=1

#============================================================
# EVENT CONSTANTS
#============================================================

EVENT_NONE="NONE"

EVENT_UP="UP"
EVENT_DOWN="DOWN"
EVENT_LEFT="LEFT"
EVENT_RIGHT="RIGHT"

EVENT_SELECT="SELECT"
EVENT_BACK="BACK"

EVENT_HOME="HOME"
EVENT_END="END"

EVENT_PAGE_UP="PAGE_UP"
EVENT_PAGE_DOWN="PAGE_DOWN"

EVENT_SPACE="SPACE"
EVENT_TAB="TAB"
EVENT_TAB_BACK="TAB_BACK"

EVENT_DELETE="DELETE"

EVENT_F1="F1"
EVENT_F2="F2"
EVENT_F3="F3"
EVENT_F4="F4"
EVENT_F5="F5"
EVENT_F6="F6"
EVENT_F7="F7"
EVENT_F8="F8"
EVENT_F9="F9"
EVENT_F10="F10"
EVENT_F11="F11"
EVENT_F12="F12"

EVENT_HELP="HELP"
EVENT_CHAR="CHAR"

#============================================================
# CONFIGURATION
#============================================================

TUI_ESCAPE_TIMEOUT="${TUI_ESCAPE_TIMEOUT:-0.15}"

TUI_TTY="${TUI_TTY:-/dev/tty}"
TUI_FD="${TUI_FD:--1}"

TUI_INITIALIZED="${TUI_INITIALIZED:-0}"
TUI_ACTIVE="${TUI_ACTIVE:-0}"

TUI_STTY_SAVED="${TUI_STTY_SAVED:-0}"
TUI_STTY_STATE="${TUI_STTY_STATE:-}"

TUI_ALT_SCREEN="${TUI_ALT_SCREEN:-0}"
TUI_CURSOR_HIDDEN="${TUI_CURSOR_HIDDEN:-0}"

TUI_ROWS="${TUI_ROWS:-24}"
TUI_COLS="${TUI_COLS:-80}"

TUI_CURSOR_ROW="${TUI_CURSOR_ROW:-1}"
TUI_CURSOR_COL="${TUI_CURSOR_COL:-1}"

TUI_COLOR_ENABLED="${TUI_COLOR_ENABLED:-1}"
TUI_UNICODE_ENABLED="${TUI_UNICODE_ENABLED:-1}"

TUI_EVENT="${TUI_EVENT:-$EVENT_NONE}"
TUI_EVENT_CHAR="${TUI_EVENT_CHAR:-}"

TUI_MENU_SELECTED="${TUI_MENU_SELECTED:-0}"
TUI_MENU_RESULT="${TUI_MENU_RESULT:-}"

TUI_PROGRESS_VALUE="${TUI_PROGRESS_VALUE:-0}"
TUI_PROGRESS_MAX="${TUI_PROGRESS_MAX:-100}"

#============================================================
# LOGGING HELPERS
#============================================================

tui_log_info()
{
    if declare -F log_info >/dev/null 2>&1
    then
        log_info "$*"
    else
        printf '[INFO] %s\n' "$*" >&2
    fi
}

tui_log_warn()
{
    if declare -F log_warn >/dev/null 2>&1
    then
        log_warn "$*"
    else
        printf '[WARN] %s\n' "$*" >&2
    fi
}

tui_log_error()
{
    if declare -F log_error >/dev/null 2>&1
    then
        log_error "$*"
    else
        printf '[ERROR] %s\n' "$*" >&2
    fi
}

#============================================================
# TERMINAL
#============================================================

tui_open_terminal()
{
    if (( TUI_FD >= 0 ))
    then
        return 0
    fi

    if [[ ! -e "$TUI_TTY" ]]
    then
        tui_log_error "TUI: terminal device not found: $TUI_TTY"
        return 1
    fi

    if ! exec {TUI_FD}<>"$TUI_TTY"
    then
        TUI_FD=-1
        tui_log_error "TUI: cannot open terminal: $TUI_TTY"
        return 1
    fi

    if ! tty <&"$TUI_FD" >/dev/null 2>&1
    then
        tui_log_error "TUI: opened device is not a TTY"
        exec {TUI_FD}>&- 2>/dev/null || true
        exec {TUI_FD}<&- 2>/dev/null || true
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
        exec {TUI_FD}<&- 2>/dev/null || true
    fi

    TUI_FD=-1
}

tui_require_tty()
{
    if (( TUI_FD < 0 ))
    then
        tui_open_terminal || return 1
    fi

    if ! tty <&"$TUI_FD" >/dev/null 2>&1
    then
        tui_log_error "TUI: terminal FD is not a TTY"
        return 1
    fi

    return 0
}

#============================================================
# OUTPUT
#============================================================

tui_print()
{
    tui_require_tty || return 1
    printf '%s' "$*" >&"$TUI_FD"
}

tui_printf()
{
    tui_require_tty || return 1
    printf "$@" >&"$TUI_FD"
}

tui_flush()
{
    return 0
}

#============================================================
# TERMINAL STATE
#============================================================

tui_save_terminal()
{
    tui_require_tty || return 1

    if (( TUI_STTY_SAVED ))
    then
        return 0
    fi

    local state

    if ! state="$(stty -g <&"$TUI_FD" 2>/dev/null)"
    then
        tui_log_error "TUI: unable to save terminal state"
        return 1
    fi

    TUI_STTY_STATE="$state"
    TUI_STTY_SAVED=1

    return 0
}

tui_restore_terminal()
{
    if (( TUI_FD < 0 ))
    then
        return 0
    fi

    if (( TUI_STTY_SAVED ))
    then
        if ! stty "$TUI_STTY_STATE" <&"$TUI_FD" 2>/dev/null
        then
            stty sane <&"$TUI_FD" 2>/dev/null || true
        fi
    else
        stty sane <&"$TUI_FD" 2>/dev/null || true
    fi

    TUI_STTY_SAVED=0
    TUI_STTY_STATE=""

    return 0
}

#============================================================
# CAPABILITIES
#============================================================

tui_detect_capabilities()
{
    if [[ -t 1 ]]
    then
        TUI_COLOR_ENABLED=1
    else
        TUI_COLOR_ENABLED=0
    fi

    if [[ "${TERM:-}" == "dumb" ]]
    then
        TUI_COLOR_ENABLED=0
        TUI_UNICODE_ENABLED=0
    fi

    if [[ "${LANG:-}" == *UTF-8* ||
          "${LANG:-}" == *utf8* ||
          "${LC_ALL:-}" == *UTF-8* ||
          "${LC_ALL:-}" == *utf8* ||
          "${LC_CTYPE:-}" == *UTF-8* ||
          "${LC_CTYPE:-}" == *utf8* ]]
    then
        TUI_UNICODE_ENABLED=1
    fi

    return 0
}

tui_update_size()
{
    local rows=""
    local cols=""

    if tui_require_tty
    then
        if command -v tput >/dev/null 2>&1
        then
            rows="$(tput lines <&"$TUI_FD" 2>/dev/null || true)"
            cols="$(tput cols <&"$TUI_FD" 2>/dev/null || true)"
        fi

        if [[ ! "$rows" =~ ^[0-9]+$ ||
              ! "$cols" =~ ^[0-9]+$ ||
              "$rows" -le 0 ||
              "$cols" -le 0 ]]
        then
            read -r rows cols < <(
                stty size <&"$TUI_FD" 2>/dev/null || printf '24 80\n'
            )
        fi
    fi

    [[ "$rows" =~ ^[0-9]+$ ]] || rows=24
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80

    TUI_ROWS="$rows"
    TUI_COLS="$cols"

    return 0
}

#============================================================
# INITIALIZATION
#============================================================

tui_init()
{
    if (( TUI_INITIALIZED ))
    then
        return 0
    fi

    tui_open_terminal || return 1
    tui_save_terminal || {
        tui_close_terminal
        return 1
    }

    tui_update_size
    tui_detect_capabilities

    TUI_INITIALIZED=1

    return 0
}

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
        tui_log_error "TUI: unable to configure terminal input"
        return 1
    fi

    return 0
}

tui_start()
{
    if (( ! TUI_INITIALIZED ))
    then
        tui_init || return 1
    fi

    tui_update_size

    if (( TUI_ROWS < 12 || TUI_COLS < 40 ))
    then
        tui_log_error \
            "TUI: terminal too small (${TUI_COLS}x${TUI_ROWS}), minimum 40x12"
        return 1
    fi

    tui_enable_input || return 1

    if (( ! TUI_ALT_SCREEN ))
    then
        tui_printf '\033[?1049h'
        TUI_ALT_SCREEN=1
    fi

    tui_clear

    tui_printf '\033[?25l'
    TUI_CURSOR_HIDDEN=1

    tui_printf '\033[0m'

    TUI_ACTIVE=1

    return 0
}

tui_abort_start()
{
    tui_restore
    return 0
}

tui_restore()
{
    if (( TUI_FD < 0 ))
    then
        TUI_ACTIVE=0
        TUI_INITIALIZED=0
        return 0
    fi

    if (( TUI_CURSOR_HIDDEN ))
    then
        tui_printf '\033[?25h' 2>/dev/null || true
        TUI_CURSOR_HIDDEN=0
    fi

    tui_printf '\033[0m' 2>/dev/null || true

    if (( TUI_ALT_SCREEN ))
    then
        tui_printf '\033[?1049l' 2>/dev/null || true
        TUI_ALT_SCREEN=0
    fi

    tui_restore_terminal

    TUI_ACTIVE=0
    TUI_INITIALIZED=0

    return 0
}

tui_shutdown()
{
    tui_restore
    tui_close_terminal
    return 0
}

#============================================================
# CURSOR
#============================================================

tui_move()
{
    local row="${1:-1}"
    local col="${2:-1}"

    [[ "$row" =~ ^[0-9]+$ ]] || row=1
    [[ "$col" =~ ^[0-9]+$ ]] || col=1

    (( row < 1 )) && row=1
    (( col < 1 )) && col=1

    tui_printf '\033[%d;%dH' "$row" "$col"

    TUI_CURSOR_ROW="$row"
    TUI_CURSOR_COL="$col"

    return 0
}

cursor_move()
{
    tui_move "$@"
}

tui_cursor_home()
{
    tui_move 1 1
}

tui_cursor_hide()
{
    tui_printf '\033[?25l'
    TUI_CURSOR_HIDDEN=1
}

tui_cursor_show()
{
    tui_printf '\033[?25h'
    TUI_CURSOR_HIDDEN=0
}

#============================================================
# COLORS
#============================================================

tui_color()
{
    local code="${1:-}"
    local text="${2-}"

    if [[ -z "$code" ]]
    then
        tui_log_error "TUI: empty color code"
        return 1
    fi

    if (( TUI_COLOR_ENABLED ))
    then
        tui_printf '\033[%sm%s\033[0m' "$code" "$text"
    else
        tui_print "$text"
    fi
}

color_error()
{
    tui_color '1;31' "$*"
}

color_success()
{
    tui_color '1;32' "$*"
}

color_warning()
{
    tui_color '1;33' "$*"
}

color_info()
{
    tui_color '1;36' "$*"
}

color_title()
{
    tui_color '1;34' "$*"
}

color_selected()
{
    tui_color '1;32' "$*"
}

color_normal()
{
    tui_color '0' "$*"
}

#============================================================
# UNICODE / ASCII
#============================================================

tui_char()
{
    local unicode="${1:-}"
    local ascii="${2:-}"

    if (( TUI_UNICODE_ENABLED ))
    then
        tui_print "$unicode"
    else
        tui_print "$ascii"
    fi
}

tui_hline_char()
{
    tui_char '─' '-'
}

tui_vline_char()
{
    tui_char '│' '|'
}

tui_corner_tl()
{
    tui_char '┌' '+'
}

tui_corner_tr()
{
    tui_char '┐' '+'
}

tui_corner_bl()
{
    tui_char '└' '+'
}

tui_corner_br()
{
    tui_char '┘' '+'
}

#============================================================
# SCREEN
#============================================================

tui_clear()
{
    tui_printf '\033[2J\033[H'
    TUI_CURSOR_ROW=1
    TUI_CURSOR_COL=1
}

screen_clear()
{
    tui_clear
}

screen_prepare()
{
    tui_clear
    tui_cursor_hide
}

screen_refresh()
{
    return 0
}

screen_rows()
{
    printf '%s\n' "${TUI_ROWS:-24}"
}

screen_cols()
{
    printf '%s\n' "${TUI_COLS:-80}"
}

#============================================================
# DRAWING
#============================================================

draw_box()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local height="${3:-3}"
    local width="${4:-20}"
    local title="${5:-}"

    (( height < 2 )) && height=2
    (( width < 2 )) && width=2

    local top=""
    local middle=""
    local bottom=""
    local i

    top="$(printf '%*s' "$(( width - 2 ))" '')"
    top="${top// /─}"

    middle="$(printf '%*s' "$(( width - 2 ))" '')"
    middle="${middle// / }"

    bottom="$top"

    tui_move "$row" "$col"
    tui_char "┌${top}┐" "+${top//─/-}+"

    if [[ -n "$title" && "$width" -gt 6 ]]
    then
        local title_text=" $title "
        local title_len="${#title_text}"

        if (( title_len < width - 2 ))
        then
            local left=$(( (width - 2 - title_len) / 2 ))
            local right=$(( width - 2 - title_len - left ))

            tui_move "$row" "$col"
            tui_print "┌"
            printf '%*s' "$left" '' | tr ' ' '─'
            color_title "$title_text"
            printf '%*s' "$right" '' | tr ' ' '─'
            tui_print "┐"
        fi
    fi

    for (( i=1; i<height-1; i++ ))
    do
        tui_move "$(( row + i ))" "$col"
        tui_char '│' '|'

        tui_move "$(( row + i ))" "$(( col + width - 1 ))"
        tui_char '│' '|'
    done

    tui_move "$(( row + height - 1 ))" "$col"
    tui_char "└${bottom}┘" "+${bottom//─/-}+"

    return 0
}

widget_box()
{
    draw_box "$@"
}

draw_panel()
{
    draw_box "$@"
}

titlebar_draw()
{
    local title="${1:-Arch Installer}"
    local width="${TUI_COLS:-80}"

    tui_move 1 1

    local line
    line="$(printf '%*s' "$width" '')"
    line="${line// / }"

    tui_printf '\033[0m'
    tui_printf '%s' "$line"

    tui_move 1 3
    color_title " $title "

    return 0
}

statusbar_draw()
{
    local text="${1:-}"
    local row="${TUI_ROWS:-24}"
    local width="${TUI_COLS:-80}"

    tui_move "$row" 1

    local line
    line="$(printf '%*s' "$width" '')"

    tui_print "$line"

    tui_move "$row" 2
    tui_print "$text"

    return 0
}

tui_text()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local text="${3-}"

    tui_move "$row" "$col"
    tui_print "$text"
}

#============================================================
# KEYBOARD EVENT PARSER
#============================================================

event_read_csi()
{
    local sequence=""
    local ch=""
    local rc=0

    while IFS= read -r -s -n 1 -t "$TUI_ESCAPE_TIMEOUT" ch <&"$TUI_FD"
    do
        sequence+="$ch"

        case "$ch" in
            [A-Za-z~])
                break
                ;;
        esac
    done

    case "$sequence" in
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

        1~|7~)
            TUI_EVENT="$EVENT_HOME"
            ;;

        4~|8~)
            TUI_EVENT="$EVENT_END"
            ;;

        2~)
            TUI_EVENT="$EVENT_INSERT"
            ;;

        3~)
            TUI_EVENT="$EVENT_DELETE"
            ;;

        5~)
            TUI_EVENT="$EVENT_PAGE_UP"
            ;;

        6~)
            TUI_EVENT="$EVENT_PAGE_DOWN"
            ;;

        11~)
            TUI_EVENT="$EVENT_F1"
            ;;

        12~)
            TUI_EVENT="$EVENT_F2"
            ;;

        13~)
            TUI_EVENT="$EVENT_F3"
            ;;

        14~)
            TUI_EVENT="$EVENT_F4"
            ;;

        15~)
            TUI_EVENT="$EVENT_F5"
            ;;

        17~)
            TUI_EVENT="$EVENT_F6"
            ;;

        18~)
            TUI_EVENT="$EVENT_F7"
            ;;

        19~)
            TUI_EVENT="$EVENT_F8"
            ;;

        20~)
            TUI_EVENT="$EVENT_F9"
            ;;

        21~)
            TUI_EVENT="$EVENT_F10"
            ;;

        23~)
            TUI_EVENT="$EVENT_F11"
            ;;

        24~)
            TUI_EVENT="$EVENT_F12"
            ;;

        1;*A)
            TUI_EVENT="$EVENT_UP"
            ;;

        1;*B)
            TUI_EVENT="$EVENT_DOWN"
            ;;

        1;*C)
            TUI_EVENT="$EVENT_RIGHT"
            ;;

        1;*D)
            TUI_EVENT="$EVENT_LEFT"
            ;;

        "")
            TUI_EVENT="$EVENT_BACK"
            ;;

        *)
            TUI_EVENT="$EVENT_NONE"
            ;;
    esac

    return "$rc"
}

event_read()
{
    local key=""
    local next=""
    local rc=0

    TUI_EVENT="$EVENT_NONE"
    TUI_EVENT_CHAR=""

    tui_require_tty || return 1

    if ! IFS= read -r -s -n 1 key <&"$TUI_FD"
    then
        return 1
    fi

    case "$key" in

        $'\e')
            #
            # ESC is ambiguous:
            #   ESC alone      -> BACK
            #   ESC [ ...      -> CSI sequence
            #   ESC O ...      -> SS3 sequence
            #
            if IFS= read -r -s -n 1 -t "$TUI_ESCAPE_TIMEOUT" next <&"$TUI_FD"
            then
                case "$next" in

                    "[")
                        event_read_csi
                        ;;

                    "O")
                        if IFS= read -r -s -n 1 -t "$TUI_ESCAPE_TIMEOUT" next <&"$TUI_FD"
                        then
                            case "$next" in
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
            else
                #
                # No second byte arrived.
                # Therefore this is a real standalone ESC.
                #
                TUI_EVENT="$EVENT_BACK"
            fi
            ;;

        $'\n'|$'\r')
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

    return "$rc"
}

tui_input()
{
    event_read
}

#============================================================
# DIALOGS
#============================================================

dialog_message()
{
    local title="${1:-Message}"
    local message="${2:-}"

    tui_update_size

    local width=$(( TUI_COLS - 10 ))
    local height=8

    (( width < 30 )) && width=30
    (( width > 70 )) && width=70

    draw_box \
        "$(( (TUI_ROWS - height) / 2 ))" \
        "$(( (TUI_COLS - width) / 2 ))" \
        "$height" \
        "$width" \
        "$title"

    local row=$(( (TUI_ROWS - height) / 2 + 2 ))
    local col=$(( (TUI_COLS - width) / 2 + 3 ))

    tui_move "$row" "$col"
    tui_print "$message"

    tui_move "$(( row + height - 3 ))" "$col"
    color_info "Press Enter to continue"

    while true
    do
        if ! event_read
        then
            return 1
        fi

        case "${TUI_EVENT:-}" in
            "$EVENT_SELECT"|"$EVENT_BACK")
                return 0
                ;;
        esac
    done
}

dialog_info()
{
    local title="${1:-Information}"
    local message="${2:-}"

    dialog_message "$title" "$message"
}

dialog_warning()
{
    local title="${1:-Warning}"
    local message="${2:-}"

    tui_log_warn "$message"
    dialog_message "$title" "$message"
}

dialog_error()
{
    local title="Error"
    local message="${1:-Unknown error}"

    #
    # Compatible with both:
    #
    #   dialog_error "message"
    #
    # and:
    #
    #   dialog_error "title" "message"
    #
    if (( $# >= 2 ))
    then
        title="${1:-Error}"
        message="${2:-Unknown error}"
    fi

    tui_log_error "$message"

    dialog_message \
        "$title" \
        "$message"
}

dialog_confirm()
{
    local message="${1:-Are you sure?}"

    tui_update_size

    local width=$(( TUI_COLS - 10 ))
    local height=8

    (( width < 36 )) && width=36
    (( width > 70 )) && width=70

    local top=$(( (TUI_ROWS - height) / 2 ))
    local left=$(( (TUI_COLS - width) / 2 ))

    draw_box \
        "$top" \
        "$left" \
        "$height" \
        "$width" \
        "Confirm"

    tui_move "$(( top + 2 ))" "$(( left + 3 ))"
    tui_print "$message"

    tui_move "$(( top + height - 3 ))" "$(( left + 3 ))"
    color_success "[Enter] Yes"

    tui_move "$(( top + height - 2 ))" "$(( left + 3 ))"
    color_warning "[Esc] No"

    while true
    do
        if ! event_read
        then
            return 1
        fi

        case "${TUI_EVENT:-}" in
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
# MENU
#============================================================

tui_menu()
{
    local title="${1:-Menu}"
    local selected="${2:-0}"
    shift 2 || true

    local items=( "$@" )
    local item_count="${#items[@]}"

    (( item_count == 0 )) && return 1

    (( selected < 0 )) && selected=0
    (( selected >= item_count )) && selected=$(( item_count - 1 ))

    while true
    do
        tui_clear

        titlebar_draw "$title"

        local i
        local row=4

        for (( i=0; i<item_count; i++ ))
        do
            tui_move "$row" 5

            if (( i == selected ))
            then
                color_selected "> ${items[i]}"
            else
                tui_print "  ${items[i]}"
            fi

            (( row++ ))
        done

        statusbar_draw \
            "↑↓ Navigate   Enter Select   Esc Back"

        if ! event_read
        then
            return 1
        fi

        case "${TUI_EVENT:-}" in

            "$EVENT_UP")
                (( selected > 0 )) && (( selected-- ))
                ;;

            "$EVENT_DOWN")
                (( selected < item_count - 1 )) && (( selected++ ))
                ;;

            "$EVENT_HOME")
                selected=0
                ;;

            "$EVENT_END")
                selected=$(( item_count - 1 ))
                ;;

            "$EVENT_SELECT")
                TUI_MENU_SELECTED="$selected"
                TUI_MENU_RESULT="${items[selected]}"
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

tui_menu_get_selected()
{
    printf '%s\n' "${TUI_MENU_SELECTED:-0}"
}

tui_menu_get_result()
{
    printf '%s\n' "${TUI_MENU_RESULT:-}"
}

#============================================================
# PROGRESS
#============================================================

progress_init()
{
    local max="${1:-100}"

    [[ "$max" =~ ^[0-9]+$ ]] || max=100
    (( max <= 0 )) && max=100

    TUI_PROGRESS_MAX="$max"
    TUI_PROGRESS_VALUE=0

    return 0
}

progress_update()
{
    local value="${1:-0}"
    local message="${2:-}"

    [[ "$value" =~ ^[0-9]+$ ]] || value=0

    (( value < 0 )) && value=0
    (( value > TUI_PROGRESS_MAX )) && value="$TUI_PROGRESS_MAX"

    TUI_PROGRESS_VALUE="$value"

    tui_update_size

    local width=$(( TUI_COLS - 10 ))
    (( width < 30 )) && width=30

    local row=$(( TUI_ROWS / 2 ))
    local col=$(( (TUI_COLS - width) / 2 ))

    tui_move "$row" "$col"

    local percent=0

    if (( TUI_PROGRESS_MAX > 0 ))
    then
        percent=$(( value * 100 / TUI_PROGRESS_MAX ))
    fi

    local bar_width=$(( width - 10 ))
    (( bar_width < 10 )) && bar_width=10

    local filled=$(( percent * bar_width / 100 ))
    local empty=$(( bar_width - filled ))

    local bar=""

    if (( filled > 0 ))
    then
        bar="$(printf '%*s' "$filled" '')"
        bar="${bar// /#}"
    fi

    if (( empty > 0 ))
    then
        local rest
        rest="$(printf '%*s' "$empty" '')"
        rest="${rest// /-}"
        bar+="$rest"
    fi

    tui_print "[${bar}] ${percent}%"

    if [[ -n "$message" ]]
    then
        tui_move "$(( row + 2 ))" "$col"
        tui_print "$message"
    fi

    return 0
}

progress_finish()
{
    local message="${1:-Complete}"

    progress_update \
        "${TUI_PROGRESS_MAX:-100}" \
        "$message"

    return 0
}

# Compatibility aliases.

tui_progress_init()
{
    progress_init "$@"
}

tui_progress_update()
{
    progress_update "$@"
}

tui_progress_finish()
{
    progress_finish "$@"
}

#============================================================
# TERMINAL TITLE
#============================================================

tui_set_title()
{
    local title="${1:-Arch Installer}"

    tui_printf '\033]0;%s\007' "$title"
}

tui_terminal_title()
{
    tui_set_title "$@"
}

#============================================================
# EXIT / SIGNAL SAFETY
#============================================================

tui_on_exit()
{
    tui_restore
}

tui_on_signal()
{
    tui_restore
}

# Do not install traps here.
#
# The main controller owns global signal handling.
# Installing traps from a library can interfere with
# install.sh and installer.sh.
#
#============================================================
# END OF lib/tui.sh
#============================================================
```
