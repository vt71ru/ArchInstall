#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  menu_main.sh
#
#  Главное меню Arch Installer.
#
#  Ответственность:
#   • отображение главного меню
#   • навигация через TUI API
#   • вызов installer controller
#   • отображение результата
#   • системная информация
#   • shell
#   • завершение installer
#
#  НЕ содержит:
#   • TTY logic
#   • stty
#   • keyboard parsing
#   • ANSI implementation
#   • partition logic
#   • filesystem logic
#   • mount logic
#   • package logic
#   • bootloader logic
#
#  Архитектура:
#
#       menu_main
#           ↓
#       installer.sh
#           ↓
#       installer_*()
#           ↓
#       *_main()
#============================================================

if [[ -n "${MENU_MAIN_SH_LOADED:-}" ]]
then
    return 0
fi

readonly MENU_MAIN_SH_LOADED=1

#============================================================
# State
#============================================================

MENU_MAIN_SELECTED=0

#============================================================
# Logging
#============================================================

menu_main_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@"
    fi
}

menu_main_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@"
    fi
}

menu_main_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@"
    fi
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

    return 0
}

#============================================================
# Operation result
#============================================================

menu_main_operation_failed()
{
    local stage="${1:-Operation}"
    local message="${2:-Operation failed.}"

    menu_main_log_error \
        "${stage}: ${message}"

    if declare -F dialog_error >/dev/null 2>&1
    then
        dialog_error \
            "$stage" \
            "$message"
    fi

    return 0
}

#============================================================
# Full installation result
#============================================================

menu_main_install()
{
    local rc=0
    local stage="unknown"

    menu_main_log_info \
        "Full installation selected"

    #--------------------------------------------------------
    # Controller
    #--------------------------------------------------------

    if installer_run
    then
        rc=0
    else
        rc=$?
    fi

    #--------------------------------------------------------
    # Success
    #--------------------------------------------------------

    if (( rc == 0 ))
    then
        menu_main_log_info \
            "Full installation completed"

        if declare -F dialog_info >/dev/null 2>&1
        then
            dialog_info \
                "Installation complete" \
                "Arch Linux installation completed successfully."
        fi

        return 0
    fi

    #--------------------------------------------------------
    # Failure
    #--------------------------------------------------------

    if declare -F installer_get_stage >/dev/null 2>&1
    then
        stage="$(installer_get_stage)"
    fi

    menu_main_log_error \
        "Full installation failed at stage: ${stage} (rc=${rc})"

    if declare -F dialog_error >/dev/null 2>&1
    then
        dialog_error \
            "Installation failed" \
            "Installation stopped at stage: ${stage}\nReturn code: ${rc}"
    fi

    return "$rc"
}

#============================================================
# Single stage wrappers
#============================================================

menu_main_partition()
{
    local rc=0

    menu_main_log_info \
        "Partition selected"

    if installer_partition
    then
        rc=0
    else
        rc=$?
    fi

    if (( rc != 0 ))
    then
        menu_main_operation_failed \
            "Partition" \
            "Partitioning was cancelled or failed."

        return "$rc"
    fi

    return 0
}

menu_main_filesystem()
{
    local rc=0

    menu_main_log_info \
        "Filesystem selected"

    if installer_filesystem
    then
        rc=0
    else
        rc=$?
    fi

    if (( rc != 0 ))
    then
        menu_main_operation_failed \
            "Filesystem" \
            "Filesystem stage was cancelled or failed."

        return "$rc"
    fi

    return 0
}

menu_main_mount()
{
    local rc=0

    menu_main_log_info \
        "Mount selected"

    if installer_mount
    then
        rc=0
    else
        rc=$?
    fi

    if (( rc != 0 ))
    then
        menu_main_operation_failed \
            "Mount" \
            "Mount stage was cancelled or failed."

        return "$rc"
    fi

    return 0
}

menu_main_packages()
{
    local rc=0

    menu_main_log_info \
        "Packages selected"

    if installer_packages
    then
        rc=0
    else
        rc=$?
    fi

    if (( rc != 0 ))
    then
        menu_main_operation_failed \
            "Packages" \
            "Package installation was cancelled or failed."

        return "$rc"
    fi

    return 0
}

menu_main_bootloader()
{
    local rc=0

    menu_main_log_info \
        "Bootloader selected"

    if installer_bootloader
    then
        rc=0
    else
        rc=$?
    fi

    if (( rc != 0 ))
    then
        menu_main_operation_failed \
            "Bootloader" \
            "Bootloader installation was cancelled or failed."

        return "$rc"
    fi

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

    screen_refresh 2>/dev/null || true

    while true
    do
        event_read

        case "$TUI_EVENT" in
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
    menu_main_log_info \
        "Opening installer shell"

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
# Exit
#============================================================

menu_main_exit()
{
    if dialog_confirm \
        "Exit Arch Installer?"
    then
        menu_main_log_info \
            "User selected exit"

        return 0
    fi

    return 1
}

#============================================================
# Draw menu
#============================================================

menu_main_draw()
{
    local -n items_ref="$1"
    local selected="$2"

    local item_count="${#items_ref[@]}"
    local box_height

    box_height=$((item_count + 4))

    menu_main_header

    draw_box \
        6 \
        5 \
        "$((TUI_COLS - 10))" \
        "$box_height" || \
        return 1

    local i
    local row

    for i in "${!items_ref[@]}"
    do
        row=$((8 + i))

        if (( row >= TUI_ROWS - 1 ))
        then
            break
        fi

        tui_move \
            "$row" \
            8 || \
            return 1

        if (( i == selected ))
        then
            color_selected \
                "> ${items_ref[i]}"
        else
            tui_print \
                "  ${items_ref[i]}"
        fi
    done

    statusbar_draw \
        '↑↓ Navigate   Home/End   Enter Select   Esc Exit' || \
        return 1

    screen_refresh 2>/dev/null || true

    return 0
}

#============================================================
# Main menu
#============================================================

menu_main()
{
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

    local selected=0
    local item_count="${#items[@]}"

    while true
    do
        if ! menu_main_draw \
            items \
            "$selected"
        then
            menu_main_log_error \
                "Failed to draw main menu"

            return 1
        fi

        event_read

        case "$TUI_EVENT" in

            #------------------------------------------------
            # Up
            #------------------------------------------------

            "$EVENT_UP")
                if (( selected > 0 ))
                then
                    selected=$((selected - 1))
                else
                    selected=$((item_count - 1))
                fi
                ;;

            #------------------------------------------------
            # Down
            #------------------------------------------------

            "$EVENT_DOWN")
                if (( selected < item_count - 1 ))
                then
                    selected=$((selected + 1))
                else
                    selected=0
                fi
                ;;

            #------------------------------------------------
            # Home
            #------------------------------------------------

            "$EVENT_HOME")
                selected=0
                ;;

            #------------------------------------------------
            # End
            #------------------------------------------------

            "$EVENT_END")
                selected=$((item_count - 1))
                ;;

            #------------------------------------------------
            # Select
            #------------------------------------------------

            "$EVENT_SELECT")

                case "$selected" in

                    #================================================
                    # Full installation
                    #================================================

                    0)
                        if ! menu_main_install
                        then
                            menu_main_log_warn \
                                "Full installation returned failure"
                        fi
                        ;;

                    #================================================
                    # Partition
                    #================================================

                    1)
                        if ! menu_main_partition
                        then
                            menu_main_log_warn \
                                "Partition operation failed"
                        fi
                        ;;

                    #================================================
                    # Filesystem
                    #================================================

                    2)
                        if ! menu_main_filesystem
                        then
                            menu_main_log_warn \
                                "Filesystem operation failed"
                        fi
                        ;;

                    #================================================
                    # Mount
                    #================================================

                    3)
                        if ! menu_main_mount
                        then
                            menu_main_log_warn \
                                "Mount operation failed"
                        fi
                        ;;

                    #================================================
                    # Packages
                    #================================================

                    4)
                        if ! menu_main_packages
                        then
                            menu_main_log_warn \
                                "Package operation failed"
                        fi
                        ;;

                    #================================================
                    # Bootloader
                    #================================================

                    5)
                        if ! menu_main_bootloader
                        then
                            menu_main_log_warn \
                                "Bootloader operation failed"
                        fi
                        ;;

                    #================================================
                    # System information
                    #================================================

                    6)
                        if ! menu_main_system_info
                        then
                            menu_main_log_warn \
                                "System information dialog failed"
                        fi
                        ;;

                    #================================================
                    # Shell
                    #================================================

                    7)
                        if ! menu_main_shell
                        then
                            menu_main_log_warn \
                                "Installer shell returned failure"
                        fi
                        ;;

                    #================================================
                    # Exit
                    #================================================

                    8)
                        if menu_main_exit
                        then
                            return 0
                        fi
                        ;;

                esac
                ;;

            #------------------------------------------------
            # Escape
            #------------------------------------------------

            "$EVENT_BACK")
                if menu_main_exit
                then
                    return 0
                fi
                ;;

        esac
    done
}
