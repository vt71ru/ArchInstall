#!/usr/bin/env bash
#
# ============================================================
# Arch Installer
# ------------------------------------------------------------
# install.sh
#
# Главный bootstrap / orchestrator.
#
# ============================================================

set -Eeuo pipefail

IFS=$'\n\t'
umask 022

# Детерминированный парсинг вывода системных утилит
# (lsblk, blkid, parted, findmnt и т.п. в live-ISO могут
# возвращать локализованные сообщения).
export LC_ALL=C

# ============================================================
# APPLICATION
# ============================================================

readonly APP_NAME="Arch Installer"
readonly APP_SLUG="arch-installer"
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
# RUNTIME
# ============================================================

LOGGER_READY=0
TUI_READY=0
TUI_INITIALIZED=0
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

readonly ROOT_DIR
readonly LIB_DIR
readonly INSTALLER_DIR
readonly ASSETS_DIR
readonly WIDGETS_DIR

export ROOT_DIR
export LIB_DIR
export INSTALLER_DIR
export ASSETS_DIR
export WIDGETS_DIR
export LC_ALL

# ============================================================
# BOOTSTRAP OUTPUT
# ============================================================

bootstrap_output()
{
    # Склеиваем все аргументы: функции часто вызывают
    # bootstrap_output с несколькими фрагментами строки.
    local message="$*"

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
    local i=0

    # Не даём длинным подстановкам раздувать лог
    if (( ${#command} > 200 ))
    then
        command="${command:0:200}..."
    fi

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

    while (( i < ${#FUNCNAME[@]} ))
    do
        bootstrap_output \
            "  #${i} ${FUNCNAME[$i]:-unknown} (${BASH_SOURCE[$i]:-unknown}:${BASH_LINENO[$i]:-unknown})"

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
# LOGGER WRAPPERS
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
# REQUIRE LIB / INSTALLER
# ============================================================

require_lib()
{
    load_module \
        lib \
        "${1:-}" || return 1

    return 0
}

require_installer()
{
    load_module \
        installer \
        "${1:-}" || return 1

    return 0
}

# ============================================================
# REQUIRE FUNCTION HELPERS
# ============================================================

require_function()
{
    local function_name="${1:-}"

    if [[ -z "$function_name" ]]
    then
        safe_log_error \
            "require_function: empty function name"

        return 1
    fi

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        safe_log_error \
            "Required function missing: ${function_name}"

        return 1
    fi

    return 0
}

require_functions()
{
    local function_name=""

    for function_name in "$@"
    do
        require_function "$function_name" || return 1
    done

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

    # Читаем /etc/os-release в текущем шелле (файл безопасен,
    # но всё равно ограничиваемся одним субшеллом для чистоты).
    os_id="$(
        . /etc/os-release
        printf '%s' "${ID:-}"
    )"

    if [[ "$os_id" != "arch" ]]
    then
        bootstrap_output \
            "Arch Linux check: FAILED"

        return 1
    fi

    # Различаем live-ISO и установленную систему.
    # Установщик должен запускаться только из live-среды.
    if [[ ! -d /run/archiso ]] && [[ -z "${ARCHISO_ISO_LABEL:-}" ]]
    then
        bootstrap_output \
            "Arch Linux check: FAILED (not a live ISO environment)"

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

    local directory=""

    for directory in \
        "$ROOT_DIR" \
        "$LIB_DIR" \
        "$INSTALLER_DIR"
    do
        if [[ ! -d "$directory" ]]
        then
            bootstrap_output \
                "ERROR: required directory missing: ${directory}"

            return 1
        fi
    done

    local file=""

    for file in \
        "${LIB_DIR}/logger.sh" \
        "${LIB_DIR}/config.sh" \
        "${LIB_DIR}/common.sh" \
        "${LIB_DIR}/colors.sh" \
        "${LIB_DIR}/tui.sh"
    do
        if [[ ! -f "$file" ]]
        then
            bootstrap_output \
                "ERROR: required file missing: ${file}"

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
    bootstrap_output \
        "Checking /mnt..."

    if [[ ! -d /mnt ]]
    then
        bootstrap_output \
            "ERROR: /mnt does not exist"

        return 1
    fi

    if mountpoint -q /mnt 2>/dev/null
    then
        bootstrap_output \
            "ERROR: /mnt is already mounted (resume or abort manually)"

        return 1
    fi

    bootstrap_output \
        "/mnt check: OK"

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
# LOGGER
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

    if ! require_functions \
        logger_info \
        logger_warn \
        logger_error
    then
        return 1
    fi

    LOGGER_READY=1

    logger_info \
        "${APP_NAME} ${APP_VERSION}" || true

    return 0
}

# ============================================================
# CORE LIBRARIES
# ============================================================

load_core_libraries()
{
    safe_log_info \
        "Loading core libraries..."

    require_lib "config.sh" || return 1
    require_lib "common.sh" || return 1
    require_lib "colors.sh" || return 1
    require_lib "tui.sh"    || return 1

    if ! require_function colors_init
    then
        safe_log_error \
            "colors_init() is unavailable"

        return 1
    fi

    if ! colors_init
    then
        safe_log_error \
            "colors_init() failed"

        return 1
    fi

    safe_log_info \
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

    if ! require_functions \
        config_init \
        config_get \
        config_set \
        config_save
    then
        safe_log_error \
            "CONFIG API incomplete"

        return 1
    fi

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

    table="$(
        config_get \
            PARTITION_TABLE \
            2>/dev/null || true
    )"

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

# (имя_модуля, обязательные_функции...)
load_installer_module()
{
    local module="${1:-}"

    shift || true

    require_installer "$module" || return 1
    require_functions "$@"       || return 1

    return 0
}

load_installer_modules()
{
    safe_log_info \
        "Loading installer modules..."

    load_installer_module "welcome.sh"          welcome_run          || return 1
    load_installer_module "keyboard.sh"         keyboard_run         || return 1
    load_installer_module "locale.sh"           locale_run           || return 1
    load_installer_module "locale_generate.sh"  locale_generate_run  || return 1
    load_installer_module "network.sh"          network_run          || return 1
    load_installer_module "mirrors.sh"          mirrors_run          || return 1
    load_installer_module "disks.sh"            disks_run            || return 1
    load_installer_module "partition.sh"        partition_run        || return 1
    load_installer_module "filesystem.sh"       filesystem_run       || return 1
    load_installer_module "mount.sh"            mount_run            || return 1
    load_installer_module "packages.sh"         packages_run         || return 1
    load_installer_module "users.sh"            users_run            || return 1
    load_installer_module "desktop.sh"          desktop_run          || return 1
    load_installer_module "services.sh"         services_run         || return 1
    load_installer_module "bootloader.sh"       bootloader_run       || return 1
    load_installer_module "summary.sh"          summary_run          || return 1

    # Контроллер ДО menu_main.sh.
    load_installer_module \
        "installer.sh" \
        installer_run \
        installer_full_install \
        installer_run_stage \
        installer_check_stage \
        installer_check_all_stages \
        installer_get_stage_function \
        installer_get_stage_title \
        installer_start_menu \
        installer_main \
        || return 1

    # menu_main.sh — последним.
    load_installer_module "menu_main.sh" menu_main || return 1

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

    if ! require_functions \
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
    then
        safe_log_error \
            "Installer API incomplete"

        return 1
    fi

    safe_log_info \
        "Installer API: OK"

    return 0
}

# ============================================================
# SAVE TERMINAL STATE
# ============================================================

save_original_terminal_state()
{
    if [[ ! -e /dev/tty ]]
    then
        TERMINAL_STATE_SAVED=0
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

    if ! require_functions tui_init tui_start
    then
        safe_log_error \
            "TUI API incomplete"

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

    TUI_INITIALIZED=1

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

    tui_clear || true

    safe_log_info \
        "TUI started successfully"

    return 0
}

# ============================================================
# STARTUP
# ============================================================

draw_startup()
{
    if (( TUI_READY == 0 ))
    then
        return 0
    fi

    tui_clear || return 1

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw "$APP_NAME" || return 1
    fi

    tui_move 5 5 || return 1

    if declare -F color_info >/dev/null 2>&1
    then
        color_info \
            "Arch Linux installation system" || return 1
    fi

    tui_move 7 5 || return 1

    tui_print \
        "Initializing installer..." || return 1

    if declare -F screen_refresh >/dev/null 2>&1
    then
        screen_refresh 2>/dev/null || true
    fi

    return 0
}

# ============================================================
# CLEANUP
# ============================================================

cleanup()
{
    # Внутри cleanup отключаем set -e, чтобы ни одна
    # промежуточная ошибка не «съела» оригинальный rc.
    local rc=$?

    set +e

    INSTALLER_EXITING=1

    if declare -F tui_restore >/dev/null 2>&1 && (( TUI_INITIALIZED != 0 ))
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
    TUI_INITIALIZED=0

    return "$rc"
}

# ============================================================
# TRAPS
# ============================================================

# Явно игнорируем SIGPIPE: записывающая сторона в пайпе
# не должна аварийно убивать скрипт. Реальные ошибки пайпа
# всё равно будут видны через set -o pipefail (код 141
# либо код ошибки записи).
trap '' PIPE

trap cleanup EXIT

trap '
    rc=$?
