#!/usr/bin/env bash
#
# ============================================================
# Arch Installer
# ------------------------------------------------------------
# installer/locale.sh
#
# Настройка локали системы.
#
# Ответственность:
#   • выбор locale
#   • восстановление сохранённого значения
#   • сохранение выбранной locale в CONFIG
#   • навигация клавиатурой
#   • подтверждение / отмена
#
# Не выполняет:
#   • locale-gen
#   • настройку установленной системы
#
# ============================================================

if [[ -n "${ARCH_INSTALLER_LOCALE_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

ARCH_INSTALLER_LOCALE_SH_LOADED=1
export ARCH_INSTALLER_LOCALE_SH_LOADED


# ============================================================
# Проверка обязательных функций
# ============================================================

locale_require_dependencies()
{
    if ! declare -F config_get >/dev/null 2>&1
    then
        return 1
    fi

    if ! declare -F config_set >/dev/null 2>&1
    then
        return 1
    fi

    if ! declare -F config_save >/dev/null 2>&1
    then
        return 1
    fi

    if ! declare -F tui_clear >/dev/null 2>&1
    then
        return 1
    fi

    if ! declare -F tui_printf >/dev/null 2>&1
    then
        return 1
    fi

    if ! declare -F draw_box >/dev/null 2>&1
    then
        return 1
    fi

    if ! declare -F event_read >/dev/null 2>&1
    then
        return 1
    fi

    return 0
}


# ============================================================
# Logging wrappers
# ============================================================

locale_log_info()
{
    if declare -F log_info >/dev/null 2>&1
    then
        log_info "$*"
    fi
}

locale_log_warn()
{
    if declare -F log_warn >/dev/null 2>&1
    then
        log_warn "$*"
    fi
}

locale_log_error()
{
    if declare -F log_error >/dev/null 2>&1
    then
        log_error "$*"
    fi
}


# ============================================================
# Доступные локали
# ============================================================

declare -ar LOCALE_AVAILABLE=(
    "en_US.UTF-8"
    "de_DE.UTF-8"
    "fr_FR.UTF-8"
    "ru_RU.UTF-8"
)


# ============================================================
# Текущее состояние
# ============================================================

LOCALE_SELECTED="${LOCALE_SELECTED:-0}"


# ============================================================
# Получить сохранённую locale
# ============================================================

locale_restore_config()
{
    local configured=""

    if ! configured="$(config_get SYSTEM_LOCALE 2>/dev/null)"
    then
        configured=""
    fi

    if [[ -z "$configured" ]]
    then
        LOCALE_SELECTED=0
        return 0
    fi

    local i

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
        "Saved locale '${configured}' is not available, using default"

    return 0
}


# ============================================================
# Проверка индекса
# ============================================================

locale_validate_index()
{
    local index="${1:-}"

    if [[ ! "$index" =~ ^[0-9]+$ ]]
    then
        locale_log_error \
            "Invalid locale index: '${index}'"

        return 1
    fi

    if (( index < 0 || index >= ${#LOCALE_AVAILABLE[@]} ))
    then
        locale_log_error \
            "Locale index out of range: ${index}"

        return 1
    fi

    return 0
}


# ============================================================
# Сохранение выбранной locale
# ============================================================

locale_save_selection()
{
    local locale_value=""

    if ! locale_validate_index "$LOCALE_SELECTED"
    then
        return 1
    fi

    locale_value="${LOCALE_AVAILABLE[$LOCALE_SELECTED]}"

    if ! config_set SYSTEM_LOCALE "$locale_value"
    then
        locale_log_error \
            "Failed to save SYSTEM_LOCALE"

        return 1
    fi

    if ! config_save
    then
        locale_log_error \
            "Failed to save locale configuration"

        return 1
    fi

    locale_log_info \
        "Locale selected: ${locale_value}"

    return 0
}


# ============================================================
# Отрисовка меню
# ============================================================

locale_draw()
{
    local i
    local selected
    local title=""

    if ! locale_validate_index "$LOCALE_SELECTED"
    then
        LOCALE_SELECTED=0
    fi

    title="Locale"

    if ! tui_clear
    then
        locale_log_error \
            "tui_clear failed"

        return 1
    fi

    if ! tui_printf '\033[1;1H'
    then
        locale_log_error \
            "Failed to position cursor"

        return 1
    fi

    if ! tui_printf '%s\n' "$title"
    then
        locale_log_error \
            "Failed to print locale title"

        return 1
    fi

    if ! tui_printf '\n'
    then
        locale_log_error \
            "Failed to print locale spacing"

        return 1
    fi

    for (( i=0; i<${#LOCALE_AVAILABLE[@]}; i++ ))
    do
        selected=" "

        if (( i == LOCALE_SELECTED ))
        then
            selected=">"
        fi

        if ! tui_printf '  %s %s\n' \
            "$selected" \
            "${LOCALE_AVAILABLE[$i]}"
        then
            locale_log_error \
                "Failed to draw locale item ${i}"

            return 1
        fi
    done

    if ! tui_printf '\n'
    then
        locale_log_error \
            "Failed to print locale footer spacing"

        return 1
    fi

    if ! tui_printf \
        '%s\n' \
        "Up/Down Navigate  Home/End First/Last  Enter Select  Esc Cancel"
    then
        locale_log_error \
            "Failed to draw locale controls"

        return 1
    fi

    return 0
}


# ============================================================
# Перемещение вверх
# ============================================================

locale_move_up()
{
    if (( LOCALE_SELECTED > 0 ))
    then
        (( LOCALE_SELECTED-- ))
    else
        LOCALE_SELECTED=$(( ${#LOCALE_AVAILABLE[@]} - 1 ))
    fi

    return 0
}


# ============================================================
# Перемещение вниз
# ============================================================

locale_move_down()
{
    if (( LOCALE_SELECTED < ${#LOCALE_AVAILABLE[@]} - 1 ))
    then
        (( LOCALE_SELECTED++ ))
    else
        LOCALE_SELECTED=0
    fi

    return 0
}


# ============================================================
# Переход в начало
# ============================================================

locale_move_home()
{
    LOCALE_SELECTED=0
    return 0
}


# ============================================================
# Переход в конец
# ============================================================

locale_move_end()
{
    LOCALE_SELECTED=$(( ${#LOCALE_AVAILABLE[@]} - 1 ))
    return 0
}


# ============================================================
# Применение выбора
# ============================================================

locale_apply()
{
    local selected_locale=""

    if ! locale_validate_index "$LOCALE_SELECTED"
    then
        return 1
    fi

    selected_locale="${LOCALE_AVAILABLE[$LOCALE_SELECTED]}"

    if ! config_set SYSTEM_LOCALE "$selected_locale"
    then
        locale_log_error \
            "Failed to set SYSTEM_LOCALE='${selected_locale}'"

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
# Основная функция выбора locale
# ============================================================

locale()
{
    local event=""

    locale_log_info \
        "Locale configuration started"

    if ! locale_require_dependencies
    then
        locale_log_error \
            "Locale module dependencies are not available"

        return 1
    fi

    if ! locale_restore_config
    then
        locale_log_error \
            "Failed to restore locale configuration"

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

        if ! event_read
        then
            locale_log_error \
                "event_read failed"

            return 1
        fi

        event="${TUI_EVENT:-}"

        locale_log_info \
            "Locale event: ${event}"

        case "$event" in

            "$EVENT_UP")
                if ! locale_move_up
                then
                    locale_log_error \
                        "Failed to move locale selection up"

                    return 1
                fi
                ;;

            "$EVENT_DOWN")
                if ! locale_move_down
                then
                    locale_log_error \
                        "Failed to move locale selection down"

                    return 1
                fi
                ;;

            "$EVENT_HOME")
                if ! locale_move_home
                then
                    locale_log_error \
                        "Failed to move locale selection to home"

                    return 1
                fi
                ;;

            "$EVENT_END")
                if ! locale_move_end
                then
                    locale_log_error \
                        "Failed to move locale selection to end"

                    return 1
                fi
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
# Alias для совместимости
# ============================================================

locale_main()
{
    locale "$@"
}


# ============================================================
# Проверка при прямом запуске
# ============================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
    locale "$@"
fi
