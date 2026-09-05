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
#   • загрузка библиотек
#   • загрузка installer-модулей
#   • инициализация logger
#   • инициализация colors
#   • инициализация TUI
#   • аварийное восстановление терминала
#   • запуск главного меню
#
# Не содержит:
#   • partition logic
#   • filesystem logic
#   • package logic
#   • bootloader logic
#   • CONFIG business logic
#   • keyboard parser
#   • menu implementation
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
# DEBUG / TRACE
# ============================================================

INSTALLER_DEBUG="${INSTALLER_DEBUG:-0}"

if (( INSTALLER_DEBUG ))
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

    cd -P "$(dirname "$source")" >/dev/null 2>&1
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

    if (( INSTALLER_EXITING ))
    then
        return "$code"
    fi

    INSTALLER_EXITING=1

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
    local stack_function=""
    local stack_source=""
    local stack_line=""

    while (( i < ${#FUNCNAME[@]} ))
    do
        stack_function="${FUNCNAME[$i]:-unknown}"
        stack_source="${BASH_SOURCE[$i]:-unknown}"
        stack_line="${BASH_LINENO[$i]:-unknown}"

        bootstrap_output \
            "  #${i} ${stack_function} (${stack_source}:${stack_line})"

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
# SIGNAL HANDLERS
# ============================================================

on_sigint()
{
    if (( INSTALLER_EXITING ))
    then
        return 130
    fi

    INSTALLER_EXITING=1

    bootstrap_output ""
    bootstrap_output "Interrupted by user."

    return 130
}

on_sigterm()
{
    if (( INSTALLER_EXITING ))
    then
        return 143
    fi

    INSTALLER_EXITING=1

    bootstrap_output ""
    bootstrap_output "Terminated."

    return 143
}

# ============================================================
# LOGGER WRAPPERS
# ============================================================

safe_log_info()
{
    if declare -F log_info >/dev/null 2>&1
    then
        log_info "$*" || true
    else
        bootstrap_output "[INFO] $*"
    fi

    return 0
}

safe_log_warn()
{
    if declare -F log_warn >/dev/null 2>&1
    then
        log_warn "$*" || true
    else
        bootstrap_output "[WARN] $*"
    fi

    return 0
}

safe_log_error()
{
    if declare -F log_error >/dev/null 2>&1
    then
        log_error "$*" || true
    else
        bootstrap_output "[ERROR] $*"
    fi

    return 0
}

# ============================================================
# LOAD ONE LIBRARY / MODULE
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
    # Source into the current shell.
    #
    # IMPORTANT:
    # Do not use a subshell here.
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
# REQUIRE LIB
# ============================================================

require_lib()
{
    local name="${1:-}"
    local file="${LIB_DIR}/${name}"

    load_module lib "$name" || return 1

    if [[ ! -f "$file" ]]
    then
        bootstrap_output \
            "ERROR: required library missing: ${file}"

        return 1
    fi

    return 0
}

# ============================================================
# REQUIRE INSTALLER MODULE
# ============================================================

require_installer()
{
    local name="${1:-}"

    load_module installer "$name" || return 1

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

    local os_release="/etc/os-release"

    if [[ ! -f "$os_release" ]]
    then
        bootstrap_output \
            "ERROR: /etc/os-release not found"

        return 1
    fi

    local id=""
    local name=""

    if ! id="$(
        . "$os_release"
        printf '%s' "${ID:-}"
    )"
    then
        bootstrap_output \
            "ERROR: unable to read distribution ID"

        return 1
    fi

    if ! name="$(
        . "$os_release"
        printf '%s' "${NAME:-}"
    )"
    then
        name=""
    fi

    if [[ "$id" != "arch" ]]
    then
        bootstrap_output \
            "Arch Linux check: FAILED"

        bootstrap_output \
            "Detected distribution: ${name:-unknown} (${id:-unknown})"

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
        "${LIB_DIR}/config.sh" \
        "${LIB_DIR}/common.sh" \
        "${LIB_DIR}/colors.sh" \
        "${LIB_DIR}/tui.sh" \
        "${LIB_DIR}/logger.sh"
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
# /mnt CHECK
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
# TERMINAL CHECK
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

    if [[ ! -t 0 && ! -t 1 && ! -t 2 ]]
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

    bootstrap_output \
        "Terminal check: OK"

    return 0
}

# ============================================================
# DEPENDENCY CHECK
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
        printf \
        date \
        tty \
        stty \
        tput \
        mountpoint \
        find
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
# LOAD CORE LIBRARIES
# ============================================================

load_core_libraries()
{
    bootstrap_output \
        "Loading core libraries..."

    require_lib "config.sh" || return 1
    require_lib "common.sh" || return 1
    require_lib "colors.sh" || return 1
    require_lib "tui.sh" || return 1

    #
    # colors.sh must provide colors_init().
    #

    if ! declare -F colors_init >/dev/null 2>&1
    then
        bootstrap_output \
            "ERROR: colors_init() is unavailable"

        return 1
    fi

    if ! colors_init
    then
        bootstrap_output \
            "ERROR: colors_init() failed"

        return 1
    fi

    bootstrap_output \
        "Core libraries loaded"

    bootstrap_output \
        "Colors initialized"

    return 0
}

# ============================================================
# LOGGER
# ============================================================

load_logger()
{
    bootstrap_output \
        "Loading logger..."

    #
    # logger.sh is loaded first if it wasn't loaded earlier.
    #

    if ! declare -F log_info >/dev/null 2>&1
    then
        if ! require_lib "logger.sh"
        then
            bootstrap_output \
                "ERROR: failed to load logger.sh"

            return 1
        fi
    fi

    if ! declare -F log_info >/dev/null 2>&1
    then
        bootstrap_output \
            "ERROR: log_info() is unavailable"

        return 1
    fi

    safe_log_info \
        "${APP_NAME} ${APP_VERSION}"

    return 0
}

# ============================================================
# CONFIG API CHECK
# ============================================================

check_config_api()
{
    safe_log_info \
        "Checking config API"

    local required_function=""

    for required_function in \
        config_init \
        config_get \
        config_set \
        config_save
    do
        if ! declare -F "$required_function" >/dev/null 2>&1
        then
            safe_log_error \
                "Config API function missing: ${required_function}"

            return 1
        fi
    done

    safe_log_info \
        "Config API: OK"

    return 0
}

# ============================================================
# CONFIG INITIALIZATION
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

    if declare -F config_set >/dev/null 2>&1
    then
        config_set BOOT_MODE "$boot_mode" || true
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

    if declare -F config_get >/dev/null 2>&1
    then
        table="$(config_get PARTITION_TABLE 2>/dev/null || true)"
    fi

    if [[ -z "$table" ]]
    then
        if [[ "${BOOT_MODE:-BIOS}" == "UEFI" ]]
        then
            table="GPT"
        else
            table="MBR"
        fi
    fi

    if declare -F config_set >/dev/null 2>&1
    then
        config_set PARTITION_TABLE "$table" || true
    fi

    export PARTITION_TABLE="$table"

    safe_log_info \
        "Partition table: ${table}"

    return 0
}

# ============================================================
# INSTALLER MODULES
# ============================================================

load_installer_modules()
{
    safe_log_info \
        "Loading installer modules..."

    #
    # IMPORTANT:
    # menu_main.sh must be loaded LAST.
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
    require_installer "installer.sh" || return 1

    #
    # Verify controller before loading menu.
    #

    if ! declare -F installer_full_install >/dev/null 2>&1
    then
        safe_log_error \
            "installer_full_install() is unavailable after installer.sh"

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
    # Menu MUST be loaded last.
    #

    require_installer "menu_main.sh" || return 1

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
# INSTALLER API CHECK
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
# SAVE ORIGINAL STTY
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

    #
    # TUI must exist.
    #

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

    #
    # Save state independently of TUI.
    #

    save_original_terminal_state || true

    #
    # Initialize TUI.
    #

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

    #
    # Set title.
    #

    if declare -F tui_set_title >/dev/null 2>&1
    then
        if ! tui_set_title "${APP_NAME} ${APP_VERSION}"
        then
            safe_log_warn \
                "tui_set_title() failed"
        fi
    fi

    if declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear || true
    fi

    safe_log_info \
        "Application initialized"

    return 0
}

# ============================================================
# STARTUP SCREEN
# ============================================================

draw_startup()
{
    if (( ! TUI_READY ))
    then
        return 0
    fi

    if ! declare -F tui_clear >/dev/null 2>&1
    then
        return 1
    fi

    if ! tui_clear
    then
        return 1
    fi

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "${APP_NAME}" || return 1
    fi

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move 5 5 || return 1
    fi

    if declare -F color_info >/dev/null 2>&1
    then
        color_info \
            "Arch Linux installation system" || return 1
    elif declare -F tui_print >/dev/null 2>&1
    then
        tui_print \
            "Arch Linux installation system" || return 1
    fi

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move 7 5 || return 1
    fi

    if declare -F tui_print >/dev/null 2>&1
    then
        tui_print \
            "Initializing installer..." || return 1
    fi

    if declare -F screen_refresh >/dev/null 2>&1
    then
        screen_refresh || true
    fi

    return 0
}

# ============================================================
# CLEANUP
# ============================================================

cleanup()
{
    local rc=$?

    if (( INSTALLER_EXITING == 0 ))
    then
        INSTALLER_EXITING=1
    fi

    #
    # Restore TUI.
    #

    if declare -F tui_restore >/dev/null 2>&1
    then
        tui_restore || true
    fi

    #
    # Restore original stty state as a final fallback.
    #

    if (( TERMINAL_STATE_SAVED )) &&
       [[ -n "${ORIGINAL_STTY_STATE:-}" ]] &&
       [[ -e /dev/tty ]]
    then
        stty "$ORIGINAL_STTY_STATE" </dev/tty 2>/dev/null || true
    fi

    #
    # Last resort.
    #

    if [[ -e /dev/tty ]]
    then
        stty sane </dev/tty 2>/dev/null || true

        printf '\033[0m' >/dev/tty 2>/dev/null || true
        printf '\033[?25h' >/dev/tty 2>/dev/null || true
        printf '\033[?1049l' >/dev/tty 2>/dev/null || true
    fi

    #
    # Close logger.
    #

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
        bootstrap_output "STEP 1 RESULT: OK"
    else
        rc=$?
        bootstrap_output "STEP 1 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 2
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 2: check_arch_environment"

    if check_arch_environment
    then
        bootstrap_output "STEP 2 RESULT: OK"
    else
        rc=$?
        bootstrap_output "STEP 2 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 3
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 3: check_project_structure"

    if check_project_structure
    then
        bootstrap_output "STEP 3 RESULT: OK"
    else
        rc=$?
        bootstrap_output "STEP 3 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 4
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 4: check_terminal"

    if check_terminal
    then
        bootstrap_output "STEP 4 RESULT: OK"
    else
        rc=$?
        bootstrap_output "STEP 4 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 5
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 5: check_dependencies"

    if check_dependencies
    then
        bootstrap_output "STEP 5 RESULT: OK"
    else
        rc=$?
        bootstrap_output "STEP 5 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 6
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 6: check_mountpoint"

    if check_mountpoint
    then
        bootstrap_output "STEP 6 RESULT: OK"
    else
        rc=$?
        bootstrap_output "STEP 6 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 7
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 7: load_core_libraries"

    if load_core_libraries
    then
        bootstrap_output "STEP 7 RESULT: OK"
    else
        rc=$?
        bootstrap_output "STEP 7 RESULT: FAILED (${rc})"
        return "$rc"
    fi

    # --------------------------------------------------------
    # STEP 8
    # --------------------------------------------------------

    bootstrap_output \
        "STEP 8: load_logger"

    if load_logger
    then
        bootstrap_output "STEP 8 RESULT: OK"
        LOGGER_READY=1
    else
        rc=$?
        bootstrap_output "STEP 8 RESULT: FAILED (${rc})"
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
    main "$@"
    exit $?
fi
