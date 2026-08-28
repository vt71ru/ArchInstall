#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# config.sh
#
# Центральная конфигурация Arch Installer.
#
# Ответственность:
#   • Хранение настроек установки
#   • Значения по умолчанию
#   • Валидация конфигурации
#   • Вычисляемые параметры
#   • Экспорт конфигурации для installer-модулей
#
# Не содержит:
#   • TUI
#   • partition logic
#   • filesystem commands
#   • mount commands
#   • pacstrap
#   • bootloader installation
#
#============================================================

if [[ -n "${CONFIG_SH_LOADED:-}" ]]
then
    return 0
fi

readonly CONFIG_SH_LOADED=1

#============================================================
# Installation target
#============================================================

TARGET_DISK=""
TARGET_DISK_MODEL=""
TARGET_DISK_SERIAL=""
TARGET_DISK_TRAN=""
TARGET_DISK_SIZE=""

#============================================================
# Partitions
#============================================================

BOOT_PARTITION=""
ROOT_PARTITION=""
SWAP_PARTITION=""

BOOT_PARTITION_NUMBER=""
ROOT_PARTITION_NUMBER=""
SWAP_PARTITION_NUMBER=""

#============================================================
# Filesystems
#============================================================

BOOT_FS="fat32"
ROOT_FS="ext4"
SWAP_ENABLED=0

#============================================================
# Mount
#============================================================

TARGET_MOUNT="/mnt"

BOOT_MOUNT=""
ROOT_MOUNT="$TARGET_MOUNT"

#============================================================
# Boot mode
#============================================================

BOOT_MODE=""

BOOT_UEFI=0
BOOT_BIOS=0

#============================================================
# UEFI
#============================================================

EFI_MOUNT="/mnt/boot"
EFI_SIZE_MIB=512

#============================================================
# System
#============================================================

HOSTNAME="archlinux"

TIMEZONE="UTC"

LOCALE="en_US.UTF-8"
KEYMAP="us"

#============================================================
# User
#============================================================

USERNAME=""
USER_SHELL="/bin/bash"

#============================================================
# Packages
#============================================================

BASE_PACKAGES=(
    base
    linux
    linux-firmware
)

NETWORK_PACKAGES=(
    networkmanager
)

EDITOR_PACKAGES=(
    nano
)

BOOT_PACKAGES=(
    grub
)

UEFI_PACKAGES=(
    efibootmgr
)

#============================================================
# Package selection
#============================================================

INSTALL_NETWORK=1
INSTALL_EDITOR=1
INSTALL_BOOTLOADER=1

#============================================================
# Installer behaviour
#============================================================

AUTO_REBOOT=0
CONFIRM_DESTRUCTIVE=1

#============================================================
# Runtime state
#============================================================

CONFIG_INITIALIZED=0
CONFIG_VALID=0

#============================================================
# Defaults
#============================================================

config_defaults()
{
    #
    # Target.
    #
    TARGET_DISK="${TARGET_DISK:-}"

    #
    # Mount.
    #
    TARGET_MOUNT="${TARGET_MOUNT:-/mnt}"

    #
    # Filesystems.
    #
    BOOT_FS="${BOOT_FS:-fat32}"
    ROOT_FS="${ROOT_FS:-ext4}"

    #
    # System.
    #
    HOSTNAME="${HOSTNAME:-archlinux}"
    TIMEZONE="${TIMEZONE:-UTC}"
    LOCALE="${LOCALE:-en_US.UTF-8}"
    KEYMAP="${KEYMAP:-us}"

    #
    # User.
    #
    USER_SHELL="${USER_SHELL:-/bin/bash}"

    return 0
}

#============================================================
# Validate boolean
#============================================================

config_validate_bool()
{
    local name="$1"
    local value="${!name}"

    if [[ "$value" != 0 && "$value" != 1 ]]
    then
        logger_error \
            "Config: $name must be 0 or 1, got '$value'"

        return 1
    fi

    return 0
}

#============================================================
# Validate non-empty
#============================================================

config_validate_required()
{
    local name="$1"
    local value="${!name}"

    if [[ -z "$value" ]]
    then
        logger_error \
            "Config: required variable '$name' is empty"

        return 1
    fi

    return 0
}

#============================================================
# Validate disk
#============================================================

config_validate_disk()
{
    if [[ -z "$TARGET_DISK" ]]
    then
        logger_error \
            "Config: TARGET_DISK is not configured"

        return 1
    fi

    if [[ ! -b "$TARGET_DISK" ]]
    then
        logger_error \
            "Config: TARGET_DISK is not a block device: $TARGET_DISK"

        return 1
    fi

    return 0
}

#============================================================
# Validate filesystem
#============================================================

config_validate_filesystem()
{
    case "$ROOT_FS"
    in
        ext4)
            ;;

        btrfs)
            ;;

        xfs)
            ;;

        f2fs)
            ;;

        *)
            logger_error \
                "Config: unsupported ROOT_FS: $ROOT_FS"

            return 1
            ;;
    esac

    case "$BOOT_FS"
    in
        fat32|vfat)
            ;;

        *)
            logger_error \
                "Config: unsupported BOOT_FS: $BOOT_FS"

            return 1
            ;;
    esac

    return 0
}

#============================================================
# Validate boot mode
#============================================================

config_detect_boot_mode()
{
    if [[ -d /sys/firmware/efi ]]
    then
        BOOT_MODE="UEFI"
        BOOT_UEFI=1
        BOOT_BIOS=0
    else
        BOOT_MODE="BIOS"
        BOOT_UEFI=0
        BOOT_BIOS=1
    fi

    logger_info \
        "Boot mode detected: $BOOT_MODE"

    return 0
}

#============================================================
# Validate hostname
#============================================================

config_validate_hostname()
{
    if [[ -z "$HOSTNAME" ]]
    then
        logger_error \
            "Config: hostname is empty"

        return 1
    fi

    if (( ${#HOSTNAME} > 253 ))
    then
        logger_error \
            "Config: hostname is too long"

        return 1
    fi

    if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]]
    then
        logger_error \
            "Config: invalid hostname: $HOSTNAME"

        return 1
    fi

    return 0
}

#============================================================
# Validate locale
#============================================================

config_validate_locale()
{
    if [[ ! "$LOCALE" =~ ^[A-Za-z_]+(\.[A-Za-z0-9_-]+)?$ ]]
    then
        logger_error \
            "Config: invalid locale: $LOCALE"

        return 1
    fi

    return 0
}

#============================================================
# Validate shell
#============================================================

config_validate_shell()
{
    if [[ "$USER_SHELL" != /* ]]
    then
        logger_error \
            "Config: USER_SHELL must be an absolute path"

        return 1
    fi

    return 0
}

#============================================================
# Full validation
#============================================================

config_validate()
{
    logger_debug \
        "Validating configuration"

    #
    # Boolean values.
    #
    config_validate_bool INSTALL_NETWORK || return 1
    config_validate_bool INSTALL_EDITOR || return 1
    config_validate_bool INSTALL_BOOTLOADER || return 1
    config_validate_bool AUTO_REBOOT || return 1
    config_validate_bool CONFIRM_DESTRUCTIVE || return 1
    config_validate_bool SWAP_ENABLED || return 1

    #
    # Basic values.
    #
    config_validate_required \
        TARGET_MOUNT || return 1

    config_validate_required \
        HOSTNAME || return 1

    config_validate_required \
        TIMEZONE || return 1

    config_validate_required \
        LOCALE || return 1

    config_validate_required \
        KEYMAP || return 1

    #
    # Specific validation.
    #
    config_validate_hostname || return 1
    config_validate_locale || return 1
    config_validate_shell || return 1
    config_validate_filesystem || return 1

    #
    # Disk may intentionally be empty before
    # the partition stage.
    #
    if [[ -n "$TARGET_DISK" ]]
    then
        config_validate_disk || return 1
    fi

    CONFIG_VALID=1

    logger_debug \
        "Configuration validation passed"

    return 0
}

#============================================================
# Initialization
#============================================================

config_init()
{
    if (( CONFIG_INITIALIZED ))
    then
        return 0
    fi

    config_defaults

    config_detect_boot_mode

    if ! config_validate
    then
        CONFIG_VALID=0

        return 1
    fi

    CONFIG_INITIALIZED=1

    logger_info \
        "Configuration initialized"

    return 0
}

#============================================================
# Set target disk
#============================================================

config_set_disk()
{
    local disk="${1:-}"

    if [[ -z "$disk" ]]
    then
        logger_error \
            "Config: disk argument is empty"

        return 1
    fi

    if [[ ! -b "$disk" ]]
    then
        logger_error \
            "Config: not a block device: $disk"

        return 1
    fi

    TARGET_DISK="$disk"

    logger_info \
        "Target disk set: $TARGET_DISK"

    return 0
}

#============================================================
# Set username
#============================================================

config_set_username()
{
    local username="${1:-}"

    if [[ -z "$username" ]]
    then
        logger_error \
            "Config: username is empty"

        return 1
    fi

    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]
    then
        logger_error \
            "Config: invalid username: $username"

        return 1
    fi

    USERNAME="$username"

    return 0
}

#============================================================
# Set hostname
#============================================================

config_set_hostname()
{
    local hostname="${1:-}"

    if [[ -z "$hostname" ]]
    then
        return 1
    fi

    HOSTNAME="$hostname"

    config_validate_hostname
}

#============================================================
# Set timezone
#============================================================

config_set_timezone()
{
    local timezone="${1:-}"

    if [[ -z "$timezone" ]]
    then
        return 1
    fi

    TIMEZONE="$timezone"

    return 0
}

#============================================================
# Configuration summary
#============================================================

config_summary()
{
    printf '%s\n' \
        "Target disk : ${TARGET_DISK:-<not selected>}" \
        "Boot mode   : ${BOOT_MODE:-<unknown>}" \
        "Root FS     : ${ROOT_FS}" \
        "Boot FS     : ${BOOT_FS}" \
        "Mount point : ${TARGET_MOUNT}" \
        "Hostname    : ${HOSTNAME}" \
        "Timezone    : ${TIMEZONE}" \
        "Locale      : ${LOCALE}" \
        "Keymap      : ${KEYMAP}" \
        "Username    : ${USERNAME:-<not configured>}"
}

#============================================================
# End
#============================================================
