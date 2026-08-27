#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  filesystem.sh
#
#  Форматирование разделов.
#
#  Ответственность:
#   • Форматирование EFI
#   • Форматирование root
#   • Форматирование home
#   • Форматирование swap-раздела
#   • Проверка результата
#
#  Не выполняет:
#   • Разметку диска
#   • Создание разделов
#   • Монтирование
#   • Установку пакетов
#============================================================

[[ -n "${FILESYSTEM_SH_LOADED:-}" ]] && return

readonly FILESYSTEM_SH_LOADED=1

#------------------------------------------------------------
# Load configuration
#------------------------------------------------------------

filesystem_load_config()
{
    local filesystem
    local boot_mode
    local root_part
    local home_part
    local efi_part
    local swap_part
    local swap_type
    local create_home

    filesystem="$(config_get FILESYSTEM)"
    boot_mode="$(config_get BOOT_MODE)"
    root_part="$(config_get ROOT_PART)"
    home_part="$(config_get HOME_PART)"
    efi_part="$(config_get EFI_PART)"
    swap_part="$(config_get SWAP_PART)"
    swap_type="$(config_get SWAP_TYPE)"
    create_home="$(config_get CREATE_HOME)"

    case "$filesystem" in
        ext4|btrfs|xfs|f2fs)
            ;;
        *)
            dialog_error \
                "Unsupported filesystem: ${filesystem:-empty}"

            return 1
            ;;
    esac

    case "$boot_mode" in
        UEFI|BIOS)
            ;;
        *)
            dialog_error \
                "Invalid boot mode: ${boot_mode:-empty}"

            return 1
            ;;
    esac

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

    if [[ "$swap_type" == "partition" ]]
    then
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
    fi

    logger_info \
        "Filesystem: ${filesystem}"

    logger_info \
        "Root partition: ${root_part}"

    logger_info \
        "Home partition: ${home_part:-none}"

    logger_info \
        "EFI partition: ${efi_part:-none}"

    logger_info \
        "Swap type: ${swap_type}"
}

#------------------------------------------------------------
# Check filesystem tools
#------------------------------------------------------------

filesystem_check_tools()
{
    local filesystem
    local swap_type

    filesystem="$(config_get FILESYSTEM)"
    swap_type="$(config_get SWAP_TYPE)"

    command -v mkfs.fat >/dev/null 2>&1 || {
        if [[ "$(config_get BOOT_MODE)" == "UEFI" ]]
        then
            dialog_error \
                "mkfs.fat not found. Install dosfstools."

            return 1
        fi
    }

    case "$filesystem" in
        ext4)
            command -v mkfs.ext4 >/dev/null 2>&1 || {
                dialog_error \
                    "mkfs.ext4 not found"

                return 1
            }
            ;;
        btrfs)
            command -v mkfs.btrfs >/dev/null 2>&1 || {
                dialog_error \
                    "mkfs.btrfs not found"

                return 1
            }
            ;;
        xfs)
            command -v mkfs.xfs >/dev/null 2>&1 || {
                dialog_error \
                    "mkfs.xfs not found"

                return 1
            }
            ;;
        f2fs)
            command -v mkfs.f2fs >/dev/null 2>&1 || {
                dialog_error \
                    "mkfs.f2fs not found"

                return 1
            }
            ;;
    esac

    if [[ "$swap_type" == "partition" ]]
    then
        command -v mkswap >/dev/null 2>&1 || {
            dialog_error \
                "mkswap not found"

            return 1
        }
    fi
}

#------------------------------------------------------------
# Format EFI
#------------------------------------------------------------

filesystem_format_efi()
{
    local boot_mode
    local efi_part

    boot_mode="$(config_get BOOT_MODE)"

    if [[ "$boot_mode" != "UEFI" ]]
    then
        return 0
    fi

    efi_part="$(config_get EFI_PART)"

    [[ -n "$efi_part" ]] || {
        dialog_error \
            "EFI partition is empty"

        return 1
    }

    logger_warn \
        "Formatting EFI partition: ${efi_part}"

    mkfs.fat \
        -F32 \
        "$efi_part" \
        || {
            logger_error \
                "EFI format failed: ${efi_part}"

            return 1
        }

    logger_info \
        "EFI partition formatted successfully"
}

#------------------------------------------------------------
# Format root
#------------------------------------------------------------

filesystem_format_root()
{
    local filesystem
    local root_part

    filesystem="$(config_get FILESYSTEM)"
    root_part="$(config_get ROOT_PART)"

    logger_warn \
        "Formatting root partition: ${root_part} as ${filesystem}"

    case "$filesystem" in
        ext4)
            mkfs.ext4 \
                -F \
                "$root_part"
            ;;
        btrfs)
            mkfs.btrfs \
                -f \
                "$root_part"
            ;;
        xfs)
            mkfs.xfs \
                -f \
                "$root_part"
            ;;
        f2fs)
            mkfs.f2fs \
                -f \
                "$root_part"
            ;;
        *)
            dialog_error \
                "Unsupported root filesystem: ${filesystem}"

            return 1
            ;;
    esac

    logger_info \
        "Root filesystem formatted successfully"
}

#------------------------------------------------------------
# Format home
#------------------------------------------------------------

filesystem_format_home()
{
    local create_home
    local filesystem
    local home_part

    create_home="$(config_get CREATE_HOME)"

    if [[ "$create_home" != "1" ]]
    then
        return 0
    fi

    filesystem="$(config_get FILESYSTEM)"
    home_part="$(config_get HOME_PART)"

    [[ -n "$home_part" ]] || {
        dialog_error \
            "Home partition is empty"

        return 1
    }

    logger_warn \
        "Formatting home partition: ${home_part} as ${filesystem}"

    case "$filesystem" in
        ext4)
            mkfs.ext4 \
                -F \
                "$home_part"
            ;;
        btrfs)
            mkfs.btrfs \
                -f \
                "$home_part"
            ;;
        xfs)
            mkfs.xfs \
                -f \
                "$home_part"
            ;;
        f2fs)
            mkfs.f2fs \
                -f \
                "$home_part"
            ;;
        *)
            dialog_error \
                "Unsupported home filesystem: ${filesystem}"

            return 1
            ;;
    esac

    logger_info \
        "Home filesystem formatted successfully"
}

#------------------------------------------------------------
# Format swap
#------------------------------------------------------------

filesystem_format_swap()
{
    local swap_type
    local swap_part

    swap_type="$(config_get SWAP_TYPE)"

    if [[ "$swap_type" != "partition" ]]
    then
        return 0
    fi

    swap_part="$(config_get SWAP_PART)"

    [[ -n "$swap_part" ]] || {
        dialog_error \
            "Swap partition is empty"

        return 1
    }

    logger_warn \
        "Formatting swap partition: ${swap_part}"

    mkswap \
        -f \
        "$swap_part" \
        || {
            logger_error \
                "Swap format failed: ${swap_part}"

            return 1
        }

    logger_info \
        "Swap partition formatted successfully"
}

#------------------------------------------------------------
# Detect filesystem type
#------------------------------------------------------------

filesystem_detect_type()
{
    local device="$1"

    blkid \
        -s TYPE \
        -o value \
        "$device" \
        2>/dev/null \
        || true
}

#------------------------------------------------------------
# Check EFI
#------------------------------------------------------------

filesystem_check_efi()
{
    local boot_mode
    local efi_part
    local actual_type

    boot_mode="$(config_get BOOT_MODE)"

    if [[ "$boot_mode" != "UEFI" ]]
    then
        return 0
    fi

    efi_part="$(config_get EFI_PART)"

    actual_type="$(
        filesystem_detect_type \
            "$efi_part"
    )"

    if [[ "$actual_type" != "vfat" ]]
    then
        dialog_error \
            "EFI filesystem check failed: expected vfat, got ${actual_type:-unknown}"

        return 1
    fi

    logger_info \
        "EFI filesystem check passed"
}

#------------------------------------------------------------
# Check root
#------------------------------------------------------------

filesystem_check_root()
{
    local root_part
    local expected
    local actual

    root_part="$(config_get ROOT_PART)"
    expected="$(config_get FILESYSTEM)"

    actual="$(
        filesystem_detect_type \
            "$root_part"
    )"

    if [[ "$actual" != "$expected" ]]
    then
        dialog_error \
            "Root filesystem check failed: expected ${expected}, got ${actual:-unknown}"

        return 1
    fi

    logger_info \
        "Root filesystem check passed"
}

#------------------------------------------------------------
# Check home
#------------------------------------------------------------

filesystem_check_home()
{
    local create_home
    local home_part
    local expected
    local actual

    create_home="$(config_get CREATE_HOME)"

    if [[ "$create_home" != "1" ]]
    then
        return 0
    fi

    home_part="$(config_get HOME_PART)"
    expected="$(config_get FILESYSTEM)"

    actual="$(
        filesystem_detect_type \
            "$home_part"
    )"

    if [[ "$actual" != "$expected" ]]
    then
        dialog_error \
            "Home filesystem check failed: expected ${expected}, got ${actual:-unknown}"

        return 1
    fi

    logger_info \
        "Home filesystem check passed"
}

#------------------------------------------------------------
# Check swap
#------------------------------------------------------------

filesystem_check_swap()
{
    local swap_type
    local swap_part
    local actual

    swap_type="$(config_get SWAP_TYPE)"

    if [[ "$swap_type" != "partition" ]]
    then
        return 0
    fi

    swap_part="$(config_get SWAP_PART)"

    actual="$(
        filesystem_detect_type \
            "$swap_part"
    )"

    if [[ "$actual" != "swap" ]]
    then
        dialog_error \
            "Swap filesystem check failed: expected swap, got ${actual:-unknown}"

        return 1
    fi

    logger_info \
        "Swap filesystem check passed"
}

#------------------------------------------------------------
# Check result
#------------------------------------------------------------

filesystem_check()
{
    filesystem_check_efi || \
        return 1

    filesystem_check_root || \
        return 1

    filesystem_check_home || \
        return 1

    filesystem_check_swap || \
        return 1

    logger_info \
        "Filesystem validation passed"
}

#------------------------------------------------------------
# Save state
#------------------------------------------------------------

filesystem_save()
{
    config_save

    logger_info \
        "Filesystem state saved"
}

#------------------------------------------------------------
# Main
#------------------------------------------------------------

filesystem()
{
    logger_info \
        "Filesystem formatting started"

    filesystem_load_config || \
        return 1

    filesystem_check_tools || \
        return 1

    filesystem_format_efi || \
        return 1

    filesystem_format_root || \
        return 1

    filesystem_format_home || \
        return 1

    filesystem_format_swap || \
        return 1

    filesystem_check || \
        return 1

    filesystem_save || \
        return 1

    dialog_message \
        "Filesystem" \
        "Formatting completed successfully"

    logger_info \
        "Filesystem formatting finished"
}