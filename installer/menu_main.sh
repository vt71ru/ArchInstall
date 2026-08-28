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
#   • отображение главного меню
#   • навигация
#   • запуск installer controller
#   • системная информация
#   • shell
#   • завершение installer
#
# Не содержит:
#   • TTY logic
#   • stty
#   • keyboard parsing
#   • partition logic
#   • filesystem logic
#   • mount logic
#   • package logic
#   • bootloader logic
#
# Зависимости:
#   • tui.sh
#   • installer.sh
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

MENU_MAIN_INSTALLER="$MENU_MAIN_ROOT/installer"

readonly MENU_MAIN_INSTALLER

#============================================================
# Load installer controller
#============================================================

menu_main_load_installer()
{
    local file="$MENU_MAIN_INSTALLER/installer.sh"

    if [[ ! -f "$file" ]]
    then
        logger_error \
            "Main menu: installer controller not found: $file"

        return 1
    fi

    # shellcheck disable=SC1090
    if ! source "$file"
    then
        logger_error \
            "Main menu: failed to load installer controller: $file"

        return 1
    fi

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

    tui_move \
        3 \
        5

    color_info \
        "Arch Linux Installation System"

    tui_move \
        4 \
        5

    tui_print \
        "Select an operation"
}

#============================================================
# Partition
#============================================================

menu_main_partition()
{
    menu_main_load_installer || \
        return 1

    installer_partition
}

#============================================================
# Filesystem
#============================================================

menu_main_filesystem()
{
    menu_main_load_installer || \
        return 1

    installer_filesystem
}

#============================================================
# Mount
#============================================================

menu_main_mount()
{
    menu_main_load_installer || \
        return 1

    installer_mount
}

#============================================================
# Packages
#============================================================

menu_main_packages()
{
    menu_main_load_installer || \
        return 1

    installer_packages
}

#============================================================
# Bootloader
#============================================================

menu_main_bootloader()
{
    menu_main_load_installer || \
        return 1

    installer_bootloader
}

#============================================================
# Full installation
#============================================================

menu_main_install()
{
    logger_info \
        "Full installation selected"

    menu_main_load_installer || \
        return 1

    if installer_run
    then
        logger_info \
            "Full installation completed"

        dialog_info \
            "Installation complete" \
            "Arch Linux installation completed successfully."

        return 0
    fi

    logger_error \
        "Full installation failed at stage: ${INSTALLER_STAGE:-unknown}"

    return "${INSTALLER_LAST_RC:-1}"
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
        awk '
            /MemTotal:/ {
                printf "%.0f MiB", $2 / 1024
            }
        ' /proc/meminfo
    )"

    cpu="$(
        awk -F: '
            /model name/ {
                print $2
                exit
            }
        ' /proc/cpuinfo |
        sed 's/^ *//'
    )"

    tui_clear

    draw_panel \
        "System Information" \
        4 \
        5 \
        12 \
        "$((TUI_COLS - 10))"

    tui_move \
        6 \
        8

    tui_print \
        "Kernel:  $kernel"

    tui_move \
        7 \
        8

    tui_print \
        "Arch:    $arch"

    tui_move \
        8 \
        8

    tui_print \
        "Memory:  $memory"

    tui_move \
        9 \
        8

    tui_print \
        "CPU:     $cpu"

    tui_move \
        14 \
        8

    tui_print \
        "Enter = Back"

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
    local i

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

        #----------------------------------------------------
        # Menu box
        #----------------------------------------------------

        draw_box \
            6 \
            5 \
            "$((TUI_COLS - 10))" \
            "$(( ${#items[@]} + 4 ))" || \
            return 1

        #----------------------------------------------------
        # Menu entries
        #----------------------------------------------------

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

        #----------------------------------------------------
        # Status bar
        #----------------------------------------------------

        statusbar_draw \
            '↑↓ Navigate   Home/End   Enter Select   Esc Exit'

        #----------------------------------------------------
        # Read event
        #----------------------------------------------------

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
                case "$selected"
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
