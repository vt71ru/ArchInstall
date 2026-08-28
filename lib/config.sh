#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# config.sh
#
# Центральное состояние и конфигурация установщика.
#
# Ответственность:
#   • Значения конфигурации
#   • Значения по умолчанию
#   • Boot mode
#   • Target disk
#   • Partition information
#   • Filesystem configuration
#   • System configuration
#   • User configuration
#   • Validation
#
# Не содержит:
#   • TUI
#   • partition commands
#   • mkfs
#   • mount
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
# Configuration state
#============================================================

CONFIG_INITIALIZED=0
CONFIG_VALID=0

#============================================================
# Target disk
#============================================================

TARGET_DISK=""
TARGET_DISK_MODEL=""
TARGET_DISK_SERIAL=""
TARGET_DISK_TRAN=""
TARGET_DISK_SIZE=""
TARGET_DISK_SECTOR_SIZE=""

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
SWAP_FS="swap"

SWAP_ENABLED=0

#============================================================
# Mount
#============================================================

TARGET_MOUNT="/mnt"

ROOT_MOUNT="/mnt"
BOOT_MOUNT="/mnt/boot"

#============================================================
# Boot mode
#============================================================

BOOT_MODE=""

BOOT_UEFI=0
BOOT_BIOS=0

#============================================================
# EFI
#============================================================

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
# Installation options
#============================================================

INSTALL_NETWORK=1
INSTALL_EDITOR=1
INSTALL_BOOTLOADER=1

AUTO_REBOOT=0

CONFIRM_DESTRUCTIVE=1

#============================================================
# Package lists
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
# Defaults
#============================================================

config_defaults()
{
    TARGET_MOUNT="/mnt"

    ROOT_MOUNT="$TARGET_MOUNT"
    BOOT_MOUNT="$TARGET_MOUNT/boot"

    BOOT_FS="fat32"
    ROOT_FS="ext4"
    SWAP_FS="swap"

    SWAP_ENABLED=0

    HOSTNAME="archlinux"

    TIMEZONE="UTC"

    LOCALE="en_US.UTF-8"

    KEYMAP="us"

    USER_SHELL="/bin/bash"

    INSTALL_NETWORK=1
    INSTALL_EDITOR=1
    INSTALL_BOOTLOADER=1

    AUTO_REBOOT=0
    CONFIRM_DESTRUCTIVE=1

    return 0
}

#============================================================
# Detect boot mode
#============================================================

config_detect_boot_mode()
{
    BOOT_MODE=""
    BOOT_UEFI=0
    BOOT_BIOS=0

    if [[ -d /sys/firmware/efi ]]
    then
        BOOT_MODE="UEFI"
        BOOT_UEFI=1
    else
        BOOT_MODE="BIOS"
        BOOT_BIOS=1
    fi

    logger_info \
        "Boot mode: $BOOT_MODE"

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
            "Config: $name must be 0 or 1"

        return 1
    fi

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
    if [[ -z "$LOCALE" ]]
    then
        logger_error \
            "Config: locale is empty"

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
        ext4|btrfs|xfs|f2fs)
            ;;

        *)
            logger_error \
                "Config: unsupported root filesystem: $ROOT_FS"

            return 1
            ;;
    esac

    case "$BOOT_FS"
    in
        fat32|vfat)
            ;;

        *)
            logger_error \
                "Config: unsupported boot filesystem: $BOOT_FS"

            return 1
            ;;
    esac

    return 0
}

#============================================================
# Validate mount point
#============================================================

config_validate_mount()
{
    if [[ -z "$TARGET_MOUNT" ]]
    then
        logger_error \
            "Config: TARGET_MOUNT is empty"

        return 1
    fi

    if [[ "$TARGET_MOUNT" != /* ]]
    then
        logger_error \
            "Config: TARGET_MOUNT must be absolute"

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
# Validate static configuration
#============================================================

config_validate()
{
    CONFIG_VALID=0

    logger_debug \
        "Validating configuration"

    #
    # Boolean options.
    #
    config_validate_bool INSTALL_NETWORK || return 1
    config_validate_bool INSTALL_EDITOR || return 1
    config_validate_bool INSTALL_BOOTLOADER || return 1
    config_validate_bool AUTO_REBOOT || return 1
    config_validate_bool CONFIRM_DESTRUCTIVE || return 1
    config_validate_bool SWAP_ENABLED || return 1

    #
    # Filesystem.
    #
    config_validate_filesystem || return 1

    #
    # Mount.
    #
    config_validate_mount || return 1

    #
    # Hostname.
    #
    config_validate_hostname || return 1

    #
    # Locale.
    #
    config_validate_locale || return 1

    #
    # Shell.
    #
    config_validate_shell || return 1

    CONFIG_VALID=1

    logger_debug \
        "Configuration valid"

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

    logger_debug \
        "Initializing configuration"

    config_defaults

    config_detect_boot_mode

    if ! config_validate
    then
        logger_error \
            "Configuration initialization failed"

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
            "Config: disk is empty"

        return 1
    fi

    if [[ ! -b "$disk" ]]
    then
        logger_error \
            "Config: not a block device: $disk"

        return 1
    fi

    TARGET_DISK="$disk"

    return 0
}

#============================================================
# Set disk information
#============================================================

config_set_disk_info()
{
    local model="${1-}"
    local serial="${2-}"
    local tran="${3-}"
    local size="${4-}"
    local sector_size="${5-}"

    TARGET_DISK_MODEL="$model"
    TARGET_DISK_SERIAL="$serial"
    TARGET_DISK_TRAN="$tran"
    TARGET_DISK_SIZE="$size"
    TARGET_DISK_SECTOR_SIZE="$sector_size"

    return 0
}

#============================================================
# Set partitions
#============================================================

config_set_partitions()
{
    local boot="${1:-}"
    local root="${2:-}"
    local swap="${3-}"

    if [[ -z "$boot" ]]
    then
        logger_error \
            "Config: boot partition is empty"

        return 1
    fi

    if [[ -z "$root" ]]
    then
        logger_error \
            "Config: root partition is empty"

        return 1
    fi

    BOOT_PARTITION="$boot"
    ROOT_PARTITION="$root"
    SWAP_PARTITION="$swap"

    return 0
}

#============================================================
# Set partition numbers
#============================================================

config_set_partition_numbers()
{
    BOOT_PARTITION_NUMBER="${1-}"
    ROOT_PARTITION_NUMBER="${2-}"
    SWAP_PARTITION_NUMBER="${3-}"

    return 0
}

#============================================================
# Set filesystem
#============================================================

config_set_root_fs()
{
    local filesystem="${1:-}"

    case "$filesystem"
    in
        ext4|btrfs|xfs|f2fs)
            ROOT_FS="$filesystem"
            ;;

        *)
            logger_error \
                "Config: unsupported filesystem: $filesystem"

            return 1
            ;;
    esac

    return 0
}

#============================================================
# Set hostname
#============================================================

config_set_hostname()
{
    local hostname="${1:-}"

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
        logger_error \
            "Config: timezone is empty"

        return 1
    fi

    TIMEZONE="$timezone"

    return 0
}

#============================================================
# Set locale
#============================================================

config_set_locale()
{
    local locale="${1:-}"

    if [[ -z "$locale" ]]
    then
        logger_error \
            "Config: locale is empty"

        return 1
    fi

    LOCALE="$locale"

    return 0
}

#============================================================
# Set keymap
#============================================================

config_set_keymap()
{
    local keymap="${1:-}"

    if [[ -z "$keymap" ]]
    then
        logger_error \
            "Config: keymap is empty"

        return 1
    fi

    KEYMAP="$keymap"

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
# Check target disk
#============================================================

config_require_disk()
{
    if [[ -z "$TARGET_DISK" ]]
    then
        logger_error \
            "Config: target disk has not been selected"

        return 1
    fi

    if [[ ! -b "$TARGET_DISK" ]]
    then
        logger_error \
            "Config: target disk is not a block device: $TARGET_DISK"

        return 1
    fi

    return 0
}

#============================================================
# Check partitions
#============================================================

config_require_partitions()
{
    if [[ -z "$ROOT_PARTITION" ]]
    then
        logger_error \
            "Config: root partition is not configured"

        return 1
    fi

    if [[ "$BOOT_MODE" == "UEFI" &&
          -z "$BOOT_PARTITION" ]]
    then
        logger_error \
            "Config: EFI partition is not configured"

        return 1
    fi

    return 0
}

#============================================================
# Configuration summary
#============================================================

config_summary()
{
    printf '%s\n' \
        "========================================" \
        " Arch Installer configuration" \
        "========================================" \
        "Target disk : ${TARGET_DISK:-<not selected>}" \
        "Model       : ${TARGET_DISK_MODEL:-<unknown>}" \
        "Serial      : ${TARGET_DISK_SERIAL:-<unknown>}" \
        "Transport   : ${TARGET_DISK_TRAN:-<unknown>}" \
        "Size        : ${TARGET_DISK_SIZE:-<unknown>}" \
        "Boot mode   : ${BOOT_MODE:-<unknown>}" \
        "Boot part.  : ${BOOT_PARTITION:-<not configured>}" \
        "Root part.  : ${ROOT_PARTITION:-<not configured>}" \
        "Swap part.  : ${SWAP_PARTITION:-<disabled>}" \
        "Boot FS     : ${BOOT_FS}" \
        "Root FS     : ${ROOT_FS}" \
        "Mount       : ${TARGET_MOUNT}" \
        "Hostname    : ${HOSTNAME}" \
        "Timezone    : ${TIMEZONE}" \
        "Locale      : ${LOCALE}" \
        "Keymap      : ${KEYMAP}" \
        "Username    : ${USERNAME:-<not configured>}" \
        "========================================"
}

#============================================================
# Reset runtime installation state
#============================================================

config_reset_install_state()
{
    TARGET_DISK=""

    TARGET_DISK_MODEL=""
    TARGET_DISK_SERIAL=""
    TARGET_DISK_TRAN=""
    TARGET_DISK_SIZE=""
    TARGET_DISK_SECTOR_SIZE=""

    BOOT_PARTITION=""
    ROOT_PARTITION=""
    SWAP_PARTITION=""

    BOOT_PARTITION_NUMBER=""
    ROOT_PARTITION_NUMBER=""
    SWAP_PARTITION_NUMBER=""

    return 0
}

#============================================================
# End
#============================================================
