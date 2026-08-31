#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  installer.sh
#
#  Центральный controller установки.
#
#============================================================

if [[ -n "${INSTALLER_SH_LOADED:-}" ]]
then
    return 0
fi

readonly INSTALLER_SH_LOADED=1

#============================================================
# Runtime state
#============================================================

INSTALLER_STAGE="idle"
INSTALLER_LAST_RC=0
INSTALLER_LAST_FUNCTION=""
INSTALLER_LAST_MESSAGE=""

#============================================================
# Logging
#============================================================

installer_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@"
    else
        printf '[INSTALLER] [INFO] %s\n' "$*" >&2
    fi

    return 0
}

installer_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@"
    else
        printf '[INSTALLER] [WARN] %s\n' "$*" >&2
    fi

    return 0
}

installer_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@"
    else
        printf '[INSTALLER] [ERROR] %s\n' "$*" >&2
    fi

    return 0
}

installer_log_debug()
{
    if declare -F logger_debug >/dev/null 2>&1
    then
        logger_debug "$@"
    fi

    return 0
}

#============================================================
# Output
#============================================================

installer_output()
{
    local message="${1:-}"

    if declare -F bootstrap_output >/dev/null 2>&1
    then
        bootstrap_output "$message"
    else
        printf '%s\n' "$message"
    fi

    return 0
}

#============================================================
# Require function
#============================================================

installer_require_function()
{
    local function_name="${1:-}"

    if [[ -z "$function_name" ]]
    then
        installer_log_error \
            "Entry point name is empty"

        return 1
    fi

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        installer_log_error \
            "Required installer entry point is missing: ${function_name}"

        return 1
    fi

    return 0
}

#============================================================
# Reset state
#============================================================

installer_reset()
{
    INSTALLER_STAGE="idle"
    INSTALLER_LAST_RC=0
    INSTALLER_LAST_FUNCTION=""
    INSTALLER_LAST_MESSAGE=""

    return 0
}

#============================================================
# Run one stage
#============================================================

installer_run_stage()
{
    local stage="${1:-}"
    local function_name="${2:-}"
    local rc=0

    if [[ -z "$stage" ]]
    then
        INSTALLER_STAGE="unknown"
        INSTALLER_LAST_RC=1
        INSTALLER_LAST_MESSAGE="Stage name is empty"

        installer_log_error \
            "$INSTALLER_LAST_MESSAGE"

        return 1
    fi

    if [[ -z "$function_name" ]]
    then
        INSTALLER_STAGE="$stage"
        INSTALLER_LAST_RC=1
        INSTALLER_LAST_FUNCTION=""
        INSTALLER_LAST_MESSAGE="Function name is empty"

        installer_log_error \
            "Stage ${stage}: ${INSTALLER_LAST_MESSAGE}"

        return 1
    fi

    INSTALLER_STAGE="$stage"
    INSTALLER_LAST_RC=0
    INSTALLER_LAST_FUNCTION="$function_name"
    INSTALLER_LAST_MESSAGE=""

    installer_log_info \
        "========================================"

    installer_log_info \
        "START STAGE: ${stage}"

    installer_log_info \
        "FUNCTION: ${function_name}"

    installer_output \
        "[START] ${stage}"

    #--------------------------------------------------------
    # Check entry point
    #--------------------------------------------------------

    if ! installer_require_function "$function_name"
    then
        INSTALLER_LAST_RC=1
        INSTALLER_LAST_MESSAGE="Missing function: ${function_name}"

        installer_output \
            "[FAILED] ${stage} rc=1"

        return 1
    fi

    #--------------------------------------------------------
    # Run stage
    #--------------------------------------------------------

    installer_log_debug \
        "Executing ${function_name}()"

    if "$function_name"
    then
        rc=0
    else
        rc=$?
    fi

    INSTALLER_LAST_RC="$rc"

    #--------------------------------------------------------
    # Failure
    #--------------------------------------------------------

    if (( rc != 0 ))
    then
        INSTALLER_LAST_MESSAGE \
            "Stage ${stage} returned ${rc}"

        installer_log_error \
            "========================================"

        installer_log_error \
            "STAGE FAILED: ${stage}"

        installer_log_error \
            "FUNCTION: ${function_name}"

        installer_log_error \
            "RETURN CODE: ${rc}"

        installer_log_error \
            "========================================"

        installer_output \
            "[FAILED] ${stage} rc=${rc}"

        return "$rc"
    fi

    #--------------------------------------------------------
    # Success
    #--------------------------------------------------------

    INSTALLER_LAST_MESSAGE \
        "Stage completed successfully"

    installer_log_info \
        "STAGE OK: ${stage}"

    installer_output \
        "[ OK ] ${stage}"

    return 0
}

#============================================================
# Individual stages
#============================================================

installer_partition()
{
    installer_run_stage \
        "Partition" \
        "partition_main"
}

installer_filesystem()
{
    installer_run_stage \
        "Filesystem" \
        "filesystem_main"
}

installer_mount()
{
    installer_run_stage \
        "Mount" \
        "mount_main"
}

installer_packages()
{
    installer_run_stage \
        "Packages" \
        "packages_main"
}

installer_users()
{
    installer_run_stage \
        "Users" \
        "users_main"
}

installer_desktop()
{
    installer_run_stage \
        "Desktop" \
        "desktop_main"
}

installer_services()
{
    installer_run_stage \
        "Services" \
        "services_main"
}

installer_bootloader()
{
    installer_run_stage \
        "Bootloader" \
        "bootloader_main"
}

installer_summary()
{
    installer_run_stage \
        "Summary" \
        "summary_main"
}

#============================================================
# Full installation
#============================================================

installer_run()
{
    local rc=0

    installer_reset

    INSTALLER_STAGE="starting"

    installer_log_info \
        "========================================"

    installer_log_info \
        "FULL INSTALLATION STARTED"

    installer_log_info \
        "========================================"

    installer_output \
        "========================================"

    installer_output \
        "FULL INSTALLATION STARTED"

    installer_output \
        "========================================"

    #========================================================
    # 1. Partition
    #========================================================

    installer_output \
        "STEP 1/8: Partition"

    if installer_partition
    then
        :
    else
        rc=$?
        INSTALLER_LAST_RC="$rc"
        INSTALLER_STAGE="Partition"

        installer_output \
            "FULL INSTALLATION STOPPED: Partition"

        return "$rc"
    fi

    #========================================================
    # 2. Filesystem
    #========================================================

    installer_output \
        "STEP 2/8: Filesystem"

    if installer_filesystem
    then
        :
    else
        rc=$?
        INSTALLER_LAST_RC="$rc"
        INSTALLER_STAGE="Filesystem"

        installer_output \
            "FULL INSTALLATION STOPPED: Filesystem"

        return "$rc"
    fi

    #========================================================
    # 3. Mount
    #========================================================

    installer_output \
        "STEP 3/8: Mount"

    if installer_mount
    then
        :
    else
        rc=$?
        INSTALLER_LAST_RC="$rc"
        INSTALLER_STAGE="Mount"

        installer_output \
            "FULL INSTALLATION STOPPED: Mount"

        return "$rc"
    fi

    #========================================================
    # 4. Packages
    #========================================================

    installer_output \
        "STEP 4/8: Packages"

    if installer_packages
    then
        :
    else
        rc=$?
        INSTALLER_LAST_RC="$rc"
        INSTALLER_STAGE="Packages"

        installer_output \
            "FULL INSTALLATION STOPPED: Packages"

        return "$rc"
    fi

    #========================================================
    # 5. Users
    #========================================================

    installer_output \
        "STEP 5/8: Users"

    if installer_users
    then
        :
    else
        rc=$?
        INSTALLER_LAST_RC="$rc"
        INSTALLER_STAGE="Users"

        installer_output \
            "FULL INSTALLATION STOPPED: Users"

        return "$rc"
    fi

    #========================================================
    # 6. Desktop
    #========================================================

    installer_output \
        "STEP 6/8: Desktop"

    if installer_desktop
    then
        :
    else
        rc=$?
        INSTALLER_LAST_RC="$rc"
        INSTALLER_STAGE="Desktop"

        installer_output \
            "FULL INSTALLATION STOPPED: Desktop"

        return "$rc"
    fi

    #========================================================
    # 7. Services
    #========================================================

    installer_output \
        "STEP 7/8: Services"

    if installer_services
    then
        :
    else
        rc=$?
        INSTALLER_LAST_RC="$rc"
        INSTALLER_STAGE="Services"

        installer_output \
            "FULL INSTALLATION STOPPED: Services"

        return "$rc"
    fi

    #========================================================
    # 8. Bootloader
    #========================================================

    installer_output \
        "STEP 8/8: Bootloader"

    if installer_bootloader
    then
        :
    else
        rc=$?
        INSTALLER_LAST_RC="$rc"
        INSTALLER_STAGE="Bootloader"

        installer_output \
            "FULL INSTALLATION STOPPED: Bootloader"

        return "$rc"
    fi

    #========================================================
    # Final state
    #========================================================

    INSTALLER_STAGE="completed"
    INSTALLER_LAST_RC=0
    INSTALLER_LAST_FUNCTION=""
    INSTALLER_LAST_MESSAGE="Full installation completed"

    installer_output \
        "========================================"

    installer_output \
        "FULL INSTALLATION COMPLETED"

    installer_output \
        "========================================"

    installer_log_info \
        "FULL INSTALLATION COMPLETED SUCCESSFULLY"

    return 0
}

#============================================================
# Selected stage
#============================================================

installer_run_selected()
{
    local stage="${1:-}"

    case "$stage"
    in
        partition)
            installer_partition
            ;;

        filesystem)
            installer_filesystem
            ;;

        mount)
            installer_mount
            ;;

        packages)
            installer_packages
            ;;

        users)
            installer_users
            ;;

        desktop)
            installer_desktop
            ;;

        services)
            installer_services
            ;;

        bootloader)
            installer_bootloader
            ;;

        summary)
            installer_summary
            ;;

        full)
            installer_run
            ;;

        *)
            INSTALLER_STAGE="unknown"
            INSTALLER_LAST_RC=1
            INSTALLER_LAST_MESSAGE="Unknown stage: ${stage}"

            installer_log_error \
                "$INSTALLER_LAST_MESSAGE"

            return 1
            ;;
    esac
}

#============================================================
# Status
#============================================================

installer_get_stage()
{
    printf '%s\n' \
        "${INSTALLER_STAGE:-unknown}"

    return 0
}

installer_get_last_rc()
{
    printf '%s\n' \
        "${INSTALLER_LAST_RC:-1}"

    return 0
}

installer_get_last_function()
{
    printf '%s\n' \
        "${INSTALLER_LAST_FUNCTION:-}"

    return 0
}

installer_get_last_message()
{
    printf '%s\n' \
        "${INSTALLER_LAST_MESSAGE:-}"

    return 0
}

#============================================================
# Status display
#============================================================

installer_status()
{
    printf \
        'Stage    : %s\n' \
        "${INSTALLER_STAGE:-unknown}"

    printf \
        'Function : %s\n' \
        "${INSTALLER_LAST_FUNCTION:-none}"

    printf \
        'Return   : %s\n' \
        "${INSTALLER_LAST_RC:-1}"

    printf \
        'Message  : %s\n' \
        "${INSTALLER_LAST_MESSAGE:-none}"

    return 0
}
