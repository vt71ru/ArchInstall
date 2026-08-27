#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# events.sh
#
# Обработка событий клавиатуры.
#
# Ответственность:
#  • Чтение управляющих последовательностей терминала
#  • Распознавание клавиш
#  • Преобразование клавиш в EVENT_*
#
# Не содержит:
#  • Логику меню
#  • Логику installer
#============================================================

[[ -n "${EVENTS_SH_LOADED:-}" ]] && return

readonly EVENTS_SH_LOADED=1

#------------------------------------------------------------
# Events
#------------------------------------------------------------

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

#------------------------------------------------------------
# Timing
#------------------------------------------------------------

readonly EVENT_ESCAPE_TIMEOUT="${EVENT_ESCAPE_TIMEOUT:-0.08}"

#------------------------------------------------------------
# Read escape sequence
#------------------------------------------------------------

event_read_escape()
{
    local sequence=""
    local byte=""

    if ! IFS= read \
        -rsn1 \
        -t "$EVENT_ESCAPE_TIMEOUT" \
        byte
    then
        printf '%s' \
            "$EVENT_BACK"

        return 0
    fi

    sequence+="$byte"

    case "$sequence" in
        "[")
            event_read_csi
            ;;
        "O")
            event_read_ss3
            ;;
        *)
            printf '%s' \
                "$EVENT_NONE"
            ;;
    esac
}

#------------------------------------------------------------
# Read CSI sequence
#------------------------------------------------------------

event_read_csi()
{
    local sequence="["
    local byte=""

    while true
    do
        if ! IFS= read \
            -rsn1 \
            -t "$EVENT_ESCAPE_TIMEOUT" \
            byte
        then
            printf '%s' \
                "$EVENT_BACK"

            return 0
        fi

        sequence+="$byte"

        case "$byte" in
            A|B|C|D|H|F|Z)
                break
                ;;
            "~")
                break
                ;;
        esac

        if (( ${#sequence} >= 16 ))
        then
            printf '%s' \
                "$EVENT_NONE"

            return 0
        fi
    done

    case "$sequence" in
        "[A")
            printf '%s' \
                "$EVENT_UP"
            ;;
        "[B")
            printf '%s' \
                "$EVENT_DOWN"
            ;;
        "[C")
            printf '%s' \
                "$EVENT_RIGHT"
            ;;
        "[D")
            printf '%s' \
                "$EVENT_LEFT"
            ;;
        "[H")
            printf '%s' \
                "$EVENT_HOME"
            ;;
        "[F")
            printf '%s' \
                "$EVENT_END"
            ;;
        "[Z")
            printf '%s' \
                "$EVENT_TAB_BACK"
            ;;
        "[1~")
            printf '%s' \
                "$EVENT_HOME"
            ;;
        "[2~")
            printf '%s' \
                "$EVENT_NONE"
            ;;
        "[3~")
            printf '%s' \
                "$EVENT_DELETE"
            ;;
        "[4~")
            printf '%s' \
                "$EVENT_END"
            ;;
        "[5~")
            printf '%s' \
                "$EVENT_PAGE_UP"
            ;;
        "[6~")
            printf '%s' \
                "$EVENT_PAGE_DOWN"
            ;;
        "[7~")
            printf '%s' \
                "$EVENT_HOME"
            ;;
        "[8~")
            printf '%s' \
                "$EVENT_END"
            ;;
        "[11~")
            printf '%s' \
                "$EVENT_F1"
            ;;
        "[12~")
            printf '%s' \
                "$EVENT_F2"
            ;;
        "[13~")
            printf '%s' \
                "$EVENT_F3"
            ;;
        "[14~")
            printf '%s' \
                "$EVENT_F4"
            ;;
        "[15~")
            printf '%s' \
                "$EVENT_F5"
            ;;
        "[17~")
            printf '%s' \
                "$EVENT_F6"
            ;;
        "[18~")
            printf '%s' \
                "$EVENT_F7"
            ;;
        "[19~")
            printf '%s' \
                "$EVENT_F8"
            ;;
        "[20~")
            printf '%s' \
                "$EVENT_F9"
            ;;
        "[21~")
            printf '%s' \
                "$EVENT_F10"
            ;;
        "[23~")
            printf '%s' \
                "$EVENT_F11"
            ;;
        "[24~")
            printf '%s' \
                "$EVENT_F12"
            ;;
        *)
            case "$sequence" in
                "[1;5A"|"[1;2A")
                    printf '%s' \
                        "$EVENT_UP"
                    ;;
                "[1;5B"|"[1;2B")
                    printf '%s' \
                        "$EVENT_DOWN"
                    ;;
                "[1;5C"|"[1;2C")
                    printf '%s' \
                        "$EVENT_RIGHT"
                    ;;
                "[1;5D"|"[1;2D")
                    printf '%s' \
                        "$EVENT_LEFT"
                    ;;
                *)
                    printf '%s' \
                        "$EVENT_NONE"
                    ;;
            esac
            ;;
    esac
}

#------------------------------------------------------------
# Read SS3 sequence
#------------------------------------------------------------

event_read_ss3()
{
    local key=""

    if ! IFS= read \
        -rsn1 \
        -t "$EVENT_ESCAPE_TIMEOUT" \
        key
    then
        printf '%s' \
            "$EVENT_BACK"

        return 0
    fi

    case "$key" in
        A)
            printf '%s' \
                "$EVENT_UP"
            ;;
        B)
            printf '%s' \
                "$EVENT_DOWN"
            ;;
        C)
            printf '%s' \
                "$EVENT_RIGHT"
            ;;
        D)
            printf '%s' \
                "$EVENT_LEFT"
            ;;
        H)
            printf '%s' \
                "$EVENT_HOME"
            ;;
        F)
            printf '%s' \
                "$EVENT_END"
            ;;
        P)
            printf '%s' \
                "$EVENT_F1"
            ;;
        Q)
            printf '%s' \
                "$EVENT_F2"
            ;;
        R)
            printf '%s' \
                "$EVENT_F3"
            ;;
        S)
            printf '%s' \
                "$EVENT_F4"
            ;;
        *)
            printf '%s' \
                "$EVENT_NONE"
            ;;
    esac
}

#------------------------------------------------------------
# Read event
#------------------------------------------------------------

event_read()
{
    local key=""

    if ! IFS= read \
        -rsn1 \
        key
    then
        printf '%s' \
            "$EVENT_BACK"

        return 0
    fi

    case "$key" in
        $'\e')
            event_read_escape
            ;;
        "")
            printf '%s' \
                "$EVENT_SELECT"
            ;;
        " ")
            printf '%s' \
                "$EVENT_SPACE"
            ;;
        $'\t')
            printf '%s' \
                "$EVENT_TAB"
            ;;
        $'\177'|$'\b')
            printf '%s' \
                "$EVENT_DELETE"
            ;;
        q|Q)
            printf '%s' \
                "$EVENT_BACK"
            ;;
        *)
            printf '%s' \
                "$EVENT_NONE"
            ;;
    esac
}

#------------------------------------------------------------
# Event predicates
#------------------------------------------------------------

event_is_navigation()
{
    case "${1:-}" in
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

event_is_up()
{
    [[ "${1:-}" == "$EVENT_UP" ]]
}

event_is_down()
{
    [[ "${1:-}" == "$EVENT_DOWN" ]]
}

event_is_left()
{
    [[ "${1:-}" == "$EVENT_LEFT" ]]
}

event_is_right()
{
    [[ "${1:-}" == "$EVENT_RIGHT" ]]
}

event_is_home()
{
    [[ "${1:-}" == "$EVENT_HOME" ]]
}

event_is_end()
{
    [[ "${1:-}" == "$EVENT_END" ]]
}

event_is_page_up()
{
    [[ "${1:-}" == "$EVENT_PAGE_UP" ]]
}

event_is_page_down()
{
    [[ "${1:-}" == "$EVENT_PAGE_DOWN" ]]
}

event_is_delete()
{
    [[ "${1:-}" == "$EVENT_DELETE" ]]
}

event_is_f1()
{
    [[ "${1:-}" == "$EVENT_F1" ]]
}

event_is_f2()
{
    [[ "${1:-}" == "$EVENT_F2" ]]
}

event_is_help()
{
    [[ "${1:-}" == "$EVENT_F1" ||
       "${1:-}" == "$EVENT_HELP" ]]
}