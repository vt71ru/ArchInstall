#!/usr/bin/env bash
#
# ============================================================
# Arch Installer
# ------------------------------------------------------------
# install.sh
#
# Главный bootstrap / orchestrator.
#
# Ответственность:
#   • определение ROOT_DIR
#   • проверка окружения
#   • загрузка logger
#   • загрузка core libraries
#   • загрузка installer modules
#   • инициализация CONFIG
#   • определение boot mode
#   • инициализация TUI
#   • аварийное восстановление терминала
#   • запуск главного меню
#
# ============================================================

set -Eeuo pipefail

IFS=$'\n\t'
umask 022

# ============================================================
# APPLICATION
# ============================================================

readonly APP_NAME="Arch Installer"
readonly APP_VERSION="0.1.0"

# ============================================================
# PATHS
# ============================================================

ROOT_DIR=""
LIB_DIR=""
INSTALLER_DIR=""
ASSETS_DIR=""
WIDGETS_DIR=""

# ============================================================
# RUNTIME STATE
# ============================================================

LOGGER_READY=0
TUI_READY=0
INSTALLER_EXITING=0
TERMINAL_STATE_SAVED=0
ORIGINAL_STTY_STATE=""

# ============================================================
# DEBUG
# ============================================================

INSTALLER_DEBUG="${INSTALLER_DEBUG:-0}"

if (( INSTALLER_DEBUG != 0 ))
then
    PS4='+ ${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]}: '
fi

# ============================================================
# SCRIPT DIRECTORY
# ============================================================

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

ROOT_DIR="$(get_script_dir)"

if [[ -z "$ROOT_DIR" || ! -d "$ROOT_DIR" ]]
then
    printf '%s\n' \
        "ERROR: cannot determine project root" \
        >&2

    exit 1
fi

LIB_DIR="${ROOT_DIR}/lib"
INSTALLER_DIR="${ROOT_DIR}/installer"
ASSETS_DIR="${ROOT_DIR}/assets"
WIDGETS_DIR="${ROOT_DIR}/widgets"

export ROOT_DIR
export LIB_DIR
export INSTALLER_DIR
export ASSETS_DIR
export WIDGETS_DIR

# ============================================================
# BOOTSTRAP OUTPUT
# ============================================================

bootstrap_output()
{
    local message="${1-}"

    if [[ -e /dev/tty ]]
    then
        if { : </dev/tty; } 2>/dev/null
        then
            printf '%s\n' "$message" >/dev/tty
            return 0
        fi
    fi

    printf '%s\n' "$message" >&2

    return 0
}

# ============================================================
# ERROR HANDLER
# ============================================================

on_error()
{
    local code="${1:-1}"
    local line="${2:-unknown}"
    local source_file="${3:-unknown}"
    local function_name="${4:-main}"
    local command="${BASH_COMMAND:-unknown}"

    bootstrap_output ""
    bootstrap_output "============================================================"
    bootstrap_output "FATAL ERROR"
    bootstrap_output "============================================================"
    bootstrap_output "Return code : ${code}"
    bootstrap_output "Source file : ${source_file}"
    bootstrap_output "Line        : ${line}"
    bootstrap_output "Function    : ${function_name}"
    bootstrap_output "Command     : ${command}"
    bootstrap_output ""

    bootstrap_output "CALL STACK:"

    local i=0

    while (( i < ${#FUNCNAME[@]} ))
    do
        bootstrap_output \
            "  #${i} ${FUNCNAME[$i]:-unknown} " \
            "(${BASH_SOURCE[$i]:-unknown}:${BASH_LINENO[$i]:-unknown})"

        (( i += 1 ))
    done

    bootstrap_output ""

    if [[ -n "${LOG_FILE:-}" ]]
    then
        bootstrap_output \
            "Log file: ${LOG_FILE}"
    fi

    bootstrap_output \
        "============================================================"

    return "$code"
}

# ============================================================
# SIGNALS
# ============================================================

on_sigint()
{
    INSTALLER_EXITING=1

    bootstrap_output ""
    bootstrap_output "Interrupted by user."

    return 130
}

on_sigterm()
{
    INSTALLER_EXITING=1

    bootstrap_output ""
    bootstrap_output "Terminated."

    return 143
}

# ============================================================
# SAFE LOGGER WRAPPERS
# ============================================================

safe_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$*" || true
    else
        bootstrap_output "[INFO] $*"
    fi

    return 0
}

safe_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$*" || true
    else
        bootstrap_output "[WARN] $*"
    fi

    return 0
}

safe_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$*" || true
    else
        bootstrap_output "[ERROR] $*"
    fi

    return 0
}

# ============================================================
# LOAD MODULE
# ============================================================

load_module()
{
    local kind="${1:-}"
    local name="${2:-}"
    local directory=""
    local file=""

    case "$kind"
    in
        lib)
            directory="$LIB_DIR"
            ;;

        installer)
            directory="$INSTALLER_DIR"
            ;;

        *)
            bootstrap_output \
                "ERROR: unknown module type: ${kind}"

            return 1
            ;;
    esac

    if [[ -z "$name" ]]
    then
        bootstrap_output \
            "ERROR: empty module name"

        return 1
    fi

    file="${directory}/${name}"

    if [[ ! -f "$file" ]]
    then
        bootstrap_output \
            "ERROR: module not found: ${file}"

        return 1
    fi

    bootstrap_output \
        "Loading ${kind}: ${name}"

    if ! bash -n "$file"
    then
        bootstrap_output \
            "ERROR: syntax check failed: ${file}"

        return 1
    fi

    #
    # Не использовать subshell.
    # Модуль должен загрузиться в текущий shell.
    #

    if ! source "$file"
    then
        bootstrap_output \
            "ERROR: failed to source: ${file}"

        return 1
    fi

    bootstrap_output \
        "Loaded ${kind}: ${name}"

    return 0
}

# ============================================================
# REQUIRE LIBRARY
# ============================================================

require_lib()
{
    local name="${1:-}"

    load_module \
        lib \
        "$name" || return 1

    return 0
}

# ============================================================
# REQUIRE INSTALLER
# ============================================================

require_installer()
{
    local name="${1:-}"

    load_module \
        installer \
        "$name" || return 1

    return 0
}

# ============================================================
# ROOT CHECK
# ============================================================

check_root()
{
    bootstrap_output \
        "Checking root privileges..."

    if (( EUID != 0 ))
    then
        bootstrap_output \
            "Root check: FAILED"

        return 1
    fi

    bootstrap_output \
        "Root check: OK"

    return 0
}

# ============================================================
# ARCH ENVIRONMENT
# ============================================================

check_arch_environment()
{
    bootstrap_output \
        "Checking Arch Linux environment..."

    if [[ ! -f /etc/os-release ]]
    then
        bootstrap_output \
            "ERROR: /etc/os-release not found"

        return 1
    fi

    local os_id=""

    if ! os_id="$(
        . /etc/os-release
        printf '%s' "${ID:-}"
    )"
    then
        bootstrap_output \
            "ERROR: cannot read operating system ID"

        return 1
    fi

    if [[ "$os_id" != "arch" ]]
    then
        bootstrap_output \
            "Arch Linux check: FAILED"

        return 1
    fi

    bootstrap_output \
        "Arch Linux check: OK"

    return 0
}

# ============================================================
# PROJECT STRUCTURE
# ============================================================

check_project_structure()
{
    bootstrap_output \
        "Checking project structure..."

    local required_directory=""

    for required_directory in \
        "$ROOT_DIR" \
        "$LIB_DIR" \
        "$INSTALLER_DIR"
    do
        if [[ ! -d "$required_directory" ]]
        then
            bootstrap_output \
                "ERROR: required directory missing: ${required_directory}"

            return 1
        fi
    done

    local required_file=""

    for required_file in \
        "${LIB_DIR}/logger.sh" \
        "${LIB_DIR}/config.sh" \
        "${LIB_DIR}/common.sh" \
        "${LIB_DIR}/colors.sh" \
        "${LIB_DIR}/tui.sh"
    do
        if [[ ! -f "$required_file" ]]
        then
            bootstrap_output \
                "ERROR: required file missing: ${required_file}"

            return 1
        fi
    done

    bootstrap_output \
        "Project structure: OK"

    return 0
}

# ============================================================
# MOUNTPOINT
# ============================================================

check_mountpoint()
{
    if [[ ! -d /mnt ]]
    then
        bootstrap_output \
            "ERROR: /mnt does not exist"

        return 1
    fi

    return 0
}

# ============================================================
# TERMINAL
# ============================================================

check_terminal()
{
    bootstrap_output \
        "Checking terminal..."

    if [[ ! -e /dev/tty ]]
    then
        bootstrap_output \
            "Terminal check: FAILED"

        return 1
    fi

    if ! command -v stty >/dev/null 2>&1
    then
        bootstrap_output \
            "ERROR: stty not found"

        return 1
    fi

    if ! command -v tput >/dev/null 2>&1
    then
        bootstrap_output \
            "ERROR: tput not found"

        return 1
    fi

    if ! stty -g </dev/tty >/dev/null 2>&1
    then
        bootstrap_output \
            "Terminal check: FAILED"

        return 1
    fi

    bootstrap_output \
        "Terminal check: OK"

    return 0
}

# ============================================================
# DEPENDENCIES
# ============================================================

check_dependencies()
{
    bootstrap_output \
        "Checking dependencies..."

    local dependency=""

    for dependency in \
        bash \
        awk \
        sed \
        grep \
        cat \
        date \
        tty \
        stty \
        tput \
        mountpoint \
        find \
        lsblk \
        blkid \
        findmnt
    do
        if ! command -v "$dependency" >/dev/null 2>&1
        then
            bootstrap_output \
                "ERROR: dependency not found: ${dependency}"

            return 1
        fi
    done

    bootstrap_output \
        "Dependencies: OK"

    return 0
}

# ============================================================
# LOAD LOGGER
# ============================================================

load_logger()
{
    bootstrap_output \
        "Loading logger..."

    if ! declare -F logger_info >/dev/null 2>&1
    then
        require_lib \
            "logger.sh" || return 1
    fi

    if ! declare -F logger_info >/dev/null 2>&1
    then
        bootstrap_output \
            "ERROR: logger_info() is unavailable"

        return 1
    fi

    if ! declare -F logger_warn >/dev/null 2>&1
    then
        bootstrap_output \
            "ERROR: logger_warn() is unavailable"

        return 1
    fi

    if ! declare -F logger_error >/dev/null 2>&1
    then
        bootstrap_output \
            "ERROR: logger_error() is unavailable"

        return 1
    fi

    LOGGER_READY=1

    logger_info \
        "${APP_NAME} ${APP_VERSION}"

    return 0
}

# ============================================================
# LOAD CORE LIBRARIES
# ============================================================

load_core_libraries()
{
    bootstrap_output \
        "Loading core libraries..."

    #
    # logger уже должен быть загружен.
    #

    if ! declare -F logger_info >/dev/null 2>&1
    then
        bootstrap_output \
            "ERROR: logger_info() is unavailable"

        return 1
    fi

    require_lib \
        "config.sh" || return 1

    require_lib \
        "common.sh" || return 1

    require_lib \
        "colors.sh" || return 1

    require_lib \
        "tui.sh" || return 1

    #
    # Проверяем colors_init после source colors.sh.
    #

    if ! declare -F colors_init >/dev/null 2>&1
    then
        logger_error \
            "colors_init() is unavailable"

        return 1
    fi

    if ! colors_init
    then
        logger_error \
            "colors_init() failed"

        return 1
    fi

    logger_info \
        "Core libraries loaded"

    bootstrap_output \
        "Core libraries: OK"

    return 0
}

# ============================================================
# CONFIG API
# ============================================================

check_config_api()
{
    safe_log_info \
        "Checking CONFIG API"

    local function_name=""

    for function_name in \
        config_init \
        config_get \
        config_set \
        config_save
    do
        if ! declare -F "$function_name" >/dev/null 2>&1
        then
            safe_log_error \
                "CONFIG API function missing: ${function_name}"

            return 1
        fi
    done

    safe_log_info \
        "CONFIG API: OK"

    return 0
}

# ============================================================
# CONFIG INIT
# ============================================================

config_init_load()
{
    safe_log_info \
        "Initializing configuration"

    if ! config_init
    then
        safe_log_error \
            "config_init() failed"

        return 1
    fi

    safe_log_info \
        "Configuration initialized"

    return 0
}

# ============================================================
# BOOT MODE
# ============================================================

detect_boot_mode()
{
    local boot_mode=""

    if [[ -d /sys/firmware/efi ]]
    then
        boot_mode="UEFI"
    else
        boot_mode="BIOS"
    fi

    if ! config_set \
        BOOT_MODE \
        "$boot_mode"
    then
        safe_log_error \
            "Failed to save BOOT_MODE"

        return 1
    fi

    export BOOT_MODE="$boot_mode"

    safe_log_info \
        "Boot mode: ${boot_mode}"

    return 0
}

# ============================================================
# PARTITION TABLE
# ============================================================

detect_partition_table()
{
    local table=""

    if ! table="$(
        config_get \
            PARTITION_TABLE \
            2>/dev/null
    )"
    then
        table=""
    fi

    if [[ -z "$table" ]]
    then
        case "${BOOT_MODE:-BIOS}"
        in
            UEFI)
                table="GPT"
                ;;

            BIOS)
                table="MBR"
                ;;

            *)
                safe_log_error \
                    "Cannot determine partition table"

                return 1
                ;;
        esac

        if ! config_set \
            PARTITION_TABLE \
            "$table"
        then
            safe_log_error \
                "Failed to save PARTITION_TABLE"

            return 1
        fi
    fi

    export PARTITION_TABLE="$table"

    safe_log_info \
        "Partition table: ${table}"

    return 0
}

# ============================================================
# LOAD INSTALLER MODULES
# ============================================================

load_installer_modules()
{
    safe_log_info \
        "Loading installer modules..."

    #
    # Stage modules.
    #

    require_installer "welcome.sh" || return 1
    require_installer "keyboard.sh" || return 1
    require_installer "locale.sh" || return 1
    require_installer "locale_generate.sh" || return 1
    require_installer "network.sh" || return 1
    require_installer "mirrors.sh" || return 1
    require_installer "disks.sh" || return 1
    require_installer "partition.sh" || return 1
    require_installer "filesystem.sh" || return 1
    require_installer "mount.sh" || return 1
    require_installer "packages.sh" || return 1
    require_installer "users.sh" || return 1
    require_installer "desktop.sh" || return 1
    require_installer "services.sh" || return 1
    require_installer "bootloader.sh" || return 1
    require_installer "summary.sh" || return 1

    #
    # Controller MUST be loaded before menu.
    #

    require_installer "installer.sh" || return 1

    if ! declare -F installer_full_install >/dev/null 2>&1
    then
        safe_log_error \
            "installer_full_install() is unavailable"

        return 1
    fi

    if ! declare -F installer_run_stage >/dev/null 2>&1
    then
        safe_log_error \
            "installer_run_stage() is unavailable"

        return 1
    fi

    if ! declare -F installer_get_stage_title >/dev/null 2>&1
    then
        safe_log_error \
            "installer_get_stage_title() is unavailable"

        return 1
    fi

    if ! declare -F installer_check_all_stages >/dev/null 2>&1
    then
        safe_log_error \
            "installer_check_all_stages() is unavailable"

        return 1
    fi

    #
    # menu_main MUST be loaded LAST.
    #

    require_installer \
        "menu_main.sh" || return 1

    if ! declare -F menu_main >/dev/null 2>&1
    then
        safe_log_error \
            "menu_main() is unavailable"

        return 1
    fi

    safe_log_info \
        "Installer modules loaded"

    return 0
}

# ============================================================
# INSTALLER API
# ============================================================

check_installer_api()
{
    safe_log_info \
        "Checking installer API"

    local required_function=""

    for required_function in \
        installer_run \
        installer_full_install \
        installer_run_stage \
        installer_check_stage \
        installer_check_all_stages \
        installer_get_stage_function \
        installer_get_stage_title \
        installer_start_menu \
        installer_main \
        menu_main
    do
        if ! declare -F "$required_function" >/dev/null 2>&1
        then
            safe_log_error \
                "Installer API function missing: ${required_function}"

            return 1
        fi
    done

    safe_log_info \
        "Installer API: OK"

    return 0
}

# ============================================================
# SAVE ORIGINAL TERMINAL STATE
# ============================================================

save_original_terminal_state()
{
    if [[ ! -e /dev/tty ]]
    then
        return 1
    fi

    if ORIGINAL_STTY_STATE="$(
        stty -g </dev/tty 2>/dev/null
    )"
    then
        if [[ -n "$ORIGINAL_STTY_STATE" ]]
        then
            TERMINAL_STATE_SAVED=1
            return 0
        fi
    fi

    TERMINAL_STATE_SAVED=0

    return 1
}

# ============================================================
# APPLICATION INIT
# ============================================================

app_init()
{
    safe_log_info \
        "Initializing application"

    if ! declare -F tui_init >/dev/null 2>&1
    then
        safe_log_error \
            "tui_init() unavailable"

        return 1
    fi

    if ! declare -F tui_start >/dev/null 2>&1
    then
        safe_log_error \
            "tui_start() unavailable"

        return 1
    fi

    save_original_terminal_state || true

    safe_log_info \
        "Initializing TUI"

    if ! tui_init
    then
        safe_log_error \
            "tui_init() failed"

        return 1
    fi

    safe_log_info \
        "Starting TUI..."

    if ! tui_start
    then
        safe_log_error \
            "tui_start() failed"

        return 1
    fi

    TUI_READY=1

    if declare -F tui_set_title >/dev/null 2>&1
    then
        tui_set_title \
            "${APP_NAME} ${APP_VERSION}" || true
    fi

    if declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear || true
    fi

    safe_log_info \
        "TUI started successfully"

    return 0
}

# ============================================================
# STARTUP SCREEN
# ============================================================

draw_startup()
{
    if (( TUI_READY == 0 ))
    then
        return 0
    fi

    if ! tui_clear
    then
        return 1
    fi

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "$APP_NAME" || return 1
    fi

    tui_move \
        5 \
        5 || return 1

    if declare -F color_info >/dev/null 2>&1
    then
        color_info \
            "Arch Linux installation system" || return 1
    else
        tui_print \
            "Arch Linux installation system" || return 1
    fi

    tui_move \
        7 \
        5 || return 1

    tui_print \
        "Initializing installer..." || return 1

    screen_refresh 2>/dev/null || true

    return 0
}

# ============================================================
# CLEANUP
# ============================================================

cleanup()
{
    local rc=$?

    INSTALLER_EXITING=1

    if declare -F tui_restore >/dev/null 2>&1
    then
        tui_restore || true
    fi

    if (( TERMINAL_STATE_SAVED != 0 )) &&
       [[ -n "${ORIGINAL_STTY_STATE:-}" ]] &&
       [[ -e /dev/tty ]]
    then
        stty \
            "$ORIGINAL_STTY_STATE" \
            </dev/tty \
            2>/dev/null || true
    fi

    if [[ -e /dev/tty ]]
    then
        stty sane </dev/tty 2>/dev/null || true

        printf '\033[0m' \
            >/dev/tty \
            2>/dev/null || true

        printf '\033[?25h' \
            >/dev/tty \
            2>/dev/null || true

        printf '\033[?1049l' \
            >/dev/tty \
            2>/dev/null || true
    fi

    if declare -F logger_shutdown >/dev/null 2>&1
    then
        logger_shutdown || true
    elif declare -F log_shutdown >/dev/null 2>&1
    then
        log_shutdown || true
    fi

    LOGGER_READY=0
    TUI_READY=0

    return "$rc"
}

# ============================================================
# TRAPS
# ============================================================

trap cleanup EXIT

trap '
    rc=$?
    on_error \
        "$rc" \
        "$LINENO" \
        "${BASH_SOURCE[0]}" \
        "${FUNCNAME[1]:-main}" || true
    exit "$rc"
' ERR

trap '
    rc=$?
    on_sigint || true
    exit "$rc"
' INT

trap '
    rc=$?
    on_sigterm || true
    exit "$rc"
' TERM

# ============================================================
# MAIN
# ============================================================

main()
{
    local rc=0

    bootstrap_output \
        "${APP_NAME} ${APP_VERSION}"

    bootstrap_output \
        "Project root: ${ROOT_DIR}"

    # --------------------------------------------------------
    # STEP 1
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 1: check_root"

    if check_root
    then
        bootstrap_output \
            "STEP 1 RESULT: OK"
    else
        rc=$?
        bootstrap_output \
            "STEP 1 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 2
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 2: check_arch_environment"

    if check_arch_environment
    then
        bootstrap_output \
            "STEP 2 RESULT: OK"
    else
        rc=$?
        bootstrap_output \
            "STEP 2 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 3
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 3: check_project_structure"

    if check_project_structure
    then
        bootstrap_output \
            "STEP 3 RESULT: OK"
    else
        rc=$?
        bootstrap_output \
            "STEP 3 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 4
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 4: check_terminal"

    if check_terminal
    then
        bootstrap_output \
            "STEP 4 RESULT: OK"
    else
        rc=$?
        bootstrap_output \
            "STEP 4 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 5
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 5: check_dependencies"

    if check_dependencies
    then
        bootstrap_output \
            "STEP 5 RESULT: OK"
    else
        rc=$?
        bootstrap_output \
            "STEP 5 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 6
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 6: check_mountpoint"

    if check_mountpoint
    then
        bootstrap_output \
            "STEP 6 RESULT: OK"
    else
        rc=$?
        bootstrap_output \
            "STEP 6 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 7
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 7: load_logger"

    if load_logger
    then
        bootstrap_output \
            "STEP 7 RESULT: OK"
    else
        rc=$?
        bootstrap_output \
            "STEP 7 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 8
    # --------------------------------------------------------

    safe_log_info \
        "STEP 8: load_core_libraries"

    if load_core_libraries
    then
        safe_log_info \
            "STEP 8 RESULT: OK"
    else
        rc=$?
        safe_log_error \
            "STEP 8 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 9
    # --------------------------------------------------------

    safe_log_info \
        "STEP 9: check_config_api"

    if check_config_api
    then
        safe_log_info \
            "STEP 9 RESULT: OK"
    else
        rc=$?
        safe_log_error \
            "STEP 9 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 10
    # --------------------------------------------------------

    safe_log_info \
        "STEP 10: config_init_load"

    if config_init_load
    then
        safe_log_info \
            "STEP 10 RESULT: OK"
    else
        rc=$?
        safe_log_error \
            "STEP 10 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 11
    # --------------------------------------------------------

    safe_log_info \
        "STEP 11: detect_boot_mode"

    if detect_boot_mode
    then
        safe_log_info \
            "STEP 11 RESULT: OK"
    else
        rc=$?
        safe_log_error \
            "STEP 11 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 12
    # --------------------------------------------------------

    safe_log_info \
        "STEP 12: detect_partition_table"

    if detect_partition_table
    then
        safe_log_info \
            "STEP 12 RESULT: OK"
    else
        rc=$?
        safe_log_error \
            "STEP 12 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 13
    # --------------------------------------------------------

    safe_log_info \
        "STEP 13: load_installer_modules"

    if load_installer_modules
    then
        safe_log_info \
            "STEP 13 RESULT: OK"
    else
        rc=$?
        safe_log_error \
            "STEP 13 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 14
    # --------------------------------------------------------

    safe_log_info \
        "STEP 14: check_installer_api"

    if check_installer_api
    then
        safe_log_info \
            "STEP 14 RESULT: OK"
    else
        rc=$?
        safe_log_error \
            "STEP 14 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 15
    # --------------------------------------------------------

    safe_log_info \
        "STEP 15: app_init"

    if app_init
    then
        safe_log_info \
            "STEP 15 RESULT: OK"
    else
        rc=$?
        safe_log_error \
            "STEP 15 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 16
    # --------------------------------------------------------

    safe_log_info \
        "STEP 16: draw_startup"

    if draw_startup
    then
        safe_log_info \
            "STEP 16 RESULT: OK"
    else
        rc=$?
        safe_log_error \
            "STEP 16 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 17
    # --------------------------------------------------------

    safe_log_info \
        "STEP 17: menu_main"

    if menu_main "$@"
    then
        rc=0
    else
        rc=$?
    fi

    safe_log_info \
        "menu_main returned rc=${rc}"

    return "$rc"
}

# ============================================================
# ENTRY POINT
# ============================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
    if main "$@"
    then
        exit 0
    else
        rc=$?
        exit "$rc"
    fi
fi
