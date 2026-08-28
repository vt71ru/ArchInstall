```bash
#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  screen.sh
#
#  Управление экраном TUI.
#
#  Ответственность:
#   • Получение размеров терминала
#   • Подготовка экрана
#   • Очистка экрана
#   • Очистка области
#   • Обновление кадра
#   • Проверка размеров
#
#  Не содержит:
#   • stty
#   • Обработку клавиш
#   • Логику меню
#   • Installer logic
#
#  Зависит от:
#   • terminal.sh
#   • cursor.sh
#   • tui.sh
#============================================================

if [[ -n "${SCREEN_SH_LOADED:-}" ]]
then
    return 0
fi

readonly SCREEN_SH_LOADED=1

#============================================================
# State
#============================================================

SCREEN_INITIALIZED=0

SCREEN_ROWS=0
SCREEN_COLS=0

SCREEN_MIN_ROWS=20
SCREEN_MIN_COLS=70

SCREEN_DIRTY=1

#============================================================
# Initialization
#============================================================

screen_init()
{
    if (( SCREEN_INITIALIZED ))
    then
        screen_update_size

        return 0
    fi

    if ! declare -F terminal_rows >/dev/null 2>&1
    then
        logger_error \
            "terminal_rows() is not available"

        return 1
    fi

    if ! declare -F terminal_cols >/dev/null 2>&1
    then
        logger_error \
            "terminal_cols() is not available"

        return 1
    fi

    if ! declare -F cursor_move >/dev/null 2>&1
    then
        logger_error \
            "cursor_move() is not available"

        return 1
    fi

    if ! screen_update_size
    then
        return 1
    fi

    SCREEN_INITIALIZED=1
    SCREEN_DIRTY=1

    logger_debug \
        "Screen initialized: ${SCREEN_COLS}x${SCREEN_ROWS}"

    return 0
}

#============================================================
# Update terminal size
#============================================================

screen_update_size()
{
    local rows
    local cols

    rows="$(
        terminal_rows
    )"

    cols="$(
        terminal_cols
    )"

    if [[ ! "$rows" =~ ^[0-9]+$ ||
          ! "$cols" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid terminal dimensions: ${cols}x${rows}"

        return 1
    fi

    if (( rows <= 0 || cols <= 0 ))
    then
        logger_error \
            "Terminal dimensions are zero: ${cols}x${rows}"

        return 1
    fi

    SCREEN_ROWS="$rows"
    SCREEN_COLS="$cols"

    return 0
}

#============================================================
# Check minimum size
#============================================================

screen_check_size()
{
    screen_update_size || \
        return 1

    if (( SCREEN_ROWS < SCREEN_MIN_ROWS ||
          SCREEN_COLS < SCREEN_MIN_COLS ))
    then
        logger_warn \
            "Screen too small: ${SCREEN_COLS}x${SCREEN_ROWS}; minimum ${SCREEN_MIN_COLS}x${SCREEN_MIN_ROWS}"

        return 1
    fi

    return 0
}

#============================================================
# Clear complete screen
#============================================================

screen_clear()
{
    printf \
        '\033[2J\033[H'

    SCREEN_DIRTY=0

    return 0
}

#============================================================
# Clear current line
#============================================================

screen_clear_line()
{
    printf \
        '\033[2K'

    return 0
}

#============================================================
# Clear from cursor to end of screen
#============================================================

screen_clear_to_end()
{
    printf \
        '\033[J'

    return 0
}

#============================================================
# Clear from start of screen to cursor
#============================================================

screen_clear_to_cursor()
{
    printf \
        '\033[1J'

    return 0
}

#============================================================
# Prepare frame
#============================================================

screen_prepare()
{
    if (( ! SCREEN_INITIALIZED ))
    then
        screen_init || \
            return 1
    fi

    screen_update_size || \
        return 1

    screen_clear

    SCREEN_DIRTY=1

    return 0
}

#============================================================
# Mark dirty
#============================================================

screen_mark_dirty()
{
    SCREEN_DIRTY=1
}

#============================================================
# Mark clean
#============================================================

screen_mark_clean()
{
    SCREEN_DIRTY=0
}

#============================================================
# Is dirty
#============================================================

screen_is_dirty()
{
    (( SCREEN_DIRTY ))
}

#============================================================
# Refresh
#============================================================

screen_refresh()
{
    if (( ! SCREEN_INITIALIZED ))
    then
        screen_init || \
            return 1
    fi

    if ! screen_update_size
    then
        return 1
    fi

    #
    # Bash/terminal output is immediate. The function exists
    # as the frame synchronization point for the TUI.
    #
    if declare -F tui_flush >/dev/null 2>&1
    then
        tui_flush || \
            return 1
    elif declare -F terminal_flush >/dev/null 2>&1
    then
        terminal_flush || \
            return 1
    else
        printf ''
    fi

    SCREEN_DIRTY=0

    return 0
}

#============================================================
# Get rows
#============================================================

screen_rows()
{
    if (( ! SCREEN_INITIALIZED ))
    then
        screen_init || \
            return 1
    fi

    printf '%s' \
        "$SCREEN_ROWS"
}

#============================================================
# Get columns
#============================================================

screen_cols()
{
    if (( ! SCREEN_INITIALIZED ))
    then
        screen_init || \
            return 1
    fi

    printf '%s' \
        "$SCREEN_COLS"
}

#============================================================
# Center column
#============================================================

screen_center_col()
{
    local width="${1:-0}"
    local col

    if [[ ! "$width" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid width: ${width}"

        return 1
    fi

    if (( ! SCREEN_INITIALIZED ))
    then
        screen_init || \
            return 1
    fi

    if (( width >= SCREEN_COLS ))
    then
        printf '1'
        return 0
    fi

    col=$(( (SCREEN_COLS - width) / 2 + 1 ))

    printf '%s' \
        "$col"
}

#============================================================
# Center text
#============================================================

screen_center_text()
{
    local row="${1:-1}"
    local text="${2-}"
    local width
    local col

    width="${#text}"

    col="$(
        screen_center_col \
            "$width"
    )" || \
        return 1

    cursor_move \
        "$row" \
        "$col" || \
        return 1

    printf '%s' \
        "$text"
}

#============================================================
# Put text
#============================================================

screen_put()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local text="${3-}"

    cursor_move \
        "$row" \
        "$col" || \
        return 1

    printf '%s' \
        "$text"
}

#============================================================
# Clear rectangular area
#============================================================

screen_clear_area()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local width="${3:-0}"
    local height="${4:-0}"
    local y
    local x

    if [[ ! "$width" =~ ^[0-9]+$ ||
          ! "$height" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid area dimensions"

        return 1
    fi

    if (( width == 0 || height == 0 ))
    then
        return 0
    fi

    for (( y=0; y<height; y++ ))
    do
        cursor_move \
            "$((row + y))" \
            "$col" || \
            return 1

        for (( x=0; x<width; x++ ))
        do
            printf ' '
        done
    done

    SCREEN_DIRTY=1

    return 0
}

#============================================================
# Draw full-width separator
#============================================================

screen_hline()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local width="${3:-0}"
    local char="${4:--}"
    local i

    if [[ ! "$width" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid line width: ${width}"

        return 1
    fi

    cursor_move \
        "$row" \
        "$col" || \
        return 1

    for (( i=0; i<width; i++ ))
    do
        printf '%s' \
            "$char"
    done

    SCREEN_DIRTY=1

    return 0
}

#============================================================
# Resize notification
#============================================================

screen_resize()
{
    local old_rows="$SCREEN_ROWS"
    local old_cols="$SCREEN_COLS"

    screen_update_size || \
        return 1

    if (( old_rows != SCREEN_ROWS ||
          old_cols != SCREEN_COLS ))
    then
        logger_debug \
            "Terminal resized: ${old_cols}x${old_rows} -> ${SCREEN_COLS}x${SCREEN_ROWS}"

        SCREEN_DIRTY=1
    fi

    return 0
}

#============================================================
# Reset screen state
#============================================================

screen_reset()
{
    SCREEN_ROWS=0
    SCREEN_COLS=0
    SCREEN_DIRTY=1
    SCREEN_INITIALIZED=0

    return 0
}

#============================================================
# End
#============================================================
