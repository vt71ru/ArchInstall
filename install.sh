#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# install.sh
#
# Главный bootstrap / orchestrator.
#
# Ответственность:
#   • Определение ROOT_DIR
#   • Загрузка библиотек
#   • Проверка окружения
#   • Инициализация logger
#   • Инициализация TUI
#   • Установка аварийного восстановления
#   • Запуск главного меню
#
# Не содержит:
#   • partition logic
#   • filesystem logic
#   • package logic
#   • bootloader logic
#   • CONFIG business logic
#   • drawing logic
#   • keyboard parsing
#
#============================================================

set -Eeuo pipefail

#============================================================
# Bootstrap state
#============================================================

readonly INSTALLER_NAME="Arch Installer"

INSTALLER_ROOT=""
INSTALLER_LIB=""
INSTALLER_MODULES=""

INSTALLER_EXITING=0

#============================================================
# Determine script directory
#============================================================

get_script_dir()
{
    local source="${BASH_SOURCE[0]}"

    while [[ -h "$source" ]]
    do
        local dir=""

        dir="$(
            cd -P "$(dirname "$source")" >/dev/null 2>&1 &&
            pwd
        )"

        source="$(readlink "$source")"

        if [[ "$source" != /* ]]
        then
            source="$dir/$source"
        fi
    done

    cd -P "$(dirname "$source")" >/dev/null 2>&1 &&
        pwd
}

#============================================================
# Project paths
#============================================================

INSTALLER_ROOT="$(get_script_dir)"

if [[ -z "$INSTALLER_ROOT" ]]
then
    printf '%s\n' \
        "ERROR: cannot determine installer root" \
        >&2

    exit 1
fi

readonly INSTALLER_ROOT

INSTALLER_LIB="$INSTALLER_ROOT/lib"
INSTALLER_MODULES="$INSTALLER_ROOT/installer"

readonly INSTALLER_LIB
readonly INSTALLER_MODULES

#============================================================
# Bootstrap output
#============================================================

bootstrap_output()
{
    local message="${1-}"

    #
    # Prefer real terminal.
    #
    if [[ -e /dev/tty ]] &&
       { : </dev/tty; } 2>/dev/null
    then
        printf '%s\n' "$message" >/dev/tty
        return 0
    fi

    #
    # Fallback to stderr.
    #
    printf '%s\n' "$message" >&2
}

#============================================================
# Bootstrap logging
#============================================================

bootstrap_log()
{
    local level="${1:-INFO}"

    shift || true

    bootstrap_output \
        "[$INSTALLER_NAME] [$level] $*"
}

#============================================================
# Load library
#============================================================

load_library()
{
    local file="${1:-}"

    if [[ -z "$file" ]]
    then
        bootstrap_log ERROR \
            "load_library(): empty file path"

        return 1
    fi

    if [[ ! -f "$file" ]]
    then
        bootstrap_log ERROR \
            "Required library not found: $file"

        return 1
    fi

    bootstrap_log DEBUG \
        "Loading library: $file"

    # shellcheck disable=SC1090
    if ! source "$file"
    then
        bootstrap_log ERROR \
            "Failed to load library: $file"

        return 1
    fi

    return 0
}

#============================================================
# Load logger
#============================================================

load_logger()
{
    local logger_file="$INSTALLER_LIB/logger.sh"

    if [[ ! -f "$logger_file" ]]
    then
        bootstrap_log ERROR \
            "logger.sh not found: $logger_file"

        return 1
    fi

    bootstrap_log DEBUG \
        "Loading logger"

    # shellcheck disable=SC1090
    if ! source "$logger_file"
    then
        bootstrap_log ERROR \
            "Failed to load logger.sh"

        return 1
    fi

    if ! declare -F logger_init >/dev/null 2>&1
    then
        bootstrap_log ERROR \
            "logger_init() is unavailable"

        return 1
    fi

    if ! declare -F logger_info >/dev/null 2>&1
    then
        bootstrap_log ERROR \
            "logger_info() is unavailable"

        return 1
    fi

    if ! declare -F logger_error >/dev/null 2>&1
    then
        bootstrap_log ERROR \
            "logger_error() is unavailable"

        return 1
    fi

    return 0
}

#============================================================
# Load TUI
#============================================================

load_tui()
{
    local tui_file="$INSTALLER_LIB/tui.sh"

    if [[ ! -f "$tui_file" ]]
    then
        logger_error \
            "tui.sh not found: $tui_file"

        return 1
    fi

    logger_debug \
        "Loading TUI: $tui_file"

    # shellcheck disable=SC1090
    if ! source "$tui_file"
    then
        logger_error \
            "Failed to load tui.sh"

        return 1
    fi

    if ! declare -F tui_init >/dev/null 2>&1
    then
        logger_error \
            "tui.sh loaded but tui_init() is unavailable"

        return 1
    fi

    if ! declare -F tui_start >/dev/null 2>&1
    then
        logger_error \
            "tui.sh loaded but tui_start() is unavailable"

        return 1
    fi

    if ! declare -F tui_restore >/dev/null 2>&1
    then
        logger_error \
            "tui.sh loaded but tui_restore() is unavailable"

        return 1
    fi

    return 0
}

#============================================================
# Load main menu
#============================================================

load_main_menu()
{
    local menu_file="$INSTALLER_MODULES/menu_main.sh"

    if [[ ! -f "$menu_file" ]]
    then
        logger_error \
            "Main menu not found: $menu_file"

        return 1
    fi

    logger_debug \
        "Loading main menu: $menu_file"

    # shellcheck disable=SC1090
    if ! source "$menu_file"
    then
        logger_error \
            "Failed to load main menu: $menu_file"

        return 1
    fi

    if ! declare -F menu_main >/dev/null 2>&1
    then
        logger_error \
            "menu_main.sh loaded but menu_main() is unavailable"

        return 1
    fi

    return 0
}

#============================================================
# Environment checks
#============================================================

check_environment()
{
    logger_debug \
        "Checking runtime environment"

    #--------------------------------------------------------
    # Bash
    #--------------------------------------------------------

    if (( BASH_VERSINFO[0] < 5 ))
    then
        logger_error \
            "Bash 5.x or newer is required"

        return 1
    fi

    #--------------------------------------------------------
    # Root
    #--------------------------------------------------------

    if (( EUID != 0 ))
    then
        logger_error \
            "Arch Installer must be run as root"

        return 1
    fi

    #--------------------------------------------------------
    # /dev/tty
    #--------------------------------------------------------

    if [[ ! -e /dev/tty ]]
    then
        logger_error \
            "/dev/tty is unavailable"

        return 1
    fi

    #--------------------------------------------------------
    # Test /dev/tty
    #--------------------------------------------------------

    if ! { : </dev/tty; } 2>/dev/null
    then
        logger_error \
            "Cannot access /dev/tty"

        return 1
    fi

    #--------------------------------------------------------
    # Required commands
    #--------------------------------------------------------

    local command

    for command in \
        bash \
        stty \
        tput \
        tty \
        lsblk \
        mount \
        umount \
        awk \
        sed
    do
        if ! command -v "$command" >/dev/null 2>&1
        then
            logger_error \
                "Required command not found: $command"

            return 1
        fi
    done

    #--------------------------------------------------------
    # Verify actual TTY
    #--------------------------------------------------------

    if ! tty </dev/tty >/dev/null 2>&1
    then
        logger_error \
            "/dev/tty is not a usable terminal"

        return 1
    fi

    logger_debug \
        "Runtime environment check passed"

    return 0
}

#============================================================
# TUI cleanup
#============================================================

cleanup_tui()
{
    if (( INSTALLER_EXITING ))
    then
        return 0
    fi

    INSTALLER_EXITING=1

    #
    # tui.sh may not have been loaded yet.
    #
    if ! declare -F tui_restore >/dev/null 2>&1
    then
        return 0
    fi

    #
    # Nothing to restore.
    #
    if [[ "${TUI_INITIALIZED:-0}" != "1" ]]
    then
        return 0
    fi

    tui_restore || true
}

#============================================================
# ERR handler
#============================================================

on_error()
{
    local rc="$?"
    local line="${BASH_LINENO[0]:-unknown}"
    local command="${BASH_COMMAND:-unknown}"

    #
    # Do not process ERR twice.
    #
    if (( INSTALLER_EXITING ))
    then
        return "$rc"
    fi

    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error \
            "Fatal error: rc=$rc line=$line command=$command"
    else
        bootstrap_log ERROR \
            "Fatal error: rc=$rc line=$line command=$command"
    fi

    cleanup_tui

    return "$rc"
}

#============================================================
# EXIT handler
#============================================================

on_exit()
{
    local rc="$?"

    cleanup_tui

    #
    # Do not call exit from EXIT recursively.
    #
    return "$rc"
}

#============================================================
# INT
#============================================================

on_interrupt()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn \
            "Installer interrupted by user"
    else
        bootstrap_log WARN \
            "Installer interrupted by user"
    fi

    cleanup_tui

    exit 130
}

#============================================================
# TERM
#============================================================

on_term()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn \
            "Installer terminated"
    else
        bootstrap_log WARN \
            "Installer terminated"
    fi

    cleanup_tui

    exit 143
}

#============================================================
# Install traps
#============================================================

install_traps()
{
    trap 'on_error' ERR
    trap 'on_exit' EXIT
    trap 'on_interrupt' INT
    trap 'on_term' TERM

    return 0
}

#============================================================
# Initialize logger
#============================================================

init_logger()
{
    if ! declare -F logger_init >/dev/null 2>&1
    then
        bootstrap_log ERROR \
            "logger_init() is unavailable"

        return 1
    fi

    if ! logger_init "$INSTALLER_ROOT"
    then
        bootstrap_log ERROR \
            "logger_init() failed"

        return 1
    fi

    return 0
}

#============================================================
# Initialize TUI
#============================================================

init_tui()
{
    logger_debug \
        "Initializing TUI"

    #
    # Initialize only.
    #
    if ! tui_init
    then
        logger_error \
            "tui_init() failed"

        return 1
    fi

    logger_debug \
        "TUI initialized: ${TUI_COLS}x${TUI_ROWS}"

    #
    # Start TUI.
    #
    if ! tui_start
    then
        logger_error \
            "tui_start() failed"

        tui_restore || true

        return 1
    fi

    logger_info \
        "TUI started"

    return 0
}

#============================================================
# Main
#============================================================

main()
{
    #--------------------------------------------------------
    # Bootstrap message
    #--------------------------------------------------------

    bootstrap_log INFO \
        "Starting $INSTALLER_NAME"

    bootstrap_log DEBUG \
        "ROOT: $INSTALLER_ROOT"

    bootstrap_log DEBUG \
        "LIB:  $INSTALLER_LIB"

    bootstrap_log DEBUG \
        "MOD:  $INSTALLER_MODULES"

    #--------------------------------------------------------
    # Install traps as early as possible
    #--------------------------------------------------------

    install_traps

    #--------------------------------------------------------
    # Logger
    #--------------------------------------------------------

    if ! load_logger
    then
        bootstrap_log ERROR \
            "Failed to load logger"

        return 1
    fi

    if ! init_logger
    then
        bootstrap_log ERROR \
            "Failed to initialize logger"

        return 1
    fi

    logger_info \
        "$INSTALLER_NAME starting"

    #--------------------------------------------------------
    # Environment
    #--------------------------------------------------------

    if ! check_environment
    then
        logger_error \
            "Environment check failed"

        return 1
    fi

    #--------------------------------------------------------
    # TUI
    #--------------------------------------------------------

    if ! load_tui
    then
        logger_error \
            "Failed to load TUI"

        return 1
    fi

    if ! init_tui
    then
        logger_error \
            "Failed to initialize TUI"

        return 1
    fi

    #--------------------------------------------------------
    # Main menu
    #--------------------------------------------------------

    if ! load_main_menu
    then
        logger_error \
            "Failed to load main menu"

        return 1
    fi

    logger_info \
        "Starting main menu"

    if menu_main
    then
        logger_info \
            "Main menu finished successfully"

        return 0
    else
        local rc="$?"

        logger_error \
            "Main menu finished with rc=$rc"

        return "$rc"
    fi
}

#============================================================
# Entry point
#============================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
    main "$@"
fi
