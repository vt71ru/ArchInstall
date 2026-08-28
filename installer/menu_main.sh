#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# menu_main.sh
#
# Главное меню Arch Installer.
#
# Ответственность:
#   • Отображение главного меню
#   • Навигация
#   • Запуск installer-модулей
#   • Возврат результата
#
# Не содержит:
#   • TTY logic
#   • stty
#   • ANSI-коды
#   • keyboard parsing
#   • drawing implementation
#   • partition logic
#   • filesystem logic
#   • package logic
#   • bootloader logic
#
# Зависимости:
#   • tui.sh
#
#============================================================

if [[ -n "${MENU_MAIN_SH_LOADED:-}" ]]
then
    return 0
fi

readonly MENU_MAIN_SH_LOADED=1

#============================================================
# Paths
#============================================================

MENU_MAIN_ROOT="${INSTALLER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

readonly MENU_MAIN_ROOT

MENU_MAIN_MODULES="$MENU_MAIN_ROOT/modules"

readonly MENU_MAIN_MODULES

#============================================================
# Module loader
#============================================================

menu_main_load_module()
{
    local module="$1"
    local file="$MENU_MAIN_MODULES/$module"

    if [[ ! -f "$file" ]]
    then
        logger_error \
            "Main menu: module not found: $file"

        return 1
    fi

    # shellcheck disable=SC1090
    source "$file"

    return 0
}

#============================================================
# Header
#============================================================

menu_main_header()
{
    tui_clear

    titlebar_draw \
        "Arch Installer"

    tui_move 3 5

    color_info \
        "Arch Linux Installation System"

    tui_move 4 5

    tui_print \
        "Select an operation"
}

#============================================================
# Installation modules
#============================================================

menu_main_partition()
{
    menu_main_load_module \
        "partition.sh" || \
        return 1

    if ! declare -F partition_main >/dev/null 2>&1
    then
        logger_error \
            "partition.sh does not provide partition_main()"

        return 1
    fi

    partition_main
}

menu_main_filesystem()
{
    menu_main_load_module \
        "filesystem.sh" || \
        return 1

    if ! declare -F filesystem_main >/dev/null 2>&1
    then
        logger_error \
            "filesystem.sh does not provide filesystem_main()"

        return 1
    fi

    filesystem_main
}

menu_main_mount()
{
    menu_main_load_module \
        "mount.sh" || \
        return 1

    if ! declare -F mount_main >/dev/null 2>&1
    then
        logger_error \
            "mount.sh does not provide mount_main()"

        return 1
    fi

    mount_main
}

menu_main_packages()
{
    menu_main_load_module \
        "packages.sh" || \
        return 1

    if ! declare -F packages_main >/dev/null 2>&1
    then
        logger_error \
            "packages.sh does not provide packages_main()"

        return 1
    fi

    packages_main
}

menu_main_bootloader()
{
    menu_main_load_module \
        "bootloader.sh" || \
        return 1

    if ! declare -F bootloader_main >/dev/null 2>&1
    then
        logger_error \
            "bootloader.sh does not provide bootloader_main()"

        return 1
    fi

    bootloader_main
}

#============================================================
# Full installation
#============================================================

menu_main_install()
{
    logger_info \
        "Full installation selected"

    #
    # Partition
    #
    if ! menu_main_partition
    then
        logger_warn \
            "Partition stage cancelled or failed"

        return 1
    fi

    #
    # Filesystem
    #
    if ! menu_main_filesystem
    then
        logger_warn \
            "Filesystem stage cancelled or failed"

        return 1
    fi

    #
    # Mount
    #
    if ! menu_main_mount
    then
        logger_warn \
            "Mount stage cancelled or failed"

        return 1
    fi

    #
    # Packages
    #
    if ! menu_main_packages
    then
        logger_warn \
            "Package stage cancelled or failed"

        return 1
    fi

    #
    # Bootloader
    #
    if ! menu_main_bootloader
    then
        logger_warn \
            "Bootloader stage cancelled or failed"

        return 1
    fi

    logger_info \
        "Full installation completed"

    dialog_info \
        "Installation complete" \
        "Arch Linux installation completed successfully."

    return 0
}

#============================================================
# System information
#============================================================

menu_main_system_info()
{
    local kernel
    local arch
    local memory
    local cpu

    kernel="$(uname -r)"
    arch="$(uname -m)"

    memory="$(
        awk '/MemTotal:/ {
            printf "%.0f MiB", $2 / 1024
        }' /proc/meminfo
    )"

    cpu="$(
        awk -F: '/model name/ {
            print $2
            exit
        }' /proc/cpuinfo |
        sed 's/^ *//'
    )"

    tui_clear

    draw_panel \
        "System Information" \
        4 \
        5 \
        12 \
        "$((TUI_COLS - 10))"

    tui_move 6 8
    tui_print "Kernel:  $kernel"

    tui_move 7 8
    tui_print "Arch:    $arch"

    tui_move 8 8
    tui_print "Memory:  $memory"

    tui_move 9 8
    tui_print "CPU:     $cpu"

    tui_move 14 8
    tui_print "Enter = Back"

    while true
    do
        event_read

        case "$TUI_EVENT"
        in
            "$EVENT_SELECT"|"$EVENT_BACK")
                return 0
                ;;
        esac
    done
}

#============================================================
# Shell
#============================================================

menu_main_shell()
{
    tui_restore

    printf '\n'
    printf 'Arch Installer shell\n'
    printf 'Type "exit" to return to the installer.\n\n'

    /bin/bash

    printf '\nReturning to Arch Installer...\n'

    sleep 1

    tui_start || \
        return 1

    return 0
}

#============================================================
# Exit confirmation
#============================================================

menu_main_exit()
{
    if dialog_confirm \
        "Exit Arch Installer?"
    then
        logger_info \
            "User selected exit"

        return 0
    fi

    return 1
}

#============================================================
# Main menu
#============================================================

menu_main()
{
    local selected=0
    local result
    local items=(
        "Full installation"
        "Partition disk"
        "Create filesystem"
        "Mount filesystems"
        "Install packages"
        "Install bootloader"
        "System information"
        "Open shell"
        "Exit"
    )

    logger_info \
        "Main menu started"

    while true
    do
        menu_main_header

        #
        # Menu box
        #
        draw_box \
            6 \
            5 \
            "$((TUI_COLS - 10))" \
            "$(( ${#items[@]} + 4 ))" || \
            return 1

        local i

        for i in "${!items[@]}"
        do
            tui_move \
                "$((8 + i))" \
                8

            if (( i == selected ))
            then
                color_selected \
                    "> ${items[i]}"
            else
                tui_print \
                    "  ${items[i]}"
            fi
        done

        statusbar_draw \
            '↑↓ Navigate   Home/End   Enter Select   Esc Exit'

        event_read

        case "$TUI_EVENT"
        in
            "$EVENT_UP")
                if (( selected > 0 ))
                then
                    selected=$((selected - 1))
                else
                    selected=$((${#items[@]} - 1))
                fi
                ;;

            "$EVENT_DOWN")
                if (( selected < ${#items[@]} - 1 ))
                then
                    selected=$((selected + 1))
                else
                    selected=0
                fi
                ;;

            "$EVENT_HOME")
                selected=0
                ;;

            "$EVENT_END")
                selected=$((${#items[@]} - 1))
                ;;

            "$EVENT_SELECT")
                result="$selected"

                case "$result"
                in
                    0)
                        if ! menu_main_install
                        then
                            dialog_warning \
                                "Installation" \
                                "Installation was cancelled or failed."
                        fi
                        ;;

                    1)
                        if ! menu_main_partition
                        then
                            dialog_warning \
                                "Partition" \
                                "Partitioning was cancelled or failed."
                        fi
                        ;;

                    2)
                        if ! menu_main_filesystem
                        then
                            dialog_warning \
                                "Filesystem" \
                                "Filesystem stage was cancelled or failed."
                        fi
                        ;;

                    3)
                        if ! menu_main_mount
                        then
                            dialog_warning \
                                "Mount" \
                                "Mount stage was cancelled or failed."
                        fi
                        ;;

                    4)
                        if ! menu_main_packages
                        then
                            dialog_warning \
                                "Packages" \
                                "Package installation was cancelled or failed."
                        fi
                        ;;

                    5)
                        if ! menu_main_bootloader
                        then
                            dialog_warning \
                                "Bootloader" \
                                "Bootloader installation was cancelled or failed."
                        fi
                        ;;

                    6)
                        menu_main_system_info
                        ;;

                    7)
                        if ! menu_main_shell
                        then
                            dialog_error \
                                "Failed to return to TUI"
                        fi
                        ;;

                    8)
                        if menu_main_exit
                        then
                            logger_info \
                                "Main menu exited"

                            return 0
                        fi
                        ;;

                esac
                ;;

            "$EVENT_BACK")
                if menu_main_exit
                then
                    logger_info \
                        "Main menu exited"

                    return 0
                fi
                ;;
        esac
    done
}

#============================================================
# End
#============================================================
