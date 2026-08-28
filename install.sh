#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# install.sh
#
# Главный bootstrap/orchestrator.
#============================================================

set -Eeuo pipefail

IFS=$'\n\t'
umask 022

#============================================================
# Application
#============================================================

readonly APP_NAME="Arch Installer"
readonly APP_VERSION="0.2.0"

readonly ROOT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

readonly LIB_DIR="${ROOT_DIR}/lib"
readonly INSTALLER_DIR="${ROOT_DIR}/installer"
readonly ASSET_DIR="${ROOT_DIR}/assets"

LOGGER_READY=0
TUI_READY=0

#============================================================
# Paths
#============================================================

readonly LOGGER_MODULE="${LIB_DIR}/logger.sh"

#============================================================
# Logger bootstrap
#============================================================

if [[ ! -f "$LOGGER_MODULE" ]]
then
    printf \
        'Missing logger module: %s\n' \
        "$LOGGER_MODULE" \
        >&2

    exit 1
fi

export LOGGER_FILE="${LOGGER_FILE:-/tmp/arch-installer.log}"
export LOGGER_LEVEL="${LOGGER_LEVEL:-INFO}"

# shellcheck source=/dev/null
source "$LOGGER_MODULE"

#============================================================
# Fatal
#============================================================

die()
{
    local message="${1:-Fatal error}"

    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error \
            "$message" \
            || true
    fi

    printf \
        'Error: %s\n' \
        "$message" \
        >&2

    return 1
}

#============================================================
# Load library
#============================================================

load_lib()
{
    local name="${1:-}"
    local file="${LIB_DIR}/${name}"

    if [[ -z "$name" ]]
    then
        die "Library name is empty"
        return 1
    fi

    if [[ ! -f "$file" ]]
    then
        die "Missing library module: ${file}"
        return 1
    fi

    logger_debug \
        "Loading library: ${name}"

    # shellcheck source=/dev/null
    source "$file"
}

#============================================================
# Load installer module
#============================================================

load_installer()
{
    local name="${1:-}"
    local file="${INSTALLER_DIR}/${name}"

    if [[ -z "$name" ]]
    then
        die "Installer module name is empty"
        return 1
    fi

    if [[ ! -f "$file" ]]
    then
        die "Missing installer module: ${file}"
        return 1
    fi

    logger_debug \
        "Loading installer module: ${name}"

    # shellcheck source=/dev/null
    source "$file"
}

#============================================================
# Environment
#============================================================

check_environment()
{
    if (( EUID != 0 ))
    then
        die \
            "Arch Installer must be run as root"

        return 1
    fi

    if [[ ! -f /etc/arch-release ]]
    then
        die \
            "This installer must be run from Arch Linux"

        return 1
    fi

    if [[ ! -t 0 ]]
    then
        die \
            "stdin is not a TTY"

        return 1
    fi

    if [[ ! -t 1 ]]
    then
        die \
            "stdout is not a TTY"

        return 1
    fi

    if [[ ! -t 2 ]]
    then
        die \
            "stderr is not a TTY"

        return 1
    fi

    if [[ -z "${TERM:-}" ||
          "${TERM:-}" == "dumb" ]]
    then
        die \
            "Unsupported terminal: ${TERM:-unset}"

        return 1
    fi

    if [[ ! -d "$LIB_DIR" ]]
    then
        die \
            "Missing lib directory: ${LIB_DIR}"

        return 1
    fi

    if [[ ! -d "$INSTALLER_DIR" ]]
    then
        die \
            "Missing installer directory: ${INSTALLER_DIR}"

        return 1
    fi
}

#============================================================
# Dependencies
#============================================================

check_dependencies()
{
    local required=(
        bash
        awk
        sed
        grep
        date
        dirname
        touch
        mkdir
        chmod
        mv
        rm
        mktemp

        tput
        stty

        lsblk
        blkid
        findmnt
        mountpoint
        swapon

        base64
    )

    local command_name

    for command_name in "${required[@]}"
    do
        if ! command -v \
            "$command_name" \
            >/dev/null 2>&1
        then
            die \
                "Missing required program: ${command_name}"

            return 1
        fi
    done

    logger_info \
        "Bootstrap dependencies verified"
}

#============================================================
# Load libraries
#============================================================

load_libraries()
{
    load_lib config.sh
    load_lib common.sh
    load_lib tui.sh

    logger_info \
        "Core libraries loaded"
}

#============================================================
# Load installer
#============================================================

load_installer_modules()
{
    load_installer welcome.sh
    load_installer keyboard.sh
    load_installer locale.sh
    load_installer locale_generate.sh
    load_installer network.sh
    load_installer mirrors.sh

    load_installer disks.sh
    load_installer partition.sh
    load_installer filesystem.sh
    load_installer mount.sh
    load_installer packages.sh

    load_installer users.sh
    load_installer desktop.sh
    load_installer services.sh

    load_installer bootloader.sh

    load_installer summary.sh

    # MUST be loaded last.
    load_installer menu_main.sh

    logger_info \
        "Installer modules loaded"
}

#============================================================
# Boot mode
#============================================================

detect_boot_mode()
{
    local current
    local mode

    current="$(
        config_get \
            BOOT_MODE \
            2>/dev/null ||
            true
    )"

    if [[ -n "$current" ]]
    then
        return 0
    fi

    if [[ -d /sys/firmware/efi ]]
    then
        mode="UEFI"
    else
        mode="BIOS"
    fi

    config_set \
        BOOT_MODE \
        "$mode"

    logger_info \
        "Boot mode detected: ${mode}"
}

#============================================================
# Partition table
#============================================================

detect_partition_table()
{
    local current
    local boot_mode
    local table

    current="$(
        config_get \
            PARTITION_TABLE \
            2>/dev/null ||
            true
    )"

    if [[ -n "$current" ]]
    then
        return 0
    fi

    boot_mode="$(
        config_get \
            BOOT_MODE
    )"

    case "$boot_mode"
    in
        UEFI)
            table="GPT"
            ;;

        BIOS)
            table="MBR"
            ;;

        *)
            die \
                "Cannot determine partition table"

            return 1
            ;;
    esac

    config_set \
        PARTITION_TABLE \
        "$table"

    logger_info \
        "Default partition table: ${table}"
}

#============================================================
# Cleanup
#============================================================

cleanup()
{
    local rc=$?

    if declare -F tui_restore >/dev/null 2>&1
    then
        tui_restore || true
    fi

    if (( LOGGER_READY ))
    then
        if declare -F logger_close >/dev/null 2>&1
        then
            logger_close || true
        fi
    fi

    return "$rc"
}

#============================================================
# Error
#============================================================

on_error()
{
    local rc="${1:-1}"
    local line="${2:-unknown}"
    local file="${3:-unknown}"
    local func="${4:-unknown}"

    printf \
        '\nFATAL ERROR\n' \
        >&2

    printf \
        'Code: %s\n' \
        "$rc" \
        >&2

    printf \
        'File: %s\n' \
        "$file" \
        >&2

    printf \
        'Line: %s\n' \
        "$line" \
        >&2

    printf \
        'Function: %s\n' \
        "$func" \
        >&2

    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error \
            "Fatal error: code=${rc} file=${file} line=${line} function=${func}" \
            || true
    fi

    exit "$rc"
}

#============================================================
# Signals
#============================================================

on_sigint()
{
    logger_warn \
        "Interrupted by SIGINT" \
        || true

    exit 130
}

on_sigterm()
{
    logger_warn \
        "Terminated by SIGTERM" \
        || true

    exit 143
}

#============================================================
# Traps
#============================================================

trap cleanup EXIT

trap \
    'rc=$?; on_error "$rc" "$LINENO" "${BASH_SOURCE[0]}" "${FUNCNAME[1]:-main}"' \
    ERR

trap on_sigint INT
trap on_sigterm TERM

#============================================================
# Main
#============================================================

main()
{
    logger_init || {
        printf \
            'Failed to initialize logger\n' \
            >&2

        return 1
    }

    LOGGER_READY=1

    logger_info \
        "Starting ${APP_NAME} ${APP_VERSION}"

    logger_info \
        "Project root: ${ROOT_DIR}"

    check_environment
    check_dependencies

    load_libraries

    config_init_load

    detect_boot_mode
    detect_partition_table

    if ! config_validate
    then
        logger_warn \
            "Configuration is incomplete"
    fi

    load_installer_modules

    tui_init || \
        return 1

    TUI_READY=1

    tui_start || \
        return 1

    menu_main

    return 0
}

#============================================================
# Entry
#============================================================

main "$@"
