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
# Logging
#============================================================

installer_log()
{
    local message="${1:-}"

    if declare -F tui_log >/dev/null 2>&1
    then
        tui_log "$message"
    else
        printf '%s\n' "$message"
    fi

    return 0
}


installer_log_info()
{
    local message="${1:-}"

    if declare -F tui_log_info >/dev/null 2>&1
    then
        tui_log_info "$message"
    else
        printf '[INFO] %s\n' "$message"
    fi

    return 0
}


installer_log_warn()
{
    local message="${1:-}"

    if declare -F tui_log_warn >/dev/null 2>&1
    then
        tui_log_warn "$message"
    else
        printf '[WARN] %s\n' "$message" >&2
    fi

    return 0
}


installer_log_error()
{
    local message="${1:-}"

    if declare -F tui_log_error >/dev/null 2>&1
    then
        tui_log_error "$message"
    else
        printf '[ERROR] %s\n' "$message" >&2
    fi

    return 0
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
            printf '%s\n' 'filesystem'
            ;;

        mount)
            printf '%s\n' 'mount'
            ;;

        packages)
            printf '%s\n' 'packages'
            ;;

        users)
            printf '%s\n' 'users'
            ;;

        desktop)
            printf '%s\n' 'desktop'
            ;;

        services)
            printf '%s\n' 'services'
            ;;

        bootloader)
            printf '%s\n' 'bootloader'
            ;;

        summary)
            printf '%s\n' 'summary'
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
# Check one stage
#============================================================

installer_check_stage()
{
    local stage="${1:-}"
    local function_name

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
            installer_log_error \
                "Stage check failed: $stage"

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
    local function_name
    local title
    local rc

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

        return 127
    fi

    installer_log_info \
        "Starting: $title"

    "$function_name"
    rc=$?

    if (( rc != 0 ))
    then
        installer_log_error \
            "Stage failed: $title (exit code $rc)"

        return "$rc"
    fi

    installer_log_info \
        "Completed: $title"

    return 0
}


#============================================================
# Full installation
#============================================================

installer_full_install()
{
    local stage
    local title
    local rc
    local step=0
    local total=0

    installer_log_info \
        "=========================================="

    installer_log_info \
        "Starting full installation"

    installer_log_info \
        "=========================================="

    #--------------------------------------------------------
    # Check all entry points before doing anything
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
            "STEP ${step}/${total}: ${title}"

        #----------------------------------------------------
        # IMPORTANT:
        # Do NOT use:
        #
        # if ! installer_run_stage ...
        # then
        #     rc=$?
        #
        # because $? then belongs to !
        #----------------------------------------------------

        installer_run_stage "$stage"
        rc=$?

        if (( rc != 0 ))
        then
            installer_log_error \
                "=========================================="

            installer_log_error \
                "Full installation FAILED"

            installer_log_error \
                "Failed stage: ${title}"

            installer_log_error \
                "Exit code: ${rc}"

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
# Individual controller entry points
#============================================================

installer_keyboard()
{
    installer_run_stage keyboard
}


installer_locale()
{
    installer_run_stage locale
}


installer_network()
{
    installer_run_stage network
}


installer_mirrors()
{
    installer_run_stage mirrors
}


installer_disks()
{
    installer_run_stage disks
}


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
# Generic operation dispatcher
#============================================================

installer_run()
{
    local operation="${1:-full}"
    local rc

    case "$operation" in

        full|full_install|install)
            installer_full_install
            rc=$?
            ;;

        keyboard)
            installer_keyboard
            rc=$?
            ;;

        locale)
            installer_locale
            rc=$?
            ;;

        network)
            installer_network
            rc=$?
            ;;

        mirrors)
            installer_mirrors
            rc=$?
            ;;

        disks|disk)
            installer_disks
            rc=$?
            ;;

        partition|part)
            installer_partition
            rc=$?
            ;;

        filesystem|fs)
            installer_filesystem
            rc=$?
            ;;

        mount)
            installer_mount
            rc=$?
            ;;

        packages|pkg)
            installer_packages
            rc=$?
            ;;

        users|user)
            installer_users
            rc=$?
            ;;

        desktop)
            installer_desktop
            rc=$?
            ;;

        services)
            installer_services
            rc=$?
            ;;

        bootloader|boot)
            installer_bootloader
            rc=$?
            ;;

        summary)
            installer_summary
            rc=$?
            ;;

        *)
            installer_log_error \
                "Unknown installer operation: ${operation:-<empty>}"

            return 2
            ;;

    esac

    return "$rc"
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
    local rc

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
