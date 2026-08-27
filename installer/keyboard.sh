#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  keyboard.sh
#
#  Настройка раскладки клавиатуры.
#
#  Ответственность:
#   • Выбор keymap
#   • Восстановление сохранённого значения
#   • Сохранение SYSTEM_KEYMAP
#
#  Не выполняет:
#   • Изменение раскладки Live ISO
#   • Настройку target system
#
#  Применение к установленной системе выполняется
#  отдельным post-install этапом.
#============================================================

[[ -n "${KEYBOARD_SH_LOADED:-}" ]] && return

readonly KEYBOARD_SH_LOADED=1

#------------------------------------------------------------
# Available layouts
#------------------------------------------------------------

declare -ga KEYBOARD_LAYOUTS=(
    us
    de
    fr
    ru
)

KEYBOARD_SELECTED=0

readonly KEYBOARD_VISIBLE=6

#------------------------------------------------------------
# Restore configuration
#------------------------------------------------------------

keyboard_restore_config()
{
    local configured
    local index

    configured="$(
        config_get SYSTEM_KEYMAP \
            2>/dev/null \
            || true
    )"

    [[ -n "$configured" ]] || \
        return 0

    for index in "${!KEYBOARD_LAYOUTS[@]}"
    do
        if [[ "${KEYBOARD_LAYOUTS[index]}" == "$configured" ]]
        then
            KEYBOARD_SELECTED="$index"

            logger_debug \
                "Restored keyboard layout: ${configured}"

            return 0
        fi
    done

    logger_warn \
        "Configured keyboard layout is unavailable: ${configured}"
}

#------------------------------------------------------------
# Validate layout
#------------------------------------------------------------

keyboard_validate_layout()
{
    local layout="$1"

    case "$layout" in
        us|de|fr|ru)
            return 0
            ;;
        *)
            logger_error \
                "Unsupported keyboard layout: ${layout}"

            return 1
            ;;
    esac
}

#------------------------------------------------------------
# Draw
#------------------------------------------------------------

keyboard_draw()
{
    local row=5
    local index

    tui_clear

    titlebar_draw \
        "Keyboard layout"

    draw_panel \
        "Select keyboard" \
        3 \
        5 \
        12 \
        45

    for (( index=0; index<${#KEYBOARD_LAYOUTS[@]} && index<KEYBOARD_VISIBLE; index++ ))
    do
        cursor_move \
            "$row" \
            8

        if (( index == KEYBOARD_SELECTED ))
        then
            printf \
                '> %s' \
                "${KEYBOARD_LAYOUTS[index]}"
        else
            printf \
                '  %s' \
                "${KEYBOARD_LAYOUTS[index]}"
        fi

        ((row += 1))
    done

    statusbar_draw \
        "↑↓ Select   Enter Apply   Esc Back"

    screen_refresh
}

#------------------------------------------------------------
# Navigation
#------------------------------------------------------------

keyboard_previous()
{
    if (( KEYBOARD_SELECTED > 0 ))
    then
        ((KEYBOARD_SELECTED -= 1))
    else
        KEYBOARD_SELECTED=$(( ${#KEYBOARD_LAYOUTS[@]} - 1 ))
    fi
}

keyboard_next()
{
    if (( KEYBOARD_SELECTED < ${#KEYBOARD_LAYOUTS[@]} - 1 ))
    then
        ((KEYBOARD_SELECTED += 1))
    else
        KEYBOARD_SELECTED=0
    fi
}

#------------------------------------------------------------
# Apply
#------------------------------------------------------------

keyboard_apply()
{
    local layout

    layout="${KEYBOARD_LAYOUTS[KEYBOARD_SELECTED]}"

    keyboard_validate_layout \
        "$layout" || \
        return 1

    config_set \
        SYSTEM_KEYMAP \
        "$layout"

    config_save

    logger_info \
        "Keyboard layout selected: ${layout}"

    dialog_message \
        "Keyboard" \
        "Selected: ${layout}"
}

#------------------------------------------------------------
# Main
#------------------------------------------------------------

keyboard()
{
    local event

    logger_info \
        "Keyboard configuration started"

    keyboard_restore_config

    while true
    do
        keyboard_draw

        event="$(
            event_read
        )"

        case "$event" in
            "$EVENT_UP")
                keyboard_previous
                ;;
            "$EVENT_DOWN")
                keyboard_next
                ;;
            "$EVENT_SELECT")
                keyboard_apply || \
                    continue
                ;;
            "$EVENT_BACK")
                break
                ;;
        esac
    done

    logger_info \
        "Keyboard configuration finished"
}