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
# Paths
#============================================================

: "${INSTALLER_ROOT:?INSTALLER_ROOT is not set}"

INSTALLER_DIR="$INSTALLER_ROOT/installer"

readonly INSTALLER_DIR

#============================================================
# State
#============================================================

INSTALLER_STAGE=""
INSTALLER_LAST_RC=0

#============================================================
# Load module
#============================================================

installer_load_module()
{
    local module="${1:-}"
    local file

    if [[ -z "$module" ]]
    then
        logger_error \
            "Installer: module name is empty"

        return 1
    fi

    file="$INSTALLER_DIR/$module"

    if [[ ! -f "$file" ]]
    then
        logger_error \
            "Installer: module not found: $file"

        return 1
    fi

    logger_debug \
        "Installer: loading module: $module"

    # shellcheck disable=SC1090
    if ! source "$file"
    then
        logger_error \
            "Installer: failed to load module: $file"

        return 1
    fi

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
        logger_error \
            "Installer: function name is empty"

        return 1
    fi

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        logger_error \
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
    local stage="$1"
    local module="$2"
    local function_name="$3"

    INSTALLER_STAGE="$stage"

    logger_info \
        "Starting stage: $stage"

    #--------------------------------------------------------
    # Load module
    #--------------------------------------------------------

    if ! installer_load_module "$module"
    then
        logger_error \
            "Stage '$stage': failed to load $module"

        INSTALLER_LAST_RC=1

        return 1
    fi

    #--------------------------------------------------------
    # Check entry point
    #--------------------------------------------------------

    if ! installer_require_function "$function_name"
    then
        logger_error \
            "Stage '$stage': entry point missing: $function_name"

        INSTALLER_LAST_RC=1

        return 1
    fi

    #--------------------------------------------------------
    # Execute stage
    #--------------------------------------------------------

    "$function_name"
    INSTALLER_LAST_RC=$?

    if (( INSTALLER_LAST_RC != 0 ))
    then
        logger_error \
            "Stage failed: $stage (rc=$INSTALLER_LAST_RC)"

        return "$INSTALLER_LAST_RC"
    fi

    logger_info \
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
    logger_info \
        "Starting full Arch Linux installation"

    #--------------------------------------------------------
    # 1. Partition
    #--------------------------------------------------------

    if ! installer_partition
    then
        logger_error \
            "Installation stopped at partition stage"

        return 1
    fi

    #--------------------------------------------------------
    # 2. Filesystem
    #--------------------------------------------------------

    if ! installer_filesystem
    then
        logger_error \
            "Installation stopped at filesystem stage"

        return 1
    fi

    #--------------------------------------------------------
    # 3. Mount
    #--------------------------------------------------------

    if ! installer_mount
    then
        logger_error \
            "Installation stopped at mount stage"

        return 1
    fi

    #--------------------------------------------------------
    # 4. Packages
    #--------------------------------------------------------

    if ! installer_packages
    then
        logger_error \
            "Installation stopped at packages stage"

        return 1
    fi

    #--------------------------------------------------------
    # 5. Bootloader
    #--------------------------------------------------------

    if ! installer_bootloader
    then
        logger_error \
            "Installation stopped at bootloader stage"

        return 1
    fi

    INSTALLER_STAGE="complete"
    INSTALLER_LAST_RC=0

    logger_info \
        "Full Arch Linux installation completed"

    return 0
}
