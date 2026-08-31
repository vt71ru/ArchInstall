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
#   • Возврат управления controller после выбора
#
#  Не выполняет:
#   • Изменение раскладки Live ISO
#   • Настройку target system
#
#  Применение к установленной системе выполняется
#  отдельным post-install этапом.
#
#============================================================

if [[ -n "${KEYBOARD_SH_LOADED:-}" ]]
then
    return 0
fi

readonly KEYBOARD_SH_LOADED=1

#============================================================
# Available layouts
#============================================================

declare -ga KEYBOARD_LAYOUTS=(
    us
    de
    fr
    ru
)

KEYBOARD_SELECTED=0

readonly KEYBOARD_VISIBLE=6

#============================================================
# Logging
#============================================================

keyboard_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@"
    fi

    return 0
}

keyboard_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@"
    fi

    return 0
}

keyboard_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@"
    fi

    return 0
}

#============================================================
# Restore configuration
#============================================================

keyboard_restore_config()
{
    local configured=""
    local index

    if ! declare -F config_get >/dev/null 2>&1
    then
        keyboard_log_warn \
            "config_get() is not available"

        return 0
    fi

    configured="$(
        config_get SYSTEM_KEYMAP \
            2>/dev/null \
            || true
    )"

    if [[ -z "$configured" ]]
    then
        KEYBOARD_SELECTED=0
        return 0
    fi

    for index in "${!KEYBOARD_LAYOUTS[@]}"
    do
        if [[ "${KEYBOARD_LAYOUTS[index]}" == "$configured" ]]
        then
            KEYBOARD_SELECTED="$index"

            keyboard_log_info \
                "Restored keyboard layout: ${configured}"

            return 0
        fi
    done

    keyboard_log_warn \
        "Configured keyboard layout is unavailable: ${configured}"

    KEYBOARD_SELECTED=0

    return 0
}

#============================================================
# Validate layout
#============================================================

keyboard_validate_layout()
{
    local layout="${1:-}"

    case "$layout"
    in
        us|de|fr|ru)
            return 0
            ;;

        *)
            keyboard_log_error \
                "Unsupported keyboard layout: ${layout}"

            return 1
            ;;
    esac
}

#============================================================
# Draw
#============================================================

keyboard_draw()
{
    local row=5
    local index
    local width="${TUI_COLS:-80}"

    if declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear || return 1
    fi

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "Keyboard layout" || return 1
    fi

    if declare -F draw_panel >/dev/null 2>&1
    then
        draw_panel \
            "Select keyboard" \
            3 \
            5 \
            12 \
            45 || return 1
    fi

    for (( index=0; index<${#KEYBOARD_LAYOUTS[@]} && index<KEYBOARD_VISIBLE; index++ ))
    do
        if declare -F tui_move >/dev/null 2>&1
        then
            tui_move \
                "$row" \
                8 || return 1
        elif declare -F cursor_move >/dev/null 2>&1
        then
            cursor_move \
                "$row" \
                8 || return 1
        else
            printf '\n'
        fi

        if (( index == KEYBOARD_SELECTED ))
        then
            if declare -F color_selected >/dev/null 2>&1
            then
                color_selected \
                    "> ${KEYBOARD_LAYOUTS[index]}"
            elif declare -F tui_print >/dev/null 2>&1
            then
                tui_print \
                    "> ${KEYBOARD_LAYOUTS[index]}"
            else
                printf '> %s' \
                    "${KEYBOARD_LAYOUTS[index]}"
            fi
        else
            if declare -F tui_print >/dev/null 2>&1
            then
                tui_print \
                    "  ${KEYBOARD_LAYOUTS[index]}"
            else
                printf '  %s' \
                    "${KEYBOARD_LAYOUTS[index]}"
            fi
        fi

        row=$((row + 1))
    done

    if declare -F statusbar_draw >/dev/null 2>&1
    then
        statusbar_draw \
            "↑↓ Select   Enter Apply   Esc Back" \
            || return 1
    fi

    if declare -F screen_refresh >/dev/null 2>&1
    then
        screen_refresh \
            2>/dev/null \
            || true
    fi

    return 0
}

#============================================================
# Navigation
#============================================================

keyboard_previous()
{
    if (( KEYBOARD_SELECTED > 0 ))
    then
        KEYBOARD_SELECTED=$((KEYBOARD_SELECTED - 1))
    else
        KEYBOARD_SELECTED=$(( ${#KEYBOARD_LAYOUTS[@]} - 1 ))
    fi

    return 0
}

keyboard_next()
{
    if (( KEYBOARD_SELECTED < ${#KEYBOARD_LAYOUTS[@]} - 1 ))
    then
        KEYBOARD_SELECTED=$((KEYBOARD_SELECTED + 1))
    else
        KEYBOARD_SELECTED=0
    fi

    return 0
}

#============================================================
# Apply
#============================================================

keyboard_apply()
{
    local layout=""

    if (( KEYBOARD_SELECTED < 0 ))
    then
        keyboard_log_error \
            "Invalid keyboard selection index: ${KEYBOARD_SELECTED}"

        return 1
    fi

    if (( KEYBOARD_SELECTED >= ${#KEYBOARD_LAYOUTS[@]} ))
    then
        keyboard_log_error \
            "Keyboard selection index out of range: ${KEYBOARD_SELECTED}"

        return 1
    fi

    layout="${KEYBOARD_LAYOUTS[KEYBOARD_SELECTED]}"

    if ! keyboard_validate_layout "$layout"
    then
        return 1
    fi

    #--------------------------------------------------------
    # Save configuration
    #--------------------------------------------------------

    if ! declare -F config_set >/dev/null 2>&1
    then
        keyboard_log_error \
            "config_set() is not available"

        return 1
    fi

    if ! config_set \
        SYSTEM_KEYMAP \
        "$layout"
    then
        keyboard_log_error \
            "Failed to set SYSTEM_KEYMAP=${layout}"

        return 1
    fi

    if declare -F config_save >/dev/null 2>&1
    then
        if ! config_save
        then
            keyboard_log_error \
                "Failed to save keyboard configuration"

            return 1
        fi
    fi

    keyboard_log_info \
        "Keyboard layout selected: ${layout}"

    return 0
}

#============================================================
# Main
#============================================================

keyboard()
{
    local event=""

    keyboard_log_info \
        "Keyboard configuration started"

    #--------------------------------------------------------
    # Restore saved configuration
    #--------------------------------------------------------

    keyboard_restore_config || return 1

    #--------------------------------------------------------
    # Selection loop
    #--------------------------------------------------------

    while true
    do
        if ! keyboard_draw
        then
            keyboard_log_error \
                "Failed to draw keyboard configuration screen"

            return 1
        fi

        #----------------------------------------------------
        # event_read() in this project stores the result in
        # TUI_EVENT. Do not use command substitution here.
        #----------------------------------------------------

        if ! event_read
        then
            keyboard_log_error \
                "event_read() failed"

            return 1
        fi

        event="${TUI_EVENT:-}"

        case "$event"
        in

            #------------------------------------------------
            # Up
            #------------------------------------------------

            "$EVENT_UP")
                keyboard_previous
                ;;

            #------------------------------------------------
            # Down
            #------------------------------------------------

            "$EVENT_DOWN")
                keyboard_next
                ;;

            #------------------------------------------------
            # Enter
            #
            # IMPORTANT:
            # After successful Apply we RETURN from keyboard().
            # This allows installer_full_install() to continue
            # with the next stage: locale.
            #------------------------------------------------

            "$EVENT_SELECT")

                if ! keyboard_apply
                then
                    keyboard_log_error \
                        "Failed to apply keyboard layout"

                    continue
                fi

                keyboard_log_info \
                    "Keyboard configuration completed"

                return 0
                ;;

            #------------------------------------------------
            # Escape
            #
            # In a full installation Esc should NOT silently
            # report success. Otherwise the controller would
            # continue to the next installation stage without
            # a valid keyboard selection.
            #------------------------------------------------

            "$EVENT_BACK")

                keyboard_log_warn \
                    "Keyboard configuration cancelled"

                return 1
                ;;

            #------------------------------------------------
            # Unknown event
            #------------------------------------------------

            *)
                keyboard_log_warn \
                    "Unknown keyboard event: ${event:-<empty>}"
                ;;
        esac
    done
}
