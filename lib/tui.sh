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
EVENT_INSERT="INSERT"

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
        if tty <&"$TUI_FD" >/dev/null 2>&1
        then
            return 0
        fi

        TUI_FD=-1
    fi

    if [[ ! -e "$TUI_TTY" ]]
    then
        tui_log_error \
            "TUI: terminal device not found: $TUI_TTY"

        return 1
    fi

    if ! exec {TUI_FD}<>"$TUI_TTY"
    then
        TUI_FD=-1

        tui_log_error \
            "TUI: cannot open terminal: $TUI_TTY"

        return 1
    fi

    if ! tty <&"$TUI_FD" >/dev/null 2>&1
    then
        tui_log_error \
            "TUI: opened device is not a TTY"

        exec {TUI_FD}>&- 2>/dev/null || true
        exec {TUI_FD}<&- 2>/dev/null || true

        TUI_FD=-1

        return 1
    fi

    return 0
}

tui_close_terminal()
{
    local fd="${TUI_FD:--1}"

    if (( fd >= 0 ))
    then
        exec {fd}>&- 2>/dev/null || true
        exec {fd}<&- 2>/dev/null || true
    fi

    TUI_FD=-1

    return 0
}

tui_require_tty()
{
    if (( TUI_FD < 0 ))
    then
        tui_open_terminal || return 1
    fi

    if ! tty <&"$TUI_FD" >/dev/null 2>&1
    then
        tui_log_error \
            "TUI: terminal FD is not a TTY"

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

    local format="${1:-}"

    shift || true

    printf "$format" "$@" >&"$TUI_FD"
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

    local state=""

    if ! state="$(stty -g <&"$TUI_FD" 2>/dev/null)"
    then
        tui_log_error \
            "TUI: unable to save terminal state"

        return 1
    fi

    if [[ -z "$state" ]]
    then
        tui_log_error \
            "TUI: saved terminal state is empty"

        return 1
    fi

    TUI_STTY_STATE="$state"
    TUI_STTY_SAVED=1

    return 0
}

tui_restore_terminal()
{
    local fd="${TUI_FD:--1}"

    #
    # First try exact restoration using the TUI FD.
    #
    if (( fd >= 0 ))
    then
        if (( TUI_STTY_SAVED )) &&
           [[ -n "${TUI_STTY_STATE:-}" ]]
        then
            if stty "$TUI_STTY_STATE" <&"$fd" 2>/dev/null
            then
                TUI_STTY_SAVED=0
                TUI_STTY_STATE=""
                return 0
            fi
        fi

        #
        # Fallback for the current TUI FD.
        #
        stty sane <&"$fd" 2>/dev/null || true
    fi

    #
    # Mandatory fallback through /dev/tty.
    #
    # This is important if TUI_FD is already invalid
    # or was closed unexpectedly.
    #
    if [[ -e /dev/tty ]]
    then
        if (( TUI_STTY_SAVED )) &&
           [[ -n "${TUI_STTY_STATE:-}" ]]
        then
            if ! stty "$TUI_STTY_STATE" </dev/tty 2>/dev/null
            then
                stty sane </dev/tty 2>/dev/null || true
            fi
        else
            stty sane </dev/tty 2>/dev/null || true
        fi
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
                stty size <&"$TUI_FD" 2>/dev/null ||
                printf '24 80\n'
            )
        fi
    fi

    [[ "$rows" =~ ^[0-9]+$ ]] || rows=24
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80

    (( rows > 0 )) || rows=24
    (( cols > 0 )) || cols=80

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

    #
    # Save the real terminal state BEFORE modifying stty.
    #
    if ! tui_save_terminal
    then
        tui_close_terminal
        return 1
    fi

    tui_update_size
    tui_detect_capabilities

    TUI_INITIALIZED=1
    TUI_ACTIVE=0
    TUI_ALT_SCREEN=0
    TUI_CURSOR_HIDDEN=0

    return 0
}

tui_enable_input()
{
    tui_require_tty || return 1

    #
    # Minimal terminal modification:
    #   -echo
    #   -echonl
    #   -icanon
    #   -ixon
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
            "TUI: unable to configure terminal input"

        return 1
    fi

    return 0
}

tui_disable_input()
{
    tui_restore_terminal
    return 0
}

#============================================================
# TUI START
#============================================================

tui_start()
{
    tui_log_info "TUI_START: enter"

    if (( ! TUI_INITIALIZED ))
    then
        tui_log_info "TUI_START: calling tui_init"

        if ! tui_init
        then
            tui_log_error "TUI_START: tui_init failed"
            return 1
        fi

        tui_log_info "TUI_START: tui_init OK"
    fi

    tui_log_info "TUI_START: TUI_FD=${TUI_FD}"

    if ! tui_require_tty
    then
        tui_log_error "TUI_START: tui_require_tty failed"
        tui_restore
        return 1
    fi

    tui_log_info "TUI_START: TTY OK"

    tui_update_size

    tui_log_info \
        "TUI_START: size=${TUI_COLS}x${TUI_ROWS}"

    if (( TUI_ROWS < 12 || TUI_COLS < 40 ))
    then
        tui_log_error \
            "TUI: terminal too small (${TUI_COLS}x${TUI_ROWS}), minimum 40x12"

        tui_restore
        return 1
    fi

    tui_log_info "TUI_START: enabling input"

    if ! tui_enable_input
    then
        tui_log_error "TUI_START: tui_enable_input failed"
        tui_restore
        return 1
    fi

    tui_log_info "TUI_START: input enabled"

    if (( ! TUI_ALT_SCREEN ))
    then
        tui_log_info "TUI_START: entering alternate screen"

        if ! tui_printf '\033[?1049h'
        then
            tui_log_error \
                "TUI: unable to enter alternate screen"

            tui_restore
            return 1
        fi

        TUI_ALT_SCREEN=1

        tui_log_info "TUI_START: alternate screen OK"
    fi

    if ! tui_clear
    then
        tui_log_error \
            "TUI: unable to clear screen"

        tui_restore
        return 1
    fi

    tui_log_info "TUI_START: screen cleared"

    if ! tui_printf '\033[?25l'
    then
        tui_log_error \
            "TUI: unable to hide cursor"

        tui_restore
        return 1
    fi

    TUI_CURSOR_HIDDEN=1

    tui_printf '\033[0m' || true

    TUI_ACTIVE=1

    tui_log_info "TUI_START: complete"

    return 0
}
#============================================================
# TUI ABORT
#============================================================

tui_abort_start()
{
    tui_restore
    return 0
}

#============================================================
# TUI RESTORE
#============================================================

tui_restore()
{
    local fd="${TUI_FD:--1}"

    #
    # Restore terminal input mode FIRST.
    #
    tui_restore_terminal || true

    #
    # Restore terminal screen using TUI FD.
    #
    if (( fd >= 0 ))
    then
        printf '\033[0m' >&"$fd" 2>/dev/null || true
        printf '\033[?25h' >&"$fd" 2>/dev/null || true

        TUI_CURSOR_HIDDEN=0

        if (( TUI_ALT_SCREEN ))
        then
            printf '\033[?1049l' >&"$fd" 2>/dev/null || true
            TUI_ALT_SCREEN=0
        fi

        printf '\033[0m' >&"$fd" 2>/dev/null || true
        printf '\033[H' >&"$fd" 2>/dev/null || true
    fi

    #
    # Always perform a final screen reset through /dev/tty.
    #
    # This protects against a broken or closed TUI_FD.
    #
    if [[ -e /dev/tty ]]
    then
        printf '\033[0m' >/dev/tty 2>/dev/null || true
        printf '\033[?25h' >/dev/tty 2>/dev/null || true
        printf '\033[?1049l' >/dev/tty 2>/dev/null || true
        printf '\033[0m\033[H' >/dev/tty 2>/dev/null || true

        #
        # Last-resort terminal recovery.
        #
        stty sane </dev/tty 2>/dev/null || true
    fi

    TUI_ACTIVE=0
    TUI_INITIALIZED=0
    TUI_ALT_SCREEN=0
    TUI_CURSOR_HIDDEN=0

    return 0
}

#============================================================
# SHUTDOWN
#============================================================

tui_shutdown()
{
    tui_restore || true
    tui_close_terminal || true

    TUI_ACTIVE=0
    TUI_INITIALIZED=0
    TUI_ALT_SCREEN=0
    TUI_CURSOR_HIDDEN=0

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

    tui_printf '\033[%d;%dH' "$row" "$col" || return 1

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
    tui_printf '\033[?25l' || return 1

    TUI_CURSOR_HIDDEN=1

    return 0
}

tui_cursor_show()
{
    tui_printf '\033[?25h' || return 1

    TUI_CURSOR_HIDDEN=0

    return 0
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
        tui_log_error \
            "TUI: empty color code"

        return 1
    fi

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
    tui_printf '\033[2J\033[H' || return 1

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
    tui_clear || return 1
    tui_cursor_hide || return 1

    return 0
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
    local bottom=""
    local i

    top="$(printf '%*s' "$(( width - 2 ))" '')"
    top="${top// /─}"

    bottom="$top"

    #
    # Top border.
    #
    tui_move "$row" "$col" || return 1

    tui_char \
        "┌${top}┐" \
        "+${top//─/-}+" || return 1

    #
    # Optional title.
    #
    if [[ -n "$title" && "$width" -gt 6 ]]
    then
        local title_text=" $title "
        local title_len="${#title_text}"

        if (( title_len < width - 2 ))
        then
            local left=$(( (width - 2 - title_len) / 2 ))
            local right=$(( width - 2 - title_len - left ))

            tui_move "$row" "$col" || return 1

            tui_print "┌" || return 1

            if (( left > 0 ))
            then
                printf '%*s' "$left" '' |
                    tr ' ' '─' >&"$TUI_FD"
            fi

            color_title "$title_text" || return 1

            if (( right > 0 ))
            then
                printf '%*s' "$right" '' |
                    tr ' ' '─' >&"$TUI_FD"
            fi

            tui_print "┐" || return 1
        fi
    fi

    #
    # Vertical borders.
    #
    for (( i=1; i<height-1; i++ ))
    do
        tui_move \
            "$(( row + i ))" \
            "$col" || return 1

        tui_char '│' '|' || return 1

        tui_move \
            "$(( row + i ))" \
            "$(( col + width - 1 ))" || return 1

        tui_char '│' '|' || return 1
    done

    #
    # Bottom border.
    #
    tui_move \
        "$(( row + height - 1 ))" \
        "$col" || return 1

    tui_char \
        "└${bottom}┘" \
        "+${bottom//─/-}+" || return 1

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

    tui_move 1 1 || return 1

    local line

    line="$(printf '%*s' "$width" '')"

    tui_printf '\033[0m' || return 1
    tui_print "$line" || return 1

    tui_move 1 3 || return 1

    color_title " $title " || return 1

    return 0
}

statusbar_draw()
{
    local text="${1:-}"
    local row="${TUI_ROWS:-24}"
    local width="${TUI_COLS:-80}"

    tui_move "$row" 1 || return 1

    local line

    line="$(printf '%*s' "$width" '')"

    tui_print "$line" || return 1

    tui_move "$row" 2 || return 1

    tui_print "$text" || return 1

    return 0
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
# KEYBOARD EVENT PARSER
#============================================================

event_read_csi()
{
    local sequence=""
    local ch=""

    while IFS= read \
        -r \
        -s \
        -n 1 \
        -t "$TUI_ESCAPE_TIMEOUT" \
        ch <&"$TUI_FD"
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

        '1;*A')
            TUI_EVENT="$EVENT_UP"
            ;;

        '1;*B')
            TUI_EVENT="$EVENT_DOWN"
            ;;

        '1;*C')
            TUI_EVENT="$EVENT_RIGHT"
            ;;

        '1;*D')
            TUI_EVENT="$EVENT_LEFT"
            ;;

        "")
            TUI_EVENT="$EVENT_BACK"
            ;;

        *)
            TUI_EVENT="$EVENT_NONE"
            ;;
    esac

    return 0
}

event_read()
{
    local key=""
    local next=""

    TUI_EVENT="$EVENT_NONE"
    TUI_EVENT_CHAR=""

    tui_require_tty || return 1

    #--------------------------------------------------------
    # Read one key.
    #
    # IMPORTANT:
    #
    # With bash `read -n 1`, pressing Enter can produce an
    # empty value because newline is treated as delimiter.
    #
    # Therefore empty "$key" MUST be interpreted as ENTER.
    #--------------------------------------------------------

    if ! IFS= read \
        -r \
        -s \
        -n 1 \
        key <&"$TUI_FD"
    then
        return 1
    fi

    case "$key"
    in

        #----------------------------------------------------
        # ENTER
        #
        # Bash read -n 1 may return an empty key for newline.
        #----------------------------------------------------

        "")
            TUI_EVENT="$EVENT_SELECT"
            ;;

        #----------------------------------------------------
        # ESC
        #----------------------------------------------------

        $'\e')
            #
            # ESC can be:
            #
            #   ESC
            #   ESC [ ...
            #   ESC O ...
            #

            if IFS= read \
                -r \
                -s \
                -n 1 \
                -t "$TUI_ESCAPE_TIMEOUT" \
                next <&"$TUI_FD"
            then
                case "$next"
                in

                    "[")
                        event_read_csi
                        ;;

                    "O")
                        if IFS= read \
                            -r \
                            -s \
                            -n 1 \
                            -t "$TUI_ESCAPE_TIMEOUT" \
                            next <&"$TUI_FD"
                        then
                            case "$next"
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

                    *)
                        TUI_EVENT="$EVENT_NONE"
                        ;;
                esac
            else
                # Standalone ESC = Back
                TUI_EVENT="$EVENT_BACK"
            fi
            ;;

        #----------------------------------------------------
        # ENTER / NEWLINE
        #----------------------------------------------------

        $'\n'|$'\r')
            TUI_EVENT="$EVENT_SELECT"
            ;;

        #----------------------------------------------------
        # SPACE
        #----------------------------------------------------

        " ")
            TUI_EVENT="$EVENT_SPACE"
            ;;

        #----------------------------------------------------
        # TAB
        #----------------------------------------------------

        $'\t')
            TUI_EVENT="$EVENT_TAB"
            ;;

        #----------------------------------------------------
        # BACKSPACE
        #----------------------------------------------------

        $'\177'|$'\b')
            TUI_EVENT="$EVENT_DELETE"
            ;;

        #----------------------------------------------------
        # ORDINARY CHARACTER
        #----------------------------------------------------

        *)
            TUI_EVENT="$EVENT_CHAR"
            TUI_EVENT_CHAR="$key"
            ;;
    esac

    return 0
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

    local top=$(( (TUI_ROWS - height) / 2 ))
    local left=$(( (TUI_COLS - width) / 2 ))

    (( top < 1 )) && top=1
    (( left < 1 )) && left=1

    draw_box \
        "$top" \
        "$left" \
        "$height" \
        "$width" \
        "$title" || return 1

    local row=$(( top + 2 ))
    local col=$(( left + 3 ))

    tui_move "$row" "$col" || return 1
    tui_print "$message" || return 1

    tui_move \
        "$(( row + height - 3 ))" \
        "$col" || return 1

    color_info "Press Enter to continue" || return 1

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

    dialog_message \
        "$title" \
        "$message"
}

dialog_warning()
{
    local title="${1:-Warning}"
    local message="${2:-}"

    tui_log_warn "$message"

    dialog_message \
        "$title" \
        "$message"
}

dialog_error()
{
    local title="Error"
    local message="${1:-Unknown error}"

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

    (( top < 1 )) && top=1
    (( left < 1 )) && left=1

    draw_box \
        "$top" \
        "$left" \
        "$height" \
        "$width" \
        "Confirm" || return 1

    tui_move \
        "$(( top + 2 ))" \
        "$(( left + 3 ))" || return 1

    tui_print "$message" || return 1

    tui_move \
        "$(( top + height - 3 ))" \
        "$(( left + 3 ))" || return 1

    color_success "[Enter] Yes" || return 1

    tui_move \
        "$(( top + height - 2 ))" \
        "$(( left + 3 ))" || return 1

    color_warning "[Esc] No" || return 1

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

    if (( item_count == 0 ))
    then
        return 1
    fi

    [[ "$selected" =~ ^[0-9]+$ ]] || selected=0

    (( selected < 0 )) && selected=0

    if (( selected >= item_count ))
    then
        selected=$(( item_count - 1 ))
    fi

    while true
    do
        tui_clear || return 1

        titlebar_draw "$title" || return 1

        local i
        local row=4

        for (( i=0; i<item_count; i++ ))
        do
            tui_move "$row" 5 || return 1

            if (( i == selected ))
            then
                color_selected \
                    "> ${items[i]}" || return 1
            else
                tui_print \
                    "  ${items[i]}" || return 1
            fi

            row=$(( row + 1 ))
        done

        statusbar_draw \
            "↑↓ Navigate   Enter Select   Esc Back" ||
            return 1

        if ! event_read
        then
            return 1
        fi

        case "${TUI_EVENT:-}" in

            "$EVENT_UP")
                if (( selected > 0 ))
                then
                    selected=$(( selected - 1 ))
                fi
                ;;

            "$EVENT_DOWN")
                if (( selected < item_count - 1 ))
                then
                    selected=$(( selected + 1 ))
                fi
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

    if (( value > TUI_PROGRESS_MAX ))
    then
        value="$TUI_PROGRESS_MAX"
    fi

    TUI_PROGRESS_VALUE="$value"

    tui_update_size

    local width=$(( TUI_COLS - 10 ))

    (( width < 30 )) && width=30

    local row=$(( TUI_ROWS / 2 ))
    local col=$(( (TUI_COLS - width) / 2 ))

    (( row < 1 )) && row=1
    (( col < 1 )) && col=1

    tui_move "$row" "$col" || return 1

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
        local rest=""

        rest="$(printf '%*s' "$empty" '')"
        rest="${rest// /-}"

        bar+="$rest"
    fi

    tui_print \
        "[${bar}] ${percent}%" || return 1

    if [[ -n "$message" ]]
    then
        tui_move \
            "$(( row + 2 ))" \
            "$col" || return 1

        tui_print "$message" || return 1
    fi

    return 0
}

progress_finish()
{
    local message="${1:-Complete}"

    progress_update \
        "${TUI_PROGRESS_MAX:-100}" \
        "$message"
}

#============================================================
# COMPATIBILITY PROGRESS ALIASES
#============================================================

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

#============================================================
# END OF lib/tui.sh
#============================================================
