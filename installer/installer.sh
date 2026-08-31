#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# installer/installer.sh
#
# Центральный controller установки.
#
# Ответственность:
#   • управление этапами установки
#   • запуск отдельных этапов
#   • запуск полной установки
#   • контроль порядка этапов
#   • проверка API этапов
#   • хранение состояния выполнения
#   • возврат кодов ошибок
#
# Не отвечает за:
#   • загрузку библиотек
#   • загрузку installer-модулей
#   • проверку Arch Linux
#   • проверку root
#   • инициализацию TUI
#   • хранение CONFIG
#
#============================================================

#============================================================
# Include guard
#============================================================

if [[ -n "${ARCH_INSTALLER_INSTALLER_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

readonly ARCH_INSTALLER_INSTALLER_SH_LOADED=1

#============================================================
# Controller state
#============================================================

INSTALLER_CURRENT_STAGE=""
INSTALLER_CURRENT_TITLE=""
INSTALLER_LAST_FUNCTION=""
INSTALLER_LAST_MESSAGE=""
INSTALLER_LAST_RC=0
INSTALLER_STEP=0
INSTALLER_TOTAL_STEPS=0
INSTALLER_RUNNING=0

#============================================================
# Logging helpers
#============================================================

installer_log()
{
    local message="${1:-}"

    if declare -F tui_log >/dev/null 2>&1
    then
        tui_log "$message"
        return 0
    fi

    printf '%s\n' "$message"

    return 0
}

installer_log_info()
{
    local message="${1:-}"

    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$message"
        return 0
    fi

    printf '[INFO] %s\n' "$message"

    return 0
}

installer_log_warn()
{
    local message="${1:-}"

    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$message"
        return 0
    fi

    printf '[WARN] %s\n' "$message" >&2

    return 0
}

installer_log_error()
{
    local message="${1:-}"

    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$message"
        return 0
    fi

    printf '[ERROR] %s\n' "$message" >&2

    return 0
}

#============================================================
# Controller state getters
#============================================================

installer_get_stage()
{
    printf '%s\n' \
        "${INSTALLER_CURRENT_STAGE:-}"
}

installer_get_stage_title()
{
    local stage="${1:-}"

    case "$stage"
    in
        welcome)
            printf '%s\n' 'Welcome'
            ;;

        keyboard)
            printf '%s\n' 'Keyboard configuration'
            ;;

        locale)
            printf '%s\n' 'Locale configuration'
            ;;

        locale_generate)
            printf '%s\n' 'Locale generation'
            ;;

        network)
            printf '%s\n' 'Network configuration'
            ;;

        mirrors)
            printf '%s\n' 'Mirror configuration'
            ;;

        disks)
            printf '%s\n' 'Disk selection'
            ;;

        partition)
            printf '%s\n' 'Disk partitioning'
            ;;

        filesystem)
            printf '%s\n' 'Filesystem creation'
            ;;

        mount)
            printf '%s\n' 'Mount filesystems'
            ;;

        packages)
            printf '%s\n' 'Package installation'
            ;;

        users)
            printf '%s\n' 'User configuration'
            ;;

        desktop)
            printf '%s\n' 'Desktop installation'
            ;;

        services)
            printf '%s\n' 'Service configuration'
            ;;

        bootloader)
            printf '%s\n' 'Bootloader installation'
            ;;

        summary)
            printf '%s\n' 'Installation summary'
            ;;

        *)
            printf '%s\n' "$stage"
            ;;
    esac
}

installer_get_last_function()
{
    printf '%s\n' \
        "${INSTALLER_LAST_FUNCTION:-unknown}"
}

installer_get_last_message()
{
    printf '%s\n' \
        "${INSTALLER_LAST_MESSAGE:-unknown}"
}

installer_get_last_rc()
{
    printf '%s\n' \
        "${INSTALLER_LAST_RC:-0}"
}

#============================================================
# Stage -> function mapping
#
# IMPORTANT:
# Function names here MUST match the functions exported by
# the corresponding installer/*.sh modules.
#============================================================

installer_get_stage_function()
{
    local stage="${1:-}"

    case "$stage"
    in
        welcome)
            printf '%s\n' 'welcome'
            ;;

        keyboard)
            printf '%s\n' 'keyboard'
            ;;

        locale)
            printf '%s\n' 'locale'
            ;;

        locale_generate)
            printf '%s\n' 'locale_generate'
            ;;

        network)
            printf '%s\n' 'network'
            ;;

        mirrors)
            printf '%s\n' 'mirrors'
            ;;

        disks)
            printf '%s\n' 'disks'
            ;;

        partition)
            printf '%s\n' 'installer_partition'
            ;;

        filesystem)
            printf '%s\n' 'installer_filesystem'
            ;;

        mount)
            printf '%s\n' 'installer_mount'
            ;;

        packages)
            printf '%s\n' 'installer_packages'
            ;;

        users)
            printf '%s\n' 'installer_users'
            ;;

        desktop)
            printf '%s\n' 'installer_desktop'
            ;;

        services)
            printf '%s\n' 'installer_services'
            ;;

        bootloader)
            printf '%s\n' 'installer_bootloader'
            ;;

        summary)
            printf '%s\n' 'installer_summary'
            ;;

        *)
            return 1
            ;;
    esac

    return 0
}

#============================================================
# Full installation stage list
#
# welcome is intentionally excluded because it is a screen,
# not an installation operation.
#============================================================

installer_full_installation_stages()
{
    cat <<'EOF'
keyboard
locale
locale_generate
network
mirrors
disks
partition
filesystem
mount
packages
users
desktop
services
bootloader
summary
EOF

    return 0
}

#============================================================
# Count installation stages
#============================================================

installer_count_stages()
{
    local count=0
    local stage

    while IFS= read -r stage
    do
        [[ -z "$stage" ]] && continue

        count=$((count + 1))
    done < <(
        installer_full_installation_stages
    )

    printf '%s\n' "$count"

    return 0
}

#============================================================
# Set failure state
#============================================================

installer_set_failure()
{
    local stage="${1:-unknown}"
    local function_name="${2:-unknown}"
    local rc="${3:-1}"
    local message="${4:-Stage failed}"

    INSTALLER_CURRENT_STAGE="$stage"
    INSTALLER_CURRENT_TITLE="$(
        installer_get_stage_title "$stage"
    )"

    INSTALLER_LAST_FUNCTION="$function_name"
    INSTALLER_LAST_MESSAGE="$message"
    INSTALLER_LAST_RC="$rc"

    return 0
}

#============================================================
# Reset controller state
#============================================================

installer_reset_state()
{
    INSTALLER_CURRENT_STAGE=""
    INSTALLER_CURRENT_TITLE=""
    INSTALLER_LAST_FUNCTION=""
    INSTALLER_LAST_MESSAGE=""
    INSTALLER_LAST_RC=0
    INSTALLER_STEP=0
    INSTALLER_TOTAL_STEPS=0
    INSTALLER_RUNNING=0

    return 0
}

#============================================================
# Check one stage
#============================================================

installer_check_stage()
{
    local stage="${1:-}"
    local function_name=""

    if [[ -z "$stage" ]]
    then
        installer_log_error \
            "installer_check_stage: empty stage"

        return 1
    fi

    if ! function_name="$(
        installer_get_stage_function "$stage"
    )"
    then
        installer_log_error \
            "Unknown installer stage: ${stage}"

        return 1
    fi

    if [[ -z "$function_name" ]]
    then
        installer_log_error \
            "Empty function for stage: ${stage}"

        return 1
    fi

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        installer_log_error \
            "Stage function is not loaded: ${function_name} (stage=${stage})"

        return 1
    fi

    return 0
}

#============================================================
# Check all stages
#============================================================

installer_check_all_stages()
{
    local stage

    installer_log_info \
        "Checking all installer stages"

    while IFS= read -r stage
    do
        [[ -z "$stage" ]] && continue

        installer_log_info \
            "Checking stage: ${stage}"

        if ! installer_check_stage "$stage"
        then
            installer_set_failure \
                "$stage" \
                "unknown" \
                1 \
                "Required stage function is missing"

            return 1
        fi

    done < <(
        installer_full_installation_stages
    )

    installer_log_info \
        "All installer stages are available"

    return 0
}

#============================================================
# Run one stage
#============================================================

installer_run_stage()
{
    local stage="${1:-}"
    local function_name=""
    local title=""
    local rc=0

    if [[ -z "$stage" ]]
    then
        installer_log_error \
            "installer_run_stage: empty stage"

        installer_set_failure \
            "unknown" \
            "unknown" \
            1 \
            "Empty installer stage"

        return 1
    fi

    if ! function_name="$(
        installer_get_stage_function "$stage"
    )"
    then
        installer_log_error \
            "Unknown installer stage: ${stage}"

        installer_set_failure \
            "$stage" \
            "unknown" \
            1 \
            "Unknown installer stage"

        return 1
    fi

    title="$(
        installer_get_stage_title "$stage"
    )"

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        installer_log_error \
            "Function not found: ${function_name}"

        installer_set_failure \
            "$stage" \
            "$function_name" \
            127 \
            "Stage function is not loaded"

        return 127
    fi

    INSTALLER_CURRENT_STAGE="$stage"
    INSTALLER_CURRENT_TITLE="$title"
    INSTALLER_LAST_FUNCTION="$function_name"
    INSTALLER_LAST_MESSAGE=""
    INSTALLER_LAST_RC=0

    installer_log_info \
        "Starting stage: ${title}"

    installer_log_info \
        "Function: ${function_name}"

    #--------------------------------------------------------
    # IMPORTANT:
    # Do NOT call:
    #
    #     "$function_name"
    #     rc=$?
    #
    # directly under set -e.
    #
    #--------------------------------------------------------

    if "$function_name"
    then
        rc=0
    else
        rc=$?
    fi

    INSTALLER_LAST_RC="$rc"

    if (( rc != 0 ))
    then
        INSTALLER_LAST_MESSAGE="Stage returned error"

        installer_log_error \
            "Stage failed: ${title}"

        installer_log_error \
            "Function: ${function_name}"

        installer_log_error \
            "Return code: ${rc}"

        return "$rc"
    fi

    INSTALLER_LAST_MESSAGE="Stage completed successfully"

    installer_log_info \
        "Stage completed: ${title}"

    return 0
}

#============================================================
# Full installation
#============================================================

installer_full_install()
{
    local stage=""
    local title=""
    local function_name=""
    local rc=0
    local step=0
    local total=0

    installer_reset_state

    INSTALLER_RUNNING=1

    installer_log_info \
        "=========================================="

    installer_log_info \
        "Starting full installation"

    installer_log_info \
        "=========================================="

    #--------------------------------------------------------
    # Validate all required functions BEFORE doing anything
    #--------------------------------------------------------

    if ! installer_check_all_stages
    then
        INSTALLER_RUNNING=0

        installer_log_error \
            "Full installation cannot start"

        installer_log_error \
            "One or more installer stages are unavailable"

        return 1
    fi

    total="$(
        installer_count_stages
    )"

    INSTALLER_TOTAL_STEPS="$total"

    installer_log_info \
        "Total installation stages: ${total}"

    #--------------------------------------------------------
    # Execute stages
    #--------------------------------------------------------

    while IFS= read -r stage
    do
        [[ -z "$stage" ]] && continue

        step=$((step + 1))

        INSTALLER_STEP="$step"
        INSTALLER_CURRENT_STAGE="$stage"

        title="$(
            installer_get_stage_title "$stage"
        )"

        function_name="$(
            installer_get_stage_function "$stage"
        )"

        INSTALLER_CURRENT_TITLE="$title"
        INSTALLER_LAST_FUNCTION="$function_name"
        INSTALLER_LAST_MESSAGE=""
        INSTALLER_LAST_RC=0

        installer_log_info \
            "=========================================="

        installer_log_info \
            "STEP ${step}/${total}: ${title}"

        installer_log_info \
            "Function: ${function_name}"

        installer_log_info \
            "=========================================="

        #----------------------------------------------------
        # Run stage safely under set -e
        #----------------------------------------------------

        if installer_run_stage "$stage"
        then
            rc=0
        else
            rc=$?
        fi

        if (( rc != 0 ))
        then
            INSTALLER_RUNNING=0
            INSTALLER_LAST_RC="$rc"

            installer_log_error \
                "=========================================="

            installer_log_error \
                "FULL INSTALLATION FAILED"

            installer_log_error \
                "Failed stage : ${title}"

            installer_log_error \
                "Function     : ${function_name}"

            installer_log_error \
                "Return code  : ${rc}"

            installer_log_error \
                "Message      : ${INSTALLER_LAST_MESSAGE:-unknown}"

            installer_log_error \
                "=========================================="

            return "$rc"
        fi

    done < <(
        installer_full_installation_stages
    )

    #--------------------------------------------------------
    # Success
    #--------------------------------------------------------

    INSTALLER_RUNNING=0
    INSTALLER_LAST_RC=0
    INSTALLER_LAST_MESSAGE="Full installation completed successfully"

    installer_log_info \
        "=========================================="

    installer_log_info \
        "FULL INSTALLATION COMPLETED SUCCESSFULLY"

    installer_log_info \
        "=========================================="

    return 0
}

#============================================================
# Individual installer operations
#
# These functions are the public API used by menu_main.sh.
#============================================================

installer_partition()
{
    installer_run_stage partition
}

installer_filesystem()
{
    installer_run_stage filesystem
}

installer_mount()
{
    installer_run_stage mount
}

installer_packages()
{
    installer_run_stage packages
}

installer_users()
{
    installer_run_stage users
}

installer_desktop()
{
    installer_run_stage desktop
}

installer_services()
{
    installer_run_stage services
}

installer_bootloader()
{
    installer_run_stage bootloader
}

installer_summary()
{
    installer_run_stage summary
}

#============================================================
# Run installer operation
#============================================================

installer_run()
{
    local operation="${1:-}"

    case "$operation"
    in
        full|full_install|install)
            installer_full_install
            ;;

        welcome)
            installer_run_stage welcome
            ;;

        keyboard)
            installer_run_stage keyboard
            ;;

        locale)
            installer_run_stage locale
            ;;

        locale_generate)
            installer_run_stage locale_generate
            ;;

        network)
            installer_run_stage network
            ;;

        mirrors)
            installer_run_stage mirrors
            ;;

        disks|disk)
            installer_run_stage disks
            ;;

        partition|part)
            installer_partition
            ;;

        filesystem|fs)
            installer_filesystem
            ;;

        mount)
            installer_mount
            ;;

        packages|pkg)
            installer_packages
            ;;

        users|user)
            installer_users
            ;;

        desktop)
            installer_desktop
            ;;

        services)
            installer_services
            ;;

        bootloader|boot)
            installer_bootloader
            ;;

        summary)
            installer_summary
            ;;

        *)
            installer_log_error \
                "Unknown installer operation: ${operation:-<empty>}"

            INSTALLER_LAST_RC=2
            INSTALLER_LAST_MESSAGE="Unknown installer operation"

            return 2
            ;;
    esac
}

#============================================================
# Main menu
#============================================================

installer_start_menu()
{
    if ! declare -F menu_main >/dev/null 2>&1
    then
        installer_log_error \
            "menu_main() is not loaded"

        return 127
    fi

    installer_log_info \
        "Starting main installer menu"

    menu_main
}

#============================================================
# Controller entry point
#============================================================

installer_main()
{
    local operation="${1:-menu}"

    case "$operation"
    in
        menu)
            installer_start_menu
            ;;

        full|full_install|install)
            installer_full_install
            ;;

        *)
            installer_run "$operation"
            ;;
    esac
}

#============================================================
# Public aliases
#============================================================

run_full_installation()
{
    installer_full_install "$@"
}

run_installation_stage()
{
    installer_run_stage "$@"
}

#============================================================
# End of controller
#
# installer.sh is sourced by install.sh.
# It must NOT start itself when sourced.
#============================================================

return 0 2>/dev/null || true
