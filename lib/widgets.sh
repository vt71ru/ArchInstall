#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  widgets.sh
#
#  Базовые TUI-виджеты.
#
#  Ответственность:
#   • Отрисовка отдельных элементов интерфейса
#   • Menu item
#   • Checkbox
#   • Radio
#   • Separator
#   • Box
#   • Label
#   • Status indicator
#
#  Не содержит:
#   • Обработку клавиш
#   • Логику меню
#   • Installer logic
#   • Изменение CONFIG[]
#
#  Зависит от:
#   • colors.sh
#   • unicode.sh
#   • tui.sh
#============================================================

if [[ -n "${WIDGETS_SH_LOADED:-}" ]]
then
    return 0
fi

readonly WIDGETS_SH_LOADED=1

#============================================================
# State
#============================================================

WIDGETS_INITIALIZED=0

#============================================================
# Initialization
#============================================================

widgets_init()
{
    if (( WIDGETS_INITIALIZED ))
    then
        return 0
    fi

    if ! declare -F tui_move_to >/dev/null 2>&1
    then
        logger_error \
            "tui_move_to() is not available"

        return 1
    fi

    if ! declare -F colors_print >/dev/null 2>&1
    then
        logger_error \
            "colors_print() is not available"

        return 1
    fi

    if ! declare -F unicode_init >/dev/null 2>&1
    then
        logger_error \
            "unicode_init() is not available"

        return 1
    fi

    unicode_init

    WIDGETS_INITIALIZED=1

    logger_debug \
        "Widgets initialized"

    return 0
}

#============================================================
# Print at position
#============================================================

widget_print_at()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local text="${3-}"

    tui_move_to \
        "$row" \
        "$col" || \
        return 1

    printf '%s' \
        "$text"
}

#============================================================
# Label
#============================================================

widget_label()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local text="${3-}"

    widget_print_at \
        "$row" \
        "$col" \
        "$text"
}

#============================================================
# Separator
#============================================================

widget_separator()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local width="${3:-10}"
    local i

    if ! [[ "$width" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid separator width: ${width}"

        return 1
    fi

    tui_move_to \
        "$row" \
        "$col" || \
        return 1

    for (( i=0; i<width; i++ ))
    do
        printf '%s' \
            "${UI_BORDER_HORIZONTAL:--}"
    done
}

#============================================================
# Horizontal line
#============================================================

widget_hline()
{
    widget_separator \
        "$@"
}

#============================================================
# Box
#============================================================

widget_box()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local width="${3:-10}"
    local height="${4:-3}"
    local x
    local y

    if (( width < 2 || height < 2 ))
    then
        logger_error \
            "Invalid box dimensions: ${width}x${height}"

        return 1
    fi

    # Top border.
    tui_move_to \
        "$row" \
        "$col"

    printf '%s' \
        "${UI_BORDER_TOP_LEFT:-+}"

    for (( x=0; x<width-2; x++ ))
    do
        printf '%s' \
            "${UI_BORDER_HORIZONTAL:--}"
    done

    printf '%s' \
        "${UI_BORDER_TOP_RIGHT:-+}"

    # Sides.
    for (( y=1; y<height-1; y++ ))
    do
        tui_move_to \
            "$((row + y))" \
            "$col"

        printf '%s' \
            "${UI_BORDER_VERTICAL:-|}"

        tui_move_to \
            "$((row + y))" \
            "$((col + width - 1))"

        printf '%s' \
            "${UI_BORDER_VERTICAL:-|}"
    done

    # Bottom border.
    tui_move_to \
        "$((row + height - 1))" \
        "$col"

    printf '%s' \
        "${UI_BORDER_BOTTOM_LEFT:-+}"

    for (( x=0; x<width-2; x++ ))
    do
        printf '%s' \
            "${UI_BORDER_HORIZONTAL:--}"
    done

    printf '%s' \
        "${UI_BORDER_BOTTOM_RIGHT:-+}"
}

#============================================================
# Checkbox
#============================================================

widget_checkbox()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local label="${3-}"
    local checked="${4:-0}"
    local marker

    case "$checked"
    in
        1|true|TRUE|yes|YES)
            marker="${UI_CHECK:-[x]}"
            ;;

        *)
            marker="${UI_CROSS:-[ ]}"
            ;;
    esac

    widget_print_at \
        "$row" \
        "$col" \
        "${marker} ${label}"
}

#============================================================
# Radio
#============================================================

widget_radio()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local label="${3-}"
    local selected="${4:-0}"
    local marker

    case "$selected"
    in
        1|true|TRUE|yes|YES)
            marker="${UI_RADIO_ON:-(*)}"
            ;;

        *)
            marker="${UI_RADIO_OFF:-( )}"
            ;;
    esac

    widget_print_at \
        "$row" \
        "$col" \
        "${marker} ${label}"
}

#============================================================
# Bullet item
#============================================================

widget_bullet()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local text="${3-}"

    widget_print_at \
        "$row" \
        "$col" \
        "${UI_BULLET:-*} ${text}"
}

#============================================================
# Menu item
#============================================================

widget_menu_item()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local text="${3-}"
    local selected="${4:-0}"

    tui_move_to \
        "$row" \
        "$col" || \
        return 1

    if [[ "$selected" == "1" ]]
    then
        if declare -F color_selected >/dev/null 2>&1
        then
            color_selected \
                "$text"
        else
            printf \
                '\033[7m%s\033[0m' \
                "$text"
        fi
    else
        printf '%s' \
            "$text"
    fi
}

#============================================================
# Menu item with marker
#============================================================

widget_menu_item_marked()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local text="${3-}"
    local selected="${4:-0}"
    local prefix="  "

    if [[ "$selected" == "1" ]]
    then
        prefix="${UI_ARROW_RIGHT:->} "
    fi

    widget_menu_item \
        "$row" \
        "$col" \
        "${prefix}${text}" \
        "$selected"
}

#============================================================
# Status
#============================================================

widget_status()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local label="${3-}"
    local state="${4:-INFO}"

    tui_move_to \
        "$row" \
        "$col" || \
        return 1

    case "$state"
    in
        OK|SUCCESS)
            if declare -F color_success >/dev/null 2>&1
            then
                color_success \
                    "[OK] ${label}"
            else
                printf '[OK] %s' \
                    "$label"
            fi
            ;;

        ERROR|FAIL)
            if declare -F color_error >/dev/null 2>&1
            then
                color_error \
                    "[ERROR] ${label}"
            else
                printf '[ERROR] %s' \
                    "$label"
            fi
            ;;

        WARN|WARNING)
            if declare -F color_warning >/dev/null 2>&1
            then
                color_warning \
                    "[WARN] ${label}"
            else
                printf '[WARN] %s' \
                    "$label"
            fi
            ;;

        *)
            if declare -F color_info >/dev/null 2>&1
            then
                color_info \
                    "[INFO] ${label}"
            else
                printf '[INFO] %s' \
                    "$label"
            fi
            ;;
    esac
}

#============================================================
# Title
#============================================================

widget_title()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local text="${3-}"

    tui_move_to \
        "$row" \
        "$col" || \
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
# Center text
#============================================================

widget_center()
{
    local row="${1:-1}"
    local text="${2-}"
    local width
    local text_length
    local col

    width="$(
        terminal_cols
    )"

    if [[ ! "$width" =~ ^[0-9]+$ ]] ||
       (( width == 0 ))
    then
        return 1
    fi

    text_length="${#text}"

    if (( text_length >= width ))
    then
        col=1
    else
        col=$(( (width - text_length) / 2 + 1 ))
    fi

    widget_print_at \
        "$row" \
        "$col" \
        "$text"
}

#============================================================
# Progress
#============================================================

widget_progress()
{
    local row="${1:-1}"
    local col="${2:-1}"
    local width="${3:-30}"
    local percent="${4:-0}"
    local filled
    local empty
    local i

    if ! [[ "$width" =~ ^[0-9]+$ &&
            "$percent" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid progress arguments"

        return 1
    fi

    (( percent > 100 )) && \
        percent=100

    filled=$(( width * percent / 100 ))
    empty=$(( width - filled ))

    tui_move_to \
        "$row" \
        "$col" || \
        return 1

    printf '[%s%s] %3d%%' \
        "$(
            for (( i=0; i<filled; i++ ))
            do
                printf '#'
            done
        )" \
        "$(
            for (( i=0; i<empty; i++ ))
            do
                printf ' '
            done
        )" \
        "$percent"
}

#============================================================
# Initialization check
#============================================================

widgets_is_initialized()
{
    (( WIDGETS_INITIALIZED ))
}

#============================================================
# End
#============================================================
