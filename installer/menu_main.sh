#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  menu_main.sh
#
#  Главное меню установщика.
#
#  Ответственность:
#   • Отображение меню
#   • Навигация
#   • Запуск подготовительных модулей
#   • Контроль порядка установки
#   • Контроль состояния стадий
#   • Обработка ошибок без выхода из меню
#
#  Критическая цепочка:
#
#   disks
#     ↓
#   partition
#     ↓
#   filesystem
#     ↓
#   mount
#     ↓
#   packages_install
#     ↓
#   locale_generate
#     ↓
#   users
#     ↓
#   desktop
#     ↓
#   services
#     ↓
#   bootloader
#     ↓
#   summary
#
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
    "mount"
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
# Get stage status
#------------------------------------------------------------

menu_main_stage_status()
{
    local action="$1"

    case "$action" in
        disks)
            (( MENU_STAGE_DISK )) && printf '[OK]' || printf '[--]'
            ;;
        partition)
            (( MENU_STAGE_PARTITION )) && printf '[OK]' || printf '[--]'
            ;;
        filesystem)
            (( MENU_STAGE_FILESYSTEM )) && printf '[OK]' || printf '[--]'
            ;;
        mount)
            (( MENU_STAGE_MOUNT )) && printf '[OK]' || printf '[--]'
            ;;
        packages_install)
            (( MENU_STAGE_PACKAGES )) && printf '[OK]' || printf '[--]'
            ;;
        locale_generate)
            (( MENU_STAGE_LOCALE )) && printf '[OK]' || printf '[--]'
            ;;
        users)
            (( MENU_STAGE_USERS )) && printf '[OK]' || printf '[--]'
            ;;
        desktop)
            (( MENU_STAGE_DESKTOP )) && printf '[OK]' || printf '[--]'
            ;;
        services)
            (( MENU_STAGE_SERVICES )) && printf '[OK]' || printf '[--]'
            ;;
        bootloader)
            (( MENU_STAGE_BOOTLOADER )) && printf '[OK]' || printf '[--]'
            ;;
        summary)
            (( MENU_STAGE_SUMMARY )) && printf '[OK]' || printf '[--]'
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
    if config_has_target_disk
    then
        MENU_STAGE_DISK=1
    fi

    if config_has_root
    then
        MENU_STAGE_PARTITION=1
    fi

    if [[ -b "$(config_get ROOT_PART)" ]]
    then
        local root_type

        root_type="$(
            blkid \
                -s TYPE \
                -o value \
                "$(config_get ROOT_PART)" \
                2>/dev/null \
                || true
        )"

        if [[ -n "$root_type" ]]
        then
            MENU_STAGE_FILESYSTEM=1
        fi
    fi

    if mountpoint -q /mnt
    then
        MENU_STAGE_MOUNT=1
    fi

    if [[ -x /mnt/usr/bin/bash &&
          -f /mnt/etc/fstab ]]
    then
        MENU_STAGE_PACKAGES=1
    fi

    if [[ -f /mnt/etc/locale.conf &&
          -f /mnt/etc/vconsole.conf ]]
    then
        MENU_STAGE_LOCALE=1
    fi

    if [[ -v "CONFIG[USER_NAME]" ]]
    then
        local user_name

        user_name="$(config_get USER_NAME)"

        if [[ -n "$user_name" &&
              -f /mnt/etc/passwd ]]
        then
            if arch-chroot \
                /mnt \
                getent passwd \
                "$user_name" \
                >/dev/null 2>&1
            then
                MENU_STAGE_USERS=1
            fi
        fi
    fi

    if [[ -n "$(config_get DESKTOP)" ]]
    then
        case "$(config_get DESKTOP)" in
            gnome)
                if arch-chroot \
                    /mnt \
                    systemctl \
                    is-enabled \
                    gdm.service \
                    >/dev/null 2>&1
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
                    >/dev/null 2>&1
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
                    >/dev/null 2>&1
                then
                    MENU_STAGE_DESKTOP=1
                fi
                ;;
        esac
    else
        MENU_STAGE_DESKTOP=1
    fi

    if arch-chroot \
        /mnt \
        systemctl \
        is-enabled \
        NetworkManager.service \
        >/dev/null 2>&1
    then
        MENU_STAGE_SERVICES=1
    fi

    if [[ -f /mnt/boot/grub/grub.cfg ]]
    then
        MENU_STAGE_BOOTLOADER=1
    fi
}

#------------------------------------------------------------
# Draw
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
        "↑↓ Navigate   Enter Select   Esc Exit"

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
}

#------------------------------------------------------------
# Check filesystem
#------------------------------------------------------------

menu_main_require_filesystem()
{
    menu_main_require_partition || \
        return 1

    local filesystem

    filesystem="$(
        blkid \
            -s TYPE \
            -o value \
            "$(config_get ROOT_PART)" \
            2>/dev/null \
            || true
    )"

    if [[ -z "$filesystem" ]]
    then
        dialog_error \
            "Root filesystem has not been formatted"

        return 1
    fi
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

    if [[ ! -f /mnt/etc/fstab ]]
    then
        dialog_error \
            "Target fstab is missing"

        return 1
    fi
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
}

#------------------------------------------------------------
# Check users
#------------------------------------------------------------

menu_main_require_users()
{
    menu_main_require_locale || \
        return 1

    if [[ ! -v "CONFIG[USER_NAME]" ]]
    then
        dialog_error \
            "User configuration is missing"

        return 1
    fi

    local user_name

    user_name="$(config_get USER_NAME)"

    if [[ -z "$user_name" ]]
    then
        dialog_error \
            "User name is empty"

        return 1
    fi

    if ! arch-chroot \
        /mnt \
        getent passwd \
        "$user_name" \
        >/dev/null 2>&1
    then
        dialog_error \
            "Create the user first"

        return 1
    fi
}

#------------------------------------------------------------
# Check desktop
#------------------------------------------------------------

menu_main_require_desktop()
{
    menu_main_require_users || \
        return 1

    local desktop

    desktop="$(config_get DESKTOP)"

    if [[ -z "$desktop" ]]
    then
        return 0
    fi

    case "$desktop" in
        gnome)
            arch-chroot \
                /mnt \
                systemctl \
                is-enabled \
                gdm.service \
                >/dev/null 2>&1
            ;;
        kde)
            arch-chroot \
                /mnt \
                systemctl \
                is-enabled \
                sddm.service \
                >/dev/null 2>&1
            ;;
        xfce)
            arch-chroot \
                /mnt \
                systemctl \
                is-enabled \
                lightdm.service \
                >/dev/null 2>&1
            ;;
        *)
            dialog_error \
                "Unsupported desktop: ${desktop}"

            return 1
            ;;
    esac || {
        dialog_error \
            "Configure desktop first"

        return 1
    }
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
        >/dev/null 2>&1
    then
        dialog_error \
            "Configure system services first"

        return 1
    fi
}

#------------------------------------------------------------
# Check bootloader
#------------------------------------------------------------

menu_main_require_bootloader()
{
    menu_main_require_services || \
        return 1

    if [[ ! -f /mnt/etc/fstab ]]
    then
        dialog_error \
            "fstab is missing"

        return 1
    fi
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
            return 0
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
        mount)
            menu_main_require_filesystem
            ;;
        packages_install)
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
        disks)
            MENU_STAGE_DISK=1
            ;;
        partition)
            MENU_STAGE_PARTITION=1
            ;;
        filesystem)
            MENU_STAGE_FILESYSTEM=1
            ;;
        mount)
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
# Execute
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
        >/dev/null 2>&1
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

    set +e

    "$action"

    result=$?

    set -e

    menu_main_clear_screen

    screen_refresh

    if (( result == 0 ))
    then
        menu_main_mark_stage \
            "$action"

        logger_info \
            "Menu action completed: ${action}"
    else
        logger_error \
            "Menu action failed: ${action}, exit=${result}"

        dialog_error \
            "Action failed: ${action}"
    fi

    #
    # Ошибка action не завершает главное меню.
    #

    return 0
}

#------------------------------------------------------------
# Run complete installation
#------------------------------------------------------------

menu_main_install_all()
{
    local action
    local result

    for action in \
        disks \
        partition \
        filesystem \
        mount \
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
            >/dev/null 2>&1
        then
            dialog_error \
                "Missing installation stage: ${action}"

            return 1
        fi

        "$action"

        result=$?

        if (( result != 0 ))
        then
            logger_error \
                "Automatic installation stopped at: ${action}"

            dialog_error \
                "Installation stopped at:\n${action}"

            return "$result"
        fi

        menu_main_mark_stage \
            "$action"
    done

    return 0
}

#------------------------------------------------------------
# Main loop
#------------------------------------------------------------

menu_main()
{
    local event

    MENU_EXIT_REQUESTED=0

    menu_main_refresh_state

    logger_info \
        "Main menu started"

    while (( ! MENU_EXIT_REQUESTED ))
    do
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
}#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  menu_main.sh
#
#  Главное меню установщика.
#
#  Ответственность:
#   • Навигация по разделам installer
#   • Проверка зависимостей workflow
#   • Запуск installer-модулей
#   • Контроль порядка критических стадий
#   • Обработка ошибок без выхода из меню
#
#  Критическая цепочка:
#
#   disks
#     ↓
#   partition
#     ↓
#   filesystem
#     ↓
#   mount
#     ↓
#   packages
#     ↓
#   bootloader
#
#============================================================

[[ -n "${MENU_MAIN_SH_LOADED:-}" ]] && return

readonly MENU_MAIN_SH_LOADED=1

#------------------------------------------------------------
# Menu state
#------------------------------------------------------------

MENU_SELECTED=0
MENU_EXIT_REQUESTED=0

#------------------------------------------------------------
# Menu data
#------------------------------------------------------------

MENU_ITEMS=(
    "Welcome"
    "Keyboard"
    "Locale"
    "Locale generation"
    "Network"
    "Mirrors"
    "Disk selection"
    "Partition disk"
    "Filesystem"
    "Mount system"
    "Install packages"
    "Bootloader"
    "Users"
    "Desktop"
    "Services"
    "Summary"
    "Exit"
)

MENU_ACTIONS=(
    "welcome"
    "keyboard"
    "locale"
    "locale_generate"
    "network"
    "mirrors"
    "disks"
    "partition"
    "filesystem"
    "mount"
    "packages_install"
    "bootloader"
    "users"
    "desktop"
    "services"
    "summary"
    "exit"
)

#------------------------------------------------------------
# Colors / status
#------------------------------------------------------------

menu_main_item_status()
{
    local action="$1"

    case "$action" in
        disks)
            if config_has_target_disk
            then
                printf '[OK]'
            else
                printf '[--]'
            fi
            ;;
        partition)
            if config_has_root
            then
                printf '[OK]'
            else
                printf '[--]'
            fi
            ;;
        filesystem)
            if config_has_root &&
               [[ "$(config_get FILESYSTEM)" == "ext4" ||
                  "$(config_get FILESYSTEM)" == "btrfs" ||
                  "$(config_get FILESYSTEM)" == "xfs" ||
                  "$(config_get FILESYSTEM)" == "f2fs" ]]
            then
                printf '[OK]'
            else
                printf '[--]'
            fi
            ;;
        mount)
            if mountpoint -q /mnt
            then
                printf '[OK]'
            else
                printf '[--]'
            fi
            ;;
        packages_install)
            if [[ -x /mnt/usr/bin/bash ]]
            then
                printf '[OK]'
            else
                printf '[--]'
            fi
            ;;
        bootloader)
            if [[ -f /mnt/etc/fstab &&
                  -d /mnt/boot/grub ]]
            then
                printf '[OK]'
            else
                printf '[--]'
            fi
            ;;
        *)
            printf '   '
            ;;
    esac
}

#------------------------------------------------------------
# Clear screen
#------------------------------------------------------------

menu_main_clear_screen()
{
    printf '\033[2J'
    printf '\033[H'
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
            menu_main_item_status \
                "$action"
        )"

        cursor_move \
            "$row" \
            5

        if [[ "$index" -eq "$MENU_SELECTED" ]]
        then
            printf '> %-24s %s' \
                "${MENU_ITEMS[index]}" \
                "$status"
        else
            printf '  %-24s %s' \
                "${MENU_ITEMS[index]}" \
                "$status"
        fi

        ((row++))
    done

    statusbar_draw \
        "↑↓ Navigate   Enter Select   Esc Exit"

    screen_refresh
}

#------------------------------------------------------------
# Navigation
#------------------------------------------------------------

menu_main_next()
{
    ((MENU_SELECTED++))

    if (( MENU_SELECTED >= ${#MENU_ITEMS[@]} ))
    then
        MENU_SELECTED=0
    fi
}

menu_main_previous()
{
    ((MENU_SELECTED--))

    if (( MENU_SELECTED < 0 ))
    then
        MENU_SELECTED=$(( ${#MENU_ITEMS[@]} - 1 ))
    fi
}

#------------------------------------------------------------
# Critical workflow prerequisites
#------------------------------------------------------------

menu_main_check_partition()
{
    if ! config_has_target_disk
    then
        dialog_error \
            "Select target disk first"

        return 1
    fi

    return 0
}

menu_main_check_filesystem()
{
    if ! config_has_root
    then
        dialog_error \
            "Create disk partitions first"

        return 1
    fi

    return 0
}

menu_main_check_mount()
{
    if ! config_has_root
    then
        dialog_error \
            "Create disk partitions first"

        return 1
    fi

    if [[ "$(config_get BOOT_MODE)" == "UEFI" &&
          ! config_has_efi ]]
    then
        dialog_error \
            "EFI partition is not configured"

        return 1
    fi

    local root_type

    root_type="$(
        blkid \
            -s TYPE \
            -o value \
            "$(config_get ROOT_PART)" \
            2>/dev/null \
            || true
    )"

    if [[ -z "$root_type" ]]
    then
        dialog_error \
            "Root filesystem is not formatted"

        return 1
    fi

    return 0
}

menu_main_check_packages()
{
    if ! mountpoint -q /mnt
    then
        dialog_error \
            "Mount the target system first"

        return 1
    fi

    return 0
}

menu_main_check_bootloader()
{
    if [[ ! -x /mnt/usr/bin/bash ]]
    then
        dialog_error \
            "Install the base system first"

        return 1
    fi

    if [[ ! -f /mnt/etc/fstab ]]
    then
        dialog_error \
            "fstab is missing"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Action prerequisites
#------------------------------------------------------------

menu_main_check_action()
{
    local action="$1"

    case "$action" in
        partition)
            menu_main_check_partition
            ;;
        filesystem)
            menu_main_check_filesystem
            ;;
        mount)
            menu_main_check_mount
            ;;
        packages_install)
            menu_main_check_packages
            ;;
        bootloader)
            menu_main_check_bootloader
            ;;
        *)
            return 0
            ;;
    esac
}

#------------------------------------------------------------
# Execute action
#------------------------------------------------------------

menu_main_execute()
{
    local action
    local result

    action="${MENU_ACTIONS[MENU_SELECTED]}"

    logger_info \
        "Menu action: ${action}"

    if [[ "$action" == "exit" ]]
    then
        MENU_EXIT_REQUESTED=1
        return 0
    fi

    if ! declare -F "$action" >/dev/null 2>&1
    then
        dialog_error \
            "Missing installer action: ${action}"

        logger_error \
            "Missing installer action: ${action}"

        return 0
    fi

    if ! menu_main_check_action "$action"
    then
        return 0
    fi

    menu_main_clear_screen

    screen_refresh

    "$action"

    result=$?

    menu_main_clear_screen

    screen_refresh

    if (( result != 0 ))
    then
        logger_error \
            "Menu action failed: ${action} exit=${result}"

        dialog_error \
            "Action failed: ${action}"
    else
        logger_info \
            "Menu action completed: ${action}"
    fi

    #
    # КРИТИЧНО:
    # Ошибка действия НЕ должна означать выход из меню.
    #

    return 0
}

#------------------------------------------------------------
# Main event loop
#------------------------------------------------------------

menu_main()
{
    local event

    MENU_EXIT_REQUESTED=0

    logger_info \
        "Main menu started"

    while (( ! MENU_EXIT_REQUESTED ))
    do
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