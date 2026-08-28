#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# common.sh
#
# Общие helper-функции.
#============================================================

if [[ -n "${COMMON_SH_LOADED:-}" ]]
then
    return 0
fi

readonly COMMON_SH_LOADED=1

#============================================================
# Files
#============================================================

file_exists()
{
    [[ -f "${1:-}" ]]
}

directory_exists()
{
    [[ -d "${1:-}" ]]
}

file_create()
{
    local file="${1:-}"

    [[ -n "$file" ]] || return 1

    touch \
        -- \
        "$file"
}

file_append()
{
    local file="${1:-}"

    [[ -n "$file" ]] || return 1

    shift

    printf '%s\n' "$@" >> "$file"
}

#============================================================
# Commands
#============================================================

command_exists()
{
    [[ -n "${1:-}" ]] || return 1

    command -v \
        "$1" \
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
    [[ -z "${1-}" ]]
}

string_not_empty()
{
    [[ -n "${1-}" ]]
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
    [[ "${1-}" =~ ^[0-9]+$ ]]
}

clamp()
{
    local value="${1:-0}"
    local min="${2:-0}"
    local max="${3:-0}"

    is_number "$value" || return 1
    is_number "$min" || return 1
    is_number "$max" || return 1

    (( min <= max )) || return 1

    if (( value < min ))
    then
        printf '%s' "$min"
    elif (( value > max ))
    then
        printf '%s' "$max"
    else
        printf '%s' "$value"
    fi
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

sleep_ms()
{
    local ms="${1:-}"

    [[ "$ms" =~ ^[0-9]+$ ]] || \
        return 1

    sleep "$(
        awk \
            -v ms="$ms" \
            'BEGIN { printf "%.3f", ms / 1000 }'
    )"
}

#============================================================
# Debug configuration
#============================================================

debug_var()
{
    local name="${1:-}"
    local value

    [[ -n "$name" ]] || \
        return 1

    if ! config_exists "$name"
    then
        logger_warn \
            "Unknown configuration key: ${name}"

        return 1
    fi

    value="$(
        config_get "$name"
    )" || \
        return 1

    logger_debug \
        "${name}=${value}"
}
