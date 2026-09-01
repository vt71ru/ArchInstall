```bash
#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  lib/colors.sh
#
#  Единая система цветового оформления проекта.
#
#  Ответственность:
#   • ANSI-цвета
#   • включение/отключение цветов
#   • цветовой вывод
#   • цветовые алиасы
#
#  Не содержит:
#   • TUI-логику
#   • меню
#   • логику установки
#   • CONFIG
#
#============================================================

#============================================================
# Include guard
#============================================================

if [[ -n "${ARCH_INSTALLER_COLORS_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

ARCH_INSTALLER_COLORS_SH_LOADED=1
export ARCH_INSTALLER_COLORS_SH_LOADED

#============================================================
# Color state
#============================================================

COLORS_ENABLED=0

#============================================================
# ANSI codes
#============================================================

readonly COLOR_RESET='0'

readonly COLOR_BLACK='30'
readonly COLOR_RED='31'
readonly COLOR_GREEN='32'
readonly COLOR_YELLOW='33'
readonly COLOR_BLUE='34'
readonly COLOR_MAGENTA='35'
readonly COLOR_CYAN='36'
readonly COLOR_WHITE='37'

readonly COLOR_BRIGHT_BLACK='90'
readonly COLOR_BRIGHT_RED='91'
readonly COLOR_BRIGHT_GREEN='92'
readonly COLOR_BRIGHT_YELLOW='93'
readonly COLOR_BRIGHT_BLUE='94'
readonly COLOR_BRIGHT_MAGENTA='95'
readonly COLOR_BRIGHT_CYAN='96'
readonly COLOR_BRIGHT_WHITE='97'

#============================================================
# Initialize colors
#============================================================

colors_init()
{
    COLORS_ENABLED=0

    if [[ -t 1 ]]
    then
        COLORS_ENABLED=1
    fi

    if [[ -n "${NO_COLOR:-}" ]]
    then
        COLORS_ENABLED=0
    fi

    if [[ "${TERM:-}" == "dumb" ]]
    then
        COLORS_ENABLED=0
    fi

    return 0
}

#============================================================
# Enable / disable
#============================================================

colors_enable()
{
    COLORS_ENABLED=1
}

colors_disable()
{
    COLORS_ENABLED=0
}

colors_enabled()
{
    (( COLORS_ENABLED != 0 ))
}

#============================================================
# Generic color output
#============================================================

color_print()
{
    local code="${1:-}"
    local text="${2-}"

    if [[ -z "$code" ]]
    then
        printf '%s' "$text"
        return 0
    fi

    if (( COLORS_ENABLED ))
    then
        printf '\033[%sm%s\033[0m' \
            "$code" \
            "$text"
    else
        printf '%s' "$text"
    fi
}

color_println()
{
    local code="${1:-}"
    local text="${2-}"

    color_print \
        "$code" \
        "$text"

    printf '\n'
}

#============================================================
# Semantic colors
#============================================================

color_success()
{
    color_println \
        "$COLOR_GREEN" \
        "${1-}"
}

color_error()
{
    color_println \
        "$COLOR_RED" \
        "${1-}"
}

color_warning()
{
    color_println \
        "$COLOR_YELLOW" \
        "${1-}"
}

color_info()
{
    color_println \
        "$COLOR_CYAN" \
        "${1-}"
}

color_title()
{
    color_println \
        "$COLOR_BRIGHT_CYAN" \
        "${1-}"
}

color_stage()
{
    color_println \
        "$COLOR_BRIGHT_BLUE" \
        "${1-}"
}

color_step()
{
    color_println \
        "$COLOR_BRIGHT_MAGENTA" \
        "${1-}"
}

color_dim()
{
    color_println \
        "$COLOR_BRIGHT_BLACK" \
        "${1-}"
}

#============================================================
# Colored prefixes
#============================================================

color_prefix_info()
{
    color_print \
        "$COLOR_CYAN" \
        '[INFO]'

    printf ' '
}

color_prefix_success()
{
    color_print \
        "$COLOR_GREEN" \
        '[ OK ]'

    printf ' '
}

color_prefix_warning()
{
    color_print \
        "$COLOR_YELLOW" \
        '[WARN]'

    printf ' '
}

color_prefix_error()
{
    color_print \
        "$COLOR_RED" \
        '[ERROR]'

    printf ' '
}

#============================================================
# Header
#============================================================

color_header()
{
    local text="${1-}"

    printf '\n'

    color_println \
        "$COLOR_BRIGHT_CYAN" \
        '=========================================='

    color_println \
        "$COLOR_BRIGHT_CYAN" \
        "$text"

    color_println \
        "$COLOR_BRIGHT_CYAN" \
        '=========================================='

    printf '\n'
}

#============================================================
# Stage header
#============================================================

color_stage_header()
{
    local step="${1:-}"
    local total="${2:-}"
    local title="${3-}"

    printf '\n'

    color_print \
        "$COLOR_BRIGHT_BLUE" \
        "STEP ${step}/${total}"

    printf ' '

    color_print \
        "$COLOR_BRIGHT_WHITE" \
        "$title"

    printf '\n'

    color_println \
        "$COLOR_BRIGHT_BLACK" \
        '------------------------------------------'
}

#============================================================
# Menu item
#============================================================

color_menu_item()
{
    local number="${1:-}"
    local text="${2-}"

    color_print \
        "$COLOR_BRIGHT_CYAN" \
        "$number"

    printf ') '

    color_print \
        "$COLOR_BRIGHT_WHITE" \
        "$text"

    printf '\n'
}

#============================================================
# Color test
#============================================================

colors_test()
{
    color_header 'Arch Installer - Color Test'

    color_success \
        '[ OK ] Success'

    color_error \
        '[ERROR] Error'

    color_warning \
        '[WARN] Warning'

    color_info \
        '[INFO] Information'

    color_title \
        'Title'

    color_stage \
        'Installation stage'

    color_step \
        'Installation step'

    color_dim \
        'Secondary information'
}
```
