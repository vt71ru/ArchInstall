#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  summary.sh
#
#  Финальная проверка установленной системы.
#
#  Ответственность:
#   • Проверка конфигурации
#   • Проверка target system
#   • Проверка разделов и файловых систем
#   • Проверка /mnt и EFI
#   • Проверка fstab
#   • Проверка пользователя
#   • Проверка bootloader
#   • Отображение итоговой информации
#
#  Не выполняет:
#   • Изменение дисков
#   • Форматирование
#   • Монтирование
#   • Установку пакетов
#   • Изменение systemd
#============================================================

[[ -n "${SUMMARY_SH_LOADED:-}" ]] && return

readonly SUMMARY_SH_LOADED=1

#------------------------------------------------------------
# State
#------------------------------------------------------------

SUMMARY_OK=0
SUMMARY_ERRORS=0

#------------------------------------------------------------
# Reset state
#------------------------------------------------------------

summary_reset()
{
    SUMMARY_OK=0
    SUMMARY_ERRORS=0
}

#------------------------------------------------------------
# Result helpers
#------------------------------------------------------------

summary_ok()
{
    local message="$1"

    ((SUMMARY_OK++))

    logger_info \
        "SUMMARY OK: ${message}"
}

summary_error()
{
    local message="$1"

    ((SUMMARY_ERRORS++))

    logger_error \
        "SUMMARY ERROR: ${message}"
}

#------------------------------------------------------------
# Generic file check
#------------------------------------------------------------

summary_check_file()
{
    local file="$1"
    local description="$2"

    if [[ -f "$file" ]]
    then
        summary_ok \
            "$description"
        return 0
    fi

    summary_error \
        "$description: ${file}"

    return 1
}

#------------------------------------------------------------
# Generic directory check
#------------------------------------------------------------

summary_check_directory()
{
    local directory="$1"
    local description="$2"

    if [[ -d "$directory" ]]
    then
        summary_ok \
            "$description"
        return 0
    fi

    summary_error \
        "$description: ${directory}"

    return 1
}

#------------------------------------------------------------
# Configuration
#------------------------------------------------------------

summary_check_configuration()
{
    local boot_mode
    local partition_table
    local target_disk
    local filesystem
    local swap_type
    local desktop
    local bootloader

    boot_mode="$(config_get BOOT_MODE)"
    partition_table="$(config_get PARTITION_TABLE)"
    target_disk="$(config_get TARGET_DISK)"
    filesystem="$(config_get FILESYSTEM)"
    swap_type="$(config_get SWAP_TYPE)"
    desktop="$(config_get DESKTOP)"
    bootloader="$(config_get BOOTLOADER)"

    case "$boot_mode" in
        UEFI|BIOS)
            summary_ok \
                "Boot mode: ${boot_mode}"
            ;;
        *)
            summary_error \
                "Invalid boot mode: ${boot_mode:-empty}"
            ;;
    esac

    case "$partition_table" in
        GPT|MBR)
            summary_ok \
                "Partition table: ${partition_table}"
            ;;
        *)
            summary_error \
                "Invalid partition table: ${partition_table:-empty}"
            ;;
    esac

    if [[ -b "$target_disk" ]]
    then
        summary_ok \
            "Target disk: ${target_disk}"
    else
        summary_error \
            "Target disk missing: ${target_disk:-empty}"
    fi

    case "$filesystem" in
        ext4|btrfs|xfs|f2fs)
            summary_ok \
                "Filesystem: ${filesystem}"
            ;;
        *)
            summary_error \
                "Invalid filesystem: ${filesystem:-empty}"
            ;;
    esac

    case "$swap_type" in
        none|partition|file)
            summary_ok \
                "Swap type: ${swap_type}"
            ;;
        *)
            summary_error \
                "Invalid swap type: ${swap_type:-empty}"
            ;;
    esac

    if [[ -n "$desktop" ]]
    then
        summary_ok \
            "Desktop: ${desktop}"
    else
        summary_ok \
            "Desktop: none"
    fi

    if [[ "$bootloader" == "grub" ]]
    then
        summary_ok \
            "Bootloader: GRUB"
    else
        summary_error \
            "Bootloader not configured"
    fi
}

#------------------------------------------------------------
# Partition checks
#------------------------------------------------------------

summary_check_partitions()
{
    local root_part
    local home_part
    local efi_part
    local bios_part
    local swap_part
    local create_home
    local boot_mode
    local swap_type

    root_part="$(config_get ROOT_PART)"
    home_part="$(config_get HOME_PART)"
    efi_part="$(config_get EFI_PART)"
    bios_part="$(config_get BIOS_PART)"
    swap_part="$(config_get SWAP_PART)"
    create_home="$(config_get CREATE_HOME)"
    boot_mode="$(config_get BOOT_MODE)"
    swap_type="$(config_get SWAP_TYPE)"

    if [[ -b "$root_part" ]]
    then
        summary_ok \
            "ROOT partition: ${root_part}"
    else
        summary_error \
            "ROOT partition missing: ${root_part:-empty}"
    fi

    if [[ "$create_home" == "1" ]]
    then
        if [[ -b "$home_part" ]]
        then
            summary_ok \
                "HOME partition: ${home_part}"
        else
            summary_error \
                "HOME partition missing: ${home_part:-empty}"
        fi
    else
        summary_ok \
            "Separate HOME partition: disabled"
    fi

    if [[ "$boot_mode" == "UEFI" ]]
    then
        if [[ -b "$efi_part" ]]
        then
            summary_ok \
                "EFI partition: ${efi_part}"
        else
            summary_error \
                "EFI partition missing: ${efi_part:-empty}"
        fi
    fi

    if [[ "$boot_mode" == "BIOS" &&
          "$(config_get PARTITION_TABLE)" == "GPT" ]]
    then
        if [[ -b "$bios_part" ]]
        then
            summary_ok \
                "BIOS boot partition: ${bios_part}"
        else
            summary_error \
                "BIOS boot partition missing: ${bios_part:-empty}"
        fi
    fi

    if [[ "$swap_type" == "partition" ]]
    then
        if [[ -b "$swap_part" ]]
        then
            summary_ok \
                "SWAP partition: ${swap_part}"
        else
            summary_error \
                "SWAP partition missing: ${swap_part:-empty}"
        fi
    elif [[ "$swap_type" == "file" ]]
    then
        summary_ok \
            "SWAP file selected"
    else
        summary_ok \
            "SWAP disabled"
    fi
}

#------------------------------------------------------------
# Mount checks
#------------------------------------------------------------

summary_check_mounts()
{
    local boot_mode
    local create_home

    boot_mode="$(config_get BOOT_MODE)"
    create_home="$(config_get CREATE_HOME)"

    if mountpoint -q /mnt
    then
        summary_ok \
            "Root mounted at /mnt"
    else
        summary_error \
            "/mnt is not mounted"
    fi

    if [[ "$create_home" == "1" ]]
    then
        if mountpoint -q /mnt/home
        then
            summary_ok \
                "HOME mounted at /mnt/home"
        else
            summary_error \
                "/mnt/home is not mounted"
        fi
    fi

    if [[ "$boot_mode" == "UEFI" ]]
    then
        if mountpoint -q /mnt/boot/efi
        then
            summary_ok \
                "EFI mounted at /mnt/boot/efi"
        else
            summary_error \
                "/mnt/boot/efi is not mounted"
        fi
    fi
}

#------------------------------------------------------------
# Filesystem checks
#------------------------------------------------------------

summary_check_filesystems()
{
    local filesystem
    local root_part
    local home_part
    local efi_part
    local swap_part
    local swap_type
    local actual

    filesystem="$(config_get FILESYSTEM)"
    root_part="$(config_get ROOT_PART)"
    home_part="$(config_get HOME_PART)"
    efi_part="$(config_get EFI_PART)"
    swap_part="$(config_get SWAP_PART)"
    swap_type="$(config_get SWAP_TYPE)"

    actual="$(
        blkid \
            -s TYPE \
            -o value \
            "$root_part" \
            2>/dev/null \
            || true
    )"

    if [[ "$actual" == "$filesystem" ]]
    then
        summary_ok \
            "ROOT filesystem: ${actual}"
    else
        summary_error \
            "ROOT filesystem: expected=${filesystem}, actual=${actual:-unknown}"
    fi

    if [[ "$(config_get CREATE_HOME)" == "1" ]]
    then
        actual="$(
            blkid \
                -s TYPE \
                -o value \
                "$home_part" \
                2>/dev/null \
                || true
        )"

        if [[ "$actual" == "$filesystem" ]]
        then
            summary_ok \
                "HOME filesystem: ${actual}"
        else
            summary_error \
                "HOME filesystem: expected=${filesystem}, actual=${actual:-unknown}"
        fi
    fi

    if [[ "$(config_get BOOT_MODE)" == "UEFI" ]]
    then
        actual="$(
            blkid \
                -s TYPE \
                -o value \
                "$efi_part" \
                2>/dev/null \
                || true
        )"

        if [[ "$actual" == "vfat" ]]
        then
            summary_ok \
                "EFI filesystem: vfat"
        else
            summary_error \
                "EFI filesystem: expected=vfat, actual=${actual:-unknown}"
        fi
    fi

    if [[ "$swap_type" == "partition" ]]
    then
        actual="$(
            blkid \
                -s TYPE \
                -o value \
                "$swap_part" \
                2>/dev/null \
                || true
        )"

        if [[ "$actual" == "swap" ]]
        then
            summary_ok \
                "SWAP filesystem: swap"
        else
            summary_error \
                "SWAP filesystem: expected=swap, actual=${actual:-unknown}"
        fi
    fi
}

#------------------------------------------------------------
# fstab
#------------------------------------------------------------

summary_check_fstab()
{
    local fstab="/mnt/etc/fstab"

    if [[ ! -f "$fstab" ]]
    then
        summary_error \
            "fstab missing"

        return 1
    fi

    if [[ ! -s "$fstab" ]]
    then
        summary_error \
            "fstab is empty"

        return 1
    fi

    summary_ok \
        "fstab exists and is not empty"

    if grep -Eq '^[^#].+[[:space:]]+/[[:space:]]' "$fstab"
    then
        summary_ok \
            "fstab contains root entry"
    else
        summary_error \
            "fstab does not contain root entry"
    fi
}

#------------------------------------------------------------
# Target system
#------------------------------------------------------------

summary_check_target()
{
    summary_check_directory \
        /mnt/etc \
        "Target /etc exists"

    summary_check_directory \
        /mnt/usr \
        "Target /usr exists"

    summary_check_file \
        /mnt/etc/passwd \
        "Target passwd database exists"

    summary_check_file \
        /mnt/etc/shadow \
        "Target shadow database exists"

    summary_check_file \
        /mnt/etc/hostname \
        "Target hostname exists"

    summary_check_file \
        /mnt/root/installed-packages.txt \
        "Installed package list exists"
}

#------------------------------------------------------------
# User
#------------------------------------------------------------

summary_check_user()
{
    local user_name

    if ! [[ -v "CONFIG[USER_NAME]" ]]
    then
        summary_ok \
            "User configuration not requested"

        return 0
    fi

    user_name="$(config_get USER_NAME)"

    if [[ -z "$user_name" ]]
    then
        summary_error \
            "USER_NAME is empty"

        return 1
    fi

    if arch-chroot \
        /mnt \
        getent passwd \
        "$user_name" \
        >/dev/null 2>&1
    then
        summary_ok \
            "User exists: ${user_name}"
    else
        summary_error \
            "User missing: ${user_name}"

        return 1
    fi

    if arch-chroot \
        /mnt \
        id \
        -nG \
        "$user_name" |
        grep -Eq '(^|[[:space:]])wheel($|[[:space:]])'
    then
        summary_ok \
            "User belongs to wheel"
    else
        summary_error \
            "User is not a member of wheel"
    fi
}

#------------------------------------------------------------
# Sudo
#------------------------------------------------------------

summary_check_sudo()
{
    if [[ ! -f /mnt/etc/sudoers.d/10-wheel ]]
    then
        summary_error \
            "sudo wheel configuration missing"

        return 1
    fi

    summary_ok \
        "sudo wheel configuration exists"
}

#------------------------------------------------------------
# Network
#------------------------------------------------------------

summary_check_network()
{
    if arch-chroot \
        /mnt \
        systemctl \
        is-enabled \
        NetworkManager.service \
        >/dev/null 2>&1
    then
        summary_ok \
            "NetworkManager enabled"
    else
        summary_error \
            "NetworkManager is not enabled"
    fi
}

#------------------------------------------------------------
# SSH
#------------------------------------------------------------

summary_check_ssh()
{
    local ssh_enabled

    ssh_enabled="$(config_get SSH_ENABLED)"

    if [[ "$ssh_enabled" == "1" ]]
    then
        if arch-chroot \
            /mnt \
            systemctl \
            is-enabled \
            sshd.service \
            >/dev/null 2>&1
        then
            summary_ok \
                "sshd enabled"
        else
            summary_error \
                "sshd is not enabled"
        fi
    else
        summary_ok \
            "SSH disabled"
    fi
}

#------------------------------------------------------------
# Desktop
#------------------------------------------------------------

summary_check_desktop()
{
    local desktop
    local service

    desktop="$(config_get DESKTOP)"

    if [[ -z "$desktop" ]]
    then
        summary_ok \
            "Desktop environment not selected"

        return 0
    fi

    case "$desktop" in
        gnome)
            service="gdm.service"
            ;;
        kde)
            service="sddm.service"
            ;;
        xfce)
            service="lightdm.service"
            ;;
        *)
            summary_error \
                "Unsupported desktop: ${desktop}"

            return 1
            ;;
    esac

    if arch-chroot \
        /mnt \
        systemctl \
        is-enabled \
        "$service" \
        >/dev/null 2>&1
    then
        summary_ok \
            "Display manager enabled: ${service}"
    else
        summary_error \
            "Display manager not enabled: ${service}"
    fi

    if [[ "$(arch-chroot /mnt systemctl get-default)" == "graphical.target" ]]
    then
        summary_ok \
            "Default target: graphical.target"
    else
        summary_error \
            "Default target is not graphical.target"
    fi
}

#------------------------------------------------------------
# Bootloader
#------------------------------------------------------------

summary_check_bootloader()
{
    local boot_mode
    local grub_cfg

    boot_mode="$(config_get BOOT_MODE)"
    grub_cfg="/mnt/boot/grub/grub.cfg"

    if [[ ! -f "$grub_cfg" ]]
    then
        summary_error \
            "GRUB configuration missing"

        return 1
    fi

    summary_ok \
        "GRUB configuration exists"

    if [[ "$boot_mode" == "UEFI" ]]
    then
        if [[ -f /mnt/boot/efi/EFI/ARCHLINUX/grubx64.efi ]]
        then
            summary_ok \
                "UEFI GRUB binary exists"
        else
            summary_error \
                "UEFI GRUB binary missing"
        fi
    elif [[ "$boot_mode" == "BIOS" ]]
    then
        summary_ok \
            "BIOS GRUB mode selected"
    fi
}

#------------------------------------------------------------
# Summary draw
#------------------------------------------------------------

summary_draw()
{
    local row=3
    local user_name
    local desktop
    local boot_mode
    local partition_table
    local filesystem
    local swap_type
    local target_disk
    local hostname

    boot_mode="$(config_get BOOT_MODE)"
    partition_table="$(config_get PARTITION_TABLE)"
    filesystem="$(config_get FILESYSTEM)"
    swap_type="$(config_get SWAP_TYPE)"
    target_disk="$(config_get TARGET_DISK)"
    hostname="$(config_get HOSTNAME)"

    user_name="$(
        config_get USER_NAME \
            2>/dev/null \
            || true
    )

    desktop="$(config_get DESKTOP)"

    tui_clear

    titlebar_draw \
        "${APP_NAME:-Arch Installer} — Summary"

    cursor_move "$row" 5
    printf 'Target disk      : %s' "$target_disk"

    ((row++))

    cursor_move "$row" 5
    printf 'Boot mode        : %s' "$boot_mode"

    ((row++))

    cursor_move "$row" 5
    printf 'Partition table  : %s' "$partition_table"

    ((row++))

    cursor_move "$row" 5
    printf 'Root filesystem  : %s' "$filesystem"

    ((row++))

    cursor_move "$row" 5
    printf 'Swap             : %s' "$swap_type"

    ((row++))

    cursor_move "$row" 5
    printf 'Hostname         : %s' "$hostname"

    ((row++))

    cursor_move "$row" 5
    printf 'User             : %s' "${user_name:-none}"

    ((row++))

    cursor_move "$row" 5
    printf 'Desktop          : %s' "${desktop:-none}"

    ((row++))

    cursor_move "$row" 5
    printf 'Validation       : %d OK / %d ERROR' \
        "$SUMMARY_OK" \
        "$SUMMARY_ERRORS"

    statusbar_draw \
        "Enter Close   Esc Back"

    screen_refresh
}

#------------------------------------------------------------
# Final validation
#------------------------------------------------------------

summary_validate()
{
    summary_reset

    summary_check_configuration

    summary_check_partitions

    summary_check_filesystems

    summary_check_mounts

    summary_check_fstab

    summary_check_target

    summary_check_user

    summary_check_sudo

    summary_check_network

    summary_check_ssh

    summary_check_desktop

    summary_check_bootloader

    logger_info \
        "Final validation: ${SUMMARY_OK} OK, ${SUMMARY_ERRORS} ERROR"

    if (( SUMMARY_ERRORS > 0 ))
    then
        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Main
#------------------------------------------------------------

summary()
{
    local event

    logger_info \
        "Final summary started"

    if ! summary_validate
    then
        summary_draw

        dialog_error \
            "Installation validation failed: ${SUMMARY_ERRORS} error(s)"

        while true
        do
            event="$(event_read)"

            case "$event" in
                "$EVENT_SELECT"|"$EVENT_BACK")
                    break
                    ;;
            esac
        done

        return 1
    fi

    summary_draw

    dialog_message \
        "Installation" \
        "All final checks passed"

    while true
    do
        event="$(event_read)"

        case "$event" in
            "$EVENT_SELECT"|"$EVENT_BACK")
                break
                ;;
        esac
    done

    logger_info \
        "Final summary completed"

    return 0
}
