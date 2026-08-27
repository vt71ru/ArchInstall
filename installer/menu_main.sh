#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  menu_main.sh
#
#  Main installer menu.
#
#  Workflow:
#
#    network
#      |
#    mirrors
#      |
#    disks
#      |
#    partition
#      |
#    filesystem
#      |
#    mount
#      |
#    packages_install
#      |
#    locale_generate
#      |
#    users
#      |
#    desktop
#      |
#    services
#      |
#    bootloader
#      |
#    summary
#============================================================

[[ -n "${MENU_MAIN_SH_LOADED:-}" ]] && return

readonly MENU_MAIN_SH_LOADED=1

#------------------------------------------------------------
# Menu state
#------------------------------------------------------------

MENU_SELECTED=0
MENU_EXIT_REQUESTED=0

#------------------------------------------------------------
# Stage state
#------------------------------------------------------------

MENU_STAGE_NETWORK=0
MENU_STAGE_MIRRORS=0
MENU_STAGE_DISK=0
MENU_STAGE_PARTITION=0
MENU_STAGE_FILESYSTEM=0
MENU_STAGE_MOUNT=0
MENU_STAGE_PACKAGES=0
MENU_STAGE_LOCALE=0
MENU_STAGE_USERS=0
MENU_STAGE_DESKTOP=0
MENU_STAGE_SERVICES=0
MENU_STAGE_BOOTLOADER=0
MENU_STAGE_SUMMARY=0

#------------------------------------------------------------
# Menu data
#------------------------------------------------------------

MENU_ITEMS=(
    "Welcome"
    "Keyboard"
    "Locale"
    "Network"
    "Mirrors"
    "Disk selection"
    "Partition disk"
    "Filesystem"
    "Mount system"
    "Install packages"
    "Generate locales"
    "Users"
    "Desktop"
    "Services"
    "Bootloader"
    "Summary"
    "Exit"
)

MENU_ACTIONS=(
    "welcome"
    "keyboard"
    "locale"
    "network"
    "mirrors"
    "disks"
    "partition"
    "filesystem"
    "mount_system"
    "packages_install"
    "locale_generate"
    "users"
    "desktop"
    "services"
    "bootloader"
    "summary"
    "exit"
)

#------------------------------------------------------------
# Clear screen
#------------------------------------------------------------

menu_main_clear_screen()
{
    printf '\033[2J'
    printf '\033[H'
}

#------------------------------------------------------------
# Reset stage state
#------------------------------------------------------------

menu_main_reset_stage_state()
{
    MENU_STAGE_NETWORK=0
    MENU_STAGE_MIRRORS=0
    MENU_STAGE_DISK=0
    MENU_STAGE_PARTITION=0
    MENU_STAGE_FILESYSTEM=0
    MENU_STAGE_MOUNT=0
    MENU_STAGE_PACKAGES=0
    MENU_STAGE_LOCALE=0
    MENU_STAGE_USERS=0
    MENU_STAGE_DESKTOP=0
    MENU_STAGE_SERVICES=0
    MENU_STAGE_BOOTLOADER=0
    MENU_STAGE_SUMMARY=0
}

#------------------------------------------------------------
# Check network state without displaying dialogs
#------------------------------------------------------------

menu_main_network_ready()
{
    local iface
    local address

    iface="$(
        config_get NETWORK_INTERFACE \
            2>/dev/null \
            || true
    )"

    [[ -n "$iface" ]] || \
        return 1

    [[ -e "/sys/class/net/${iface}" ]] || \
        return 1

    address="$(
        network_ip \
            "$iface" \
            2>/dev/null \
            || true
    )"

    [[ -n "$address" ]] || \
        return 1

    ip \
        route \
        get \
        1.1.1.1 \
        >/dev/null \
        2>&1 || \
        return 1

    getent \
        hosts \
        archlinux.org \
        >/dev/null \
        2>&1 || \
        return 1

    return 0
}

#------------------------------------------------------------
# Check mirrorlist state without displaying dialogs
#------------------------------------------------------------

menu_main_mirrorlist_ready()
{
    local mirrorlist="/etc/pacman.d/mirrorlist"

    [[ -f "$mirrorlist" ]] || \
        return 1

    [[ -s "$mirrorlist" ]] || \
        return 1

    grep \
        -Eq \
        '^[[:space:]]*Server[[:space:]]*=' \
        "$mirrorlist"
}

#------------------------------------------------------------
# Get stage status
#------------------------------------------------------------

menu_main_stage_status()
{
    local action="$1"

    case "$action" in
        network)
            (( MENU_STAGE_NETWORK )) && \
                printf '[OK]' || \
                printf '[--]'
            ;;

        mirrors)
            (( MENU_STAGE_MIRRORS )) && \
                printf '[OK]' || \
                printf '[--]'
            ;;

        disks)
            (( MENU_STAGE_DISK )) && \
                printf '[OK]' || \
                printf '[--]'
            ;;

        partition)
            (( MENU_STAGE_PARTITION )) && \
                printf '[OK]' || \
                printf '[--]'
            ;;

        filesystem)
            (( MENU_STAGE_FILESYSTEM )) && \
                printf '[OK]' || \
                printf '[--]'
            ;;

        mount_system)
            (( MENU_STAGE_MOUNT )) && \
                printf '[OK]' || \
                printf '[--]'
            ;;

        packages_install)
            (( MENU_STAGE_PACKAGES )) && \
                printf '[OK]' || \
                printf '[--]'
            ;;

        locale_generate)
            (( MENU_STAGE_LOCALE )) && \
                printf '[OK]' || \
                printf '[--]'
            ;;

        users)
            (( MENU_STAGE_USERS )) && \
                printf '[OK]' || \
                printf '[--]'
            ;;

        desktop)
            (( MENU_STAGE_DESKTOP )) && \
                printf '[OK]' || \
                printf '[--]'
            ;;

        services)
            (( MENU_STAGE_SERVICES )) && \
                printf '[OK]' || \
                printf '[--]'
            ;;

        bootloader)
            (( MENU_STAGE_BOOTLOADER )) && \
                printf '[OK]' || \
                printf '[--]'
            ;;

        summary)
            (( MENU_STAGE_SUMMARY )) && \
                printf '[OK]' || \
                printf '[--]'
            ;;

        *)
            printf '   '
            ;;
    esac
}

#------------------------------------------------------------
# Refresh stage state from system
#------------------------------------------------------------

menu_main_refresh_state()
{
    local root_part
    local root_type
    local filesystem
    local user_name
    local desktop
    local mirrorlist

    menu_main_reset_stage_state

    #--------------------------------------------------------
    # Network
    #--------------------------------------------------------

    if menu_main_network_ready
    then
        MENU_STAGE_NETWORK=1
    fi

    #--------------------------------------------------------
    # Mirrors
    #--------------------------------------------------------

    if menu_main_network_ready &&
       menu_main_mirrorlist_ready
    then
        MENU_STAGE_MIRRORS=1
    fi

    #--------------------------------------------------------
    # Disk
    #--------------------------------------------------------

    if config_has_target_disk
    then
        MENU_STAGE_DISK=1
    fi

    #--------------------------------------------------------
    # Partition
    #--------------------------------------------------------

    if config_has_root
    then
        MENU_STAGE_PARTITION=1
    fi

    #--------------------------------------------------------
    # Filesystem
    #--------------------------------------------------------

    root_part="$(
        config_get ROOT_PART \
            2>/dev/null \
            || true
    )"

    filesystem="$(
        config_get FILESYSTEM \
            2>/dev/null \
            || true
    )"

    if [[ -b "$root_part" ]]
    then
        root_type="$(
            blkid \
                -p \
                -s TYPE \
                -o value \
                "$root_part" \
                2>/dev/null \
                || true
        )"

        if [[ -n "$filesystem" &&
              "$root_type" == "$filesystem" ]]
        then
            MENU_STAGE_FILESYSTEM=1
        fi
    fi

    #--------------------------------------------------------
    # Mount
    #--------------------------------------------------------

    if mountpoint -q /mnt
    then
        MENU_STAGE_MOUNT=1

        if [[ "$(config_get CREATE_HOME)" == "1" ]]
        then
            if ! mountpoint -q /mnt/home
            then
                MENU_STAGE_MOUNT=0
            fi
        fi

        if [[ "$(config_get BOOT_MODE)" == "UEFI" ]]
        then
            if ! mountpoint -q /mnt/boot/efi
            then
                MENU_STAGE_MOUNT=0
            fi
        fi
    fi

    #--------------------------------------------------------
    # Packages
    #--------------------------------------------------------

    if [[ -x /mnt/usr/bin/bash &&
          -f /mnt/etc/fstab &&
          -d /mnt/var/lib/pacman/local ]]
    then
        MENU_STAGE_PACKAGES=1
    fi

    #--------------------------------------------------------
    # Locale
    #--------------------------------------------------------

    if [[ -f /mnt/etc/locale.conf &&
          -f /mnt/etc/vconsole.conf ]]
    then
        MENU_STAGE_LOCALE=1
    fi

    #--------------------------------------------------------
    # Users
    #--------------------------------------------------------

    if [[ -v "CONFIG[USER_NAME]" ]]
    then
        user_name="$(
            config_get USER_NAME \
                2>/dev/null \
                || true
        )"

        if [[ -n "$user_name" &&
              -f /mnt/etc/passwd ]]
        then
            if arch-chroot \
                /mnt \
                getent \
                passwd \
                "$user_name" \
                >/dev/null \
                2>&1
            then
                MENU_STAGE_USERS=1
            fi
        fi
    fi

    #--------------------------------------------------------
    # Desktop
    #--------------------------------------------------------

    desktop="$(
        config_get DESKTOP \
            2>/dev/null \
            || true
    )"

    if [[ -z "$desktop" ]]
    then
        MENU_STAGE_DESKTOP=1
    else
        case "$desktop" in
            gnome)
                if arch-chroot \
                    /mnt \
                    systemctl \
                    is-enabled \
                    gdm.service \
                    >/dev/null \
                    2>&1
                then
                    MENU_STAGE_DESKTOP=1
                fi
                ;;

            kde)
                if arch-chroot \
                    /mnt \
                    systemctl \
                    is-enabled \
                    sddm.service \
                    >/dev/null \
                    2>&1
                then
                    MENU_STAGE_DESKTOP=1
                fi
                ;;

            xfce)
                if arch-chroot \
                    /mnt \
                    systemctl \
                    is-enabled \
                    lightdm.service \
                    >/dev/null \
                    2>&1
                then
                    MENU_STAGE_DESKTOP=1
                fi
                ;;
        esac
    fi

    #--------------------------------------------------------
    # Services
    #--------------------------------------------------------

    if arch-chroot \
        /mnt \
        systemctl \
        is-enabled \
        NetworkManager.service \
        >/dev/null \
        2>&1
    then
        MENU_STAGE_SERVICES=1
    fi

    #--------------------------------------------------------
    # Bootloader
    #--------------------------------------------------------

    if [[ -f /mnt/boot/grub/grub.cfg ]]
    then
        case "$(config_get BOOT_MODE)" in
            UEFI)
                if [[ -f /mnt/boot/efi/EFI/ARCHLINUX/grubx64.efi ]]
                then
                    MENU_STAGE_BOOTLOADER=1
                fi
                ;;

            BIOS)
                if [[ -d /mnt/boot/grub/i386-pc ]]
                then
                    MENU_STAGE_BOOTLOADER=1
                fi
                ;;
        esac
    fi

    #--------------------------------------------------------
    # Summary
    #--------------------------------------------------------

    if (( MENU_STAGE_BOOTLOADER == 1 ))
    then
        MENU_STAGE_SUMMARY=1
    fi
}

#------------------------------------------------------------
# Draw menu
#------------------------------------------------------------

menu_main_draw()
{
    local row=3
    local index
    local action
    local status

    menu_main_clear_screen

    titlebar_draw \
        "${APP_NAME:-Arch Installer}"

    for index in "${!MENU_ITEMS[@]}"
    do
        action="${MENU_ACTIONS[index]}"

        status="$(
            menu_main_stage_status \
                "$action"
        )"

        cursor_move \
            "$row" \
            4

        if (( index == MENU_SELECTED ))
        then
            printf \
                '> %-24s %s' \
                "${MENU_ITEMS[index]}" \
                "$status"
        else
            printf \
                '  %-24s %s' \
                "${MENU_ITEMS[index]}" \
                "$status"
        fi

        ((row += 1))
    done

    statusbar_draw \
        "Up/Down Navigate   Enter Select   Esc Exit"

    screen_refresh
}

#------------------------------------------------------------
# Navigation
#------------------------------------------------------------

menu_main_next()
{
    if (( MENU_SELECTED < ${#MENU_ITEMS[@]} - 1 ))
    then
        ((MENU_SELECTED += 1))
    else
        MENU_SELECTED=0
    fi
}

menu_main_previous()
{
    if (( MENU_SELECTED > 0 ))
    then
        ((MENU_SELECTED -= 1))
    else
        MENU_SELECTED=$(( ${#MENU_ITEMS[@]} - 1 ))
    fi
}

#------------------------------------------------------------
# Check target disk
#------------------------------------------------------------

menu_main_require_disk()
{
    if ! config_has_target_disk
    then
        dialog_error \
            "Select target disk first"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Check network
#------------------------------------------------------------

menu_main_require_network()
{
    local iface
    local address

    iface="$(
        config_get NETWORK_INTERFACE \
            2>/dev/null \
            || true
    )"

    if [[ -z "$iface" ]]
    then
        dialog_error \
            "Configure network first"

        return 1
    fi

    if [[ ! -e "/sys/class/net/${iface}" ]]
    then
        dialog_error \
            "Configured network interface does not exist: ${iface}"

        return 1
    fi

    address="$(
        network_ip \
            "$iface" \
            2>/dev/null \
            || true
    )"

    if [[ -z "$address" ]]
    then
        dialog_error \
            "Network interface has no IPv4 address: ${iface}"

        return 1
    fi

    if ! ip \
        route \
        get \
        1.1.1.1 \
        >/dev/null \
        2>&1
    then
        dialog_error \
            "Default network route is unavailable"

        return 1
    fi

    if ! getent \
        hosts \
        archlinux.org \
        >/dev/null \
        2>&1
    then
        dialog_error \
            "DNS resolution is unavailable"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Check mirrors
#------------------------------------------------------------

menu_main_require_mirrors()
{
    local mirrorlist="/etc/pacman.d/mirrorlist"

    menu_main_require_network || \
        return 1

    if [[ ! -f "$mirrorlist" ]]
    then
        dialog_error \
            "Mirrorlist is missing: ${mirrorlist}"

        return 1
    fi

    if [[ ! -s "$mirrorlist" ]]
    then
        dialog_error \
            "Mirrorlist is empty: ${mirrorlist}"

        return 1
    fi

    if ! grep \
        -Eq \
        '^[[:space:]]*Server[[:space:]]*=' \
        "$mirrorlist"
    then
        dialog_error \
            "Mirrorlist contains no active Server entries"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Check partitions
#------------------------------------------------------------

menu_main_require_partition()
{
    menu_main_require_disk || \
        return 1

    if ! config_has_root
    then
        dialog_error \
            "Create disk partitions first"

        return 1
    fi

    if [[ ! -b "$(config_get ROOT_PART)" ]]
    then
        dialog_error \
            "Root partition does not exist"

        return 1
    fi

    if [[ "$(config_get BOOT_MODE)" == "UEFI" ]]
    then
        if [[ ! -b "$(config_get EFI_PART)" ]]
        then
            dialog_error \
                "EFI partition does not exist"

            return 1
        fi
    fi

    if [[ "$(config_get BOOT_MODE)" == "BIOS" &&
          "$(config_get PARTITION_TABLE)" == "GPT" ]]
    then
        if [[ ! -b "$(config_get BIOS_PART)" ]]
        then
            dialog_error \
                "BIOS boot partition does not exist"

            return 1
        fi
    fi

    return 0
}

#------------------------------------------------------------
# Check filesystem
#------------------------------------------------------------

menu_main_require_filesystem()
{
    local root_part
    local expected
    local actual

    menu_main_require_partition || \
        return 1

    root_part="$(
        config_get ROOT_PART
    )"

    expected="$(
        config_get FILESYSTEM
    )"

    actual="$(
        blkid \
            -p \
            -s TYPE \
            -o value \
            "$root_part" \
            2>/dev/null \
            || true
    )"

    if [[ -z "$actual" ]]
    then
        dialog_error \
            "Root filesystem has not been formatted"

        return 1
    fi

    if [[ "$actual" != "$expected" ]]
    then
        dialog_error \
            "Wrong root filesystem: expected ${expected}, got ${actual}"

        return 1
    fi

    if [[ "$(config_get BOOT_MODE)" == "UEFI" ]]
    then
        local efi_type

        efi_type="$(
            blkid \
                -p \
                -s TYPE \
                -o value \
                "$(config_get EFI_PART)" \
                2>/dev/null \
                || true
        )"

        if [[ "$efi_type" != "vfat" ]]
        then
            dialog_error \
                "EFI partition is not formatted as vfat"

            return 1
        fi
    fi

    return 0
}

#------------------------------------------------------------
# Check mount
#------------------------------------------------------------

menu_main_require_mount()
{
    menu_main_require_filesystem || \
        return 1

    if ! mountpoint -q /mnt
    then
        dialog_error \
            "Mount the target system first"

        return 1
    fi

    if [[ "$(config_get CREATE_HOME)" == "1" ]]
    then
        if ! mountpoint -q /mnt/home
        then
            dialog_error \
                "Mount the home partition first"

            return 1
        fi
    fi

    if [[ "$(config_get BOOT_MODE)" == "UEFI" ]]
    then
        if ! mountpoint -q /mnt/boot/efi
        then
            dialog_error \
                "Mount the EFI partition first"

            return 1
        fi
    fi

    return 0
}

#------------------------------------------------------------
# Check packages
#------------------------------------------------------------

menu_main_require_packages()
{
    menu_main_require_mount || \
        return 1

    if [[ ! -x /mnt/usr/bin/bash ]]
    then
        dialog_error \
            "Install the base system first"

        return 1
    fi

    if [[ ! -d /mnt/var/lib/pacman/local ]]
    then
        dialog_error \
            "Target package database is missing"

        return 1
    fi

    if [[ ! -f /mnt/etc/fstab ]]
    then
        dialog_error \
            "Target fstab is missing"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Check locale
#------------------------------------------------------------

menu_main_require_locale()
{
    menu_main_require_packages || \
        return 1

    if [[ ! -f /mnt/etc/locale.gen ]]
    then
        dialog_error \
            "Target locale.gen is missing"

        return 1
    fi

    if [[ ! -f /mnt/etc/locale.conf ]]
    then
        dialog_error \
            "Generate system locales first"

        return 1
    fi

    if [[ ! -f /mnt/etc/vconsole.conf ]]
    then
        dialog_error \
            "Keyboard configuration is missing"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Check users
#------------------------------------------------------------

menu_main_require_users()
{
    local user_name

    menu_main_require_locale || \
        return 1

    if [[ ! -v "CONFIG[USER_NAME]" ]]
    then
        dialog_error \
            "User configuration is missing"

        return 1
    fi

    user_name="$(
        config_get USER_NAME
    )"

    if [[ -z "$user_name" ]]
    then
        dialog_error \
            "User name is empty"

        return 1
    fi

    if ! arch-chroot \
        /mnt \
        getent \
        passwd \
        "$user_name" \
        >/dev/null \
        2>&1
    then
        dialog_error \
            "Create the user first"

        return 1
    fi

    if [[ ! -f /mnt/etc/sudoers.d/10-wheel ]]
    then
        dialog_error \
            "Configure sudo for the user first"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Check desktop
#------------------------------------------------------------

menu_main_require_desktop()
{
    local desktop

    menu_main_require_users || \
        return 1

    desktop="$(
        config_get DESKTOP \
            2>/dev/null \
            || true
    )"

    if [[ -z "$desktop" ]]
    then
        return 0
    fi

    case "$desktop" in
        gnome)
            if ! arch-chroot \
                /mnt \
                systemctl \
                is-enabled \
                gdm.service \
                >/dev/null \
                2>&1
            then
                dialog_error \
                    "Configure GNOME display manager first"

                return 1
            fi
            ;;

        kde)
            if ! arch-chroot \
                /mnt \
                systemctl \
                is-enabled \
                sddm.service \
                >/dev/null \
                2>&1
            then
                dialog_error \
                    "Configure KDE display manager first"

                return 1
            fi
            ;;

        xfce)
            if ! arch-chroot \
                /mnt \
                systemctl \
                is-enabled \
                lightdm.service \
                >/dev/null \
                2>&1
            then
                dialog_error \
                    "Configure Xfce display manager first"

                return 1
            fi
            ;;

        *)
            dialog_error \
                "Unsupported desktop: ${desktop}"

            return 1
            ;;
    esac

    return 0
}

#------------------------------------------------------------
# Check services
#------------------------------------------------------------

menu_main_require_services()
{
    menu_main_require_desktop || \
        return 1

    if ! arch-chroot \
        /mnt \
        systemctl \
        is-enabled \
        NetworkManager.service \
        >/dev/null \
        2>&1
    then
        dialog_error \
            "Configure system services first"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Check bootloader
#------------------------------------------------------------

menu_main_require_bootloader()
{
    local boot_mode

    menu_main_require_services || \
        return 1

    if [[ ! -f /mnt/etc/fstab ]]
    then
        dialog_error \
            "fstab is missing"

        return 1
    fi

    if [[ ! -f /mnt/boot/grub/grub.cfg ]]
    then
        dialog_error \
            "GRUB configuration is missing"

        return 1
    fi

    boot_mode="$(
        config_get BOOT_MODE
    )"

    case "$boot_mode" in
        UEFI)
            if [[ ! -f /mnt/boot/efi/EFI/ARCHLINUX/grubx64.efi ]]
            then
                dialog_error \
                    "UEFI GRUB binary is missing"

                return 1
            fi
            ;;

        BIOS)
            if [[ ! -d /mnt/boot/grub/i386-pc ]]
            then
                dialog_error \
                    "BIOS GRUB files are missing"

                return 1
            fi
            ;;

        *)
            dialog_error \
                "Invalid boot mode: ${boot_mode}"

            return 1
            ;;
    esac

    return 0
}

#------------------------------------------------------------
# Action prerequisites
#------------------------------------------------------------

menu_main_check_action()
{
    local action="$1"

    case "$action" in
        welcome)
            return 0
            ;;

        keyboard)
            return 0
            ;;

        locale)
            return 0
            ;;

        network)
            return 0
            ;;

        mirrors)
            menu_main_require_mirrors
            ;;

        disks)
            return 0
            ;;

        partition)
            menu_main_require_disk
            ;;

        filesystem)
            menu_main_require_partition
            ;;

        mount_system)
            menu_main_require_filesystem
            ;;

        packages_install)
            menu_main_require_mirrors || \
                return 1

            menu_main_require_mount
            ;;

        locale_generate)
            menu_main_require_packages
            ;;

        users)
            menu_main_require_locale
            ;;

        desktop)
            menu_main_require_users
            ;;

        services)
            menu_main_require_desktop
            ;;

        bootloader)
            menu_main_require_services
            ;;

        summary)
            menu_main_require_bootloader
            ;;

        exit)
            return 0
            ;;

        *)
            dialog_error \
                "Unknown menu action: ${action}"

            return 1
            ;;
    esac
}

#------------------------------------------------------------
# Update stage after action
#------------------------------------------------------------

menu_main_mark_stage()
{
    local action="$1"

    case "$action" in
        network)
            MENU_STAGE_NETWORK=1
            ;;

        mirrors)
            MENU_STAGE_MIRRORS=1
            ;;

        disks)
            MENU_STAGE_DISK=1
            ;;

        partition)
            MENU_STAGE_PARTITION=1
            ;;

        filesystem)
            MENU_STAGE_FILESYSTEM=1
            ;;

        mount_system)
            MENU_STAGE_MOUNT=1
            ;;

        packages_install)
            MENU_STAGE_PACKAGES=1
            ;;

        locale_generate)
            MENU_STAGE_LOCALE=1
            ;;

        users)
            MENU_STAGE_USERS=1
            ;;

        desktop)
            MENU_STAGE_DESKTOP=1
            ;;

        services)
            MENU_STAGE_SERVICES=1
            ;;

        bootloader)
            MENU_STAGE_BOOTLOADER=1
            ;;

        summary)
            MENU_STAGE_SUMMARY=1
            ;;
    esac
}

#------------------------------------------------------------
# Execute selected action
#------------------------------------------------------------

menu_main_execute()
{
    local action
    local result

    action="${MENU_ACTIONS[MENU_SELECTED]}"

    logger_info \
        "Menu action selected: ${action}"

    if [[ "$action" == "exit" ]]
    then
        MENU_EXIT_REQUESTED=1
        return 0
    fi

    if ! declare -F "$action" \
        >/dev/null \
        2>&1
    then
        dialog_error \
            "Missing action function: ${action}"

        logger_error \
            "Missing action function: ${action}"

        return 0
    fi

    if ! menu_main_check_action "$action"
    then
        return 0
    fi

    menu_main_clear_screen
    screen_refresh

    #
    # Calling the action inside an if statement prevents errexit
    # from terminating the main menu unexpectedly.
    #

    if "$action"
    then
        result=0
    else
        result=$?
    fi

    menu_main_clear_screen
    screen_refresh

    if (( result == 0 ))
    then
        menu_main_mark_stage \
            "$action"

        menu_main_refresh_state

        logger_info \
            "Menu action completed: ${action}"
    else
        logger_error \
            "Menu action failed: ${action}, exit=${result}"

        dialog_error \
            "Action failed: ${action}"
    fi

    #
    # An action error must not terminate the main menu.
    #

    return 0
}

#------------------------------------------------------------
# Run complete installation
#------------------------------------------------------------

menu_main_install_all()
{
    local action

    for action in \
        network \
        mirrors \
        disks \
        partition \
        filesystem \
        mount_system \
        packages_install \
        locale_generate \
        users \
        desktop \
        services \
        bootloader \
        summary
    do
        logger_info \
            "Automatic stage: ${action}"

        if ! declare -F "$action" \
            >/dev/null \
            2>&1
        then
            dialog_error \
                "Missing installation stage: ${action}"

            logger_error \
                "Missing installation stage: ${action}"

            return 1
        fi

        if ! menu_main_check_action "$action"
        then
            logger_error \
                "Prerequisites failed for: ${action}"

            dialog_error \
                "Prerequisites failed for: ${action}"

            return 1
        fi

        if "$action"
        then
            menu_main_mark_stage \
                "$action"
        else
            logger_error \
                "Automatic installation stopped at: ${action}"

            dialog_error \
                "Installation stopped at:\n${action}"

            return 1
        fi
    done

    menu_main_refresh_state

    return 0
}

#------------------------------------------------------------
# Main loop
#------------------------------------------------------------

menu_main()
{
    local event

    MENU_SELECTED=0
    MENU_EXIT_REQUESTED=0

    menu_main_refresh_state

    logger_info \
        "Main menu started"

    while (( ! MENU_EXIT_REQUESTED ))
    do
        menu_main_refresh_state
        menu_main_draw

        event="$(
            event_read
        )"

        case "$event" in
            "$EVENT_UP")
                menu_main_previous
                ;;

            "$EVENT_DOWN")
                menu_main_next
                ;;

            "$EVENT_SELECT")
                menu_main_execute
                ;;

            "$EVENT_BACK")
                MENU_EXIT_REQUESTED=1
                ;;
        esac
    done

    menu_main_clear_screen
    screen_refresh

    logger_info \
        "Main menu finished"

    return 0
}
