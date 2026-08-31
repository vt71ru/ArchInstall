#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  installer/keyboard.sh
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
#============================================================

#============================================================
# Load guard
#============================================================

if [[ -n "${KEYBOARD_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

KEYBOARD_SH_LOADED=1

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
        logger_info "$@" || true
    else
        printf '[INFO] %s\n' "$*" >&2
    fi

    return 0
}

keyboard_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@" || true
    else
        printf '[WARN] %s\n' "$*" >&2
    fi

    return 0
}

keyboard_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@" || true
    else
        printf '[ERROR] %s\n' "$*" >&2
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

    KEYBOARD_SELECTED=0

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
        keyboard_log_info \
            "No saved keyboard layout; using default: us"

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
        "Saved keyboard layout is unavailable: ${configured}"

    KEYBOARD_SELECTED=0

    return 0
}

#============================================================
# Validate selection
#============================================================

keyboard_validate_selection()
{
    local count="${#KEYBOARD_LAYOUTS[@]}"

    if (( count == 0 ))
    then
        keyboard_log_error \
            "No keyboard layouts are available"

        return 1
    fi

    if (( KEYBOARD_SELECTED < 0 ))
    then
        keyboard_log_error \
            "Invalid keyboard selection: ${KEYBOARD_SELECTED}"

        return 1
    fi

    if (( KEYBOARD_SELECTED >= count ))
    then
        keyboard_log_error \
            "Keyboard selection out of range: ${KEYBOARD_SELECTED}"

        return 1
    fi

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

    #--------------------------------------------------------
    # Clear screen
    #--------------------------------------------------------

    if declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear || true
    elif declare -F screen_prepare >/dev/null 2>&1
    then
        screen_prepare || true
    else
        printf '\033[2J\033[H'
    fi

    #--------------------------------------------------------
    # Title
    #--------------------------------------------------------

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "Keyboard layout" || true
    else
        printf '\nKeyboard layout\n'
    fi

    #--------------------------------------------------------
    # Panel
    #--------------------------------------------------------

    if declare -F draw_panel >/dev/null 2>&1
    then
        draw_panel \
            "Select keyboard" \
            3 \
            5 \
            12 \
            45 || true
    fi

    #--------------------------------------------------------
    # Entries
    #--------------------------------------------------------

    for (( index=0; index<${#KEYBOARD_LAYOUTS[@]}; index++ ))
    do
        if (( index >= KEYBOARD_VISIBLE ))
        then
            break
        fi

        if declare -F cursor_move >/dev/null 2>&1
        then
            cursor_move \
                "$row" \
                8 || true
        elif declare -F tui_move >/dev/null 2>&1
        then
            tui_move \
                "$row" \
                8 || true
        else
            printf '\n'
        fi

        if (( index == KEYBOARD_SELECTED ))
        then
            printf '> %s' \
                "${KEYBOARD_LAYOUTS[index]}"
        else
            printf '  %s' \
                "${KEYBOARD_LAYOUTS[index]}"
        fi

        row=$((row + 1))
    done

    #--------------------------------------------------------
    # Status bar
    #--------------------------------------------------------

    if declare -F statusbar_draw >/dev/null 2>&1
    then
        statusbar_draw \
            "↑↓ Select   Enter Apply   Esc Back" || true
    fi

    #--------------------------------------------------------
    # Refresh
    #--------------------------------------------------------

    if declare -F screen_refresh >/dev/null 2>&1
    then
        screen_refresh || true
    fi

    return 0
}

#============================================================
# Navigation
#============================================================

keyboard_previous()
{
    local count="${#KEYBOARD_LAYOUTS[@]}"

    if (( count == 0 ))
    then
        return 1
    fi

    if (( KEYBOARD_SELECTED > 0 ))
    then
        KEYBOARD_SELECTED=$((KEYBOARD_SELECTED - 1))
    else
        KEYBOARD_SELECTED=$((count - 1))
    fi

    return 0
}

keyboard_next()
{
    local count="${#KEYBOARD_LAYOUTS[@]}"

    if (( count == 0 ))
    then
        return 1
    fi

    if (( KEYBOARD_SELECTED < count - 1 ))
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

    #--------------------------------------------------------
    # Validate index
    #--------------------------------------------------------

    keyboard_validate_selection || return 1

    #--------------------------------------------------------
    # Get layout
    #--------------------------------------------------------

    layout="${KEYBOARD_LAYOUTS[KEYBOARD_SELECTED]}"

    #--------------------------------------------------------
    # Validate layout
    #--------------------------------------------------------

    keyboard_validate_layout \
        "$layout" || return 1

    #--------------------------------------------------------
    # Check config_set
    #--------------------------------------------------------

    if ! declare -F config_set >/dev/null 2>&1
    then
        keyboard_log_error \
            "config_set() is not available"

        return 1
    fi

    #--------------------------------------------------------
    # Save SYSTEM_KEYMAP
    #--------------------------------------------------------

    if ! config_set \
        SYSTEM_KEYMAP \
        "$layout"
    then
        keyboard_log_error \
            "Failed to set SYSTEM_KEYMAP=${layout}"

        return 1
    fi

    #--------------------------------------------------------
    # Save configuration
    #--------------------------------------------------------

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
    # Restore saved value
    #--------------------------------------------------------

    keyboard_restore_config || return 1

    #--------------------------------------------------------
    # Selection loop
    #--------------------------------------------------------

    while true
    do
        #----------------------------------------------------
        # Draw
        #----------------------------------------------------

        if ! keyboard_draw
        then
            keyboard_log_error \
                "Failed to draw keyboard screen"

            return 1
        fi

        #----------------------------------------------------
        # Read event
        #
        # IMPORTANT:
        # event_read() must store result in TUI_EVENT.
        #
        # Do NOT use:
        #
        # event="$(event_read)"
        #
        # because event_read() belongs to the TUI event
        # subsystem and may use the return code for errors.
        #----------------------------------------------------

        TUI_EVENT=""

        if ! event_read
        then
            keyboard_log_error \
                "event_read() failed"

            return 1
        fi

        event="${TUI_EVENT:-}"

        #----------------------------------------------------
        # Process event
        #----------------------------------------------------

        case "$event"
        in

            "$EVENT_UP")
                keyboard_previous
                ;;

            "$EVENT_DOWN")
                keyboard_next
                ;;

            "$EVENT_SELECT")

                #--------------------------------------------
                # Enter = apply and EXIT keyboard stage
                #--------------------------------------------

                if keyboard_apply
                then
                    keyboard_log_info \
                        "Keyboard configuration completed"

                    return 0
                fi

                keyboard_log_error \
                    "Failed to apply keyboard layout"

                ;;

            "$EVENT_BACK")

                keyboard_log_warn \
                    "Keyboard configuration cancelled"

                return 1
                ;;

            *)

                keyboard_log_warn \
                    "Unknown keyboard event: ${event:-<empty>}"

                ;;
        esac
    done
}

