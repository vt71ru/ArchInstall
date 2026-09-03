#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  install.sh
#
#  Главный bootstrap/orchestrator проекта.
#
#  Ответственность:
#   • проверка окружения
#   • загрузка logger
#   • загрузка core libraries
#   • инициализация CONFIG
#   • определение boot mode
#   • определение partition table
#   • загрузка installer modules
#   • загрузка installer controller
#   • запуск TUI
#   • запуск main menu
#   • корректное завершение
#
#  Не выполняет установку напрямую.
#
#============================================================

set -Eeuo pipefail

IFS=$'\n\t'

umask 022

#============================================================
# Application
#============================================================

readonly APP_NAME="Arch Installer"
readonly APP_VERSION="0.1.0"

readonly ROOT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

readonly LIB_DIR="${ROOT_DIR}/lib"
readonly INSTALLER_DIR="${ROOT_DIR}/installer"
readonly WIDGET_DIR="${ROOT_DIR}/widgets"
readonly ASSET_DIR="${ROOT_DIR}/assets"

#============================================================
# Runtime state
#============================================================

LOGGER_READY=0
TUI_READY=0
INSTALLER_EXITING=0

TERMINAL_STATE_SAVED=0
ORIGINAL_STTY_STATE=""

#============================================================
# Bootstrap output
#============================================================

bootstrap_output()
{
    local message="${1-}"

    if [[ -w /dev/tty ]]
    then
        printf '%s\n' "$message" > /dev/tty
    else
        printf '%s\n' "$message" >&2
    fi

    return 0
}

#============================================================
# Logger
#============================================================

readonly LOGGER_MODULE="${LIB_DIR}/logger.sh"

if [[ ! -f "$LOGGER_MODULE" ]]
then
    bootstrap_output "ERROR: Missing logger module: ${LOGGER_MODULE}"
    exit 1
fi

export LOGGER_FILE="${LOGGER_FILE:-/tmp/arch-installer.log}"
export LOGGER_LEVEL="${LOGGER_LEVEL:-INFO}"

# shellcheck disable=SC1090
if ! source "$LOGGER_MODULE"
then
    bootstrap_output "ERROR: Cannot load logger: ${LOGGER_MODULE}"
    exit 1
fi

#============================================================
# Fatal helper
#============================================================

die()
{
    local message="${1:-Fatal error}"

    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$message" || true
    fi

    bootstrap_output "ERROR: ${message}"

    return 1
}

#============================================================
# Module loader
#============================================================

load_module()
{
    local kind="${1:-}"
    local name="${2:-}"
    local directory=""
    local file=""
    local rc=0

    case "$kind"
    in
        lib)
            directory="$LIB_DIR"
            ;;

        installer)
            directory="$INSTALLER_DIR"
            ;;

        *)
            die "Unknown module type: ${kind}"
            return 1
            ;;
    esac

    if [[ -z "$name" ]]
    then
        die "Module name is empty"
        return 1
    fi

    file="${directory}/${name}"

    if [[ ! -f "$file" ]]
    then
        die "Missing ${kind} module: ${file}"
        return 1
    fi

    bootstrap_output "Loading ${kind}: ${name}"

    if declare -F logger_debug >/dev/null 2>&1
    then
        logger_debug "Loading ${kind} module: ${file}" || true
    fi

    #--------------------------------------------------------
    # Syntax check
    #--------------------------------------------------------

    if ! bash -n "$file"
    then
        bootstrap_output "SYNTAX ERROR in ${kind}: ${name}"

        if declare -F logger_error >/dev/null 2>&1
        then
            logger_error "Syntax check failed: ${file}" || true
        fi

        return 1
    fi

    #--------------------------------------------------------
    # Source module
    #--------------------------------------------------------

    if source "$file"
    then
        bootstrap_output "Loaded ${kind}: ${name}"

        if declare -F logger_debug >/dev/null 2>&1
        then
            logger_debug "Successfully loaded ${kind}: ${file}" || true
        fi

        return 0
    fi

    rc=$?

    bootstrap_output \
        "FAILED loading ${kind}: ${name} (rc=${rc})"

    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error \
            "Failed to load ${kind} module: ${file} rc=${rc}" \
            || true
    fi

    return "$rc"
}

require_lib()
{
    if [[ $# -ne 1 ]]
    then
        die "require_lib(): module name is missing"
        return 1
    fi

    load_module lib "$1"
}

require_installer()
{
    if [[ $# -ne 1 ]]
    then
        die "require_installer(): module name is missing"
        return 1
    fi

    load_module installer "$1"
}

#============================================================
# Environment
#============================================================

check_root()
{
    bootstrap_output "Checking root privileges..."

    if (( EUID != 0 ))
    then
        die "Installer must be run as root"
        return 1
    fi

    bootstrap_output "Root check: OK"

    return 0
}

check_arch_environment()
{
    bootstrap_output "Checking Arch Linux environment..."

    if [[ ! -f /etc/arch-release ]]
    then
        die "This installer must be run from Arch Linux"
        return 1
    fi

    bootstrap_output "Arch Linux check: OK"

    return 0
}

check_project_structure()
{
    local directory

    bootstrap_output "Checking project structure..."

    for directory in \
        "$LIB_DIR" \
        "$INSTALLER_DIR"
    do
        if [[ ! -d "$directory" ]]
        then
            die "Missing project directory: ${directory}"
            return 1
        fi
    done

    if [[ ! -d /mnt ]]
    then
        die "Target directory /mnt is missing"
        return 1
    fi

    bootstrap_output "Project structure: OK"

    return 0
}

#============================================================
# Terminal check
#============================================================

check_terminal()
{
    bootstrap_output "Checking terminal..."

    if [[ ! -e /dev/tty ]]
    then
        die "/dev/tty is unavailable"
        return 1
    fi

    if [[ ! -r /dev/tty || ! -w /dev/tty ]]
    then
        die "/dev/tty is not readable/writable"
        return 1
    fi

    if [[ -z "${TERM:-}" ]]
    then
        export TERM="linux"
    fi

    if [[ "$TERM" == "dumb" ]]
    then
        die "Unsupported terminal: TERM=dumb"
        return 1
    fi

    if ! command -v tput >/dev/null 2>&1
    then
        die "tput not found"
        return 1
    fi

    if ! command -v stty >/dev/null 2>&1
    then
        die "stty not found"
        return 1
    fi

    if ! stty -g </dev/tty >/dev/null 2>&1
    then
        die "Controlling terminal does not support terminal ioctls"
        return 1
    fi

    #--------------------------------------------------------
    # Save original terminal state.
    #
    # This is independent from tui.sh and is our final
    # emergency restoration mechanism.
    #--------------------------------------------------------

    ORIGINAL_STTY_STATE="$(stty -g </dev/tty)"

    if [[ -z "$ORIGINAL_STTY_STATE" ]]
    then
        die "Unable to save original terminal state"
        return 1
    fi

    TERMINAL_STATE_SAVED=1

    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "Terminal check passed"
        logger_info "Original terminal state saved"
    fi

    bootstrap_output "Terminal check: OK"

    return 0
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
        lsblk
        blkid
        findmnt
        mountpoint
        tput
        stty
        base64
    )

    local command_name

    bootstrap_output "Checking dependencies..."

    for command_name in "${required[@]}"
    do
        if ! command -v "$command_name" >/dev/null 2>&1
        then
            die "Missing program: ${command_name}"
            return 1
        fi
    done

    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "Bootstrap dependency check passed"
    fi

    bootstrap_output "Dependencies: OK"

    return 0
}

#============================================================
# Load core libraries
#============================================================

load_core_libraries()
{
    bootstrap_output "Loading core libraries..."

    #--------------------------------------------------------
    # Configuration
    #--------------------------------------------------------

    require_lib config.sh || return 1

    #--------------------------------------------------------
    # Common functions
    #--------------------------------------------------------

    require_lib common.sh || return 1

    #--------------------------------------------------------
    # Color system
    #--------------------------------------------------------

    require_lib color.sh || return 1

    #--------------------------------------------------------
    # TUI
    #--------------------------------------------------------

    require_lib tui.sh || return 1

    #--------------------------------------------------------
    # Initialize colors after loading the module.
    #--------------------------------------------------------

    if declare -F colors_init >/dev/null 2>&1
    then
        colors_init || return 1
    else
        die "colors_init() is unavailable"
        return 1
    fi

    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "Core libraries loaded"
    fi

    bootstrap_output "Core libraries: OK"

    return 0
}

#============================================================
# Validate CONFIG API
#============================================================

check_config_api()
{
    local function_name

    bootstrap_output "Checking CONFIG API..."

    for function_name in \
        config_init \
        config_init_load \
        config_get \
        config_set \
        config_load \
        config_save \
        config_validate
    do
        if ! declare -F "$function_name" >/dev/null 2>&1
        then
            die \
                "config.sh API function unavailable: ${function_name}"

            return 1
        fi

        bootstrap_output \
            "  CONFIG API: ${function_name}: OK"
    done

    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "CONFIG API check passed"
    fi

    return 0
}

#============================================================
# Boot mode
#============================================================

detect_boot_mode()
{
    local mode=""
    local current=""

    bootstrap_output "Detecting boot mode..."

    current="$(
        config_get BOOT_MODE \
            2>/dev/null \
            || true
    )"

    if [[ "$current" == "UEFI" || "$current" == "BIOS" ]]
    then
        mode="$current"

        bootstrap_output \
            "Boot mode from configuration: ${mode}"
    else
        if [[ -d /sys/firmware/efi ]]
        then
            mode="UEFI"
        else
            mode="BIOS"
        fi

        config_set BOOT_MODE "$mode"

        bootstrap_output \
            "Boot mode detected: ${mode}"
    fi

    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "Boot mode: ${mode}"
    fi

    return 0
}

#============================================================
# Partition table
#============================================================

detect_partition_table()
{
    local boot_mode=""
    local current=""
    local table=""

    bootstrap_output "Detecting partition table..."

    current="$(
        config_get PARTITION_TABLE \
            2>/dev/null \
            || true
    )"

    if [[ "$current" == "GPT" || "$current" == "MBR" ]]
    then
        table="$current"

        bootstrap_output \
            "Partition table from configuration: ${table}"
    else
        boot_mode="$(config_get BOOT_MODE)"

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
                    "Cannot determine partition table without valid boot mode"

                return 1
                ;;
        esac

        config_set PARTITION_TABLE "$table"

        bootstrap_output \
            "Partition table selected: ${table}"
    fi

    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "Partition table: ${table}"
    fi

    return 0
}

#============================================================
# Validate installer API
#============================================================

check_installer_api()
{
    local function_name

    bootstrap_output "Checking installer controller API..."

    for function_name in \
        installer_run \
        installer_full_install \
        installer_run_stage \
        installer_check_stage \
        installer_check_all_stages \
        installer_get_stage_function \
        installer_get_stage_title \
        installer_start_menu \
        installer_main
    do
        if ! declare -F "$function_name" >/dev/null 2>&1
        then
            bootstrap_output \
                "  MISSING API: ${function_name}"

            die \
                "installer/installer.sh API function unavailable: ${function_name}"

            return 1
        fi

        bootstrap_output \
            "  API ${function_name}: OK"
    done

    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "Installer controller API check passed"
    fi

    bootstrap_output "Installer controller API: OK"

    return 0
}

#============================================================
# Load installer modules
#============================================================

load_installer_modules()
{
    bootstrap_output "Loading installer modules..."

    #--------------------------------------------------------
    # Basic modules
    #--------------------------------------------------------

    require_installer welcome.sh || return 1
    require_installer keyboard.sh || return 1
    require_installer locale.sh || return 1
    require_installer locale_generate.sh || return 1
    require_installer network.sh || return 1
    require_installer mirrors.sh || return 1
    require_installer disks.sh || return 1

    #--------------------------------------------------------
    # Installation stages
    #--------------------------------------------------------

    require_installer partition.sh || return 1
    require_installer filesystem.sh || return 1
    require_installer mount.sh || return 1
    require_installer packages.sh || return 1
    require_installer users.sh || return 1
    require_installer desktop.sh || return 1
    require_installer services.sh || return 1
    require_installer bootloader.sh || return 1
    require_installer summary.sh || return 1

    #--------------------------------------------------------
    # Central controller
    #--------------------------------------------------------

    bootstrap_output \
        "Loading central controller: installer.sh"

    require_installer installer.sh || {
        bootstrap_output \
            "ERROR: installer/installer.sh failed to load"

        return 1
    }

    bootstrap_output \
        "Central controller loaded successfully"

    #--------------------------------------------------------
    # Verify controller
    #--------------------------------------------------------

    check_installer_api || return 1

    #--------------------------------------------------------
    # Main menu
    #--------------------------------------------------------

    bootstrap_output \
        "Loading main menu: menu_main.sh"

    require_installer menu_main.sh || return 1

    if ! declare -F menu_main >/dev/null 2>&1
    then
        die \
            "menu_main() is not available after loading menu_main.sh"

        return 1
    fi

    bootstrap_output \
        "Main menu loaded successfully"

    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "Installer modules loaded"
    fi

    bootstrap_output "Installer modules: OK"

    return 0
}

#============================================================
# Application initialization
#============================================================

app_init()
{
    bootstrap_output "Initializing TUI..."

    if ! declare -F tui_init >/dev/null 2>&1
    then
        die "tui_init() is unavailable"
        return 1
    fi

    if ! tui_init
    then
        die "tui_init() failed"
        return 1
    fi

    bootstrap_output "Starting TUI..."

    if ! declare -F tui_start >/dev/null 2>&1
    then
        die "tui_start() is unavailable"
        return 1
    fi

    if ! tui_start
    then
        die "tui_start() failed"

        if declare -F tui_restore >/dev/null 2>&1
        then
            tui_restore || true
        fi

        return 1
    fi

    TUI_READY=1

    #--------------------------------------------------------
    # Terminal title
    #--------------------------------------------------------

    if declare -F tui_set_title >/dev/null 2>&1
    then
        tui_set_title "$APP_NAME" || true
    elif declare -F tui_terminal_title >/dev/null 2>&1
    then
        tui_terminal_title "$APP_NAME" || true
    fi

    #--------------------------------------------------------
    # Clear initial screen
    #--------------------------------------------------------

    if declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear || true
    fi

    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "Application initialized"
    fi

    bootstrap_output "TUI initialized successfully"

    return 0
}

#============================================================
# Startup screen
#============================================================

draw_startup()
{
    if ! declare -F tui_clear >/dev/null 2>&1
    then
        die "tui_clear() is unavailable"
        return 1
    fi

    tui_clear || return 1

    if ! declare -F titlebar_draw >/dev/null 2>&1
    then
        die "titlebar_draw() is unavailable"
        return 1
    fi

    titlebar_draw "$APP_NAME" || return 1

    tui_move 3 5

    if declare -F color_info >/dev/null 2>&1
    then
        color_info "Arch Linux Installation System"
    else
        tui_print "Arch Linux Installation System"
    fi

    tui_move 4 5

    tui_print "Initializing installer..."

    if declare -F statusbar_draw >/dev/null 2>&1
    then
        statusbar_draw \
            "F1 Help   ↑↓ Navigate   Enter Select   Esc Exit" \
            || return 1
    fi

    if declare -F screen_refresh >/dev/null 2>&1
    then
        screen_refresh || return 1
    fi

    return 0
}

#============================================================
# Cleanup
#============================================================

cleanup()
{
    local saved_rc=$?

    #--------------------------------------------------------
    # Prevent recursive cleanup.
    #--------------------------------------------------------

    if (( INSTALLER_EXITING ))
    then
        return "$saved_rc"
    fi

    INSTALLER_EXITING=1

    #--------------------------------------------------------
    # Restore TUI.
    #
    # Do NOT depend exclusively on TUI_READY.
    # tui_start() may have modified the terminal before
    # TUI_READY becomes 1.
    #--------------------------------------------------------

    if declare -F tui_restore >/dev/null 2>&1
    then
        tui_restore || true
    fi

    TUI_READY=0

    #--------------------------------------------------------
    # Restore the exact terminal state saved before TUI.
    #
    # This is the final safety net.
    #--------------------------------------------------------

    if (( TERMINAL_STATE_SAVED )) &&
       [[ -n "$ORIGINAL_STTY_STATE" ]]
    then
        if ! stty "$ORIGINAL_STTY_STATE" </dev/tty >/dev/null 2>&1
        then
            # Emergency fallback.
            stty sane </dev/tty >/dev/null 2>&1 || true
        fi
    else
        # No original state available.
        # At least make the terminal usable.
        stty sane </dev/tty >/dev/null 2>&1 || true
    fi

    #--------------------------------------------------------
    # Restore cursor and terminal attributes as an additional
    # safety measure.
    #--------------------------------------------------------

    if [[ -w /dev/tty ]]
    then
        printf '\033[0m\033[?25h\033[?1049l' > /dev/tty 2>/dev/null || true
    fi

    #--------------------------------------------------------
    # Close logger.
    #--------------------------------------------------------

    if (( LOGGER_READY ))
    then
        if declare -F logger_close >/dev/null 2>&1
        then
            logger_close || true
        fi

        LOGGER_READY=0
    fi

    return "$saved_rc"
}

#============================================================
# Error handler
#============================================================

on_error()
{
    local code="${1:-1}"
    local line="${2:-unknown}"
    local source_file="${3:-unknown}"
    local function="${4:-unknown}"

    if (( INSTALLER_EXITING ))
    then
        return "$code"
    fi

    bootstrap_output ""

    bootstrap_output "========================================"
    bootstrap_output "FATAL ERROR"
    bootstrap_output "========================================"

    bootstrap_output "Exit code : ${code}"
    bootstrap_output "File      : ${source_file}"
    bootstrap_output "Line      : ${line}"
    bootstrap_output "Function  : ${function}"
    bootstrap_output "Log       : ${LOGGER_FILE:-/tmp/arch-installer.log}"

    bootstrap_output "========================================"

    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error \
            "Fatal error: code=${code} file=${source_file} line=${line} function=${function}" \
            || true
    fi

    return "$code"
}

#============================================================
# Signals
#============================================================

on_sigint()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "Interrupted by user" || true
    fi

    exit 130
}

on_sigterm()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "Terminated by SIGTERM" || true
    fi

    exit 143
}

#============================================================
# Traps
#============================================================

trap cleanup EXIT

trap \
    'rc=$?; on_error "$rc" "$LINENO" "${BASH_SOURCE[0]}" "${FUNCNAME[1]:-main}" || true; exit "$rc"' \
    ERR

trap on_sigint INT
trap on_sigterm TERM

#============================================================
# Main
#============================================================

main()
{
    bootstrap_output "${APP_NAME} ${APP_VERSION}"
    bootstrap_output "Project root: ${ROOT_DIR}"
    bootstrap_output ""

    #--------------------------------------------------------
    # STEP 1
    #--------------------------------------------------------

    bootstrap_output "STEP 1: logger"

    if ! logger_init
    then
        bootstrap_output "ERROR: Failed to initialize logger"
        return 1
    fi

    LOGGER_READY=1

    logger_info "Starting ${APP_NAME} ${APP_VERSION}"
    logger_info "Project root: ${ROOT_DIR}"

    #--------------------------------------------------------
    # STEP 2
    #--------------------------------------------------------

    bootstrap_output "STEP 2: check_root"

    check_root || return 1

    #--------------------------------------------------------
    # STEP 3
    #--------------------------------------------------------

    bootstrap_output "STEP 3: check_arch_environment"

    check_arch_environment || return 1

    #--------------------------------------------------------
    # STEP 4
    #--------------------------------------------------------

    bootstrap_output "STEP 4: check_project_structure"

    check_project_structure || return 1

    #--------------------------------------------------------
    # STEP 5
    #--------------------------------------------------------

    bootstrap_output "STEP 5: check_terminal"

    check_terminal || return 1

    #--------------------------------------------------------
    # STEP 6
    #--------------------------------------------------------

    bootstrap_output "STEP 6: check_dependencies"

    check_dependencies || return 1

    #--------------------------------------------------------
    # STEP 7
    #--------------------------------------------------------

    bootstrap_output "STEP 7: load_core_libraries"

    load_core_libraries || return 1

    #--------------------------------------------------------
    # STEP 8
    #--------------------------------------------------------

    bootstrap_output "STEP 8: check_config_api"

    check_config_api || return 1

    #--------------------------------------------------------
    # STEP 9
    #--------------------------------------------------------

    bootstrap_output "STEP 9: config_init_load"

    if ! config_init_load
    then
        logger_error "config_init_load() failed"
        return 1
    fi

    #--------------------------------------------------------
    # STEP 10
    #--------------------------------------------------------

    bootstrap_output "STEP 10: detect_boot_mode"

    detect_boot_mode || return 1

    #--------------------------------------------------------
    # STEP 11
    #--------------------------------------------------------

    bootstrap_output "STEP 11: detect_partition_table"

    detect_partition_table || return 1

    #--------------------------------------------------------
    # STEP 12
    #--------------------------------------------------------

    bootstrap_output "STEP 12: load_installer_modules"

    load_installer_modules || return 1

    #--------------------------------------------------------
    # STEP 13
    #--------------------------------------------------------

    bootstrap_output "STEP 13: app_init"

    app_init || return 1

    #--------------------------------------------------------
    # STEP 14
    #--------------------------------------------------------

    bootstrap_output "STEP 14: draw_startup"

    draw_startup || return 1

    #--------------------------------------------------------
    # STEP 15
    #--------------------------------------------------------

    bootstrap_output "STEP 15: menu_main"

    if ! declare -F menu_main >/dev/null 2>&1
    then
        die "menu_main() is not available"
        return 1
    fi

    if menu_main
    then
        :
    else
        local rc=$?

        logger_error \
            "Main menu returned with error: ${rc}" \
            || true

        return "$rc"
    fi

    #--------------------------------------------------------
    # STEP 16
    #--------------------------------------------------------

    bootstrap_output "STEP 16: normal exit"

    logger_info "Main menu exited normally"

    return 0
}

#============================================================
# Entry point
#============================================================

main "$@"
exit $?
