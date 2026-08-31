#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  installer/installer.sh
#
#  Центральный controller установки.
#
#============================================================

if [[ -n "${ARCH_INSTALLER_INSTALLER_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

readonly ARCH_INSTALLER_INSTALLER_SH_LOADED=1

#============================================================
# Internal state
#============================================================

INSTALLER_CURRENT_STAGE=""
INSTALLER_LAST_FUNCTION=""
INSTALLER_LAST_MESSAGE=""
INSTALLER_LAST_RC=0

#============================================================
# Logging
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
}

#============================================================
# State getters
#============================================================

installer_get_stage()
{
    printf '%s\n' \
        "${INSTALLER_CURRENT_STAGE:-unknown}"
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

installer_reset_state()
{
    INSTALLER_CURRENT_STAGE=""
    INSTALLER_LAST_FUNCTION=""
    INSTALLER_LAST_MESSAGE=""
    INSTALLER_LAST_RC=0
}

#============================================================
# Stage definitions
#============================================================

installer_get_stage_function()
{
    local stage="${1:-}"

    case "$stage" in

        keyboard)
            printf '%s\n' 'keyboard_configure'
            ;;

        locale)
            printf '%s\n' 'locale_configure'
            ;;

        network)
            printf '%s\n' 'network_configure'
            ;;

        mirrors)
            printf '%s\n' 'mirrors_configure'
            ;;

        disks)
            printf '%s\n' 'disks_select'
            ;;

        partition)
            printf '%s\n' 'partition'
            ;;

        filesystem)
            printf '%s\n' 'filesystem_run'
            ;;

        mount)
            printf '%s\n' 'mount_run'
            ;;

        packages)
            printf '%s\n' 'packages_install'
            ;;

        users)
            printf '%s\n' 'users_configure'
            ;;

        desktop)
            printf '%s\n' 'desktop_install'
            ;;

        services)
            printf '%s\n' 'services_configure'
            ;;

        bootloader)
            printf '%s\n' 'bootloader_install'
            ;;

        summary)
            printf '%s\n' 'summary_show'
            ;;

        *)
            return 1
            ;;

    esac
}

#============================================================
# Stage titles
#============================================================

installer_get_stage_title()
{
    local stage="${1:-}"

    case "$stage" in

        keyboard)
            printf '%s\n' 'Keyboard configuration'
            ;;

        locale)
            printf '%s\n' 'Locale configuration'
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

#============================================================
# Full installation order
#============================================================

installer_full_installation_stages()
{
    cat <<'EOF'
keyboard
locale
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
}

#============================================================
# Check stage
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

    function_name="$(
        installer_get_stage_function "$stage"
    )" || {
        installer_log_error \
            "Unknown installer stage: $stage"

        return 1
    }

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        installer_log_error \
            "Stage function is not loaded: $function_name"

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

    while IFS= read -r stage
    do
        [[ -z "$stage" ]] && continue

        if ! installer_check_stage "$stage"
        then
            return 1
        fi

    done < <(
        installer_full_installation_stages
    )

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

        return 1
    fi

    function_name="$(
        installer_get_stage_function "$stage"
    )" || {
        installer_log_error \
            "Unknown installer stage: $stage"

        return 1
    }

    title="$(
        installer_get_stage_title "$stage"
    )"

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        installer_log_error \
            "Function not found: $function_name"

        INSTALLER_CURRENT_STAGE="$stage"
        INSTALLER_LAST_FUNCTION="$function_name"
        INSTALLER_LAST_MESSAGE="Function not found"
        INSTALLER_LAST_RC=127

        return 127
    fi

    INSTALLER_CURRENT_STAGE="$stage"
    INSTALLER_LAST_FUNCTION="$function_name"
    INSTALLER_LAST_MESSAGE=""
    INSTALLER_LAST_RC=0

    installer_log_info \
        "Starting: $title"

    if "$function_name"
    then
        rc=0
    else
        rc=$?
    fi

    INSTALLER_LAST_RC="$rc"

    if (( rc != 0 ))
    then
        INSTALLER_LAST_MESSAGE="Stage failed"

        installer_log_error \
            "Stage failed: $title (exit code $rc)"

        return "$rc"
    fi

    INSTALLER_LAST_MESSAGE="Stage completed successfully"

    installer_log_info \
        "Completed: $title"

    return 0
}

#============================================================
# Full installation
#============================================================

installer_full_install()
{
    local stage=""
    local title=""
    local rc=0
    local step=0
    local total=0

    installer_reset_state

    installer_log_info \
        "=========================================="

    installer_log_info \
        "Starting full installation"

    installer_log_info \
        "=========================================="

    #--------------------------------------------------------
    # Check all required functions BEFORE destructive work
    #--------------------------------------------------------

    if ! installer_check_all_stages
    then
        installer_log_error \
            "Full installation cannot start"

        installer_log_error \
            "One or more installer stages are missing"

        return 1
    fi

    total="$(
        installer_full_installation_stages |
            grep -c '.'
    )"

    while IFS= read -r stage
    do
        [[ -z "$stage" ]] && continue

        step=$((step + 1))

        title="$(
            installer_get_stage_title "$stage"
        )"

        installer_log_info \
            "STEP $step/$total: $title"

        if installer_run_stage "$stage"
        then
            rc=0
        else
            rc=$?

            installer_log_error \
                "=========================================="

            installer_log_error \
                "Full installation FAILED"

            installer_log_error \
                "Failed stage: $title"

            installer_log_error \
                "Function: ${INSTALLER_LAST_FUNCTION}"

            installer_log_error \
                "Exit code: $rc"

            installer_log_error \
                "=========================================="

            return "$rc"
        fi

    done < <(
        installer_full_installation_stages
    )

    installer_log_info \
        "=========================================="

    installer_log_info \
        "Full installation completed successfully"

    installer_log_info \
        "=========================================="

    return 0
}

#============================================================
# Public individual operations
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

installer_bootloader()
{
    installer_run_stage bootloader
}

#============================================================
# Generic operation dispatcher
#============================================================

installer_run()
{
    local operation="${1:-}"

    case "$operation" in

        full|full_install|install)
            installer_full_install
            ;;

        keyboard)
            installer_run_stage keyboard
            ;;

        locale)
            installer_run_stage locale
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
            installer_run_stage users
            ;;

        desktop)
            installer_run_stage desktop
            ;;

        services)
            installer_run_stage services
            ;;

        bootloader|boot)
            installer_bootloader
            ;;

        summary)
            installer_run_stage summary
            ;;

        *)
            installer_log_error \
                "Unknown installer operation: ${operation:-<empty>}"

            return 2
            ;;

    esac
}

#============================================================
# Main menu entry point
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
    local rc=0

    case "$operation" in

        menu)
            installer_start_menu
            rc=$?
            ;;

        full|full_install|install)
            installer_full_install
            rc=$?
            ;;

        *)
            installer_run "$operation"
            rc=$?
            ;;

    esac

    return "$rc"
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
# Direct execution
#============================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
    installer_main "$@"
    exit $?
fi
