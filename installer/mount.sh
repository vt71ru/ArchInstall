#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  mount.sh
#
#  Монтирование подготовленной файловой системы.
#
#  Ответственность:
#   • Подготовка /mnt
#   • Монтирование root
#   • Монтирование home
#   • Монтирование EFI
#   • Активация swap-раздела
#   • Подготовка swap-файла
#   • Проверка результата
#
#  Не выполняет:
#   • Разметку диска
#   • Форматирование
#   • Установку пакетов
#============================================================

[[ -n "${MOUNT_SH_LOADED:-}" ]] && return

readonly MOUNT_SH_LOADED=1

#------------------------------------------------------------
# Load configuration
#------------------------------------------------------------

mount_load_config()
{
    local root_part
    local home_part
    local efi_part
    local swap_part
    local boot_mode
    local create_home
    local swap_type

    root_part="$(
        config_get ROOT_PART
    )"

    home_part="$(
        config_get HOME_PART
    )"

    efi_part="$(
        config_get EFI_PART
    )"

    swap_part="$(
        config_get SWAP_PART
    )"

    boot_mode="$(
        config_get BOOT_MODE
    )"

    create_home="$(
        config_get CREATE_HOME
    )"

    swap_type="$(
        config_get SWAP_TYPE
    )"

    #--------------------------------------------------------
    # Validate boot mode
    #--------------------------------------------------------

    case "$boot_mode" in
        UEFI|BIOS)
            ;;
        *)
            dialog_error \
                "Invalid boot mode: ${boot_mode:-empty}"

            return 1
            ;;
    esac

    #--------------------------------------------------------
    # Validate root
    #--------------------------------------------------------

    if [[ -z "$root_part" ]]
    then
        dialog_error \
            "Root partition is not configured"

        return 1
    fi

    if [[ ! -b "$root_part" ]]
    then
        dialog_error \
            "Root partition does not exist: ${root_part}"

        return 1
    fi

    #--------------------------------------------------------
    # Validate home
    #--------------------------------------------------------

    if [[ "$create_home" == "1" ]]
    then
        if [[ -z "$home_part" ]]
        then
            dialog_error \
                "Home partition is not configured"

            return 1
        fi

        if [[ ! -b "$home_part" ]]
        then
            dialog_error \
                "Home partition does not exist: ${home_part}"

            return 1
        fi
    fi

    #--------------------------------------------------------
    # Validate EFI
    #--------------------------------------------------------

    if [[ "$boot_mode" == "UEFI" ]]
    then
        if [[ -z "$efi_part" ]]
        then
            dialog_error \
                "EFI partition is not configured"

            return 1
        fi

        if [[ ! -b "$efi_part" ]]
        then
            dialog_error \
                "EFI partition does not exist: ${efi_part}"

            return 1
        fi
    fi

    #--------------------------------------------------------
    # Validate swap partition
    #--------------------------------------------------------

    case "$swap_type" in
        none)
            ;;
        partition)
            if [[ -z "$swap_part" ]]
            then
                dialog_error \
                    "Swap partition is not configured"

                return 1
            fi

            if [[ ! -b "$swap_part" ]]
            then
                dialog_error \
                    "Swap partition does not exist: ${swap_part}"

                return 1
            fi
            ;;
        file)
            ;;
        *)
            dialog_error \
                "Invalid swap type: ${swap_type:-empty}"

            return 1
            ;;
    esac

    logger_info \
        "Root: ${root_part}"

    logger_info \
        "Home: ${home_part:-none}"

    logger_info \
        "EFI: ${efi_part:-none}"

    logger_info \
        "Swap: ${swap_type}"

    return 0
}

#------------------------------------------------------------
# Check mount dependencies
#------------------------------------------------------------

mount_check_dependencies()
{
    local required=(
        mount
        umount
        mountpoint
        findmnt
        mkdir
        grep
    )

    local cmd

    for cmd in "${required[@]}"
    do
        if ! command -v "$cmd" >/dev/null 2>&1
        then
            dialog_error \
                "Required program not found: ${cmd}"

            return 1
        fi
    done

    if [[ "$(config_get SWAP_TYPE)" == "partition" ]]
    then
        if ! command -v swapon >/dev/null 2>&1
        then
            dialog_error \
                "Required program not found: swapon"

            return 1
        fi
    fi

    return 0
}

#------------------------------------------------------------
# Prepare mount point
#------------------------------------------------------------

mount_prepare()
{
    logger_info \
        "Preparing /mnt"

    if [[ -L /mnt ]]
    then
        dialog_error \
            "/mnt is a symbolic link"

        return 1
    fi

    if [[ -e /mnt && ! -d /mnt ]]
    then
        dialog_error \
            "/mnt exists but is not a directory"

        return 1
    fi

    mkdir -p /mnt || {
        dialog_error \
            "Failed to create /mnt"

        return 1
    }

    if [[ ! -d /mnt ]]
    then
        dialog_error \
            "Failed to prepare /mnt"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Check whether target is already mounted
#------------------------------------------------------------

mount_is_target_mounted()
{
    local device="$1"
    local target="$2"

    if /usr/bin/mountpoint -q "$target"
    then
        if /usr/bin/findmnt \
            -rn \
            -S "$device" \
            -T "$target" \
            >/dev/null 2>&1
        then
            return 0
        fi

        return 1
    fi

    return 1
}

#------------------------------------------------------------
# Mount root
#------------------------------------------------------------

mount_root()
{
    local root_part

    root_part="$(
        config_get ROOT_PART
    )"

    if [[ -z "$root_part" ]]
    then
        dialog_error \
            "Root partition is empty"

        return 1
    fi

    if /usr/bin/mountpoint -q /mnt
    then
        if /usr/bin/findmnt \
            -rn \
            -S "$root_part" \
            -T /mnt \
            >/dev/null 2>&1
        then
            logger_info \
                "Root already mounted: ${root_part}"

            return 0
        fi

        dialog_error \
            "/mnt is already mounted by another device"

        return 1
    fi

    logger_info \
        "Mounting root: ${root_part}"

    /usr/bin/mount \
        "$root_part" \
        /mnt \
        || {
            logger_error \
                "Failed mounting root: ${root_part}"

            return 1
        }

    return 0
}

#------------------------------------------------------------
# Mount home
#------------------------------------------------------------

mount_home()
{
    local create_home
    local home_part

    create_home="$(
        config_get CREATE_HOME
    )"

    if [[ "$create_home" != "1" ]]
    then
        logger_info \
            "Home partition disabled"

        return 0
    fi

    home_part="$(
        config_get HOME_PART
    )"

    if [[ -z "$home_part" ]]
    then
        dialog_error \
            "Home partition is empty"

        return 1
    fi

    mkdir -p /mnt/home || {
        logger_error \
            "Failed to create /mnt/home"

        return 1
    }

    if /usr/bin/mountpoint -q /mnt/home
    then
        if /usr/bin/findmnt \
            -rn \
            -S "$home_part" \
            -T /mnt/home \
            >/dev/null 2>&1
        then
            logger_info \
                "Home already mounted: ${home_part}"

            return 0
        fi

        dialog_error \
            "/mnt/home is already mounted by another device"

        return 1
    fi

    logger_info \
        "Mounting home: ${home_part}"

    /usr/bin/mount \
        "$home_part" \
        /mnt/home \
        || {
            logger_error \
                "Failed mounting home: ${home_part}"

            return 1
        }

    return 0
}

#------------------------------------------------------------
# Mount EFI
#------------------------------------------------------------

mount_efi()
{
    local boot_mode
    local efi_part

    boot_mode="$(
        config_get BOOT_MODE
    )"

    if [[ "$boot_mode" != "UEFI" ]]
    then
        logger_info \
            "BIOS mode: EFI mount skipped"

        return 0
    fi

    efi_part="$(
        config_get EFI_PART
    )"

    if [[ -z "$efi_part" ]]
    then
        dialog_error \
            "EFI partition is empty"

        return 1
    fi

    mkdir -p /mnt/boot/efi || {
        logger_error \
            "Failed to create /mnt/boot/efi"

        return 1
    }

    if /usr/bin/mountpoint -q /mnt/boot/efi
    then
        if /usr/bin/findmnt \
            -rn \
            -S "$efi_part" \
            -T /mnt/boot/efi \
            >/dev/null 2>&1
        then
            logger_info \
                "EFI already mounted: ${efi_part}"

            return 0
        fi

        dialog_error \
            "/mnt/boot/efi is already mounted by another device"

        return 1
    fi

    logger_info \
        "Mounting EFI: ${efi_part}"

    /usr/bin/mount \
        "$efi_part" \
        /mnt/boot/efi \
        || {
            logger_error \
                "Failed mounting EFI: ${efi_part}"

            return 1
        }

    return 0
}

#------------------------------------------------------------
# Enable swap partition
#------------------------------------------------------------

mount_enable_swap()
{
    local swap_type
    local swap_part

    swap_type="$(
        config_get SWAP_TYPE
    )"

    if [[ "$swap_type" != "partition" ]]
    then
        logger_info \
            "Swap partition activation skipped"

        return 0
    fi

    swap_part="$(
        config_get SWAP_PART
    )"

    if [[ -z "$swap_part" ]]
    then
        dialog_error \
            "Swap partition is empty"

        return 1
    fi

    if /usr/bin/swapon \
        --show=NAME \
        --noheadings \
        2>/dev/null |
        /usr/bin/grep -Fxq "$swap_part"
    then
        logger_info \
            "Swap already enabled: ${swap_part}"

        return 0
    fi

    logger_info \
        "Enabling swap: ${swap_part}"

    /usr/bin/swapon \
        "$swap_part" \
        || {
            logger_error \
                "Failed enabling swap: ${swap_part}"

            return 1
        }

    return 0
}

#------------------------------------------------------------
# Prepare swap file configuration
#------------------------------------------------------------

mount_prepare_swap_file()
{
    local swap_type

    swap_type="$(
        config_get SWAP_TYPE
    )"

    if [[ "$swap_type" != "file" ]]
    then
        return 0
    fi

    config_set \
        SWAP_FILE \
        "/swapfile" || {
            logger_error \
                "Failed to save swap file configuration"

            return 1
        }

    logger_info \
        "Swap file configured: /swapfile"

    return 0
}

#------------------------------------------------------------
# Check root mount
#------------------------------------------------------------

mount_check_root()
{
    if ! /usr/bin/mountpoint -q /mnt
    then
        dialog_error \
            "/mnt is not mounted"

        return 1
    fi

    logger_info \
        "Root mount check passed"

    return 0
}

#------------------------------------------------------------
# Check home mount
#------------------------------------------------------------

mount_check_home()
{
    if [[ "$(config_get CREATE_HOME)" != "1" ]]
    then
        return 0
    fi

    if ! /usr/bin/mountpoint -q /mnt/home
    then
        dialog_error \
            "/mnt/home is not mounted"

        return 1
    fi

    logger_info \
        "Home mount check passed"

    return 0
}

#------------------------------------------------------------
# Check EFI mount
#------------------------------------------------------------

mount_check_efi()
{
    if [[ "$(config_get BOOT_MODE)" != "UEFI" ]]
    then
        return 0
    fi

    if ! /usr/bin/mountpoint -q /mnt/boot/efi
    then
        dialog_error \
            "/mnt/boot/efi is not mounted"

        return 1
    fi

    logger_info \
        "EFI mount check passed"

    return 0
}

#------------------------------------------------------------
# Check swap
#------------------------------------------------------------

mount_check_swap()
{
    local swap_type
    local swap_part

    swap_type="$(
        config_get SWAP_TYPE
    )"

    if [[ "$swap_type" != "partition" ]]
    then
        return 0
    fi

    swap_part="$(
        config_get SWAP_PART
    )"

    if ! /usr/bin/swapon \
        --show=NAME \
        --noheadings \
        2>/dev/null |
        /usr/bin/grep -Fxq "$swap_part"
    then
        dialog_error \
            "Swap partition is not active: ${swap_part}"

        return 1
    fi

    logger_info \
        "Swap check passed"

    return 0
}

#------------------------------------------------------------
# Check complete mount state
#------------------------------------------------------------

mount_check()
{
    mount_check_root || \
        return 1

    mount_check_home || \
        return 1

    mount_check_efi || \
        return 1

    mount_check_swap || \
        return 1

    logger_info \
        "Mount validation passed"

    return 0
}

#------------------------------------------------------------
# Save state
#------------------------------------------------------------

mount_save()
{
    config_save || {
        logger_error \
            "Failed to save mount state"

        return 1
    }

    logger_info \
        "Mount state saved"

    return 0
}

#------------------------------------------------------------
# Main installer stage
#
# IMPORTANT:
# The installer controller must call:
#
#     mount_filesystems
#
# Do NOT rename this function back to mount().
#------------------------------------------------------------

mount_filesystems()
{
    logger_info \
        "Mount process started"

    mount_load_config || \
        return 1

    mount_check_dependencies || \
        return 1

    mount_prepare || \
        return 1

    mount_root || \
        return 1

    mount_home || \
        return 1

    mount_efi || \
        return 1

    mount_enable_swap || \
        return 1

    mount_prepare_swap_file || \
        return 1

    mount_check || \
        return 1

    mount_save || \
        return 1

    dialog_message \
        "Mount" \
        "Filesystem mounted successfully"

    logger_info \
        "Mount process finished"

    return 0
}

#============================================================
# END
#============================================================

