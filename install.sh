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
#   • drawing / keyboard logic
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

INSTALLER_STARTED=0
INSTALLER_EXITING=0

#============================================================
# Determine script directory
#============================================================

get_script_dir()
{
    local source="${BASH_SOURCE[0]}"

    while [[ -h "$source" ]]
    do
        local dir

        dir="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"

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

readonly INSTALLER_ROOT

INSTALLER_LIB="$INSTALLER_ROOT/lib"
INSTALLER_MODULES="$INSTALLER_ROOT/modules"

readonly INSTALLER_LIB
readonly INSTALLER_MODULES

#============================================================
# Logging fallback
#
# logger.sh may not yet be loaded.
#============================================================

bootstrap_log()
{
    local level="${1:-INFO}"
    shift || true

    printf '[%s] [%s] %s\n' \
        "$INSTALLER_NAME" \
        "$level" \
        "$*" \
        >&2
}

#============================================================
# Load module
#============================================================

load_library()
{
    local file="$1"

    if [[ ! -f "$file" ]]
    then
        bootstrap_log ERROR \
            "Required library not found: $file"

        return 1
    fi

    # shellcheck disable=SC1090
    source "$file"
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

    # shellcheck disable=SC1090
    source "$logger_file"

    if ! declare -F logger_info >/dev/null 2>&1
    then
        bootstrap_log ERROR \
            "logger.sh loaded but logger_info() is unavailable"

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

    # shellcheck disable=SC1090
    source "$tui_file"

    if ! declare -F tui_init >/dev/null 2>&1
    then
        logger_error \
            "tui.sh loaded but tui_init() is unavailable"

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

    # shellcheck disable=SC1090
    source "$menu_file"

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

    #
    # Bash version
    #
    if (( BASH_VERSINFO[0] < 5 ))
    then
        logger_error \
            "Bash 5.x or newer is required"

        return 1
    fi

    #
    # Root
    #
    if (( EUID != 0 ))
    then
        logger_error \
            "Arch Installer must be run as root"

        return 1
    fi

    #
    # TTY
    #
    if [[ ! -e /dev/tty ]]
    then
        logger_error \
            "/dev/tty is unavailable"

        return 1
    fi

    if [[ ! -t /dev/tty ]]
    then
        logger_error \
            "/dev/tty is not a terminal"

        return 1
    fi

    #
    # Required commands
    #
    local command

    for command in \
        bash \
        stty \
        tput \
        lsblk \
        mount \
        umount
    do
        if ! command -v "$command" >/dev/null 2>&1
        then
            logger_error \
                "Required command not found: $command"

            return 1
        fi
    done

    logger_debug \
        "Environment check passed"

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

    if (( TUI_INITIALIZED ))
    then
        tui_restore || true
    fi
}

#============================================================
# Error handler
#============================================================

on_error()
{
    local rc="$?"

    local line="${BASH_LINENO[0]:-unknown}"
    local command="${BASH_COMMAND:-unknown}"

    #
    # Never attempt complex UI operations while the shell
    # itself is processing an error.
    #
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

    exit "$rc"
}

#============================================================
# INT / TERM
#============================================================

on_interrupt()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn \
            "Installer interrupted"
    fi

    cleanup_tui

    exit 130
}

on_term()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn \
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
    #
    # logger.sh must provide logger_init().
    #
    if ! declare -F logger_init >/dev/null 2>&1
    then
        bootstrap_log ERROR \
            "logger_init() is unavailable"

        return 1
    fi

    logger_init \
        "$INSTALLER_ROOT"

    return $?
}

#============================================================
# Initialize TUI
#============================================================

init_tui()
{
    logger_debug \
        "Initializing TUI"

    if ! tui_start
    then
        logger_error \
            "Failed to start TUI"

        return 1
    fi

    return 0
}

#============================================================
# Main
#============================================================

main()
{
    #
    #--------------------------------------------------------
    # Load logger first.
    #--------------------------------------------------------
    #
    load_logger || \
        return 1

    #
    #--------------------------------------------------------
    # Initialize logger.
    #--------------------------------------------------------
    #
    init_logger || \
        return 1

    logger_info \
        "$INSTALLER_NAME starting"

    logger_debug \
        "ROOT: $INSTALLER_ROOT"

    logger_debug \
        "LIB:  $INSTALLER_LIB"

    logger_debug \
        "MOD:  $INSTALLER_MODULES"

    #
    #--------------------------------------------------------
    # Load TUI.
    #--------------------------------------------------------
    #
    load_tui || \
        return 1

    #
    #--------------------------------------------------------
    # Install cleanup/error traps before starting TUI.
    #--------------------------------------------------------
    #
    install_traps

    #
    #--------------------------------------------------------
    # Environment.
    #--------------------------------------------------------
    #
    check_environment || \
        return 1

    #
    #--------------------------------------------------------
    # Start TUI.
    #--------------------------------------------------------
    #
    init_tui || \
        return 1

    INSTALLER_STARTED=1

    #
    #--------------------------------------------------------
    # Load main menu.
    #--------------------------------------------------------
    #
    load_main_menu || \
        return 1

    #
    #--------------------------------------------------------
    # Run main menu.
    #--------------------------------------------------------
    #
    logger_info \
        "Starting main menu"

    menu_main
    local rc="$?"
    logger_info \
        "Main menu finished with rc=$rc"
    return "$rc"
}
#============================================================
# Entry point
#============================================================

main "$@"
