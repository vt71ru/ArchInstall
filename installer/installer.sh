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
#   • проверка entry point installer-модулей
#   • выполнение отдельных этапов
#   • выполнение полной установки
#   • контроль порядка этапов
#   • возврат кодов ошибок
#   • диагностика отказавшего этапа
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

    return 0
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

    return 0
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
        "Installer module available: ${module}"

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

    installer_log_debug \
        "Entry point available: ${function_name}"

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

        return 1
    fi

    if [[ -z "$function_name" ]]
    then
        installer_log_error \
            "Stage '${stage}': function name is empty"

        INSTALLER_STAGE="$stage"
        INSTALLER_LAST_RC=1

        return 1
    fi

    INSTALLER_STAGE="$stage"
    INSTALLER_LAST_RC=0

    installer_log_info \
        "----------------------------------------"

    installer_log_info \
        "Starting stage: ${stage}"

    installer_log_info \
        "Entry point: ${function_name}"

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
    # Function is executed inside an if-condition.
    # This prevents set -e from terminating the installer
    # before the return code can be processed.
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
    # Failed
    #--------------------------------------------------------

    if (( rc != 0 ))
    then
        installer_log_error \
            "========================================"

        installer_log_error \
            "STAGE FAILED"

        installer_log_error \
            "Stage : ${stage}"

        installer_log_error \
            "Entry : ${function_name}"

        installer_log_error \
            "Return: ${rc}"

        installer_log_error \
            "========================================"

        return "$rc"
    fi

    #--------------------------------------------------------
    # Completed
    #--------------------------------------------------------

    installer_log_info \
        "Stage completed successfully: ${stage}"

    installer_log_info \
        "Return code: 0"

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
        "========================================"

    installer_log_info \
        "FULL INSTALLATION STARTED"

    installer_log_info \
        "========================================"

    INSTALLER_STAGE="starting"
    INSTALLER_LAST_RC=0

    #========================================================
    # STEP 1 — PARTITION
    #========================================================

    installer_log_info \
        "FULL INSTALL: STEP 1/5 — PARTITION"

    if installer_partition
    then
        installer_log_info \
            "FULL INSTALL: PARTITION OK"
    else
        rc=$?

        INSTALLER_STAGE="Partition"
        INSTALLER_LAST_RC="$rc"

        installer_log_error \
            "FULL INSTALLATION STOPPED"

        installer_log_error \
            "Failed stage: Partition"

        installer_log_error \
            "Return code: ${rc}"

        installer_print_failure \
            "Partition" \
            "$rc"

        return "$rc"
    fi

    #========================================================
    # STEP 2 — FILESYSTEM
    #========================================================

    installer_log_info \
        "FULL INSTALL: STEP 2/5 — FILESYSTEM"

    if installer_filesystem
    then
        installer_log_info \
            "FULL INSTALL: FILESYSTEM OK"
    else
        rc=$?

        INSTALLER_STAGE="Filesystem"
        INSTALLER_LAST_RC="$rc"

        installer_log_error \
            "FULL INSTALLATION STOPPED"

        installer_log_error \
            "Failed stage: Filesystem"

        installer_log_error \
            "Return code: ${rc}"

        installer_print_failure \
            "Filesystem" \
            "$rc"

        return "$rc"
    fi

    #========================================================
    # STEP 3 — MOUNT
    #========================================================

    installer_log_info \
        "FULL INSTALL: STEP 3/5 — MOUNT"

    if installer_mount
    then
        installer_log_info \
            "FULL INSTALL: MOUNT OK"
    else
        rc=$?

        INSTALLER_STAGE="Mount"
        INSTALLER_LAST_RC="$rc"

        installer_log_error \
            "FULL INSTALLATION STOPPED"

        installer_log_error \
            "Failed stage: Mount"

        installer_log_error \
            "Return code: ${rc}"

        installer_print_failure \
            "Mount" \
            "$rc"

        return "$rc"
    fi

    #========================================================
    # STEP 4 — PACKAGES
    #========================================================

    installer_log_info \
        "FULL INSTALL: STEP 4/5 — PACKAGES"

    if installer_packages
    then
        installer_log_info \
            "FULL INSTALL: PACKAGES OK"
    else
        rc=$?

        INSTALLER_STAGE="Packages"
        INSTALLER_LAST_RC="$rc"

        installer_log_error \
            "FULL INSTALLATION STOPPED"

        installer_log_error \
            "Failed stage: Packages"

        installer_log_error \
            "Return code: ${rc}"

        installer_print_failure \
            "Packages" \
            "$rc"

        return "$rc"
    fi

    #========================================================
    # STEP 5 — BOOTLOADER
    #========================================================

    installer_log_info \
        "FULL INSTALL: STEP 5/5 — BOOTLOADER"

    if installer_bootloader
    then
        installer_log_info \
            "FULL INSTALL: BOOTLOADER OK"
    else
        rc=$?

        INSTALLER_STAGE="Bootloader"
        INSTALLER_LAST_RC="$rc"

        installer_log_error \
            "FULL INSTALLATION STOPPED"

        installer_log_error \
            "Failed stage: Bootloader"

        installer_log_error \
            "Return code: ${rc}"

        installer_print_failure \
            "Bootloader" \
            "$rc"

        return "$rc"
    fi

    #========================================================
    # SUCCESS
    #========================================================

    INSTALLER_STAGE="completed"
    INSTALLER_LAST_RC=0

    installer_log_info \
        "========================================"

    installer_log_info \
        "FULL INSTALLATION COMPLETED"

    installer_log_info \
        "All installation stages completed successfully"

    installer_log_info \
        "========================================"

    return 0
}

#============================================================
# Failure display
#============================================================

installer_print_failure()
{
    local stage="${1:-unknown}"
    local rc="${2:-1}"

    printf '\n' >&2

    printf \
        '========================================\n' \
        >&2

    printf \
        ' ARCH INSTALLER — INSTALLATION FAILED\n' \
        >&2

    printf \
        '========================================\n' \
        >&2

    printf \
        'Stage : %s\n' \
        "$stage" \
        >&2

    printf \
        'Return: %s\n' \
        "$rc" \
        >&2

    printf \
        '========================================\n' \
        >&2

    printf '\n' >&2

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

        bootloader)
            installer_bootloader
            ;;

        full)
            installer_run
            ;;

        *)
            installer_log_error \
                "Unknown installer stage: ${stage:-empty}"

            INSTALLER_STAGE="unknown"
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
        "${INSTALLER_STAGE:-unknown}"

    return 0
}

#============================================================
# Get last return code
#============================================================

installer_get_last_rc()
{
    printf '%s\n' \
        "${INSTALLER_LAST_RC:-1}"

    return 0
}

#============================================================
# Reset controller
#============================================================

installer_reset()
{
    INSTALLER_STAGE="idle"
    INSTALLER_LAST_RC=0

    installer_log_debug \
        "Installer controller reset"

    return 0
}

#============================================================
# Controller status
#============================================================

installer_status()
{
    printf \
        'Stage : %s\n' \
        "${INSTALLER_STAGE:-unknown}"

    printf \
        'Return: %s\n' \
        "${INSTALLER_LAST_RC:-1}"

    return 0
}
