#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  cursor.sh
#
#  Управление положением курсора терминала.
#
#  Ответственность:
#   • Перемещение курсора
#   • Сохранение логической позиции
#   • Восстановление логической позиции
#   • Очистка строки
#   • Перемещение относительно текущей позиции
#
#  Не содержит:
#   • stty
#   • alternate screen
#   • show/hide cursor
#   • обработку клавиш
#   • логику меню
#   • installer logic
#
#  Зависит от:
#   • terminal.sh
#============================================================

if [[ -n "${CURSOR_SH_LOADED:-}" ]]
then
    return 0
fi

readonly CURSOR_SH_LOADED=1

#============================================================
# State
#============================================================

CURSOR_INITIALIZED=0

CURSOR_ROW=1
CURSOR_COL=1

CURSOR_SAVED_ROW=1
CURSOR_SAVED_COL=1

#============================================================
# Validation
#============================================================

cursor_validate_position()
{
    local row="${1:-}"
    local col="${2:-}"

    if [[ ! "$row" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid cursor row: ${row}"

        return 1
    fi

    if [[ ! "$col" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid cursor column: ${col}"

        return 1
    fi

    if (( row < 1 ))
    then
        logger_error \
            "Cursor row must be >= 1"

        return 1
    fi

    if (( col < 1 ))
    then
        logger_error \
            "Cursor column must be >= 1"

        return 1
    fi

    return 0
}

#============================================================
# Initialization
#============================================================

cursor_init()
{
    if (( CURSOR_INITIALIZED ))
    then
        return 0
    fi

    if [[ ! -t 1 ]]
    then
        logger_error \
            "Cursor output requires stdout TTY"

        return 1
    fi

    CURSOR_ROW=1
    CURSOR_COL=1

    CURSOR_SAVED_ROW=1
    CURSOR_SAVED_COL=1

    CURSOR_INITIALIZED=1

    logger_debug \
        "Cursor initialized"

    return 0
}

#============================================================
# Move to absolute position
#============================================================

cursor_move()
{
    local row="${1:-}"
    local col="${2:-}"

    if ! cursor_validate_position \
        "$row" \
        "$col"
    then
        return 1
    fi

    printf \
        '\033[%d;%dH' \
        "$row" \
        "$col"

    CURSOR_ROW="$row"
    CURSOR_COL="$col"

    return 0
}

#============================================================
# Alias
#============================================================

cursor_move_to()
{
    cursor_move \
        "$@"
}

#============================================================
# Move home
#============================================================

cursor_home()
{
    printf \
        '\033[H'

    CURSOR_ROW=1
    CURSOR_COL=1

    return 0
}

#============================================================
# Move up
#============================================================

cursor_up()
{
    local amount="${1:-1}"

    if [[ ! "$amount" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid cursor up amount: ${amount}"

        return 1
    fi

    if (( amount == 0 ))
    then
        return 0
    fi

    printf \
        '\033[%dA' \
        "$amount"

    CURSOR_ROW=$((CURSOR_ROW - amount))

    if (( CURSOR_ROW < 1 ))
    then
        CURSOR_ROW=1
    fi

    return 0
}

#============================================================
# Move down
#============================================================

cursor_down()
{
    local amount="${1:-1}"

    if [[ ! "$amount" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid cursor down amount: ${amount}"

        return 1
    fi

    if (( amount == 0 ))
    then
        return 0
    fi

    printf \
        '\033[%dB' \
        "$amount"

    CURSOR_ROW=$((CURSOR_ROW + amount))

    return 0
}

#============================================================
# Move left
#============================================================

cursor_left()
{
    local amount="${1:-1}"

    if [[ ! "$amount" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid cursor left amount: ${amount}"

        return 1
    fi

    if (( amount == 0 ))
    then
        return 0
    fi

    printf \
        '\033[%dD' \
        "$amount"

    CURSOR_COL=$((CURSOR_COL - amount))

    if (( CURSOR_COL < 1 ))
    then
        CURSOR_COL=1
    fi

    return 0
}

#============================================================
# Move right
#============================================================

cursor_right()
{
    local amount="${1:-1}"

    if [[ ! "$amount" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid cursor right amount: ${amount}"

        return 1
    fi

    if (( amount == 0 ))
    then
        return 0
    fi

    printf \
        '\033[%dC' \
        "$amount"

    CURSOR_COL=$((CURSOR_COL + amount))

    return 0
}

#============================================================
# Save position
#============================================================

cursor_save()
{
    CURSOR_SAVED_ROW="$CURSOR_ROW"
    CURSOR_SAVED_COL="$CURSOR_COL"

    printf \
        '\033[s'

    return 0
}

#============================================================
# Restore position
#============================================================

cursor_restore()
{
    printf \
        '\033[u'

    CURSOR_ROW="$CURSOR_SAVED_ROW"
    CURSOR_COL="$CURSOR_SAVED_COL"

    return 0
}

#============================================================
# Clear current line
#============================================================

cursor_clear_line()
{
    printf \
        '\033[2K'

    return 0
}

#============================================================
# Clear to end of line
#============================================================

cursor_clear_to_end()
{
    printf \
        '\033[K'

    return 0
}

#============================================================
# Clear to beginning of line
#============================================================

cursor_clear_to_begin()
{
    printf \
        '\033[1K'

    return 0
}

#============================================================
# Move to beginning of current line
#============================================================

cursor_line_begin()
{
    printf \
        '\r'

    CURSOR_COL=1

    return 0
}

#============================================================
# New line
#============================================================

cursor_newline()
{
    printf \
        '\n'

    CURSOR_ROW=$((CURSOR_ROW + 1))
    CURSOR_COL=1

    return 0
}

#============================================================
# Get current row
#============================================================

cursor_row()
{
    printf \
        '%s' \
        "$CURSOR_ROW"
}

#============================================================
# Get current column
#============================================================

cursor_col()
{
    printf \
        '%s' \
        "$CURSOR_COL"
}

#============================================================
# Set logical position without output
#============================================================

cursor_set_state()
{
    local row="${1:-}"
    local col="${2:-}"

    cursor_validate_position \
        "$row" \
        "$col" || \
        return 1

    CURSOR_ROW="$row"
    CURSOR_COL="$col"

    return 0
}

#============================================================
# Reset state
#============================================================

cursor_reset()
{
    CURSOR_ROW=1
    CURSOR_COL=1

    CURSOR_SAVED_ROW=1
    CURSOR_SAVED_COL=1

    printf \
        '\033[H'

    return 0
}

#============================================================
# End
#============================================================
