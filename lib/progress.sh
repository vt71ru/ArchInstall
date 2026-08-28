#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  progress.sh
#
#  Управление прогрессом операций.
#
#  Ответственность:
#   • Создание progress state
#   • Установка общего progress
#   • Установка текста операции
#   • Отрисовка progress bar
#   • Increment / decrement
#   • Завершение progress
#
#  Не содержит:
#   • Обработку клавиатуры
#   • Логику меню
#   • Installer logic
#   • Низкоуровневое управление terminal
#
#  Зависит от:
#   • terminal.sh
#   • tui.sh
#   • widgets.sh
#============================================================

if [[ -n "${PROGRESS_SH_LOADED:-}" ]]
then
    return 0
fi

readonly PROGRESS_SH_LOADED=1

#============================================================
# State
#============================================================

PROGRESS_INITIALIZED=0
PROGRESS_ACTIVE=0

PROGRESS_PERCENT=0
PROGRESS_WIDTH=30
PROGRESS_ROW=1
PROGRESS_COL=1

PROGRESS_TITLE=""
PROGRESS_MESSAGE=""

#============================================================
# Initialization
#============================================================

progress_init()
{
    if (( PROGRESS_INITIALIZED ))
    then
        return 0
    fi

    if ! declare -F tui_move_to >/dev/null 2>&1
    then
        logger_error \
            "tui_move_to() is not available"

        return 1
    fi

    if ! declare -F widget_progress >/dev/null 2>&1
    then
        logger_error \
            "widget_progress() is not available"

        return 1
    fi

    PROGRESS_INITIALIZED=1

    logger_debug \
        "Progress subsystem initialized"

    return 0
}

#============================================================
# Start
#============================================================

progress_start()
{
    local title="${1:-}"
    local row="${2:-1}"
    local col="${3:-1}"
    local width="${4:-30}"

    progress_init || \
        return 1

    if [[ ! "$row" =~ ^[0-9]+$ ||
          ! "$col" =~ ^[0-9]+$ ||
          ! "$width" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid progress position or width"

        return 1
    fi

    if (( width < 1 ))
    then
        logger_error \
            "Progress width must be greater than zero"

        return 1
    fi

    PROGRESS_ACTIVE=1
    PROGRESS_PERCENT=0
    PROGRESS_ROW="$row"
    PROGRESS_COL="$col"
    PROGRESS_WIDTH="$width"
    PROGRESS_TITLE="$title"
    PROGRESS_MESSAGE=""

    progress_draw

    logger_debug \
        "Progress started: ${title}"

    return 0
}

#============================================================
# Set percent
#============================================================

progress_set()
{
    local percent="${1:-0}"

    if ! [[ "$percent" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid progress percentage: ${percent}"

        return 1
    fi

    if (( percent > 100 ))
    then
        percent=100
    fi

    PROGRESS_PERCENT="$percent"

    if (( PROGRESS_ACTIVE ))
    then
        progress_draw
    fi

    return 0
}

#============================================================
# Increment
#============================================================

progress_increment()
{
    local amount="${1:-1}"

    if ! [[ "$amount" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid progress increment: ${amount}"

        return 1
    fi

    progress_set \
        "$(( PROGRESS_PERCENT + amount ))"
}

#============================================================
# Decrement
#============================================================

progress_decrement()
{
    local amount="${1:-1}"
    local value

    if ! [[ "$amount" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid progress decrement: ${amount}"

        return 1
    fi

    value=$(( PROGRESS_PERCENT - amount ))

    if (( value < 0 ))
    then
        value=0
    fi

    progress_set \
        "$value"
}

#============================================================
# Set title
#============================================================

progress_set_title()
{
    PROGRESS_TITLE="${1-}"

    if (( PROGRESS_ACTIVE ))
    then
        progress_draw
    fi
}

#============================================================
# Set message
#============================================================

progress_set_message()
{
    PROGRESS_MESSAGE="${1-}"

    if (( PROGRESS_ACTIVE ))
    then
        progress_draw
    fi
}

#============================================================
# Set state
#============================================================

progress_set_state()
{
    local percent="${1:-0}"
    local message="${2-}"

    progress_set \
        "$percent" || \
        return 1

    PROGRESS_MESSAGE="$message"

    if (( PROGRESS_ACTIVE ))
    then
        progress_draw
    fi

    return 0
}

#============================================================
# Draw
#============================================================

progress_draw()
{
    local message_row

    if (( ! PROGRESS_ACTIVE ))
    then
        return 0
    fi

    message_row=$(( PROGRESS_ROW + 1 ))

    if [[ -n "$PROGRESS_TITLE" ]]
    then
        tui_move_to \
            "$PROGRESS_ROW" \
            "$PROGRESS_COL" || \
            return 1

        printf '%s' \
            "$PROGRESS_TITLE"
    fi

    tui_move_to \
        "$message_row" \
        "$PROGRESS_COL" || \
        return 1

    widget_progress \
        "$message_row" \
        "$PROGRESS_COL" \
        "$PROGRESS_WIDTH" \
        "$PROGRESS_PERCENT" || \
        return 1

    if [[ -n "$PROGRESS_MESSAGE" ]]
    then
        tui_move_to \
            "$((message_row + 1))" \
            "$PROGRESS_COL" || \
            return 1

        printf '%s' \
            "$PROGRESS_MESSAGE"
    fi

    return 0
}

#============================================================
# Complete
#============================================================

progress_complete()
{
    local message="${1:-Complete}"

    PROGRESS_PERCENT=100
    PROGRESS_MESSAGE="$message"

    if (( PROGRESS_ACTIVE ))
    then
        progress_draw
    fi

    return 0
}

#============================================================
# Stop
#============================================================

progress_stop()
{
    PROGRESS_ACTIVE=0
    PROGRESS_PERCENT=0
    PROGRESS_TITLE=""
    PROGRESS_MESSAGE=""

    logger_debug \
        "Progress stopped"

    return 0
}

#============================================================
# Reset
#============================================================

progress_reset()
{
    PROGRESS_PERCENT=0
    PROGRESS_TITLE=""
    PROGRESS_MESSAGE=""

    return 0
}

#============================================================
# Queries
#============================================================

progress_is_active()
{
    (( PROGRESS_ACTIVE ))
}

progress_get_percent()
{
    printf '%s' \
        "$PROGRESS_PERCENT"
}

progress_get_message()
{
    printf '%s' \
        "$PROGRESS_MESSAGE"
}

#============================================================
# End
#============================================================
