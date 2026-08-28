#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# utils.sh
#
# Общие вспомогательные функции
#
# Обязанности:
#  • Проверки
#  • Работа с файлами
#  • Безопасные команды
#  • Строковые операции
#
# Не содержит логику установки.
#============================================================

if [[ -n "${UTILS_SH_LOADED:-}" ]]
then
    return 0
fi

readonly UTILS_SH_LOADED=1

#============================================================
# Files
#============================================================

file_exists()
{
    local file="${1:-}"

    [[ -f "$file" ]]
}

directory_exists()
{
    local directory="${1:-}"

    [[ -d "$directory" ]]
}

file_create()
{
    local file="${1:-}"

    [[ -n "$file" ]] || {
        logger_error \
            "file_create: file name is empty"
        return 1
    }

    touch \
        -- \
        "$file"
}

file_append()
{
    local file="${1:-}"

    if [[ -z "$file" ]]
    then
        logger_error \
            "file_append: file name is empty"

        return 1
    fi

    shift

    printf '%s\n' "$@" >> "$file"
}

#============================================================
# Commands
#============================================================

command_exists()
{
    local command_name="${1:-}"

    [[ -n "$command_name" ]] || \
        return 1

    command -v \
        "$command_name" \
        >/dev/null 2>&1
}

run_command()
{
    if (( $# == 0 ))
    then
        logger_error \
            "run_command: no command specified"

        return 1
    fi

    logger_debug \
        "Execute: $(printf '%q ' "$@")"

    "$@"
}

#============================================================
# Strings
#============================================================

string_empty()
{
    local value="${1-}"

    [[ -z "$value" ]]
}

string_not_empty()
{
    local value="${1-}"

    [[ -n "$value" ]]
}

string_trim()
{
    local value="${1-}"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s' \
        "$value"
}

#============================================================
# Numbers
#============================================================

is_number()
{
    local value="${1-}"

    [[ "$value" =~ ^[0-9]+$ ]]
}

clamp()
{
    local value="${1:-0}"
    local min="${2:-0}"
    local max="${3:-0}"

    if ! is_number "$value" ||
       ! is_number "$min" ||
       ! is_number "$max"
    then
        logger_error \
            "clamp: invalid numeric argument"

        return 1
    fi

    if (( min > max ))
    then
        logger_error \
            "clamp: min is greater than max"

        return 1
    fi

    if (( value < min ))
    then
        printf '%s' \
            "$min"

        return 0
    fi

    if (( value > max ))
    then
        printf '%s' \
            "$max"

        return 0
    fi

    printf '%s' \
        "$value"
}

#============================================================
# System
#============================================================

get_hostname()
{
    hostname
}

get_username()
{
    id -un
}

#============================================================
# Wait
#============================================================

wait_key()
{
    local message="${1:-Press Enter}"

    printf '%s ' \
        "$message"

    IFS= read -r
}

#============================================================
# Millisecond sleep
#============================================================

sleep_ms()
{
    local ms="${1:-}"

    if [[ ! "$ms" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "sleep_ms: invalid milliseconds value: ${ms}"

        return 1
    fi

    if (( ms == 0 ))
    then
        return 0
    fi

    sleep \
        "$(awk \
            -v ms="$ms" \
            'BEGIN { printf "%.3f", ms / 1000 }'
        )"
}

#============================================================
# Logging helpers
#============================================================

debug_var()
{
    local name="${1:-}"
    local value

    if [[ -z "$name" ]]
    then
        logger_error \
            "debug_var: variable name is empty"

        return 1
    fi

    if ! config_exists "$name"
    then
        logger_warn \
            "debug_var: unknown configuration key: ${name}"

        return 1
    fi

    value="$(
        config_get \
            "$name"
    )" || return 1

    logger_debug \
        "${name}=${value}"
}

#============================================================
# End
#============================================================
