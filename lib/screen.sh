#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  screen.sh
#
#  Управление рабочей областью терминала.
#
#  Ответственность:
#   • Определение размеров терминала
#   • Проверка минимального размера
#   • Очистка экрана
#   • Подготовка области вывода
#   • Обновление размеров при resize
#   • Безопасное позиционирование
#
#  Не содержит:
#   • Логику меню
#   • Обработку клавиш
#   • Управление terminal raw mode
#   • Отрисовку widgets
#============================================================

[[ -n "${SCREEN_SH_LOADED:-}" ]] && return

readonly SCREEN_SH_LOADED=1

#------------------------------------------------------------
# State
#------------------------------------------------------------

SCREEN_ROWS=24
SCREEN_COLS=80

SCREEN_MIN_ROWS=20
SCREEN_MIN_COLS=70

SCREEN_INITIALIZED=0

#------------------------------------------------------------
# Update size
#------------------------------------------------------------

screen_update_size()
{
    local rows
    local cols

    rows="$(
        tput lines 2>/dev/null \
            || printf '0'
    )"

    cols="$(
        tput cols 2>/dev/null \
            || printf '0'
    )"

    if ! [[ "$rows" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid terminal row count: ${rows}"

        return 1
    fi

    if ! [[ "$cols" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid terminal column count: ${cols}"

        return 1
    fi

    if (( rows < 1 ||
          cols < 1 ))
    then
        logger_error \
            "Invalid terminal dimensions: ${cols}x${rows}"

        return 1
    fi

    SCREEN_ROWS="$rows"
    SCREEN_COLS="$cols"

    logger_debug \
        "Screen size: ${SCREEN_COLS}x${SCREEN_ROWS}"
}

#------------------------------------------------------------
# Check minimum size
#------------------------------------------------------------

screen_check_size()
{
    if (( SCREEN_ROWS < SCREEN_MIN_ROWS ||
          SCREEN_COLS < SCREEN_MIN_COLS ))
    then
        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Rows
#------------------------------------------------------------

screen_rows()
{
    printf '%s' \
        "$SCREEN_ROWS"
}

#------------------------------------------------------------
# Columns
#------------------------------------------------------------

screen_cols()
{
    printf '%s' \
        "$SCREEN_COLS"
}

#------------------------------------------------------------
# Initialize
#------------------------------------------------------------

screen_init()
{
    screen_update_size || \
        return 1

    SCREEN_INITIALIZED=1

    logger_info \
        "Screen initialized: ${SCREEN_COLS}x${SCREEN_ROWS}"
}

#------------------------------------------------------------
# Refresh dimensions
#------------------------------------------------------------

screen_refresh_size()
{
    screen_update_size || \
        return 1

    return 0
}

#------------------------------------------------------------
# Clear screen
#------------------------------------------------------------

screen_clear()
{
    printf '\033[2J'
    printf '\033[H'
}

#------------------------------------------------------------
# Prepare screen
#------------------------------------------------------------

screen_prepare()
{
    if (( ! SCREEN_INITIALIZED ))
    then
        screen_init || \
            return 1
    else
        screen_update_size || \
            return 1
    fi

    screen_clear

    cursor_home

    return 0
}

#------------------------------------------------------------
# Refresh
#------------------------------------------------------------

screen_refresh()
{
    printf ''
}

#------------------------------------------------------------
# Validate coordinate
#------------------------------------------------------------

screen_validate_position()
{
    local row="${1:-}"
    local col="${2:-}"

    [[ "$row" =~ ^[1-9][0-9]*$ ]] || \
        return 1

    [[ "$col" =~ ^[1-9][0-9]*$ ]] || \
        return 1

    if (( row > SCREEN_ROWS ||
          col > SCREEN_COLS ))
    then
        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Safe move
#------------------------------------------------------------

screen_move()
{
    local row="${1:-}"
    local col="${2:-}"

    screen_validate_position \
        "$row" \
        "$col" || \
        return 1

    cursor_move \
        "$row" \
        "$col"
}

#------------------------------------------------------------
# Clear line
#------------------------------------------------------------

screen_clear_line()
{
    local row="${1:-}"

    [[ "$row" =~ ^[1-9][0-9]*$ ]] || \
        return 1

    (( row <= SCREEN_ROWS )) || \
        return 1

    cursor_move \
        "$row" \
        1

    cursor_clear_line
}

#------------------------------------------------------------
# Clear rectangular area
#------------------------------------------------------------

screen_clear_area()
{
    local top="${1:-}"
    local left="${2:-}"
    local bottom="${3:-}"
    local right="${4:-}"

    local row
    local width

    [[ "$top" =~ ^[1-9][0-9]*$ ]] || \
        return 1

    [[ "$left" =~ ^[1-9][0-9]*$ ]] || \
        return 1

    [[ "$bottom" =~ ^[1-9][0-9]*$ ]] || \
        return 1

    [[ "$right" =~ ^[1-9][0-9]*$ ]] || \
        return 1

    if (( bottom < top ||
          right < left ))
    then
        return 1
    fi

    if (( bottom > SCREEN_ROWS ||
          right > SCREEN_COLS ))
    then
        return 1
    fi

    width=$(( right - left + 1 ))

    for (( row=top; row<=bottom; row++ ))
    do
        cursor_move \
            "$row" \
            "$left"

        printf \
            '%*s' \
            "$width" \
            ''
    done
}

#------------------------------------------------------------
# Erase to end of screen
#------------------------------------------------------------

screen_clear_to_end()
{
    printf '\033[0J'
}

#------------------------------------------------------------
# Erase to beginning of screen
#------------------------------------------------------------

screen_clear_to_start()
{
    printf '\033[1J'
}

#------------------------------------------------------------
# Reset
#------------------------------------------------------------

screen_reset()
{
    SCREEN_ROWS=24
    SCREEN_COLS=80
    SCREEN_INITIALIZED=0
}