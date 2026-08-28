```bash
#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  dialog.sh
#
#  Диалоговый слой TUI.
#
#  Ответственность:
#   • Информационные сообщения
#   • Ошибки
#   • Предупреждения
#   • Подтверждения
#   • Простые вопросы
#   • Ожидание Enter
#
#  Не содержит:
#   • Низкоуровневое чтение клавиш
#   • stty
#   • Installer logic
#   • Основную логику меню
#
#  Зависит от:
#   • tui.sh
#   • screen.sh
#   • draw.sh
#   • cursor.sh
#   • events.sh
#   • colors.sh
#============================================================

if [[ -n "${DIALOG_SH_LOADED:-}" ]]
then
    return 0
fi

readonly DIALOG_SH_LOADED=1

#============================================================
# State
#============================================================

DIALOG_INITIALIZED=0

DIALOG_WIDTH=60
DIALOG_MIN_WIDTH=30
DIALOG_MAX_WIDTH=100

#============================================================
# Initialization
#============================================================

dialog_init()
{
    if (( DIALOG_INITIALIZED ))
    then
        return 0
    fi

    if ! declare -F screen_rows >/dev/null 2>&1
    then
        logger_error \
            "screen_rows() is not available"

        return 1
    fi

    if ! declare -F screen_cols >/dev/null 2>&1
    then
        logger_error \
            "screen_cols() is not available"

        return 1
    fi

    if ! declare -F draw_box >/dev/null 2>&1
    then
        logger_error \
            "draw_box() is not available"

        return 1
    fi

    if ! declare -F cursor_move >/dev/null 2>&1
    then
        logger_error \
            "cursor_move() is not available"

        return 1
    fi

    if ! declare -F event_read >/dev/null 2>&1
    then
        logger_error \
            "event_read() is not available"

        return 1
    fi

    DIALOG_INITIALIZED=1

    logger_debug \
        "Dialog subsystem initialized"

    return 0
}

#============================================================
# Calculate centered box
#============================================================

dialog_geometry()
{
    local width="${1:-$DIALOG_WIDTH}"
    local height="${2:-5}"

    local rows
    local cols
    local row
    local col

    rows="$(
        screen_rows
    )" || \
        return 1

    cols="$(
        screen_cols
    )" || \
        return 1

    if (( width > cols - 2 ))
    then
        width=$((cols - 2))
    fi

    if (( width < DIALOG_MIN_WIDTH ))
    then
        width="$DIALOG_MIN_WIDTH"
    fi

    if (( width > DIALOG_MAX_WIDTH ))
    then
        width="$DIALOG_MAX_WIDTH"
    fi

    if (( height > rows - 2 ))
    then
        height=$((rows - 2))
    fi

    if (( height < 3 ))
    then
        height=3
    fi

    col=$(( (cols - width) / 2 + 1 ))
    row=$(( (rows - height) / 2 + 1 ))

    printf '%d %d %d %d' \
        "$row" \
        "$col" \
        "$width" \
        "$height"
}

#============================================================
# Clear dialog area
#============================================================

dialog_clear()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local width="${3:-0}"
    local height="${4:-0}"

    if declare -F screen_clear_area >/dev/null 2>&1
    then
        screen_clear_area \
            "$row" \
            "$col" \
            "$width" \
            "$height"
    else
        return 0
    fi
}

#============================================================
# Draw title
#============================================================

dialog_draw_title()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local width="${3:-40}"
    local title="${4-}"

    local text

    text=" ${title} "

    if (( ${#text} > width - 2 ))
    then
        text="${text:0:$((width - 2))}"
    fi

    cursor_move \
        "$row" \
        "$((col + 1))" || \
        return 1

    if declare -F color_title >/dev/null 2>&1
    then
        color_title \
            "$text"
    else
        printf '%s' \
            "$text"
    fi
}

#============================================================
# Draw plain message dialog
#============================================================

dialog_draw()
{
    local title="${1:-Message}"
    local message="${2-}"
    local width="${3:-$DIALOG_WIDTH}"

    local lines=()
    local line
    local row
    local col
    local height
    local geometry
    local content_height
    local index

    dialog_init || \
        return 1

    while IFS= read -r line || [[ -n "$line" ]]
    do
        lines+=("$line")
    done < <(
        printf '%s\n' "$message"
    )

    if (( ${#lines[@]} == 0 ))
    then
        lines=("")
    fi

    height=$(( ${#lines[@]} + 5 ))

    geometry="$(
        dialog_geometry \
            "$width" \
            "$height"
    )" || \
        return 1

    read -r \
        row \
        col \
        width \
        height <<< "$geometry"

    draw_box \
        "$row" \
        "$col" \
        "$width" \
        "$height" || \
        return 1

    dialog_draw_title \
        "$row" \
        "$col" \
        "$width" \
        "$title" || \
        return 1

    content_height=$((height - 4))

    for (( index=0; index<${#lines[@]}; index++ ))
    do
        if (( index >= content_height ))
        then
            break
        fi

        cursor_move \
            "$((row + 2 + index))" \
            "$((col + 2))" || \
            return 1

        printf '%s' \
            "${lines[index]:0:$((width - 4))}"
    done

    cursor_move \
        "$((row + height - 2))" \
        "$((col + 2))" || \
        return 1

    printf '%s' \
        "Press Enter"

    screen_refresh

    return 0
}

#============================================================
# Wait for Enter or Esc
#============================================================

dialog_wait()
{
    local event

    while true
    do
        event="$(
            event_read
        )"

        case "$event"
        in
            "$EVENT_SELECT"|
            "$EVENT_BACK")
                return 0
                ;;

            *)
                ;;
        esac
    done
}

#============================================================
# Generic message
#============================================================

dialog_message()
{
    local title="${1:-Message}"
    local message="${2-}"

    dialog_draw \
        "$title" \
        "$message" || \
        return 1

    dialog_wait
}

#============================================================
# Information dialog
#============================================================

dialog_info()
{
    local title="${1:-Information}"
    local message="${2-}"

    dialog_draw \
        "$title" \
        "$message" || \
        return 1

    dialog_wait
}

#============================================================
# Warning dialog
#============================================================

dialog_warning()
{
    local title="${1:-Warning}"
    local message="${2-}"

    dialog_draw \
        "$title" \
        "$message" || \
        return 1

    dialog_wait
}

#============================================================
# Error dialog
#============================================================

dialog_error()
{
    local message="${1:-Unknown error}"

    logger_error \
        "$message"

    dialog_draw \
        "Error" \
        "$message" || \
        return 1

    dialog_wait
}

#============================================================
# Confirmation
#============================================================

dialog_confirm()
{
    local message="${1:-Continue?}"
    local event

    dialog_draw \
        "Confirmation" \
        "${message}

Enter = Yes
Esc   = No" || \
        return 1

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
# Yes / No
#============================================================

dialog_yes_no()
{
    local message="${1:-Continue?}"
    local default="${2:-yes}"
    local event

    dialog_draw \
        "Question" \
        "${message}

Enter = Yes
Esc   = No" || \
        return 1

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
# Select one item
#============================================================

dialog_select()
{
    local title="${1:-Select}"
    local selected="${2:-0}"
    shift 2

    local items=("$@")
    local count="${#items[@]}"
    local event
    local index

    if (( count == 0 ))
    then
        dialog_error \
            "No dialog items were provided"

        return 1
    fi

    if (( selected < 0 || selected >= count ))
    then
        selected=0
    fi

    while true
    do
        screen_prepare

        titlebar_draw \
            "$title"

        draw_panel \
            "$title" \
            3 \
            5 \
            "$((count + 4))" \
            65

        for index in "${!items[@]}"
        do
            cursor_move \
                "$((5 + index))" \
                8 || \
                return 1

            if (( index == selected ))
            then
                if declare -F color_selected >/dev/null 2>&1
                then
                    color_selected \
                        "> ${items[index]}"
                else
                    printf \
                        '\033[7m> %s\033[0m' \
                        "${items[index]}"
                fi
            else
                printf \
                    '  %s' \
                    "${items[index]}"
            fi
        done

        statusbar_draw \
            "↑↓ Select  Enter Choose  Esc Back"

        screen_refresh

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
                DIALOG_RESULT="$selected"
                DIALOG_VALUE="${items[selected]}"
                return 0
                ;;

            "$EVENT_BACK")
                return 1
                ;;
        esac
    done
}

#============================================================
# Result
#============================================================

DIALOG_RESULT=""
DIALOG_VALUE=""

dialog_get_result()
{
    printf '%s' \
        "$DIALOG_RESULT"
}

dialog_get_value()
{
    printf '%s' \
        "$DIALOG_VALUE"
}

#============================================================
# End
#============================================================
