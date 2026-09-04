#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  installer/locale.sh
#
#  Настройка локали установленной системы.
#
#  Ответственность:
#   • выбор локали
#   • выбор списка локалей
#   • сохранение настроек в CONFIG
#   • проверка выбранных значений
#
#  Не выполняет:
#   • locale-gen
#   • изменение target /mnt
#   • создание /etc/locale.conf
#
#  Эти действия выполняются в locale_generate.sh.
#
#============================================================

#============================================================
# Load guard
#============================================================

if [[ -n "${LOCALE_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

LOCALE_SH_LOADED=1
export LOCALE_SH_LOADED

#============================================================
# State
#============================================================

declare -ga LOCALE_AVAILABLE=(
    "en_US.UTF-8"
    "de_DE.UTF-8"
    "fr_FR.UTF-8"
    "ru_RU.UTF-8"
)

declare -ga LOCALE_SELECTED_LIST=()

LOCALE_SELECTED=0

readonly LOCALE_VISIBLE=6

#============================================================
# Logging
#============================================================

locale_log_info()
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

locale_log_warn()
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

locale_log_error()
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
# Validate locale
#============================================================

locale_validate()
{
    local locale="${1:-}"

    if [[ -z "$locale" ]]
    then
        locale_log_error \
            "Locale is empty"
        return 1
    fi

    case "$locale" in
        en_US.UTF-8|\
        de_DE.UTF-8|\
        fr_FR.UTF-8|\
        ru_RU.UTF-8)
            return 0
            ;;

        *)
            locale_log_error \
                "Unsupported locale: ${locale}"
            return 1
            ;;
    esac
}

#============================================================
# Restore configuration
#============================================================

locale_restore_config()
{
    local configured=""
    local default_locale=""
    local index

    LOCALE_SELECTED=0
    LOCALE_SELECTED_LIST=()

    #--------------------------------------------------------
    # Restore default locale
    #--------------------------------------------------------

    if declare -F config_get >/dev/null 2>&1
    then
        configured="$(
            config_get LOCALE \
                2>/dev/null \
                || true
        )"

        if [[ -n "$configured" ]]
        then
            for index in "${!LOCALE_AVAILABLE[@]}"
            do
                if [[ "${LOCALE_AVAILABLE[index]}" == "$configured" ]]
                then
                    LOCALE_SELECTED="$index"
                    default_locale="$configured"
                    break
                fi
            done
        fi
    fi

    #--------------------------------------------------------
    # Default locale
    #--------------------------------------------------------

    if [[ -z "$default_locale" ]]
    then
        default_locale="${LOCALE_AVAILABLE[0]}"
    fi

    #--------------------------------------------------------
    # Restore LOCALES
    #--------------------------------------------------------

    if declare -F config_get >/dev/null 2>&1
    then
        local saved_locales=""

        saved_locales="$(
            config_get LOCALES \
                2>/dev/null \
                || true
        )"

        if [[ -n "$saved_locales" ]]
        then
            local locale=""
            local valid=0

            for locale in $saved_locales
            do
                if locale_validate "$locale"
                then
                    LOCALE_SELECTED_LIST+=("$locale")
                    valid=1
                fi
            done

            if (( valid == 0 ))
            then
                LOCALE_SELECTED_LIST=(
                    "$default_locale"
                )
            fi
        else
            LOCALE_SELECTED_LIST=(
                "$default_locale"
            )
        fi
    else
        LOCALE_SELECTED_LIST=(
            "$default_locale"
        )
    fi

    locale_log_info \
        "Restored default locale: ${default_locale}"

    locale_log_info \
        "Configured locales: ${LOCALE_SELECTED_LIST[*]}"

    return 0
}

#============================================================
# Selection validation
#============================================================

locale_validate_selection()
{
    local count="${#LOCALE_AVAILABLE[@]}"

    if (( count == 0 ))
    then
        locale_log_error \
            "No locales are available"

        return 1
    fi

    if (( LOCALE_SELECTED < 0 ))
    then
        locale_log_error \
            "Invalid locale selection: ${LOCALE_SELECTED}"

        return 1
    fi

    if (( LOCALE_SELECTED >= count ))
    then
        locale_log_error \
            "Locale selection out of range: ${LOCALE_SELECTED}"

        return 1
    fi

    return 0
}

#============================================================
# Save configuration
#============================================================

locale_save_config()
{
    local locale=""
    local locales=""

    locale_validate_selection || return 1

    locale="${LOCALE_AVAILABLE[LOCALE_SELECTED]}"

    locale_validate "$locale" || return 1

    #--------------------------------------------------------
    # Selected locale becomes default LOCALE
    #--------------------------------------------------------

    if declare -F config_set >/dev/null 2>&1
    then
        if ! config_set \
            LOCALE \
            "$locale"
        then
            locale_log_error \
                "Failed to set LOCALE=${locale}"
            return 1
        fi

        #----------------------------------------------------
        # Ensure selected locale exists in LOCALES
        #----------------------------------------------------

        locales=""

        if declare -F config_get >/dev/null 2>&1
        then
            locales="$(
                config_get LOCALES \
                    2>/dev/null \
                    || true
            )"
        fi

        if [[ -z "$locales" ]]
        then
            locales="$locale"
        elif ! grep -Fqx \
            "$locale" \
            <(
                tr ' ' '\n' <<< "$locales"
            )
        then
            locales="${locales} ${locale}"
        fi

        if ! config_set \
            LOCALES \
            "$locales"
        then
            locale_log_error \
                "Failed to set LOCALES=${locales}"
            return 1
        fi

        #----------------------------------------------------
        # Save CONFIG
        #----------------------------------------------------

        if declare -F config_save >/dev/null 2>&1
        then
            if ! config_save
            then
                locale_log_error \
                    "Failed to save locale configuration"
                return 1
            fi
        fi
    else
        locale_log_warn \
            "config_set() is not available"
    fi

    locale_log_info \
        "Default locale selected: ${locale}"

    return 0
}

#============================================================
# Draw
#============================================================

locale_draw()
{
    local row=5
    local index

    #--------------------------------------------------------
    # Clear screen
    #--------------------------------------------------------

    if declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear || true
    else
        printf '\033[2J\033[H'
    fi

    #--------------------------------------------------------
    # Title
    #--------------------------------------------------------

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "Locale configuration" || true
    else
        printf '\nLocale configuration\n'
    fi

    #--------------------------------------------------------
    # Panel
    #--------------------------------------------------------

    if declare -F draw_panel >/dev/null 2>&1
    then
        draw_panel \
            "Select default locale" \
            3 \
            5 \
            15 \
            55 || true
    fi

    #--------------------------------------------------------
    # Entries
    #--------------------------------------------------------

    for ((index=0; index<${#LOCALE_AVAILABLE[@]}; index++))
    do
        if (( index >= LOCALE_VISIBLE ))
        then
            break
        fi

        if declare -F tui_move >/dev/null 2>&1
        then
            tui_move \
                "$row" \
                8 || true
        elif declare -F cursor_move >/dev/null 2>&1
        then
            cursor_move \
                "$row" \
                8 || true
        fi

        if (( index == LOCALE_SELECTED ))
        then
            if declare -F color_selected >/dev/null 2>&1
            then
                color_selected \
                    "> ${LOCALE_AVAILABLE[index]}" || true
            else
                printf '> %s' \
                    "${LOCALE_AVAILABLE[index]}"
            fi
        else
            if declare -F tui_print >/dev/null 2>&1
            then
                tui_print \
                    "  ${LOCALE_AVAILABLE[index]}" || true
            else
                printf '  %s' \
                    "${LOCALE_AVAILABLE[index]}"
            fi
        fi

        row=$((row + 1))
    done

    #--------------------------------------------------------
    # Current LOCALES
    #--------------------------------------------------------

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move \
            "$((row + 1))" \
            8 || true
    fi

    if declare -F tui_print >/dev/null 2>&1
    then
        tui_print \
            "Enabled: ${LOCALE_SELECTED_LIST[*]:-none}" || true
    else
        printf 'Enabled: %s' \
            "${LOCALE_SELECTED_LIST[*]:-none}"
    fi

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
    elif declare -F tui_flush >/dev/null 2>&1
    then
        tui_flush || true
    fi

    return 0
}

#============================================================
# Navigation
#============================================================

locale_previous()
{
    local count="${#LOCALE_AVAILABLE[@]}"

    if (( count == 0 ))
    then
        return 1
    fi

    if (( LOCALE_SELECTED > 0 ))
    then
        LOCALE_SELECTED=$((LOCALE_SELECTED - 1))
    else
        LOCALE_SELECTED=$((count - 1))
    fi

    return 0
}

locale_next()
{
    local count="${#LOCALE_AVAILABLE[@]}"

    if (( count == 0 ))
    then
        return 1
    fi

    if (( LOCALE_SELECTED < count - 1 ))
    then
        LOCALE_SELECTED=$((LOCALE_SELECTED + 1))
    else
        LOCALE_SELECTED=0
    fi

    return 0
}

#============================================================
# Main
#============================================================

locale()
{
    local event=""

    locale_log_info \
        "Locale configuration started"

    #--------------------------------------------------------
    # Restore saved state
    #--------------------------------------------------------

    locale_restore_config || return 1

    #--------------------------------------------------------
    # Selection loop
    #--------------------------------------------------------

    while true
    do
        if ! locale_draw
        then
            locale_log_error \
                "Failed to draw locale screen"
            return 1
        fi

        #----------------------------------------------------
        # IMPORTANT:
        #
        # event_read() stores the event in TUI_EVENT.
        #
        # Do NOT use:
        #
        # event="$(event_read)"
        #----------------------------------------------------

        TUI_EVENT=""

        if ! event_read
        then
            locale_log_error \
                "event_read() failed"
            return 1
        fi

        event="${TUI_EVENT:-}"

        #----------------------------------------------------
        # Process event
        #----------------------------------------------------

        case "$event" in

            "$EVENT_UP")
                locale_previous
                ;;

            "$EVENT_DOWN")
                locale_next
                ;;

            "$EVENT_HOME")
                LOCALE_SELECTED=0
                ;;

            "$EVENT_END")
                LOCALE_SELECTED=$(
                    (
                        ${#LOCALE_AVAILABLE[@]} - 1
                    )
                )
                ;;

            "$EVENT_SELECT")
                if locale_save_config
                then
                    locale_log_info \
                        "Locale configuration completed"
                    return 0
                fi

                locale_log_error \
                    "Failed to apply locale configuration"
                ;;

            "$EVENT_BACK")
                locale_log_warn \
                    "Locale configuration cancelled"
                return 1
                ;;

            "$EVENT_NONE")
                ;;

            *)
                locale_log_warn \
                    "Unknown locale event: ${event:-<empty>}"
                ;;
        esac
    done
}

