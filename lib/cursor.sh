#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  cursor.sh
#
#  Управление курсором терминала.
#
#  Ответственность:
#   • Перемещение курсора
#   • Скрытие/показ курсора
#   • Сохранение позиции
#   • Восстановление позиции
#   • Управление строкой
#
#  Не содержит:
#   • Логику меню
#   • Отрисовку интерфейса
#   • Обработку событий
#============================================================

[[ -n "${CURSOR_SH_LOADED:-}" ]] && return

readonly CURSOR_SH_LOADED=1

#------------------------------------------------------------
# State
#------------------------------------------------------------

CURSOR_SAVED=0

#------------------------------------------------------------
# Validate coordinate
#------------------------------------------------------------

cursor_validate_coordinate()
{
    local value="${1:-}"

    [[ "$value" =~ ^[1-9][0-9]*$ ]]
}

cursor_validate_count()
{
    local value="${1:-1}"

    [[ "$value" =~ ^[1-9][0-9]*$ ]]
}

#------------------------------------------------------------
# Visibility
#------------------------------------------------------------

cursor_hide()
{
    tput civis >/dev/null 2>&1 || \
        printf '\033[?25l'
}

cursor_show()
{
    tput cnorm >/dev/null 2>&1 || \
        printf '\033[?25h'
}

#------------------------------------------------------------
# Position
#------------------------------------------------------------

cursor_move()
{
    local row="${1:-}"
    local col="${2:-}"

    cursor_validate_coordinate "$row" || \
        return 1

    cursor_validate_coordinate "$col" || \
        return 1

    printf \
        '\033[%s;%sH' \
        "$row" \
        "$col"
}

cursor_home()
{
    printf '\033[H'
}

#------------------------------------------------------------
# Save / restore
#------------------------------------------------------------

cursor_save()
{
    printf '\0337'

    CURSOR_SAVED=1
}

cursor_restore()
{
    if (( CURSOR_SAVED == 0 ))
    then
        return 0
    fi

    printf '\0338'

    CURSOR_SAVED=0
}

#------------------------------------------------------------
# Query
#------------------------------------------------------------

cursor_request_position()
{
    printf '\033[6n'
}

#------------------------------------------------------------
# Relative movement
#------------------------------------------------------------

cursor_up()
{
    local count="${1:-1}"

    cursor_validate_count \
        "$count" || \
        return 1

    printf \
        '\033[%sA' \
        "$count"
}

cursor_down()
{
    local count="${1:-1}"

    cursor_validate_count \
        "$count" || \
        return 1

    printf \
        '\033[%sB' \
        "$count"
}

cursor_right()
{
    local count="${1:-1}"

    cursor_validate_count \
        "$count" || \
        return 1

    printf \
        '\033[%sC' \
        "$count"
}

cursor_left()
{
    local count="${1:-1}"

    cursor_validate_count \
        "$count" || \
        return 1

    printf \
        '\033[%sD' \
        "$count"
}

#------------------------------------------------------------
# Line control
#------------------------------------------------------------

cursor_line_start()
{
    printf '\r'
}

cursor_clear_line()
{
    printf '\033[2K'
}

cursor_clear_to_end()
{
    printf '\033[0K'
}

cursor_clear_to_start()
{
    printf '\033[1K'
}

#------------------------------------------------------------
# Screen-relative operations
#------------------------------------------------------------

cursor_up_begin()
{
    local count="${1:-1}"

    cursor_up \
        "$count" || \
        return 1

    cursor_line_start
}

cursor_down_begin()
{
    local count="${1:-1}"

    cursor_down \
        "$count" || \
        return 1

    cursor_line_start
}