#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  colors.sh
#
#  Цветовая схема TUI.
#
#  Ответственность:
#   • Инициализация ANSI-цветов
#   • Предоставление атрибутов текста
#   • Сброс атрибутов
#   • Проверка поддержки цвета
#
#  Не содержит:
#   • Логику меню
#   • Отрисовку
#   • Обработку клавиш
#   • Installer logic
#============================================================

if [[ -n "${COLORS_SH_LOADED:-}" ]]
then
    return 0
fi

readonly COLORS_SH_LOADED=1

#============================================================
# State
#============================================================

COLORS_ENABLED=1
COLORS_INITIALIZED=0

#============================================================
# ANSI attributes
#============================================================

COLOR_RESET=''
COLOR_BOLD=''
COLOR_DIM=''
COLOR_UNDERLINE=''
COLOR_REVERSE=''
COLOR_BLINK=''
COLOR_NOBLINK=''

#============================================================
# Foreground
#============================================================

COLOR_BLACK=''
COLOR_RED=''
COLOR_GREEN=''
COLOR_YELLOW=''
COLOR_BLUE=''
COLOR_MAGENTA=''
COLOR_CYAN=''
COLOR_WHITE=''

#============================================================
# Bright foreground
#============================================================

COLOR_BRIGHT_BLACK=''
COLOR_BRIGHT_RED=''
COLOR_BRIGHT_GREEN=''
COLOR_BRIGHT_YELLOW=''
COLOR_BRIGHT_BLUE=''
COLOR_BRIGHT_MAGENTA=''
COLOR_BRIGHT_CYAN=''
COLOR_BRIGHT_WHITE=''

#============================================================
# Background
#============================================================

COLOR_BG_BLACK=''
COLOR_BG_RED=''
COLOR_BG_GREEN=''
COLOR_BG_YELLOW=''
COLOR_BG_BLUE=''
COLOR_BG_MAGENTA=''
COLOR_BG_CYAN=''
COLOR_BG_WHITE=''

#============================================================
# Bright background
#============================================================

COLOR_BG_BRIGHT_BLACK=''
COLOR_BG_BRIGHT_RED=''
COLOR_BG_BRIGHT_GREEN=''
COLOR_BG_BRIGHT_YELLOW=''
COLOR_BG_BRIGHT_BLUE=''
COLOR_BG_BRIGHT_MAGENTA=''
COLOR_BG_BRIGHT_CYAN=''
COLOR_BG_BRIGHT_WHITE=''

#============================================================
# Detect color support
#============================================================

colors_detect()
{
    local term="${TERM:-}"

    COLORS_ENABLED=1

    if [[ -z "$term" ||
          "$term" == "dumb" ]]
    then
        COLORS_ENABLED=0
        return 0
    fi

    if [[ -n "${NO_COLOR:-}" ]]
    then
        COLORS_ENABLED=0
        return 0
    fi

    if ! tput colors >/dev/null 2>&1
    then
        COLORS_ENABLED=0
    fi

    return 0
}

#============================================================
# Initialize colors
#============================================================

colors_init()
{
    if (( COLORS_INITIALIZED ))
    then
        return 0
    fi

    colors_detect

    if (( ! COLORS_ENABLED ))
    then
        COLORS_INITIALIZED=1

        logger_debug \
            "Terminal colors disabled"

        return 0
    fi

    COLOR_RESET=$'\033[0m'

    COLOR_BOLD=$'\033[1m'
    COLOR_DIM=$'\033[2m'
    COLOR_UNDERLINE=$'\033[4m'
    COLOR_REVERSE=$'\033[7m'
    COLOR_BLINK=$'\033[5m'
    COLOR_NOBLINK=$'\033[25m'

    COLOR_BLACK=$'\033[30m'
    COLOR_RED=$'\033[31m'
    COLOR_GREEN=$'\033[32m'
    COLOR_YELLOW=$'\033[33m'
    COLOR_BLUE=$'\033[34m'
    COLOR_MAGENTA=$'\033[35m'
    COLOR_CYAN=$'\033[36m'
    COLOR_WHITE=$'\033[37m'

    COLOR_BRIGHT_BLACK=$'\033[90m'
    COLOR_BRIGHT_RED=$'\033[91m'
    COLOR_BRIGHT_GREEN=$'\033[92m'
    COLOR_BRIGHT_YELLOW=$'\033[93m'
    COLOR_BRIGHT_BLUE=$'\033[94m'
    COLOR_BRIGHT_MAGENTA=$'\033[95m'
    COLOR_BRIGHT_CYAN=$'\033[96m'
    COLOR_BRIGHT_WHITE=$'\033[97m'

    COLOR_BG_BLACK=$'\033[40m'
    COLOR_BG_RED=$'\033[41m'
    COLOR_BG_GREEN=$'\033[42m'
    COLOR_BG_YELLOW=$'\033[43m'
    COLOR_BG_BLUE=$'\033[44m'
    COLOR_BG_MAGENTA=$'\033[45m'
    COLOR_BG_CYAN=$'\033[46m'
    COLOR_BG_WHITE=$'\033[47m'

    COLOR_BG_BRIGHT_BLACK=$'\033[100m'
    COLOR_BG_BRIGHT_RED=$'\033[101m'
    COLOR_BG_BRIGHT_GREEN=$'\033[102m'
    COLOR_BG_BRIGHT_YELLOW=$'\033[103m'
    COLOR_BG_BRIGHT_BLUE=$'\033[104m'
    COLOR_BG_BRIGHT_MAGENTA=$'\033[105m'
    COLOR_BG_BRIGHT_CYAN=$'\033[106m'
    COLOR_BG_BRIGHT_WHITE=$'\033[107m'

    COLORS_INITIALIZED=1

    logger_debug \
        "Terminal colors initialized"
}

#============================================================
# Disable colors
#============================================================

colors_disable()
{
    COLORS_ENABLED=0
    COLORS_INITIALIZED=1

    COLOR_RESET=''
    COLOR_BOLD=''
    COLOR_DIM=''
    COLOR_UNDERLINE=''
    COLOR_REVERSE=''
    COLOR_BLINK=''
    COLOR_NOBLINK=''

    COLOR_BLACK=''
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_MAGENTA=''
    COLOR_CYAN=''
    COLOR_WHITE=''

    COLOR_BRIGHT_BLACK=''
    COLOR_BRIGHT_RED=''
    COLOR_BRIGHT_GREEN=''
    COLOR_BRIGHT_YELLOW=''
    COLOR_BRIGHT_BLUE=''
    COLOR_BRIGHT_MAGENTA=''
    COLOR_BRIGHT_CYAN=''
    COLOR_BRIGHT_WHITE=''

    COLOR_BG_BLACK=''
    COLOR_BG_RED=''
    COLOR_BG_GREEN=''
    COLOR_BG_YELLOW=''
    COLOR_BG_BLUE=''
    COLOR_BG_MAGENTA=''
    COLOR_BG_CYAN=''
    COLOR_BG_WHITE=''

    COLOR_BG_BRIGHT_BLACK=''
    COLOR_BG_BRIGHT_RED=''
    COLOR_BG_BRIGHT_GREEN=''
    COLOR_BG_BRIGHT_YELLOW=''
    COLOR_BG_BRIGHT_BLUE=''
    COLOR_BG_BRIGHT_CYAN=''
    COLOR_BG_BRIGHT_WHITE=''
}

#============================================================
# Enable colors
#============================================================

colors_enable()
{
    COLORS_INITIALIZED=0
    COLORS_ENABLED=1

    colors_init
}

#============================================================
# Reset
#============================================================

colors_reset()
{
    if (( COLORS_ENABLED ))
    then
        printf '%s' \
            "$COLOR_RESET"
    fi
}

#============================================================
# Generic colored output
#============================================================

colors_print()
{
    local color="${1:-}"
    local text="${2-}"

    if (( COLORS_ENABLED ))
    then
        printf \
            '%s%s%s' \
            "$color" \
            "$text" \
            "$COLOR_RESET"
    else
        printf \
            '%s' \
            "$text"
    fi
}

#============================================================
# Convenience helpers
#============================================================

color_error()
{
    colors_print \
        "$COLOR_BRIGHT_RED" \
        "${1-}"
}

color_success()
{
    colors_print \
        "$COLOR_BRIGHT_GREEN" \
        "${1-}"
}

color_warning()
{
    colors_print \
        "$COLOR_BRIGHT_YELLOW" \
        "${1-}"
}

color_info()
{
    colors_print \
        "$COLOR_BRIGHT_CYAN" \
        "${1-}"
}

color_title()
{
    colors_print \
        "$COLOR_BOLD" \
        "${1-}"
}

#============================================================
# Selected item
#============================================================

color_selected()
{
    if (( COLORS_ENABLED ))
    then
        printf \
            '%s%s%s' \
            "$COLOR_REVERSE" \
            "${1-}" \
            "$COLOR_RESET"
    else
        printf \
            '%s' \
            "${1-}"
    fi
}

#============================================================
# End
#============================================================
