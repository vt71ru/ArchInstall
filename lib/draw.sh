#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  draw.sh
#
#  Примитивы отрисовки TUI.
#
#  Ответственность:
#   • Заголовки
#   • Status bar
#   • Панели
#   • Текст
#   • Рамки
#   • Заполнение областей
#
#  Не содержит:
#   • Обработку клавиш
#   • Логику меню
#   • stty
#   • installer logic
#============================================================

[[ -n "${DRAW_SH_LOADED:-}" ]] && return

readonly DRAW_SH_LOADED=1

#------------------------------------------------------------
# Characters
#------------------------------------------------------------

DRAW_H="─"
DRAW_V="│"
DRAW_TL="┌"
DRAW_TR="┐"
DRAW_BL="└"
DRAW_BR="┘"

#------------------------------------------------------------
# Validate position
#------------------------------------------------------------

draw_validate_position()
{
    local row="${1:-}"
    local col="${2:-}"

    screen_validate_position \
        "$row" \
        "$col"
}

#------------------------------------------------------------
# Text
#------------------------------------------------------------

draw_text()
{
    local row="${1:-}"
    local col="${2:-}"
    local text="${3-}"

    draw_validate_position \
        "$row" \
        "$col" || \
        return 1

    cursor_move \
        "$row" \
        "$col"

    printf '%s' \
        "$text"
}

#------------------------------------------------------------
# Horizontal line
#------------------------------------------------------------

draw_hline()
{
    local row="${1:-}"
    local col="${2:-}"
    local width="${3:-}"

    local line

    [[ "$width" =~ ^[1-9][0-9]*$ ]] || \
        return 1

    draw_validate_position \
        "$row" \
        "$col" || \
        return 1

    if (( col + width - 1 > SCREEN_COLS ))
    then
        return 1
    fi

    line="$(
        printf \
            '%*s' \
            "$width" \
            '' |
        tr ' ' "$DRAW_H"
    )"

    cursor_move \
        "$row" \
        "$col"

    printf '%s' \
        "$line"
}

#------------------------------------------------------------
# Vertical line
#------------------------------------------------------------

draw_vline()
{
    local row="${1:-}"
    local col="${2:-}"
    local height="${3:-}"

    local index

    [[ "$height" =~ ^[1-9][0-9]*$ ]] || \
        return 1

    draw_validate_position \
        "$row" \
        "$col" || \
        return 1

    if (( row + height - 1 > SCREEN_ROWS ))
    then
        return 1
    fi

    for (( index=0; index<height; index++ ))
    do
        cursor_move \
            "$((row + index))" \
            "$col"

        printf '%s' \
            "$DRAW_V"
    done
}

#------------------------------------------------------------
# Box
#------------------------------------------------------------

draw_box()
{
    local top="${1:-}"
    local left="${2:-}"
    local bottom="${3:-}"
    local right="${4:-}"

    local width
    local height
    local horizontal
    local row

    [[ "$top" =~ ^[1-9][0-9]*$ ]] || \
        return 1

    [[ "$left" =~ ^[1-9][0-9]*$ ]] || \
        return 1

    [[ "$bottom" =~ ^[1-9][0-9]*$ ]] || \
        return 1

    [[ "$right" =~ ^[1-9][0-9]*$ ]] || \
        return 1

    if (( bottom <= top ||
          right <= left ))
    then
        return 1
    fi

    width=$((right - left + 1))
    height=$((bottom - top + 1))

    if (( bottom > SCREEN_ROWS ||
          right > SCREEN_COLS ))
    then
        return 1
    fi

    horizontal="$(
        printf \
            '%*s' \
            "$((width - 2))" \
            '' |
        tr ' ' "$DRAW_H"
    )"

    cursor_move \
        "$top" \
        "$left"

    printf \
        '%s%s%s' \
        "$DRAW_TL" \
        "$horizontal" \
        "$DRAW_TR"

    for (( row=top + 1; row<bottom; row++ ))
    do
        cursor_move \
            "$row" \
            "$left"

        printf '%s' \
            "$DRAW_V"

        cursor_move \
            "$row" \
            "$right"

        printf '%s' \
            "$DRAW_V"
    done

    cursor_move \
        "$bottom" \
        "$left"

    printf \
        '%s%s%s' \
        "$DRAW_BL" \
        "$horizontal" \
        "$DRAW_BR"

    return 0
}

#------------------------------------------------------------
# Filled rectangle
#------------------------------------------------------------

draw_fill()
{
    local top="${1:-}"
    local left="${2:-}"
    local bottom="${3:-}"
    local right="${4:-}"

    local row
    local width
    local blank

    if (( top < 1 ||
          left < 1 ||
          bottom < top ||
          right < left ))
    then
        return 1
    fi

    if (( bottom > SCREEN_ROWS ||
          right > SCREEN_COLS ))
    then
        return 1
    fi

    width=$((right - left + 1))

    blank="$(
        printf \
            '%*s' \
            "$width" \
            ''
    )"

    for (( row=top; row<=bottom; row++ ))
    do
        cursor_move \
            "$row" \
            "$left"

        printf '%s' \
            "$blank"
    done
}

#------------------------------------------------------------
# Panel
#------------------------------------------------------------

draw_panel()
{
    local title="${1-}"
    local top="${2:-}"
    local left="${3:-}"
    local bottom="${4:-}"
    local right="${5:-}"

    local title_text
    local title_width

    draw_box \
        "$top" \
        "$left" \
        "$bottom" \
        "$right" || \
        return 1

    if [[ -n "$title" ]]
    then
        title_text=" ${title} "
        title_width="${#title_text}"

        if (( left + title_width + 1 < right ))
        then
            cursor_move \
                "$top" \
                "$((left + 2))"

            printf '%s' \
                "$title_text"
        fi
    fi
}

#------------------------------------------------------------
# Title bar
#------------------------------------------------------------

titlebar_draw()
{
    local title="${1:-${APP_NAME:-Arch Installer}}"
    local width
    local text

    width="$(
        screen_cols
    )"

    if (( width < 1 ))
    then
        return 1
    fi

    screen_clear_line 1

    text=" $title "

    cursor_move \
        1 \
        1

    printf \
        '%-*s' \
        "$width" \
        "$text"
}

#------------------------------------------------------------
# Status bar
#------------------------------------------------------------

statusbar_draw()
{
    local message="${1-}"
    local row

    row="$(screen_rows)"

    if (( row < 1 ))
    then
        return 1
    fi

    screen_clear_line \
        "$row"

    cursor_move \
        "$row" \
        1

    printf \
        '%s' \
        "$message"
}

#------------------------------------------------------------
# Center text
#------------------------------------------------------------

draw_center()
{
    local row="${1:-}"
    local text="${2-}"
    local width
    local text_width
    local col

    width="$(
        screen_cols
    )"

    text_width="${#text}"

    if (( text_width >= width ))
    then
        col=1
    else
        col=$(( (width - text_width) / 2 + 1 ))
    fi

    cursor_move \
        "$row" \
        "$col"

    printf '%s' \
        "$text"
}

#------------------------------------------------------------
# Right aligned text
#------------------------------------------------------------

draw_right()
{
    local row="${1:-}"
    local text="${2-}"
    local width
    local text_width
    local col

    width="$(
        screen_cols
    )"

    text_width="${#text}"

    if (( text_width >= width ))
    then
        col=1
    else
        col=$(( width - text_width + 1 ))
    fi

    cursor_move \
        "$row" \
        "$col"

    printf '%s' \
        "$text"
}

#------------------------------------------------------------
# Separator
#------------------------------------------------------------

draw_separator()
{
    local row="${1:-}"
    local left="${2:-1}"
    local right="${3:-}"

    if [[ -z "$right" ]]
    then
        right="$(
            screen_cols
        )"
    fi

    if (( left < 1 ||
          right < left ||
          right > SCREEN_COLS ))
    then
        return 1
    fi

    draw_hline \
        "$row" \
        "$left" \
        "$((right - left + 1))"
}