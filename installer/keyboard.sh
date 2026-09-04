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
#   • выбор keymap
#   • восстановление сохранённого значения
#   • сохранение SYSTEM_KEYMAP
#   • возврат управления controller после выбора
#
#  Не выполняет:
#   • изменение раскладки Live ISO
#   • настройку target system
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
export KEYBOARD_SH_LOADED

#============================================================
# Available layouts
#============================================================

declare -ga KEYBOARD_LAYOUTS=(
    "us"
    "de"
    "fr"
    "ru"
)

KEYBOARD_SELECTED=0

readonly KEYBOARD_VISIBLE=6

#============================================================
# Logging
#============================================================

keyboard_log_info()
{
    if declare -F log_info >/dev/null 2>&1
    then
        log_info "$@" || true
    elif declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@" || true
    else
        printf '[INFO] %s\n' "$*" >&2
    fi

    return 0
}

keyboard_log_warn()
{
    if declare -F log_warn >/dev/null 2>&1
    then
        log_warn "$@" || true
    elif declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@" || true
    else
        printf '[WARN] %s\n' "$*" >&2
    fi

    return 0
}

keyboard_log_error()
{
    if declare -F log_error >/dev/null 2>&1
    then
        log_error "$@" || true
    elif declare -F logger_error >/dev/null 2>&1
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
            "config_get() is not available; using default keymap"

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

    case "$layout" in

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
    # Validate current selection
    #--------------------------------------------------------

    if ! keyboard_validate_selection
    then
        return 1
    fi

    #--------------------------------------------------------
    # Clear screen
    #--------------------------------------------------------

    if declare -F tui_clear >/dev/null 2>&1
    then
        if ! tui_clear
        then
            keyboard_log_error \
                "tui_clear() failed"

            return 1
        fi
    else
        printf '\033[2J\033[H' || return 1
    fi

    #--------------------------------------------------------
    # Title
    #--------------------------------------------------------

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        if ! titlebar_draw \
            "Keyboard layout"
        then
            keyboard_log_error \
                "titlebar_draw() failed"

            return 1
        fi
    else
        printf '\nKeyboard layout\n' || return 1
    fi

    #--------------------------------------------------------
    # Panel
    #--------------------------------------------------------

    if declare -F draw_panel >/dev/null 2>&1
    then
        if ! draw_panel \
            "Select keyboard" \
            3 \
            5 \
            12 \
            45
        then
            keyboard_log_error \
                "draw_panel() failed"

            return 1
        fi
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

        #----------------------------------------------------
        # Cursor position
        #----------------------------------------------------

        if declare -F tui_move >/dev/null 2>&1
        then
            if ! tui_move \
                "$row" \
                8
            then
                keyboard_log_error \
                    "tui_move() failed"

                return 1
            fi

        elif declare -F cursor_move >/dev/null 2>&1
        then
            if ! cursor_move \
                "$row" \
                8
            then
                keyboard_log_error \
                    "cursor_move() failed"

                return 1
            fi

        else
            printf '\033[%d;%dH' \
                "$row" \
                8 || return 1
        fi

        #----------------------------------------------------
        # Draw selected / normal item
        #----------------------------------------------------

        if (( index == KEYBOARD_SELECTED ))
        then
            if declare -F color_selected >/dev/null 2>&1
            then
                if ! color_selected \
                    "> ${KEYBOARD_LAYOUTS[index]}"
                then
                    keyboard_log_error \
                        "color_selected() failed"

                    return 1
                fi
            else
                printf '> %s' \
                    "${KEYBOARD_LAYOUTS[index]}" || return 1
            fi
        else
            if declare -F tui_print >/dev/null 2>&1
            then
                if ! tui_print \
                    "  ${KEYBOARD_LAYOUTS[index]}"
                then
                    keyboard_log_error \
                        "tui_print() failed"

                    return 1
                fi
            else
                printf '  %s' \
                    "${KEYBOARD_LAYOUTS[index]}" || return 1
            fi
        fi

        row=$((row + 1))
    done

    #--------------------------------------------------------
    # Current selection
    #--------------------------------------------------------

    if declare -F tui_move >/dev/null 2>&1
    then
        if ! tui_move \
            "$((row + 1))" \
            8
        then
            keyboard_log_error \
                "tui_move() failed for current selection"

            return 1
        fi
    elif declare -F cursor_move >/dev/null 2>&1
    then
        if ! cursor_move \
            "$((row + 1))" \
            8
        then
            keyboard_log_error \
                "cursor_move() failed for current selection"

            return 1
        fi
    fi

    if declare -F color_info >/dev/null 2>&1
    then
        if ! color_info \
            "Current: ${KEYBOARD_LAYOUTS[KEYBOARD_SELECTED]}"
        then
            keyboard_log_error \
                "color_info() failed"

            return 1
        fi

    elif declare -F tui_print >/dev/null 2>&1
    then
        if ! tui_print \
            "Current: ${KEYBOARD_LAYOUTS[KEYBOARD_SELECTED]}"
        then
            keyboard_log_error \
                "tui_print() failed for current selection"

            return 1
        fi

    else
        printf \
            'Current: %s' \
            "${KEYBOARD_LAYOUTS[KEYBOARD_SELECTED]}" \
            || return 1
    fi

    #--------------------------------------------------------
    # Status bar
    #--------------------------------------------------------

    if declare -F statusbar_draw >/dev/null 2>&1
    then
        if ! statusbar_draw \
            "↑↓ Select   Home/End Move   Enter Apply   Esc Back"
        then
            keyboard_log_error \
                "statusbar_draw() failed"

            return 1
        fi
    fi

    #--------------------------------------------------------
    # Refresh
    #--------------------------------------------------------

    if declare -F screen_refresh >/dev/null 2>&1
    then
        if ! screen_refresh
        then
            keyboard_log_error \
                "screen_refresh() failed"

            return 1
        fi

    elif declare -F tui_flush >/dev/null 2>&1
    then
        if ! tui_flush
        then
            keyboard_log_error \
                "tui_flush() failed"

            return 1
        fi
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
        keyboard_log_error \
            "Cannot move selection: no keyboard layouts"

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
        keyboard_log_error \
            "Cannot move selection: no keyboard layouts"

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

keyboard_home()
{
    if (( ${#KEYBOARD_LAYOUTS[@]} == 0 ))
    then
        keyboard_log_error \
            "Cannot move to first layout: list is empty"

        return 1
    fi

    KEYBOARD_SELECTED=0

    return 0
}

keyboard_end()
{
    local count="${#KEYBOARD_LAYOUTS[@]}"

    if (( count == 0 ))
    then
        keyboard_log_error \
            "Cannot move to last layout: list is empty"

        return 1
    fi

    KEYBOARD_SELECTED=$((count - 1))

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

    if ! keyboard_validate_selection
    then
        return 1
    fi

    #--------------------------------------------------------
    # Get layout
    #--------------------------------------------------------

    layout="${KEYBOARD_LAYOUTS[KEYBOARD_SELECTED]}"

    #--------------------------------------------------------
    # Validate layout
    #--------------------------------------------------------

    if ! keyboard_validate_layout \
        "$layout"
    then
        return 1
    fi

    #--------------------------------------------------------
    # config_set required
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
# Main stage
#============================================================

keyboard()
{
    local event=""

    keyboard_log_info \
        "Keyboard configuration started"

    #--------------------------------------------------------
    # Restore saved value
    #--------------------------------------------------------

    if ! keyboard_restore_config
    then
        keyboard_log_error \
            "Failed to restore keyboard configuration"

        return 1
    fi

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
        # event_read() sets TUI_EVENT.
        # Do not use:
        #
        #     event="$(event_read)"
        #
        # because event_read() operates with global TUI state.
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

        case "$event" in

            "$EVENT_UP")

                if ! keyboard_previous
                then
                    keyboard_log_warn \
                        "Failed to move keyboard selection up"
                fi

                ;;

            "$EVENT_DOWN")

                if ! keyboard_next
                then
                    keyboard_log_warn \
                        "Failed to move keyboard selection down"
                fi

                ;;

            "$EVENT_HOME")

                if ! keyboard_home
                then
                    keyboard_log_warn \
                        "Failed to move to first keyboard layout"
                fi

                ;;

            "$EVENT_END")

                if ! keyboard_end
                then
                    keyboard_log_warn \
                        "Failed to move to last keyboard layout"
                fi

                ;;

            "$EVENT_SELECT")

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

            "$EVENT_NONE")

                ;;

            "$EVENT_CHAR")

                keyboard_log_warn \
                    "Unsupported keyboard character event"

                ;;

            "")

                keyboard_log_warn \
                    "event_read() returned empty event"

                ;;

            *)

                keyboard_log_warn \
                    "Unknown keyboard event: ${event}"

                ;;
        esac
    done
}

#============================================================
# Direct execution
#============================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
    if keyboard
    then
        exit 0
    else
        exit $?
    fi
fi
