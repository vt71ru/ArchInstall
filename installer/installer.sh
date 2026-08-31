#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  installer.sh
#
#  Центральный controller установки.
#
#  Ответственность:
#   • контроль installer-модулей
#   • проверка entry point
#   • выполнение отдельных этапов
#   • выполнение полной установки
#   • контроль порядка этапов
#   • фиксация текущего этапа
#   • фиксация кода ошибки
#   • возврат кодов ошибок
#
#  НЕ содержит:
#   • TTY logic
#   • keyboard parsing
#   • drawing
#   • partition logic
#   • filesystem logic
#   • mount logic
#   • package logic
#   • bootloader logic
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
# Logging helpers
#============================================================

installer_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@"
    else
        printf \
            '[INSTALLER] [INFO] %s\n' \
            "$*" \
            >&2
    fi
}

installer_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@"
    else
        printf \
            '[INSTALLER] [WARN] %s\n' \
            "$*" \
            >&2
    fi
}

installer_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@"
    else
        printf \
            '[INSTALLER] [ERROR] %s\n' \
            "$*" \
            >&2
    fi
}

installer_log_debug()
{
    if declare -F logger_debug >/dev/null 2>&1
    then
        logger_debug "$@"
    fi
}

#============================================================
# Stage output
#============================================================

installer_stage_output()
{
    local message="${1:-}"

    if declare -F bootstrap_output >/dev/null 2>&1
    then
        bootstrap_output \
            "$message"
    else
        printf '%s\n' \
            "$message"
    fi
}

#============================================================
# Check installer module
#============================================================

installer_load_module()
{
    local module="${1:-}"
    local root
    local file

    if [[ -z "$module" ]]
    then
        installer_log_error \
            "Installer module name is empty"

        return 1
    fi

    root="${INSTALLER_ROOT:-}"

    if [[ -z "$root" ]]
    then
        root="$(
            cd "$(dirname "${BASH_SOURCE[0]}")" &&
            pwd
        )"
    fi

    file="${root}/${module}"

    if [[ ! -f "$file" ]]
    then
        installer_log_error \
            "Installer module not found: ${file}"

        return 1
    fi

    installer_log_debug \
        "Installer module already loaded: ${module}"

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
# Reset controller state
#============================================================

installer_reset_state()
{
    INSTALLER_STAGE="idle"
    INSTALLER_LAST_RC=0
    INSTALLER_LAST_FUNCTION=""
    INSTALLER_LAST_MESSAGE=""

    return 0
}

#============================================================
# Run one installation stage
#============================================================

installer_run_stage()
{
    local stage="${1:-}"
    local function_name="${2:-}"

    local rc=0

    if [[ -z "$stage" ]]
    then
        installer_log_error \
            "Stage name is empty"

        INSTALLER_STAGE="unknown"
        INSTALLER_LAST_RC=1
        INSTALLER_LAST_FUNCTION=""
        INSTALLER_LAST_MESSAGE="Stage name is empty"

        return 1
    fi

    if [[ -z "$function_name" ]]
    then
        installer_log_error \
            "Stage '${stage}': function name is empty"

        INSTALLER_STAGE="$stage"
        INSTALLER_LAST_RC=1
        INSTALLER_LAST_FUNCTION=""
        INSTALLER_LAST_MESSAGE="Function name is empty"

        return 1
    fi

    #--------------------------------------------------------
    # Update runtime state
    #--------------------------------------------------------

    INSTALLER_STAGE="$stage"
    INSTALLER_LAST_FUNCTION="$function_name"
    INSTALLER_LAST_MESSAGE=""

    installer_log_info \
        "Starting stage: ${stage}"

    installer_stage_output \
        "[START] ${stage}"

    #--------------------------------------------------------
    # Verify entry point
    #--------------------------------------------------------

    if ! installer_require_function "$function_name"
    then
        INSTALLER_LAST_RC=1

        INSTALLER_LAST_MESSAGE \
            "Entry point missing: ${function_name}"

        installer_log_error \
            "Stage '${stage}': ${INSTALLER_LAST_MESSAGE}"

        installer_stage_output \
            "[FAILED] ${stage} (rc=1)"

        return 1
    fi

    #--------------------------------------------------------
    # Execute stage
    #
    # IMPORTANT:
    # The function is executed inside an if statement so that
    # set -e does not terminate the entire installer before
    # we can capture its return code.
    #--------------------------------------------------------

    installer_log_debug \
        "Stage '${stage}': executing ${function_name}"

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
            "Function ${function_name} returned ${rc}"

        installer_log_error \
            "Stage failed: ${stage} (function=${function_name}, rc=${rc})"

        installer_stage_output \
            "[FAILED] ${stage} (rc=${rc})"

        return "$rc"
    fi

    #--------------------------------------------------------
    # Success
    #--------------------------------------------------------

    INSTALLER_LAST_MESSAGE \
        "Stage completed successfully"

    installer_log_info \
        "Stage completed: ${stage}"

    installer_stage_output \
        "[ OK ] ${stage}"

    return 0
}

#============================================================
# Partition
#============================================================

installer_partition()
{
    installer_run_stage \
        "Partition" \
        "partition_main"
}

#============================================================
# Filesystem
#============================================================

installer_filesystem()
{
    installer_run_stage \
        "Filesystem" \
        "filesystem_main"
}

#============================================================
# Mount
#============================================================

installer_mount()
{
    installer_run_stage \
        "Mount" \
        "mount_main"
}

#============================================================
# Packages
#============================================================

installer_packages()
{
    installer_run_stage \
        "Packages" \
        "packages_main"
}

#============================================================
# Users
#============================================================

installer_users()
{
    installer_run_stage \
        "Users" \
        "users_main"
}

#============================================================
# Desktop
#============================================================

installer_desktop()
{
    installer_run_stage \
        "Desktop" \
        "desktop_main"
}

#============================================================
# Services
#============================================================

installer_services()
{
    installer_run_stage \
        "Services" \
        "services_main"
}

#============================================================
# Bootloader
#============================================================

installer_bootloader()
{
    installer_run_stage \
        "Bootloader" \
        "bootloader_main"
}

#============================================================
# Full installation
#============================================================

installer_run()
{
    local rc=0

    installer_log_info \
        "Starting full Arch Linux installation"

    installer_reset_state

    INSTALLER_STAGE="starting"

    installer_stage_output \
        "========================================"

    installer_stage_output \
        "FULL INSTALLATION"

    installer_stage_output \
        "========================================"

    #--------------------------------------------------------
    # 1. Partition
    #--------------------------------------------------------

    if installer_partition
    then
        :
    else
        rc=$?

        INSTALLER_STAGE="Partition"
        INSTALLER_LAST_RC="$rc"

        installer_log_error \
            "Installation stopped at partition stage"

        return "$rc"
    fi

    #--------------------------------------------------------
    # 2. Filesystem
    #--------------------------------------------------------

    if installer_filesystem
    then
        :
    else
        rc=$?

        INSTALLER_STAGE="Filesystem"
        INSTALLER_LAST_RC="$rc"

        installer_log_error \
            "Installation stopped at filesystem stage"

        return "$rc"
    fi

    #--------------------------------------------------------
    # 3. Mount
    #--------------------------------------------------------

    if installer_mount
    then
        :
    else
        rc=$?

        INSTALLER_STAGE="Mount"
        INSTALLER_LAST_RC="$rc"

        installer_log_error \
            "Installation stopped at mount stage"

        return "$rc"
    fi

    #--------------------------------------------------------
    # 4. Packages
    #--------------------------------------------------------

    if installer_packages
    then
        :
    else
        rc=$?

        INSTALLER_STAGE="Packages"
        INSTALLER_LAST_RC="$rc"

        installer_log_error \
            "Installation stopped at packages stage"

        return "$rc"
    fi

    #--------------------------------------------------------
    # 5. Users
    #--------------------------------------------------------

    if installer_users
    then
        :
    else
        rc=$?

        INSTALLER_STAGE="Users"
        INSTALLER_LAST_RC="$rc"

        installer_log_error \
            "Installation stopped at users stage"

        return "$rc"
    fi

    #--------------------------------------------------------
    # 6. Desktop
    #--------------------------------------------------------

    if installer_desktop
    then
        :
    else
        rc=$?

        INSTALLER_STAGE="Desktop"
        INSTALLER_LAST_RC="$rc"

        installer_log_error \
            "Installation stopped at desktop stage"

        return "$rc"
    fi

    #--------------------------------------------------------
    # 7. Services
    #--------------------------------------------------------

    if installer_services
    then
        :
    else
        rc=$?

        INSTALLER_STAGE="Services"
        INSTALLER_LAST_RC="$rc"

        installer_log_error \
            "Installation stopped at services stage"

        return "$rc"
    fi

    #--------------------------------------------------------
    # 8. Bootloader
    #--------------------------------------------------------

    if installer_bootloader
    then
        :
    else
        rc=$?

        INSTALLER_STAGE="Bootloader"
        INSTALLER_LAST_RC="$rc"

        installer_log_error \
            "Installation stopped at bootloader stage"

        return "$rc"
    fi

    #--------------------------------------------------------
    # Completed
    #--------------------------------------------------------

    INSTALLER_STAGE="completed"
    INSTALLER_LAST_RC=0
    INSTALLER_LAST_FUNCTION=""
    INSTALLER_LAST_MESSAGE="Installation completed successfully"

    installer_stage_output \
        "========================================"

    installer_stage_output \
        "FULL INSTALLATION COMPLETED"

    installer_stage_output \
        "========================================"

    installer_log_info \
        "Full Arch Linux installation completed successfully"

    return 0
}

#============================================================
# Run selected stage
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

        full)
            installer_run
            ;;

        *)
            installer_log_error \
                "Unknown installer stage: ${stage}"

            INSTALLER_STAGE="unknown"
            INSTALLER_LAST_RC=1
            INSTALLER_LAST_FUNCTION=""
            INSTALLER_LAST_MESSAGE="Unknown stage: ${stage}"

            return 1
            ;;
    esac
}

#============================================================
# Controller status
#============================================================

installer_get_stage()
{
    printf '%s\n' \
        "$INSTALLER_STAGE"
}

installer_get_last_rc()
{
    printf '%s\n' \
        "$INSTALLER_LAST_RC"
}

installer_get_last_function()
{
    printf '%s\n' \
        "$INSTALLER_LAST_FUNCTION"
}

installer_get_last_message()
{
    printf '%s\n' \
        "$INSTALLER_LAST_MESSAGE"
}
