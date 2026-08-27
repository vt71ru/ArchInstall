#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  input.sh
#
#  Низкоуровневая система ввода TUI.
#
#  Ответственность:
#   • Чтение клавиш в raw mode
#   • Распознавание escape sequences
#   • Преобразование клавиш в KEY_*
#
#  Не содержит:
#   • Логику меню
#   • Логику installer
#   • Обработку бизнес-событий
#============================================================

[[ -n "${INPUT_SH_LOADED:-}" ]] && return

readonly INPUT_SH_LOADED=1

#------------------------------------------------------------
# Key constants
#------------------------------------------------------------

readonly KEY_NONE=""

readonly KEY_UP="UP"
readonly KEY_DOWN="DOWN"
readonly KEY_LEFT="LEFT"
readonly KEY_RIGHT="RIGHT"

readonly KEY_ENTER="ENTER"
readonly KEY_ESC="ESC"

readonly KEY_SPACE="SPACE"
readonly KEY_BACKSPACE="BACKSPACE"

readonly KEY_SLASH="SLASH"

readonly KEY_F1="F1"
readonly KEY_F2="F2"

readonly KEY_TAB="TAB"
readonly KEY_DELETE="DELETE"
readonly KEY_HOME="HOME"
readonly KEY_END="END"

#------------------------------------------------------------
# Timing
#------------------------------------------------------------

readonly INPUT_ESCAPE_TIMEOUT="${INPUT_ESCAPE_TIMEOUT:-0.08}"

#------------------------------------------------------------
# Read first byte
#------------------------------------------------------------

input_read_raw()
{
    local key=""

    IFS= read \
        -rsn1 \
        key

    printf '%s' \
        "$key"
}

#------------------------------------------------------------
# Read escape sequence remainder
#------------------------------------------------------------

input_read_escape()
{
    local sequence=""
    local byte=""

    if ! IFS= read \
        -rsn1 \
        -t "$INPUT_ESCAPE_TIMEOUT" \
        byte
    then
        printf '%s' \
            "$KEY_ESC"

        return 0
    fi

    sequence+="$byte"

    case "$sequence" in
        '[')
            if ! IFS= read \
                -rsn1 \
                -t "$INPUT_ESCAPE_TIMEOUT" \
                byte
            then
                printf '%s' \
                    "$KEY_ESC"

                return 0
            fi

            sequence+="$byte"

            case "$sequence" in
                '[A')
                    printf '%s' \
                        "$KEY_UP"
                    ;;
                '[B')
                    printf '%s' \
                        "$KEY_DOWN"
                    ;;
                '[C')
                    printf '%s' \
                        "$KEY_RIGHT"
                    ;;
                '[D')
                    printf '%s' \
                        "$KEY_LEFT"
                    ;;
                '[H')
                    printf '%s' \
                        "$KEY_HOME"
                    ;;
                '[F')
                    printf '%s' \
                        "$KEY_END"
                    ;;
                *)
                    input_read_csi "$sequence"
                    ;;
            esac
            ;;
        'O')
            if ! IFS= read \
                -rsn1 \
                -t "$INPUT_ESCAPE_TIMEOUT" \
                byte
            then
                printf '%s' \
                    "$KEY_ESC"

                return 0
            fi

            sequence+="$byte"

            case "$sequence" in
                'OP')
                    printf '%s' \
                        "$KEY_F1"
                    ;;
                'OQ')
                    printf '%s' \
                        "$KEY_F2"
                    ;;
                *)
                    printf '%s' \
                        "$KEY_ESC"
                    ;;
            esac
            ;;
        *)
            printf '%s' \
                "$KEY_ESC"
            ;;
    esac
}

#------------------------------------------------------------
# Read CSI sequence
#------------------------------------------------------------

input_read_csi()
{
    local sequence="$1"
    local byte=""

    while [[ "$sequence" != *'~' &&
            "$sequence" != *'A' &&
            "$sequence" != *'B' &&
            "$sequence" != *'C' &&
            "$sequence" != *'D' &&
            "$sequence" != *'H' &&
            "$sequence" != *'F' ]]
    do
        if ! IFS= read \
            -rsn1 \
            -t "$INPUT_ESCAPE_TIMEOUT" \
            byte
        then
            printf '%s' \
                "$KEY_ESC"

            return 0
        fi

        sequence+="$byte"

        if (( ${#sequence} > 16 ))
        then
            printf '%s' \
                "$KEY_ESC"

            return 0
        fi
    done

    case "$sequence" in
        '[1;5A'|'[1;2A')
            printf '%s' \
                "$KEY_UP"
            ;;
        '[1;5B'|'[1;2B')
            printf '%s' \
                "$KEY_DOWN"
            ;;
        '[1;5C'|'[1;2C')
            printf '%s' \
                "$KEY_RIGHT"
            ;;
        '[1;5D'|'[1;2D')
            printf '%s' \
                "$KEY_LEFT"
            ;;
        '[15~')
            printf '%s' \
                "$KEY_F5"
            ;;
        '[17~')
            printf '%s' \
                "$KEY_F6"
            ;;
        '[18~')
            printf '%s' \
                "$KEY_F7"
            ;;
        '[19~')
            printf '%s' \
                "$KEY_F8"
            ;;
        '[20~')
            printf '%s' \
                "$KEY_F9"
            ;;
        '[21~')
            printf '%s' \
                "$KEY_F10"
            ;;
        '[3~')
            printf '%s' \
                "$KEY_DELETE"
            ;;
        '[2~')
            printf '%s' \
                "$KEY_INSERT"
            ;;
        *)
            case "$sequence" in
                '[A')
                    printf '%s' \
                        "$KEY_UP"
                    ;;
                '[B')
                    printf '%s' \
                        "$KEY_DOWN"
                    ;;
                '[C')
                    printf '%s' \
                        "$KEY_RIGHT"
                    ;;
                '[D')
                    printf '%s' \
                        "$KEY_LEFT"
                    ;;
                '[H')
                    printf '%s' \
                        "$KEY_HOME"
                    ;;
                '[F')
                    printf '%s' \
                        "$KEY_END"
                    ;;
                *)
                    printf '%s' \
                        "$KEY_ESC"
                    ;;
            esac
            ;;
    esac
}

#------------------------------------------------------------
# Decode single key
#------------------------------------------------------------

input_decode()
{
    local key="${1-}"

    case "$key" in
        $'\e')
            input_read_escape
            ;;
        "")
            printf '%s' \
                "$KEY_ENTER"
            ;;
        ' ')
            printf '%s' \
                "$KEY_SPACE"
            ;;
        $'\t')
            printf '%s' \
                "$KEY_TAB"
            ;;
        $'\177'|$'\b')
            printf '%s' \
                "$KEY_BACKSPACE"
            ;;
        '/')
            printf '%s' \
                "$KEY_SLASH"
            ;;
        *)
            printf '%s' \
                "$key"
            ;;
    esac
}

#------------------------------------------------------------
# Public read
#------------------------------------------------------------

input_read()
{
    local raw
    local decoded

    raw="$(
        input_read_raw
    )"

    decoded="$(
        input_decode \
            "$raw"
    )"

    printf '%s' \
        "$decoded"
}