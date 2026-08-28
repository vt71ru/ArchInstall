#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  logger.sh
#
#  Центральный модуль журналирования.
#
#  Ответственность:
#   • Инициализация логгера
#   • Запись сообщений в файл
#   • Вывод WARN / ERROR в stderr
#   • DEBUG / INFO / WARN / ERROR
#   • Запись исключений
#   • Закрытие логгера
#
#  Не зависит от других модулей ArchInstaller.
#============================================================

if [[ -n "${LOGGER_SH_LOADED:-}" ]]
then
    return 0
fi

readonly LOGGER_SH_LOADED=1

#============================================================
# State
#============================================================

LOGGER_FILE="${LOGGER_FILE:-/tmp/arch-installer.log}"
LOGGER_LEVEL="${LOGGER_LEVEL:-INFO}"
LOGGER_FD=""
LOGGER_INITIALIZED=0

#============================================================
# Constants
#============================================================

readonly LOGGER_LEVEL_DEBUG=0
readonly LOGGER_LEVEL_INFO=1
readonly LOGGER_LEVEL_WARN=2
readonly LOGGER_LEVEL_ERROR=3

#============================================================
# Internal
#============================================================

logger_level_number()
{
    case "${1:-INFO}"
    in
        DEBUG)
            printf '%s' \
                "$LOGGER_LEVEL_DEBUG"
            ;;

        INFO)
            printf '%s' \
                "$LOGGER_LEVEL_INFO"
            ;;

        WARN)
            printf '%s' \
                "$LOGGER_LEVEL_WARN"
            ;;

        ERROR)
            printf '%s' \
                "$LOGGER_LEVEL_ERROR"
            ;;

        *)
            printf '%s' \
                "$LOGGER_LEVEL_INFO"
            ;;
    esac
}

#============================================================
# Timestamp
#============================================================

logger_timestamp()
{
    date '+%Y-%m-%d %H:%M:%S'
}

#============================================================
# Should log
#============================================================

logger_should_log()
{
    local message_level="${1:-INFO}"
    local configured_level

    configured_level="$(
        logger_level_number \
            "$LOGGER_LEVEL"
    )"

    message_level="$(
        logger_level_number \
            "$message_level"
    )"

    (( message_level >= configured_level ))
}

#============================================================
# Write
#============================================================

logger_write()
{
    local level="${1:-INFO}"
    local message="${2-}"
    local timestamp
    local line

    timestamp="$(
        logger_timestamp
    )"

    line="[${timestamp}] [${level}] ${message}"

    if (( LOGGER_INITIALIZED )) &&
       [[ -n "${LOGGER_FD:-}" ]]
    then
        printf '%s\n' \
            "$line" \
            >&"$LOGGER_FD"
    else
        printf '%s\n' \
            "$line" \
            >> "$LOGGER_FILE"
    fi

    case "$level"
    in
        WARN|ERROR)
            printf '%s\n' \
                "$line" \
                >&2
            ;;
    esac
}

#============================================================
# Initialization
#============================================================

logger_init()
{
    local directory

    if (( LOGGER_INITIALIZED ))
    then
        return 0
    fi

    : "${LOGGER_FILE:=/tmp/arch-installer.log}"
    : "${LOGGER_LEVEL:=INFO}"

    case "$LOGGER_LEVEL"
    in
        DEBUG|INFO|WARN|ERROR)
            ;;
        *)
            LOGGER_LEVEL="INFO"
            ;;
    esac

    directory="$(
        dirname \
            -- \
            "$LOGGER_FILE"
    )"

    if [[ ! -d "$directory" ]]
    then
        if ! mkdir -p \
            -- \
            "$directory"
        then
            printf \
                'Failed to create logger directory: %s\n' \
                "$directory" \
                >&2

            return 1
        fi
    fi

    if ! touch \
        -- \
        "$LOGGER_FILE"
    then
        printf \
            'Failed to create logger file: %s\n' \
            "$LOGGER_FILE" \
            >&2

        return 1
    fi

    if ! exec {LOGGER_FD}>>"$LOGGER_FILE"
    then
        printf \
            'Failed to open logger file: %s\n' \
            "$LOGGER_FILE" \
            >&2

        return 1
    fi

    LOGGER_INITIALIZED=1

    logger_write \
        INFO \
        "Logger initialized"

    logger_write \
        INFO \
        "Log file: ${LOGGER_FILE}"

    logger_write \
        INFO \
        "Log level: ${LOGGER_LEVEL}"

    return 0
}

#============================================================
# DEBUG
#============================================================

logger_debug()
{
    local message="${1-}"

    if logger_should_log DEBUG
    then
        logger_write \
            DEBUG \
            "$message"
    fi
}

#============================================================
# INFO
#============================================================

logger_info()
{
    local message="${1-}"

    if logger_should_log INFO
    then
        logger_write \
            INFO \
            "$message"
    fi
}

#============================================================
# WARN
#============================================================

logger_warn()
{
    local message="${1-}"

    if logger_should_log WARN
    then
        logger_write \
            WARN \
            "$message"
    fi
}

#============================================================
# ERROR
#============================================================

logger_error()
{
    local message="${1-}"

    if logger_should_log ERROR
    then
        logger_write \
            ERROR \
            "$message"
    fi
}

#============================================================
# Exception
#============================================================

logger_exception()
{
    local code="${1:-$?}"
    local line="${2:-${LINENO}}"
    local source_file="${3:-${BASH_SOURCE[1]:-unknown}}"
    local function="${4:-${FUNCNAME[1]:-unknown}}"
    local i

    logger_error \
        "Exception: code=${code} file=${source_file} line=${line} function=${function}"

    for (( i=1; i<${#FUNCNAME[@]}; i++ ))
    do
        logger_error \
            "Stack[${i}]: ${FUNCNAME[i]:-unknown} ${BASH_SOURCE[i]:-unknown}:${BASH_LINENO[i-1]:-unknown}"
    done
}

#============================================================
# Close
#============================================================

logger_close()
{
    if (( ! LOGGER_INITIALIZED ))
    then
        return 0
    fi

    logger_write \
        INFO \
        "Logger shutting down"

    if [[ -n "${LOGGER_FD:-}" ]]
    then
        exec {LOGGER_FD}>&- || true
    fi

    LOGGER_FD=""
    LOGGER_INITIALIZED=0

    return 0
}

#============================================================
# End
#============================================================
