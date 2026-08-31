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

if [[ -n "${SUMMARY_SH_LOADED:-}" ]]
then
    return 0
fi

readonly SUMMARY_SH_LOADED=1

#============================================================
# State
#============================================================

SUMMARY_OK=0
SUMMARY_ERRORS=0

#============================================================
# Logging
#============================================================

summary_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@"
    fi

    return 0
}

summary_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@"
    fi

    return 0
}

#============================================================
# Reset state
#============================================================

summary_reset()
{
    SUMMARY_OK=0
    SUMMARY_ERRORS=0

    return 0
}

#============================================================
# Result helpers
#============================================================

summary_ok()
{
    local message="${1:-}"

    SUMMARY_OK=$((SUMMARY_OK + 1))

    summary_log_info \
        "SUMMARY OK: ${message}"

    return 0
}

summary_error()
{
    local message="${1:-}"

    SUMMARY_ERRORS=$((SUMMARY_ERRORS + 1))

    summary_log_error \
        "SUMMARY ERROR: ${message}"

    return 0
}

#============================================================
# Safe config getter
#============================================================

summary_config_get()
{
    local key="${1:-}"
    local value=""

    if [[ -z "$key" ]]
    then
        return 1
    fi

    if ! declare -F config_get >/dev/null 2>&1
    then
        return 1
    fi

    value="$(
        config_get \
            "$key" \
            2>/dev/null \
            || true
    )"

    printf '%s\n' "$value"

    return 0
}

#============================================================
# Generic file check
#============================================================

summary_check_file()
{
    local file="${1:-}"
    local description="${2:-File}"

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

#============================================================
# Generic directory check
#============================================================

summary_check_directory()
{
    local directory="${1:-}"
    local description="${2:-Directory}"

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

#============================================================
# Configuration
#============================================================

summary_check_configuration()
{
    local boot_mode=""
    local partition_table=""
    local target_disk=""
    local filesystem=""
    local swap_type=""
    local desktop=""
    local bootloader=""

    boot_mode="$(summary_config_get BOOT_MODE)"
    partition_table="$(summary_config_get PARTITION_TABLE)"
    target_disk="$(summary_config_get TARGET_DISK)"
    filesystem="$(summary_config_get FILESYSTEM)"
    swap_type="$(summary_config_get SWAP_TYPE)"
    desktop="$(summary_config_get DESKTOP)"
    bootloader="$(summary_config_get BOOTLOADER)"

    #--------------------------------------------------------
    # Boot mode
    #--------------------------------------------------------

    case "$boot_mode"
    in
        UEFI|BIOS)
            summary_ok \
                "Boot mode: ${boot_mode}"
            ;;

        *)
            summary_error \
                "Invalid boot mode: ${boot_mode:-empty}"
            ;;
    esac

    #--------------------------------------------------------
    # Partition table
    #--------------------------------------------------------

    case "$partition_table"
    in
        GPT|MBR)
            summary_ok \
                "Partition table: ${partition_table}"
            ;;

        *)
            summary_error \
                "Invalid partition table: ${partition_table:-empty}"
            ;;
    esac

    #--------------------------------------------------------
    # Target disk
    #--------------------------------------------------------

    if [[ -n "$target_disk" && -b "$target_disk" ]]
    then
        summary_ok \
            "Target disk: ${target_disk}"
    else
        summary_error \
            "Target disk missing: ${target_disk:-empty}"
    fi

    #--------------------------------------------------------
    # Filesystem
    #--------------------------------------------------------

    case "$filesystem"
    in
        ext4|btrfs|xfs|f2fs)
            summary_ok \
                "Filesystem: ${filesystem}"
            ;;

        *)
            summary_error \
                "Invalid filesystem: ${filesystem:-empty}"
            ;;
    esac

    #--------------------------------------------------------
    # Swap
    #--------------------------------------------------------

    case "$swap_type"
    in
        none|partition|file)
            summary_ok \
                "Swap type: ${swap_type}"
            ;;

        *)
            summary_error \
                "Invalid swap type: ${swap_type:-empty}"
            ;;
    esac

    #--------------------------------------------------------
    # Desktop
    #--------------------------------------------------------

    if [[ -n "$desktop" ]]
    then
        summary_ok \
            "Desktop: ${desktop}"
    else
        summary_ok \
            "Desktop: none"
    fi

    #--------------------------------------------------------
    # Bootloader
    #--------------------------------------------------------

    case "$bootloader"
    in
        grub)
            summary_ok \
                "Bootloader: GRUB"
            ;;

        "")
            summary_error \
                "Bootloader not configured"
            ;;

        *)
            summary_error \
                "Unsupported bootloader: ${bootloader}"
            ;;
    esac

    return 0
}

#============================================================
# Partition checks
#============================================================

summary_check_partitions()
{
    local root_part=""
    local home_part=""
    local efi_part=""
    local bios_part=""
    local swap_part=""
    local create_home=""
    local boot_mode=""
    local swap_type=""
    local partition_table=""

    root_part="$(summary_config_get ROOT_PART)"
    home_part="$(summary_config_get HOME_PART)"
    efi_part="$(summary_config_get EFI_PART)"
    bios_part="$(summary_config_get BIOS_PART)"
    swap_part="$(summary_config_get SWAP_PART)"
    create_home="$(summary_config_get CREATE_HOME)"
    boot_mode="$(summary_config_get BOOT_MODE)"
    swap_type="$(summary_config_get SWAP_TYPE)"
    partition_table="$(summary_config_get PARTITION_TABLE)"

    #--------------------------------------------------------
    # ROOT
    #--------------------------------------------------------

    if [[ -n "$root_part" && -b "$root_part" ]]
    then
        summary_ok \
            "ROOT partition: ${root_part}"
    else
        summary_error \
            "ROOT partition missing: ${root_part:-empty}"
    fi

    #--------------------------------------------------------
    # HOME
    #--------------------------------------------------------

    if [[ "$create_home" == "1" ]]
    then
        if [[ -n "$home_part" && -b "$home_part" ]]
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

    #--------------------------------------------------------
    # EFI
    #--------------------------------------------------------

    if [[ "$boot_mode" == "UEFI" ]]
    then
        if [[ -n "$efi_part" && -b "$efi_part" ]]
        then
            summary_ok \
                "EFI partition: ${efi_part}"
        else
            summary_error \
                "EFI partition missing: ${efi_part:-empty}"
        fi
    fi

    #--------------------------------------------------------
    # BIOS boot partition
    #--------------------------------------------------------

    if [[ "$boot_mode" == "BIOS" &&
          "$partition_table" == "GPT" ]]
    then
        if [[ -n "$bios_part" && -b "$bios_part" ]]
        then
            summary_ok \
                "BIOS boot partition: ${bios_part}"
        else
            summary_error \
                "BIOS boot partition missing: ${bios_part:-empty}"
        fi
    fi

    #--------------------------------------------------------
    # SWAP
    #--------------------------------------------------------

    case "$swap_type"
    in
        partition)
            if [[ -n "$swap_part" && -b "$swap_part" ]]
            then
                summary_ok \
                    "SWAP partition: ${swap_part}"
            else
                summary_error \
                    "SWAP partition missing: ${swap_part:-empty}"
            fi
            ;;

        file)
            summary_ok \
                "SWAP file selected"
            ;;

        none|"")
            summary_ok \
                "SWAP disabled"
            ;;

        *)
            summary_error \
                "Unknown SWAP type: ${swap_type}"
            ;;
    esac

    return 0
}

#============================================================
# Mount checks
#============================================================

summary_check_mounts()
{
    local boot_mode=""
    local create_home=""

    boot_mode="$(summary_config_get BOOT_MODE)"
    create_home="$(summary_config_get CREATE_HOME)"

    #--------------------------------------------------------
    # Root
    #--------------------------------------------------------

    if mountpoint -q /mnt
    then
        summary_ok \
            "Root mounted at /mnt"
    else
        summary_error \
            "/mnt is not mounted"
    fi

    #--------------------------------------------------------
    # HOME
    #--------------------------------------------------------

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

    #--------------------------------------------------------
    # EFI
    #--------------------------------------------------------

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

    return 0
}

#============================================================
# Filesystem checks
#============================================================

summary_check_filesystems()
{
    local filesystem=""
    local root_part=""
    local home_part=""
    local efi_part=""
    local swap_part=""
    local swap_type=""
    local actual=""
    local create_home=""
    local boot_mode=""

    filesystem="$(summary_config_get FILESYSTEM)"
    root_part="$(summary_config_get ROOT_PART)"
    home_part="$(summary_config_get HOME_PART)"
    efi_part="$(summary_config_get EFI_PART)"
    swap_part="$(summary_config_get SWAP_PART)"
    swap_type="$(summary_config_get SWAP_TYPE)"
    create_home="$(summary_config_get CREATE_HOME)"
    boot_mode="$(summary_config_get BOOT_MODE)"

    #--------------------------------------------------------
    # ROOT
    #--------------------------------------------------------

    if [[ -n "$root_part" && -b "$root_part" ]]
    then
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
    else
        summary_error \
            "Cannot check ROOT filesystem: partition unavailable"
    fi

    #--------------------------------------------------------
    # HOME
    #--------------------------------------------------------

    if [[ "$create_home" == "1" ]]
    then
        if [[ -n "$home_part" && -b "$home_part" ]]
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
        else
            summary_error \
                "Cannot check HOME filesystem: partition unavailable"
        fi
    fi

    #--------------------------------------------------------
    # EFI
    #--------------------------------------------------------

    if [[ "$boot_mode" == "UEFI" ]]
    then
        if [[ -n "$efi_part" && -b "$efi_part" ]]
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
        else
            summary_error \
                "Cannot check EFI filesystem: partition unavailable"
        fi
    fi

    #--------------------------------------------------------
    # SWAP
    #--------------------------------------------------------

    if [[ "$swap_type" == "partition" ]]
    then
        if [[ -n "$swap_part" && -b "$swap_part" ]]
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
        else
            summary_error \
                "Cannot check SWAP filesystem: partition unavailable"
        fi
    elif [[ "$swap_type" == "file" ]]
    then
        if [[ -f /mnt/swapfile ]]
        then
            summary_ok \
                "SWAP file exists: /mnt/swapfile"
        else
            summary_error \
                "SWAP file missing: /mnt/swapfile"
        fi
    fi

    return 0
}

#============================================================
# fstab
#============================================================

summary_check_fstab()
{
    local fstab="/mnt/etc/fstab"

    if [[ ! -f "$fstab" ]]
    then
        summary_error \
            "fstab missing: ${fstab}"

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

    if grep -Eq \
        '^[^#[:space:]].+[[:space:]]+/[[:space:]]' \
        "$fstab"
    then
        summary_ok \
            "fstab contains root entry"
    else
        summary_error \
            "fstab does not contain root entry"
    fi

    return 0
}

#============================================================
# Target system
#============================================================

summary_check_target()
{
    summary_check_directory \
        /mnt/etc \
        "Target /etc exists"

    summary_check_directory \
        /mnt/usr \
        "Target /usr exists"

    summary_check_directory \
        /mnt/root \
        "Target /root exists"

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

    return 0
}

#============================================================
# User
#============================================================

summary_check_user()
{
    local user_name=""

    user_name="$(
        summary_config_get USER_NAME
    )"

    # No user configured
    if [[ -z "$user_name" ]]
    then
        summary_ok \
            "User configuration not requested"

        return 0
    fi

    if ! command -v arch-chroot >/dev/null 2>&1
    then
        summary_error \
            "arch-chroot is unavailable"

        return 1
    fi

    #--------------------------------------------------------
    # User exists
    #--------------------------------------------------------

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

    #--------------------------------------------------------
    # Wheel membership
    #--------------------------------------------------------

    if arch-chroot \
        /mnt \
        id \
        -nG \
        "$user_name" \
        2>/dev/null |
        tr ' ' '\n' |
        grep -qx 'wheel'
    then
        summary_ok \
            "User belongs to wheel"
    else
        summary_error \
            "User is not a member of wheel"
    fi

    return 0
}

#============================================================
# Sudo
#============================================================

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

    return 0
}

#============================================================
# Network
#============================================================

summary_check_network()
{
    if ! command -v arch-chroot >/dev/null 2>&1
    then
        summary_error \
            "arch-chroot is unavailable"

        return 1
    fi

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

    return 0
}

#============================================================
# SSH
#============================================================

summary_check_ssh()
{
    local ssh_enabled=""

    ssh_enabled="$(summary_config_get SSH_ENABLED)"

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

    return 0
}

#============================================================
# Desktop
#============================================================

summary_check_desktop()
{
    local desktop=""
    local service=""

    desktop="$(summary_config_get DESKTOP)"

    if [[ -z "$desktop" ]]
    then
        summary_ok \
            "Desktop environment not selected"

        return 0
    fi

    case "$desktop"
    in
        gnome)
            service="gdm.service"
            ;;

        kde|plasma)
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

    if arch-chroot \
        /mnt \
        systemctl \
        get-default \
        2>/dev/null |
        grep -qx 'graphical.target'
    then
        summary_ok \
            "Default target: graphical.target"
    else
        summary_error \
            "Default target is not graphical.target"
    fi

    return 0
}

#============================================================
# Bootloader
#============================================================

summary_check_bootloader()
{
    local boot_mode=""
    local grub_cfg="/mnt/boot/grub/grub.cfg"

    boot_mode="$(summary_config_get BOOT_MODE)"

    #--------------------------------------------------------
    # GRUB configuration
    #--------------------------------------------------------

    if [[ ! -f "$grub_cfg" ]]
    then
        summary_error \
            "GRUB configuration missing: ${grub_cfg}"

        return 1
    fi

    summary_ok \
        "GRUB configuration exists"

    #--------------------------------------------------------
    # UEFI
    #--------------------------------------------------------

    if [[ "$boot_mode" == "UEFI" ]]
    then
        if [[ -f /mnt/boot/efi/EFI/ARCHLINUX/grubx64.efi ]]
        then
            summary_ok \
                "UEFI GRUB binary exists"
        elif [[ -f /mnt/boot/efi/EFI/GRUB/grubx64.efi ]]
        then
            summary_ok \
                "UEFI GRUB binary exists"
        elif [[ -f /mnt/boot/efi/EFI/BOOT/BOOTX64.EFI ]]
        then
            summary_ok \
                "UEFI fallback bootloader exists"
        else
            summary_error \
                "UEFI GRUB binary missing"
        fi

    #--------------------------------------------------------
    # BIOS
    #--------------------------------------------------------

    elif [[ "$boot_mode" == "BIOS" ]]
    then
        summary_ok \
            "BIOS GRUB mode selected"
    fi

    return 0
}

#============================================================
# Summary draw
#============================================================

summary_draw()
{
    local row=3
    local user_name=""
    local desktop=""
    local boot_mode=""
    local partition_table=""
    local filesystem=""
    local swap_type=""
    local target_disk=""
    local hostname=""

    boot_mode="$(summary_config_get BOOT_MODE)"
    partition_table="$(summary_config_get PARTITION_TABLE)"
    filesystem="$(summary_config_get FILESYSTEM)"
    swap_type="$(summary_config_get SWAP_TYPE)"
    target_disk="$(summary_config_get TARGET_DISK)"
    hostname="$(summary_config_get HOSTNAME)"

    user_name="$(summary_config_get USER_NAME)"
    desktop="$(summary_config_get DESKTOP)"

    if declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear
    fi

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "${APP_NAME:-Arch Installer} - Summary"
    fi

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move "$row" 5
        tui_print "Target disk      : ${target_disk}"
        row=$((row + 1))

        tui_move "$row" 5
        tui_print "Boot mode        : ${boot_mode}"
        row=$((row + 1))

        tui_move "$row" 5
        tui_print "Partition table  : ${partition_table}"
        row=$((row + 1))

        tui_move "$row" 5
        tui_print "Root filesystem  : ${filesystem}"
        row=$((row + 1))

        tui_move "$row" 5
        tui_print "Swap             : ${swap_type}"
        row=$((row + 1))

        tui_move "$row" 5
        tui_print "Hostname         : ${hostname}"
        row=$((row + 1))

        tui_move "$row" 5
        tui_print "User             : ${user_name:-none}"
        row=$((row + 1))

        tui_move "$row" 5
        tui_print "Desktop          : ${desktop:-none}"
        row=$((row + 1))

        tui_move "$row" 5
        tui_print \
            "Validation       : ${SUMMARY_OK} OK / ${SUMMARY_ERRORS} ERROR"
    fi

    if declare -F statusbar_draw >/dev/null 2>&1
    then
        statusbar_draw \
            "Enter Close   Esc Back"
    fi

    if declare -F screen_refresh >/dev/null 2>&1
    then
        screen_refresh 2>/dev/null || true
    fi

    return 0
}

#============================================================
# Wait for user
#============================================================

summary_wait()
{
    local event=""

    while true
    do
        event="$(
            event_read
        )"

        case "$event"
        in
            "$EVENT_SELECT"|"$EVENT_BACK")
                return 0
                ;;

            *)
                ;;
        esac
    done
}

#============================================================
# Final validation
#============================================================

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

    summary_log_info \
        "Final validation: ${SUMMARY_OK} OK, ${SUMMARY_ERRORS} ERROR"

    if (( SUMMARY_ERRORS > 0 ))
    then
        return 1
    fi

    return 0
}

#============================================================
# Main
#============================================================

summary()
{
    summary_log_info \
        "Final summary started"

    if ! summary_validate
    then
        summary_draw

        if declare -F dialog_error >/dev/null 2>&1
        then
            dialog_error \
                "Installation validation failed" \
                "${SUMMARY_ERRORS} error(s) detected."
        fi

        summary_wait

        return 1
    fi

    summary_draw

    if declare -F dialog_info >/dev/null 2>&1
    then
        dialog_info \
            "Installation" \
            "All final checks passed."
    fi

    summary_wait

    summary_log_info \
        "Final summary completed"

    return 0
}

#============================================================
# Compatibility entry point
#============================================================

summary_main()
{
    summary
}
