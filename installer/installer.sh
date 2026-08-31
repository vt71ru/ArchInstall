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
#   • загрузка installer-модулей
#   • проверка entry point
#   • выполнение отдельных этапов
#   • выполнение полной установки
#   • контроль порядка этапов
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
#  API installer-модулей:
#
#       partition.sh    -> partition_main()
#       filesystem.sh   -> filesystem_main()
#       mount.sh        -> mount_main()
#       packages.sh     -> packages_main()
#       bootloader.sh   -> bootloader_main()
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
        "Installer module already expected to be loaded: ${module}"

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

        INSTALLER_LAST_RC=1

        return 1
    fi

    if [[ -z "$function_name" ]]
    then
        installer_log_error \
            "Stage '$stage': function name is empty"

        INSTALLER_LAST_RC=1

        return 1
    fi

    INSTALLER_STAGE="$stage"

    installer_log_info \
        "Starting stage: ${stage}"

    #--------------------------------------------------------
    # Verify entry point
    #--------------------------------------------------------

    if ! installer_require_function "$function_name"
    then
        installer_log_error \
            "Stage '${stage}': entry point missing: ${function_name}"

        INSTALLER_LAST_RC=1

        return 1
    fi

    #--------------------------------------------------------
    # Execute stage
    #
    # IMPORTANT:
    # The function is called inside an if-condition so that
    # set -e does not terminate the installer before we can
    # process its return code.
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
    # Stage failed
    #--------------------------------------------------------

    if (( rc != 0 ))
    then
        installer_log_error \
            "Stage failed: ${stage} (rc=${rc})"

        return "$rc"
    fi

    #--------------------------------------------------------
    # Stage completed
    #--------------------------------------------------------

    installer_log_info \
        "Stage completed: ${stage}"

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

    INSTALLER_STAGE="starting"
    INSTALLER_LAST_RC=0

    #--------------------------------------------------------
    # 1. Partition
    #--------------------------------------------------------

    if installer_partition
    then
        :
    else
        rc=$?

        installer_log_error \
            "Installation stopped at partition stage"

        INSTALLER_STAGE="Partition"
        INSTALLER_LAST_RC="$rc"

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

        installer_log_error \
            "Installation stopped at filesystem stage"

        INSTALLER_STAGE="Filesystem"
        INSTALLER_LAST_RC="$rc"

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

        installer_log_error \
            "Installation stopped at mount stage"

        INSTALLER_STAGE="Mount"
        INSTALLER_LAST_RC="$rc"

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

        installer_log_error \
            "Installation stopped at packages stage"

        INSTALLER_STAGE="Packages"
        INSTALLER_LAST_RC="$rc"

        return "$rc"
    fi

    #--------------------------------------------------------
    # 5. Bootloader
    #--------------------------------------------------------

    if installer_bootloader
    then
        :
    else
        rc=$?

        installer_log_error \
            "Installation stopped at bootloader stage"

        INSTALLER_STAGE="Bootloader"
        INSTALLER_LAST_RC="$rc"

        return "$rc"
    fi

    #--------------------------------------------------------
    # Completed
    #--------------------------------------------------------

    INSTALLER_STAGE="completed"
    INSTALLER_LAST_RC=0

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

    case "$stage" in
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

        bootloader)
            installer_bootloader
            ;;

        full)
            installer_run
            ;;

        *)
            installer_log_error \
                "Unknown installer stage: ${stage}"

            INSTALLER_LAST_RC=1

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
