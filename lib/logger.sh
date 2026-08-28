#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# logger.sh
#============================================================

if [[ -n "${LOGGER_SH_LOADED:-}" ]]
then
    return 0
fi

readonly LOGGER_SH_LOADED=1

LOGGER_FILE="${LOGGER_FILE:-/tmp/arch-installer.log}"
LOGGER_LEVEL="${LOGGER_LEVEL:-INFO}"

LOGGER_FD=""
LOGGER_INITIALIZED=0

readonly LOGGER_LEVEL_DEBUG=0
readonly LOGGER_LEVEL_INFO=1
readonly LOGGER_LEVEL_WARN=2
readonly LOGGER_LEVEL_ERROR=3

logger_level_number()
{
    case "${1:-INFO}"
    in
        DEBUG)
            printf '%s' "$LOGGER_LEVEL_DEBUG"
            ;;

        INFO)
            printf '%s' "$LOGGER_LEVEL_INFO"
            ;;

        WARN)
            printf '%s' "$LOGGER_LEVEL_WARN"
            ;;

        ERROR)
            printf '%s' "$LOGGER_LEVEL_ERROR"
            ;;

        *)
            printf '%s' "$LOGGER_LEVEL_INFO"
            ;;
    esac
}

logger_should_log()
{
    local message_level
    local configured_level

    message_level="$(
        logger_level_number \
            "${1:-INFO}"
    )"

    configured_level="$(
        logger_level_number \
            "$LOGGER_LEVEL"
    )"

    (( message_level >= configured_level ))
}

logger_write()
{
    local level="${1:-INFO}"
    local message="${2-}"
    local timestamp
    local line

    timestamp="$(
        date '+%Y-%m-%d %H:%M:%S'
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

logger_init()
{
    local directory

    if (( LOGGER_INITIALIZED ))
    then
        return 0
    fi

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

    mkdir -p \
        -- \
        "$directory" || {
        printf \
            'Cannot create log directory: %s\n' \
            "$directory" \
            >&2

        return 1
    }

    touch \
        -- \
        "$LOGGER_FILE" || {
        printf \
            'Cannot create log file: %s\n' \
            "$LOGGER_FILE" \
            >&2

        return 1
    }

    if ! exec {LOGGER_FD}>>"$LOGGER_FILE"
    then
        printf \
            'Cannot open log file: %s\n' \
            "$LOGGER_FILE" \
            >&2

        return 1
    fi

    LOGGER_INITIALIZED=1

    logger_write INFO "Logger initialized"
    logger_write INFO "Log file: ${LOGGER_FILE}"
    logger_write INFO "Log level: ${LOGGER_LEVEL}"

    return 0
}

logger_debug()
{
    local message="${1-}"

    if logger_should_log DEBUG
    then
        logger_write DEBUG "$message"
    fi
}

logger_info()
{
    local message="${1-}"

    if logger_should_log INFO
    then
        logger_write INFO "$message"
    fi
}

logger_warn()
{
    local message="${1-}"

    if logger_should_log WARN
    then
        logger_write WARN "$message"
    fi
}

logger_error()
{
    local message="${1-}"

    if logger_should_log ERROR
    then
        logger_write ERROR "$message"
    fi
}

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
