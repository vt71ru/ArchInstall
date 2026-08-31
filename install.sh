```bash
#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# install.sh
#
# Главный bootstrap/orchestrator проекта.
#
# Ответственность:
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
# Не выполняет установку напрямую.
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
    cd "$(dirname "${BASH_SOURCE[0]}")" &&
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
TUI_TTY_FD=""

#============================================================
# Logger
#============================================================

readonly LOGGER_MODULE="${LIB_DIR}/logger.sh"

if [[ ! -f "$LOGGER_MODULE" ]]
then
    printf 'Missing logger module: %s\n' \
        "$LOGGER_MODULE" \
        >&2
    exit 1
fi

export LOGGER_FILE="${LOGGER_FILE:-/tmp/arch-installer.log}"
export LOGGER_LEVEL="${LOGGER_LEVEL:-INFO}"

# shellcheck disable=SC1090
source "$LOGGER_MODULE"

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

    printf 'Error: %s\n' \
        "$message" \
        >&2

    return 1
}

#============================================================
# Bootstrap output
#============================================================

bootstrap_output()
{
    local message="${1-}"

    if [[ -e /dev/tty ]] &&
       { : </dev/tty; } 2>/dev/null
    then
        printf '%s\n' \
            "$message" \
            >/dev/tty
        return 0
    fi

    printf '%s\n' \
        "$message" \
        >&2
}

#============================================================
# Terminal
#============================================================

open_terminal_fd()
{
    if [[ -n "${TUI_TTY_FD:-}" ]]
    then
        return 0
    fi

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

    if ! exec {TUI_TTY_FD}<>/dev/tty
    then
        die "Cannot open controlling terminal"
        return 1
    fi

    export TUI_TTY_FD

    logger_debug \
        "Controlling terminal opened on FD ${TUI_TTY_FD}"

    return 0
}

close_terminal_fd()
{
    if [[ -n "${TUI_TTY_FD:-}" ]]
    then
        eval \
            "exec ${TUI_TTY_FD}>&-" \
            2>/dev/null \
            || true

        TUI_TTY_FD=""

        export TUI_TTY_FD
    fi

    return 0
}

#============================================================
# Module loader
#============================================================

load_module()
{
    local kind="${1:-}"
    local name="${2:-}"
    local directory
    local file

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

    bootstrap_output \
        "Loading ${kind}: ${name}"

    logger_debug \
        "Loading ${kind} module: ${name}"

    #--------------------------------------------------------
    # Source module.
    # Capture status explicitly so that the exact failing
    # module is reported.
    #--------------------------------------------------------

    if source "$file"
    then
        bootstrap_output \
            "Loaded ${kind}: ${name}"

        logger_debug \
            "Successfully loaded ${kind} module: ${name}"

        return 0
    fi

    local rc=$?

    bootstrap_output \
        "FAILED loading ${kind}: ${name}"

    logger_error \
        "Failed to load ${kind} module: ${file} (rc=${rc})"

    return "$rc"
}

require_lib()
{
    load_module \
        lib \
        "$1"
}

require_installer()
{
    load_module \
        installer \
        "$1"
}

#============================================================
# Environment
#============================================================

check_root()
{
    if (( EUID != 0 ))
    then
        die "Installer must be run as root"
        return 1
    fi

    return 0
}

check_arch_environment()
{
    if [[ ! -f /etc/arch-release ]]
    then
        die "This installer must be run from Arch Linux"
        return 1
    fi

    return 0
}

check_project_structure()
{
    local directory

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

    return 0
}

check_terminal()
{
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

    if [[ "${TERM}" == "dumb" ]]
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

    open_terminal_fd || return 1

    if ! stty -g <&"$TUI_TTY_FD" >/dev/null 2>&1
    then
        die "Controlling terminal does not support terminal ioctls"
        return 1
    fi

    logger_info "Terminal check passed"

    return 0
}

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

    for command_name in "${required[@]}"
    do
        if ! command -v "$command_name" >/dev/null 2>&1
        then
            die "Missing program: ${command_name}"
            return 1
        fi
    done

    logger_info "Bootstrap dependency check passed"

    return 0
}

#============================================================
# Load core libraries
#============================================================

load_core_libraries()
{
    require_lib config.sh || return 1
    require_lib common.sh || return 1
    require_lib tui.sh || return 1

    logger_info "Core libraries loaded"

    return 0
}

#============================================================
# Validate CONFIG API
#============================================================

check_config_api()
{
    local function_name

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
    done

    logger_info "CONFIG API check passed"

    return 0
}

#============================================================
# Boot mode detection
#============================================================

detect_boot_mode()
{
    local mode
    local current

    current="$(
        config_get BOOT_MODE \
            2>/dev/null \
            || true
    )"

    if [[ -n "$current" ]]
    then
        case "$current"
        in
            UEFI|BIOS)
                logger_info \
                    "Boot mode loaded from configuration: ${current}"
                return 0
                ;;
        esac
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

    return 0
}

#============================================================
# Partition table
#============================================================

detect_partition_table()
{
    local boot_mode
    local current
    local table

    current="$(
        config_get PARTITION_TABLE \
            2>/dev/null \
            || true
    )"

    if [[ -n "$current" ]]
    then
        case "$current"
        in
            GPT|MBR)
                logger_info \
                    "Partition table loaded from configuration: ${current}"
                return 0
                ;;
        esac
    fi

    boot_mode="$(
        config_get BOOT_MODE
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
                "Cannot determine partition table without valid boot mode"
            return 1
            ;;
    esac

    config_set \
        PARTITION_TABLE \
        "$table"

    logger_info \
        "Partition table selected: ${table}"

    return 0
}

#============================================================
# Validate installer API
#============================================================

check_installer_api()
{
    local function_name

    bootstrap_output \
        "Checking installer controller API..."

    for function_name in \
        installer_run \
        installer_full_install \
        installer_run_stage \
        installer_check_stage \
        installer_check_all_stages \
        installer_get_stage_function \
        installer_get_stage_title \
        installer_full_installation_stages \
        installer_start_menu \
        installer_main
    do
        if ! declare -F "$function_name" >/dev/null 2>&1
        then
            bootstrap_output \
                "MISSING API: ${function_name}"

            die \
                "installer.sh API function unavailable: ${function_name}"

            return 1
        fi

        bootstrap_output \
            "OK: ${function_name}"
    done

    logger_info \
        "Installer controller API check passed"

    return 0
}

#============================================================
# Load installer modules
#============================================================

load_installer_modules()
{
    bootstrap_output \
        "Loading installer modules..."

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

    require_installer menu_main.sh || return 1

    if ! declare -F menu_main >/dev/null 2>&1
    then
        die "menu_main() is not available after loading menu_main.sh"
        return 1
    fi

    logger_info \
        "Installer modules loaded"

    return 0
}

#============================================================
# Application initialization
#============================================================

app_init()
{
    logger_info "Initializing application"

    if ! tui_init
    then
        logger_error "tui_init() failed"
        return 1
    fi

    if ! tui_start
    then
        logger_error "tui_start() failed"
        tui_restore || true
        return 1
    fi

    TUI_READY=1

    if declare -F terminal_title >/dev/null 2>&1
    then
        terminal_title "$APP_NAME"
    fi

    if declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear
    fi

    logger_info "Application initialized"

    return 0
}

#============================================================
# Startup screen
#============================================================

draw_startup()
{
    tui_clear || return 1

    titlebar_draw \
        "$APP_NAME" \
        || return 1

    statusbar_draw \
        "F1 Help   ↑↓ Navigate   Enter Select   Esc Exit" \
        || return 1

    screen_refresh || return 1

    return 0
}

#============================================================
# Cleanup
#============================================================

cleanup()
{
    local saved_rc=$?

    INSTALLER_EXITING=1

    if (( TUI_READY ))
    then
        if declare -F tui_restore >/dev/null 2>&1
        then
            tui_restore || true
        fi

        TUI_READY=0
    fi

    if declare -F terminal_restore >/dev/null 2>&1
    then
        terminal_restore || true
    fi

    close_terminal_fd

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

    printf '\nFatal error.\n' >&2

    printf 'Exit code: %s\n' \
        "$code" \
        >&2

    printf 'File: %s\n' \
        "$source_file" \
        >&2

    printf 'Line: %s\n' \
        "$line" \
        >&2

    printf 'Function: %s\n' \
        "$function" \
        >&2

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
        logger_warn \
            "Interrupted by user" \
            || true
    fi

    exit 130
}

on_sigterm()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn \
            "Terminated by SIGTERM" \
            || true
    fi

    exit 143
}

#============================================================
# Traps
#============================================================

trap cleanup EXIT

trap \
    'on_error "$?" "$LINENO" "${BASH_SOURCE[0]}" "${FUNCNAME[1]:-main}"' \
    ERR

trap on_sigint INT
trap on_sigterm TERM

#============================================================
# Main
#============================================================

main()
{
    bootstrap_output \
        "${APP_NAME} ${APP_VERSION}"

    bootstrap_output \
        "Project root: ${ROOT_DIR}"

    #--------------------------------------------------------
    # STEP 1
    #--------------------------------------------------------

    bootstrap_output "STEP 1: logger"

    if ! logger_init
    then
        printf 'Failed to initialize logger\n' >&2
        return 1
    fi

    LOGGER_READY=1

    logger_info \
        "Starting ${APP_NAME} ${APP_VERSION}"

    logger_info \
        "Project root: ${ROOT_DIR}"

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

    if ! menu_main
    then
        logger_error "Main menu returned with error"
        return 1
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
```
