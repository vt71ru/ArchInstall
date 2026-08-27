#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  bootloader.sh
#
#  Установка загрузчика GRUB.
#
#  Поддерживает:
#   • UEFI + GPT
#   • BIOS + GPT
#   • BIOS + MBR
#
#  Ответственность:
#   • Проверка конфигурации
#   • Установка GRUB в target system
#   • Установка efibootmgr для UEFI
#   • Установка BIOS/GPT GRUB
#   • Генерация grub.cfg
#   • Проверка результата
#
#  Не выполняет:
#   • Разметку диска
#   • Форматирование
#   • Монтирование
#============================================================

[[ -n "${BOOTLOADER_SH_LOADED:-}" ]] && return

readonly BOOTLOADER_SH_LOADED=1

#------------------------------------------------------------
# Constants
#------------------------------------------------------------

readonly BOOTLOADER_ID="ARCHLINUX"
readonly BOOTLOADER_EFI_TARGET="x86_64-efi"
readonly BOOTLOADER_BIOS_TARGET="i386-pc"
readonly BOOTLOADER_EFI_DIR="/boot/efi"
readonly BOOTLOADER_GRUB_DIR="/boot/grub"
readonly BOOTLOADER_CONFIG="/boot/grub/grub.cfg"

#------------------------------------------------------------
# Load configuration
#------------------------------------------------------------

bootloader_load_config()
{
    local boot_mode
    local partition_table
    local target_disk
    local efi_part
    local bios_part

    boot_mode="$(config_get BOOT_MODE)"
    partition_table="$(config_get PARTITION_TABLE)"
    target_disk="$(config_get TARGET_DISK)"
    efi_part="$(config_get EFI_PART)"
    bios_part="$(config_get BIOS_PART)"

    case "$boot_mode" in
        UEFI|BIOS)
            ;;
        *)
            dialog_error \
                "Invalid boot mode: ${boot_mode:-empty}"

            return 1
            ;;
    esac

    case "$partition_table" in
        GPT|MBR)
            ;;
        *)
            dialog_error \
                "Invalid partition table: ${partition_table:-empty}"

            return 1
            ;;
    esac

    if [[ -z "$target_disk" ]]
    then
        dialog_error \
            "Target disk is not configured"

        return 1
    fi

    if [[ ! -b "$target_disk" ]]
    then
        dialog_error \
            "Target disk does not exist: ${target_disk}"

        return 1
    fi

    if [[ "$boot_mode" == "UEFI" ]]
    then
        if [[ "$partition_table" != "GPT" ]]
        then
            dialog_error \
                "UEFI installation requires GPT"

            return 1
        fi

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

    if [[ "$boot_mode" == "BIOS" &&
          "$partition_table" == "GPT" ]]
    then
        if [[ -z "$bios_part" ]]
        then
            dialog_error \
                "BIOS boot partition is not configured"

            return 1
        fi

        if [[ ! -b "$bios_part" ]]
        then
            dialog_error \
                "BIOS boot partition does not exist: ${bios_part}"

            return 1
        fi
    fi

    logger_info \
        "Boot mode: ${boot_mode}"

    logger_info \
        "Partition table: ${partition_table}"

    logger_info \
        "Target disk: ${target_disk}"

    logger_info \
        "EFI partition: ${efi_part:-none}"

    logger_info \
        "BIOS boot partition: ${bios_part:-none}"
}

#------------------------------------------------------------
# Validate target system
#------------------------------------------------------------

bootloader_check_target()
{
    if [[ ! -d /mnt ]]
    then
        dialog_error \
            "Target root /mnt does not exist"

        return 1
    fi

    if ! mountpoint -q /mnt
    then
        dialog_error \
            "/mnt is not mounted"

        return 1
    fi

    if [[ ! -d /mnt/boot ]]
    then
        dialog_error \
            "Target /boot directory does not exist"

        return 1
    fi

    logger_info \
        "Target system check passed"
}

#------------------------------------------------------------
# Validate UEFI environment
#------------------------------------------------------------

bootloader_check_uefi_environment()
{
    local boot_mode

    boot_mode="$(config_get BOOT_MODE)"

    if [[ "$boot_mode" != "UEFI" ]]
    then
        return 0
    fi

    if [[ ! -d /sys/firmware/efi ]]
    then
        dialog_error \
            "Installer was not booted in UEFI mode"

        return 1
    fi

    if [[ ! -d /sys/firmware/efi/efivars ]]
    then
        dialog_error \
            "EFI variables are not available"

        return 1
    fi

    logger_info \
        "UEFI firmware environment detected"
}

#------------------------------------------------------------
# Check required host tools
#------------------------------------------------------------

bootloader_check_host_tools()
{
    local required=(
        pacstrap
        arch-chroot
        mountpoint
        findmnt
        blkid
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
}

#------------------------------------------------------------
# Install GRUB packages into target
#------------------------------------------------------------

bootloader_install_packages()
{
    local boot_mode

    boot_mode="$(config_get BOOT_MODE)"

    logger_info \
        "Installing bootloader packages into target"

    case "$boot_mode" in
        UEFI)
            pacstrap \
                -K \
                /mnt \
                grub \
                efibootmgr \
                || {
                    logger_error \
                        "Failed installing GRUB/efibootmgr"

                    return 1
                }
            ;;
        BIOS)
            pacstrap \
                -K \
                /mnt \
                grub \
                || {
                    logger_error \
                        "Failed installing GRUB"

                    return 1
                }
            ;;
        *)
            dialog_error \
                "Unsupported boot mode: ${boot_mode}"

            return 1
            ;;
    esac

    logger_info \
        "Bootloader packages installed"
}

#------------------------------------------------------------
# Check target GRUB tools
#------------------------------------------------------------

bootloader_check_target_tools()
{
    if ! arch-chroot \
        /mnt \
        command -v grub-install \
        >/dev/null 2>&1
    then
        dialog_error \
            "grub-install is not available in target system"

        return 1
    fi

    if ! arch-chroot \
        /mnt \
        command -v grub-mkconfig \
        >/dev/null 2>&1
    then
        dialog_error \
            "grub-mkconfig is not available in target system"

        return 1
    fi
}

#------------------------------------------------------------
# Check EFI mount
#------------------------------------------------------------

bootloader_check_efi_mount()
{
    local boot_mode
    local efi_part

    boot_mode="$(config_get BOOT_MODE)"

    if [[ "$boot_mode" != "UEFI" ]]
    then
        return 0
    fi

    efi_part="$(config_get EFI_PART)"

    if ! mountpoint -q /mnt/boot/efi
    then
        dialog_error \
            "/mnt/boot/efi is not mounted"

        return 1
    fi

    if ! findmnt \
        -rn \
        -S "$efi_part" \
        -T /mnt/boot/efi \
        >/dev/null 2>&1
    then
        dialog_error \
            "EFI partition is not mounted at /mnt/boot/efi"

        return 1
    fi

    logger_info \
        "EFI mount check passed"
}

#------------------------------------------------------------
# Check BIOS/GPT partition
#------------------------------------------------------------

bootloader_check_bios_partition()
{
    local boot_mode
    local partition_table
    local bios_part
    local part_type

    boot_mode="$(config_get BOOT_MODE)"
    partition_table="$(config_get PARTITION_TABLE)"

    if [[ "$boot_mode" != "BIOS" ||
          "$partition_table" != "GPT" ]]
    then
        return 0
    fi

    bios_part="$(config_get BIOS_PART)"

    part_type="$(
        blkid \
            -s PARTTYPE \
            -o value \
            "$bios_part" \
            2>/dev/null \
            || true
    )"

    if [[ "$part_type" != "21686148-6449-6E6F-744E-656564454649" ]]
    then
        dialog_error \
            "Invalid BIOS boot partition type: ${part_type:-unknown}"

        return 1
    fi

    logger_info \
        "BIOS/GPT boot partition check passed"
}

#------------------------------------------------------------
# Install UEFI GRUB
#------------------------------------------------------------

bootloader_install_uefi()
{
    logger_info \
        "Installing GRUB for UEFI"

    arch-chroot \
        /mnt \
        grub-install \
        --target="$BOOTLOADER_EFI_TARGET" \
        --efi-directory="$BOOTLOADER_EFI_DIR" \
        --bootloader-id="$BOOTLOADER_ID" \
        --recheck \
        || {
            logger_error \
                "UEFI GRUB installation failed"

            return 1
        }

    logger_info \
        "UEFI GRUB installed successfully"
}

#------------------------------------------------------------
# Install BIOS GRUB
#------------------------------------------------------------

bootloader_install_bios()
{
    local target_disk

    target_disk="$(config_get TARGET_DISK)"

    logger_info \
        "Installing GRUB for BIOS: ${target_disk}"

    arch-chroot \
        /mnt \
        grub-install \
        --target="$BOOTLOADER_BIOS_TARGET" \
        "$target_disk" \
        --recheck \
        || {
            logger_error \
                "BIOS GRUB installation failed"

            return 1
        }

    logger_info \
        "BIOS GRUB installed successfully"
}

#------------------------------------------------------------
# Generate GRUB configuration
#------------------------------------------------------------

bootloader_generate_config()
{
    logger_info \
        "Generating GRUB configuration"

    arch-chroot \
        /mnt \
        grub-mkconfig \
        -o "$BOOTLOADER_CONFIG" \
        || {
            logger_error \
                "Failed generating GRUB configuration"

            return 1
        }

    logger_info \
        "GRUB configuration generated"
}

#------------------------------------------------------------
# Validate GRUB files
#------------------------------------------------------------

bootloader_check_files()
{
    local boot_mode

    boot_mode="$(config_get BOOT_MODE)"

    if [[ ! -d "/mnt${BOOTLOADER_GRUB_DIR}" ]]
    then
        dialog_error \
            "GRUB directory is missing: /mnt${BOOTLOADER_GRUB_DIR}"

        return 1
    fi

    if [[ ! -f "/mnt${BOOTLOADER_CONFIG}" ]]
    then
        dialog_error \
            "GRUB configuration is missing: /mnt${BOOTLOADER_CONFIG}"

        return 1
    fi

    if [[ "$boot_mode" == "UEFI" ]]
    then
        if [[ ! -f "/mnt/boot/efi/EFI/${BOOTLOADER_ID}/grubx64.efi" ]]
        then
            dialog_error \
                "UEFI GRUB binary was not installed"

            return 1
        fi
    fi

    logger_info \
        "GRUB file validation passed"
}

#------------------------------------------------------------
# Validate target bootloader
#------------------------------------------------------------

bootloader_check_installation()
{
    local boot_mode
    local partition_table

    boot_mode="$(config_get BOOT_MODE)"
    partition_table="$(config_get PARTITION_TABLE)"

    bootloader_check_files || \
        return 1

    case "$boot_mode:$partition_table" in
        UEFI:GPT)
            logger_info \
                "Validated installation mode: UEFI/GPT"
            ;;
        BIOS:GPT)
            logger_info \
                "Validated installation mode: BIOS/GPT"
            ;;
        BIOS:MBR)
            logger_info \
                "Validated installation mode: BIOS/MBR"
            ;;
        *)
            dialog_error \
                "Unsupported bootloader configuration"

            return 1
            ;;
    esac

    return 0
}

#------------------------------------------------------------
# Save state
#------------------------------------------------------------

bootloader_save()
{
    config_set \
        BOOTLOADER \
        "grub"

    config_save

    logger_info \
        "Bootloader state saved"
}

#------------------------------------------------------------
# Main
#------------------------------------------------------------

bootloader()
{
    local boot_mode
    local partition_table

    logger_info \
        "Bootloader installation started"

    bootloader_load_config || \
        return 1

    bootloader_check_target || \
        return 1

    bootloader_check_host_tools || \
        return 1

    bootloader_check_uefi_environment || \
        return 1

    bootloader_check_bios_partition || \
        return 1

    bootloader_check_efi_mount || \
        return 1

    bootloader_install_packages || \
        return 1

    bootloader_check_target_tools || \
        return 1

    boot_mode="$(config_get BOOT_MODE)"
    partition_table="$(config_get PARTITION_TABLE)"

    case "$boot_mode:$partition_table" in
        UEFI:GPT)
            bootloader_install_uefi || \
                return 1
            ;;
        BIOS:GPT|BIOS:MBR)
            bootloader_install_bios || \
                return 1
            ;;
        *)
            dialog_error \
                "Unsupported bootloader configuration: ${boot_mode}/${partition_table}"

            return 1
            ;;
    esac

    bootloader_generate_config || \
        return 1

    bootloader_check_installation || \
        return 1

    bootloader_save || \
        return 1

    dialog_message \
        "Bootloader" \
        "GRUB installed successfully"

    logger_info \
        "Bootloader installation finished"
}
