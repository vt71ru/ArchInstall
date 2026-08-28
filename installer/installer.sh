#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# installer.sh
#
# Центральный controller установки.
#
# Ответственность:
#   • загрузка installer-модулей
#   • проверка entry point
#   • выполнение отдельных этапов
#   • выполнение полной установки
#   • контроль порядка этапов
#   • возврат кодов ошибок
#
# Не содержит:
#   • TTY logic
#   • stty
#   • keyboard handling
#   • drawing
#   • partition implementation
#   • filesystem implementation
#   • mount implementation
#   • package implementation
#   • bootloader implementation
#
#============================================================

if [[ -n "${INSTALLER_SH_LOADED:-}" ]]
then
    return 0
fi

readonly INSTALLER_SH_LOADED=1

#============================================================
# Requirements
#============================================================

: "${INSTALLER_ROOT:?INSTALLER_ROOT is not set}"

#============================================================
# Paths
#============================================================

INSTALLER_DIR="$INSTALLER_ROOT/installer"

readonly INSTALLER_DIR

#============================================================
# State
#============================================================

INSTALLER_STAGE="idle"
INSTALLER_LAST_RC=0

#============================================================
# Internal logging
#============================================================

installer_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@"
    else
        printf '[INSTALLER] [ERROR] %s\n' "$*" >&2
    fi
}

installer_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@"
    else
        printf '[INSTALLER] [WARN] %s\n' "$*" >&2
    fi
}

installer_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@"
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
# Load module
#============================================================

installer_load_module()
{
    local module="${1:-}"
    local file=""

    #--------------------------------------------------------
    # Validate module name
    #--------------------------------------------------------

    if [[ -z "$module" ]]
    then
        installer_log_error \
            "Installer: module name is empty"

        return 1
    fi

    #--------------------------------------------------------
    # Prevent path traversal
    #--------------------------------------------------------

    case "$module"
    in
        /*|../*|*/../*|..)
            installer_log_error \
                "Installer: invalid module path: $module"

            return 1
            ;;
    esac

    #--------------------------------------------------------
    # Build path
    #--------------------------------------------------------

    file="$INSTALLER_DIR/$module"

    #--------------------------------------------------------
    # Check file
    #--------------------------------------------------------

    if [[ ! -f "$file" ]]
    then
        installer_log_error \
            "Installer: module not found: $file"

        return 1
    fi

    #--------------------------------------------------------
    # Load module
    #--------------------------------------------------------

    installer_log_debug \
        "Installer: loading module: $module"

    # shellcheck disable=SC1090
    if ! source "$file"
    then
        installer_log_error \
            "Installer: failed to load module: $file"

        return 1
    fi

    installer_log_debug \
        "Installer: module loaded: $module"

    return 0
}

#============================================================
# Check function
#============================================================

installer_require_function()
{
    local function_name="${1:-}"

    if [[ -z "$function_name" ]]
    then
        installer_log_error \
            "Installer: function name is empty"

        return 1
    fi

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        installer_log_error \
            "Installer: required function not found: $function_name"

        return 1
    fi

    return 0
}

#============================================================
# Run stage
#============================================================

installer_run_stage()
{
    local stage="${1:-}"
    local module="${2:-}"
    local function_name="${3:-}"
    local rc=0

    #--------------------------------------------------------
    # Validate arguments
    #--------------------------------------------------------

    if [[ -z "$stage" ]]
    then
        installer_log_error \
            "Installer: stage name is empty"

        INSTALLER_STAGE="error"
        INSTALLER_LAST_RC=1

        return 1
    fi

    if [[ -z "$module" ]]
    then
        installer_log_error \
            "Installer: module is empty for stage: $stage"

        INSTALLER_STAGE="$stage"
        INSTALLER_LAST_RC=1

        return 1
    fi

    if [[ -z "$function_name" ]]
    then
        installer_log_error \
            "Installer: entry point is empty for stage: $stage"

        INSTALLER_STAGE="$stage"
        INSTALLER_LAST_RC=1

        return 1
    fi

    #--------------------------------------------------------
    # Set current stage
    #--------------------------------------------------------

    INSTALLER_STAGE="$stage"
    INSTALLER_LAST_RC=0

    installer_log_info \
        "Starting stage: $stage"

    #--------------------------------------------------------
    # Load module
    #--------------------------------------------------------

    if ! installer_load_module "$module"
    then
        installer_log_error \
            "Stage '$stage': failed to load module: $module"

        INSTALLER_LAST_RC=1

        return 1
    fi

    #--------------------------------------------------------
    # Check entry point
    #--------------------------------------------------------

    if ! installer_require_function "$function_name"
    then
        installer_log_error \
            "Stage '$stage': entry point missing: $function_name"

        INSTALLER_LAST_RC=1

        return 1
    fi

    #--------------------------------------------------------
    # Execute stage
    #
    # IMPORTANT:
    # The function is called inside an if-condition so that
    # set -e does not terminate the entire installer before
    # we can process the return code.
    #--------------------------------------------------------

    installer_log_debug \
        "Stage '$stage': executing $function_name"

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
            "Stage failed: $stage (rc=$rc)"

        return "$rc"
    fi

    #--------------------------------------------------------
    # Stage completed
    #--------------------------------------------------------

    installer_log_info \
        "Stage completed: $stage"

    return 0
}

#============================================================
# Partition
#============================================================

installer_partition()
{
    installer_run_stage \
        "Partition" \
        "partition.sh" \
        "partition"
}

#============================================================
# Filesystem
#============================================================

installer_filesystem()
{
    installer_run_stage \
        "Filesystem" \
        "filesystem.sh" \
        "filesystem"
}

#============================================================
# Mount
#============================================================

installer_mount()
{
    installer_run_stage \
        "Mount" \
        "mount.sh" \
        "mount"
}

#============================================================
# Packages
#============================================================

installer_packages()
{
    installer_run_stage \
        "Packages" \
        "packages.sh" \
        "packages_install"
}

#============================================================
# Bootloader
#============================================================

installer_bootloader()
{
    installer_run_stage \
        "Bootloader" \
        "bootloader.sh" \
        "bootloader"
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

    if ! installer_partition
    then
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

    if ! installer_filesystem
    then
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

    if ! installer_mount
    then
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

    if ! installer_packages
    then
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

    if ! installer_bootloader
    then
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

    INSTALLER_STAGE="complete"
    INSTALLER_LAST_RC=0

    installer_log_info \
        "Full Arch Linux installation completed"

    return 0
}

#============================================================
# Status
#============================================================

installer_get_stage()
{
    printf '%s' "$INSTALLER_STAGE"
}

installer_get_last_rc()
{
    printf '%s' "$INSTALLER_LAST_RC"
}

#============================================================
# Reset state
#============================================================

installer_reset_state()
{
    INSTALLER_STAGE="idle"
    INSTALLER_LAST_RC=0

    return 0
}

#============================================================
# End
#============================================================
