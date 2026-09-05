#!/usr/bin/env bash
#
# ============================================================
# Arch Installer
# ------------------------------------------------------------
# installer/locale.sh
#
# Настройка локали.
#
# ============================================================

# ============================================================
# AVAILABLE LOCALES
# ============================================================

declare -ar LOCALE_AVAILABLE=(
    "en_US.UTF-8"
    "de_DE.UTF-8"
    "fr_FR.UTF-8"
    "ru_RU.UTF-8"
)

LOCALE_SELECTED="${LOCALE_SELECTED:-0}"

# ============================================================
# LOGGING
# ============================================================

locale_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$*"
    else
        printf '[INFO] %s\n' "$*" >&2
    fi

    return 0
}

locale_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$*"
    else
        printf '[WARN] %s\n' "$*" >&2
    fi

    return 0
}

locale_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$*"
    else
        printf '[ERROR] %s\n' "$*" >&2
    fi

    return 0
}

# ============================================================
# DEPENDENCIES
# ============================================================

locale_require_dependencies()
{
    local function_name=""

    for function_name in \
        config_get \
        config_set \
        config_save \
        tui_clear \
        tui_printf \
        event_read \
        draw_box
    do
        if ! declare -F "$function_name" >/dev/null 2>&1
        then
            locale_log_error \
                "Required function unavailable: ${function_name}"

            return 1
        fi
    done

    return 0
}

# ============================================================
# RESTORE CONFIG
# ============================================================

locale_restore_config()
{
    local configured=""
    local i=0

    configured="$(
        config_get SYSTEM_LOCALE 2>/dev/null || true
    )"

    if [[ -z "$configured" ]]
    then
        LOCALE_SELECTED=0
        return 0
    fi

    for (( i=0; i<${#LOCALE_AVAILABLE[@]}; i++ ))
    do
        if [[ "${LOCALE_AVAILABLE[$i]}" == "$configured" ]]
        then
            LOCALE_SELECTED="$i"

            locale_log_info \
                "Restored locale configuration: ${configured}"

            return 0
        fi
    done

    LOCALE_SELECTED=0

    locale_log_warn \
        "Saved locale '${configured}' is unavailable"

    return 0
}

# ============================================================
# VALIDATE INDEX
# ============================================================

locale_validate_index()
{
    local index="${1:-}"

    if [[ ! "$index" =~ ^[0-9]+$ ]]
    then
        return 1
    fi

    if (( index >= ${#LOCALE_AVAILABLE[@]} ))
    then
        return 1
    fi

    return 0
}

# ============================================================
# DRAW
# ============================================================

locale_draw()
{
    local i=0
    local marker=""
    local width="${TUI_COLS:-80}"

    if ! locale_validate_index "$LOCALE_SELECTED"
    then
        LOCALE_SELECTED=0
    fi

    if ! tui_clear
    then
        locale_log_error \
            "tui_clear failed"

        return 1
    fi

    if ! tui_printf '\033[1;1H'
    then
        return 1
    fi

    tui_printf \
        '%s\n\n' \
        "Locale configuration" || return 1

    for (( i=0; i<${#LOCALE_AVAILABLE[@]}; i++ ))
    do
        marker=" "

        if (( i == LOCALE_SELECTED ))
        then
            marker=">"
        fi

        tui_printf \
            '  %s %s\n' \
            "$marker" \
            "${LOCALE_AVAILABLE[$i]}" || return 1
    done

    tui_printf '\n' || return 1

    tui_printf \
        '%s\n' \
        "↑↓ Navigate   Home/End Move   Enter Select   Esc Cancel" \
        || return 1

    return 0
}

# ============================================================
# MOVE
# ============================================================

locale_move_up()
{
    if (( LOCALE_SELECTED > 0 ))
    then
        (( LOCALE_SELECTED -= 1 ))
    else
        LOCALE_SELECTED=$(( ${#LOCALE_AVAILABLE[@]} - 1 ))
    fi

    return 0
}

locale_move_down()
{
    if (( LOCALE_SELECTED < ${#LOCALE_AVAILABLE[@]} - 1 ))
    then
        (( LOCALE_SELECTED += 1 ))
    else
        LOCALE_SELECTED=0
    fi

    return 0
}

locale_move_home()
{
    LOCALE_SELECTED=0
    return 0
}

locale_move_end()
{
    LOCALE_SELECTED=$(( ${#LOCALE_AVAILABLE[@]} - 1 ))
    return 0
}

# ============================================================
# APPLY
# ============================================================

locale_apply()
{
    local selected_locale=""

    if ! locale_validate_index "$LOCALE_SELECTED"
    then
        locale_log_error \
            "Invalid locale selection: ${LOCALE_SELECTED}"

        return 1
    fi

    selected_locale="${LOCALE_AVAILABLE[$LOCALE_SELECTED]}"

    if ! config_set \
        SYSTEM_LOCALE \
        "$selected_locale"
    then
        locale_log_error \
            "Failed to set SYSTEM_LOCALE"

        return 1
    fi

    if ! config_save
    then
        locale_log_error \
            "Failed to save locale configuration"

        return 1
    fi

    locale_log_info \
        "Locale selected: ${selected_locale}"

    return 0
}

# ============================================================
# MAIN
# ============================================================

locale()
{
    local event=""

    locale_log_info \
        "Locale configuration started"

    if ! locale_require_dependencies
    then
        return 1
    fi

    if ! locale_restore_config
    then
        return 1
    fi

    while true
    do
        if ! locale_draw
        then
            locale_log_error \
                "Failed to draw locale screen"

            return 1
        fi

        TUI_EVENT=""
        TUI_EVENT_CHAR=""

        if ! event_read
        then
            locale_log_error \
                "event_read failed"

            return 1
        fi

        event="${TUI_EVENT:-}"

        locale_log_info \
            "Locale event: ${event}"

        case "$event"
        in
            "$EVENT_UP")
                locale_move_up
                ;;

            "$EVENT_DOWN")
                locale_move_down
                ;;

            "$EVENT_HOME")
                locale_move_home
                ;;

            "$EVENT_END")
                locale_move_end
                ;;

            "$EVENT_SELECT")
                if locale_apply
                then
                    locale_log_info \
                        "Locale configuration completed"

                    return 0
                fi

                locale_log_error \
                    "Failed to apply locale"
                ;;

            "$EVENT_BACK")
                locale_log_warn \
                    "Locale configuration cancelled"

                return 1
                ;;

            "$EVENT_NONE"|"")
                ;;

            *)
                locale_log_warn \
                    "Unknown locale event: ${event}"
                ;;
        esac
    done
}

# ============================================================
# COMPATIBILITY
# ============================================================

locale_main()
{
    locale "$@"
}

# ============================================================
# DIRECT EXECUTION
# ============================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
    locale "$@"
fi
