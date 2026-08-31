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
#
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

    return 0
}

menu_main_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@"
    fi

    return 0
}

menu_main_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@"
    fi

    return 0
}

#============================================================
# Header
#============================================================

menu_main_header()
{
    tui_clear || return 1

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "Arch Installer" || return 1
    fi

    tui_move \
        3 \
        5 || return 1

    if declare -F color_info >/dev/null 2>&1
    then
        color_info \
            "Arch Linux Installation System"
    else
        tui_print \
            "Arch Linux Installation System"
    fi

    tui_move \
        4 \
        5 || return 1

    tui_print \
        "Select an operation"

    return 0
}

#============================================================
# Generic operation failure
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
    else
        printf '\n'
        printf '========================================\n'
        printf ' %s\n' "$stage"
        printf '========================================\n'
        printf '%s\n' "$message"
        printf '\n'
    fi

    return 0
}

#============================================================
# Full installation
#============================================================

menu_main_install()
{
    local rc=0
    local stage="unknown"
    local last_function="unknown"
    local last_message="unknown"

    menu_main_log_info \
        "========================================"

    menu_main_log_info \
        "FULL INSTALLATION SELECTED"

    menu_main_log_info \
        "========================================"

    #--------------------------------------------------------
    # Controller check
    #--------------------------------------------------------

    if ! declare -F installer_run >/dev/null 2>&1
    then
        menu_main_log_error \
            "installer_run() is not available"

        menu_main_operation_failed \
            "Installation" \
            "installer_run() is not available."

        return 1
    fi

    #--------------------------------------------------------
    # Prepare installation screen
    #--------------------------------------------------------

    if declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear || true
    fi

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "Full Installation" \
            || true
    fi

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move \
            4 \
            5 || true
    fi

    if declare -F tui_print >/dev/null 2>&1
    then
        tui_print \
            "Starting full Arch Linux installation..."
    fi

    if declare -F screen_refresh >/dev/null 2>&1
    then
        screen_refresh \
            2>/dev/null \
            || true
    fi

    menu_main_log_info \
        "Calling installer_run()"

    #--------------------------------------------------------
    # Run controller
    #--------------------------------------------------------

    if installer_run
    then
        rc=0
    else
        rc=$?
    fi

    #--------------------------------------------------------
    # Read controller state
    #--------------------------------------------------------

    if declare -F installer_get_stage >/dev/null 2>&1
    then
        stage="$(
            installer_get_stage \
                2>/dev/null \
                || printf '%s' "unknown"
        )"
    fi

    if declare -F installer_get_last_function >/dev/null 2>&1
    then
        last_function="$(
            installer_get_last_function \
                2>/dev/null \
                || printf '%s' "unknown"
        )"
    fi

    if declare -F installer_get_last_message >/dev/null 2>&1
    then
        last_message="$(
            installer_get_last_message \
                2>/dev/null \
                || printf '%s' "unknown"
        )"
    fi

    #--------------------------------------------------------
    # Success
    #--------------------------------------------------------

    if (( rc == 0 ))
    then
        menu_main_log_info \
            "Full installation completed successfully"

        if declare -F dialog_info >/dev/null 2>&1
        then
            dialog_info \
                "Installation complete" \
                "Full Arch Linux installation completed successfully."
        else
            printf '\n'
            printf '========================================\n'
            printf ' INSTALLATION COMPLETED\n'
            printf '========================================\n'
            printf '\n'
        fi

        return 0
    fi

    #--------------------------------------------------------
    # Failure
    #--------------------------------------------------------

    menu_main_log_error \
        "Full installation failed"

    menu_main_log_error \
        "Stage: ${stage}"

    menu_main_log_error \
        "Function: ${last_function}"

    menu_main_log_error \
        "Return code: ${rc}"

    menu_main_log_error \
        "Message: ${last_message}"

    #--------------------------------------------------------
    # Show failure
    #--------------------------------------------------------

    if declare -F dialog_error >/dev/null 2>&1
    then
        dialog_error \
            "Installation failed" \
            "Stage: ${stage}\nFunction: ${last_function}\nReturn code: ${rc}"
    else
        printf '\n'
        printf '========================================\n'
        printf ' INSTALLATION FAILED\n'
        printf '========================================\n'
        printf '\n'
        printf 'Stage    : %s\n' "$stage"
        printf 'Function : %s\n' "$last_function"
        printf 'Return   : %s\n' "$rc"
        printf 'Message  : %s\n' "$last_message"
        printf '\n'
        printf 'Log      : %s\n' \
            "${LOGGER_FILE:-/tmp/arch-installer.log}"
        printf '\n'
    fi

    return "$rc"
}

#============================================================
# Partition
#============================================================

menu_main_partition()
{
    local rc=0

    menu_main_log_info \
        "Partition selected"

    if ! declare -F installer_partition >/dev/null 2>&1
    then
        menu_main_operation_failed \
            "Partition" \
            "installer_partition() is not available."

        return 1
    fi

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
            "Partitioning failed. Return code: ${rc}"

        return "$rc"
    fi

    return 0
}

#============================================================
# Filesystem
#============================================================

menu_main_filesystem()
{
    local rc=0

    menu_main_log_info \
        "Filesystem selected"

    if ! declare -F installer_filesystem >/dev/null 2>&1
    then
        menu_main_operation_failed \
            "Filesystem" \
            "installer_filesystem() is not available."

        return 1
    fi

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
            "Filesystem stage failed. Return code: ${rc}"

        return "$rc"
    fi

    return 0
}

#============================================================
# Mount
#============================================================

menu_main_mount()
{
    local rc=0

    menu_main_log_info \
        "Mount selected"

    if ! declare -F installer_mount >/dev/null 2>&1
    then
        menu_main_operation_failed \
            "Mount" \
            "installer_mount() is not available."

        return 1
    fi

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
            "Mount stage failed. Return code: ${rc}"

        return "$rc"
    fi

    return 0
}

#============================================================
# Packages
#============================================================

menu_main_packages()
{
    local rc=0

    menu_main_log_info \
        "Packages selected"

    if ! declare -F installer_packages >/dev/null 2>&1
    then
        menu_main_operation_failed \
            "Packages" \
            "installer_packages() is not available."

        return 1
    fi

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
            "Package installation failed. Return code: ${rc}"

        return "$rc"
    fi

    return 0
}

#============================================================
# Bootloader
#============================================================

menu_main_bootloader()
{
    local rc=0

    menu_main_log_info \
        "Bootloader selected"

    if ! declare -F installer_bootloader >/dev/null 2>&1
    then
        menu_main_operation_failed \
            "Bootloader" \
            "installer_bootloader() is not available."

        return 1
    fi

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
            "Bootloader installation failed. Return code: ${rc}"

        return "$rc"
    fi

    return 0
}

#============================================================
# System information
#============================================================

menu_main_system_info()
{
    local kernel=""
    local arch=""
    local memory=""
    local cpu=""

    kernel="$(uname -r)"
    arch="$(uname -m)"

    memory="$(
        awk '
            /MemTotal:/ {
                printf "%.0f MiB", $2 / 1024
                exit
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

    tui_clear || return 1

    if declare -F draw_panel >/dev/null 2>&1
    then
        draw_panel \
            "System Information" \
            4 \
            5 \
            12 \
            "$((TUI_COLS - 10))" \
            || return 1
    fi

    tui_move \
        6 \
        8 || return 1

    tui_print \
        "Kernel:  ${kernel}"

    tui_move \
        7 \
        8 || return 1

    tui_print \
        "Arch:    ${arch}"

    tui_move \
        8 \
        8 || return 1

    tui_print \
        "Memory:  ${memory}"

    tui_move \
        9 \
        8 || return 1

    tui_print \
        "CPU:     ${cpu:-unknown}"

    tui_move \
        11 \
        8 || return 1

    tui_print \
        "Press Enter or Esc to return."

    if declare -F statusbar_draw >/dev/null 2>&1
    then
        statusbar_draw \
            "Enter Back   Esc Back" \
            || true
    fi

    screen_refresh \
        2>/dev/null \
        || true

    while true
    do
        event_read

        case "${TUI_EVENT:-}" in
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
    local rc=0

    menu_main_log_info \
        "Opening installer shell"

    if declare -F tui_restore >/dev/null 2>&1
    then
        tui_restore || true
    fi

    printf '\n'
    printf '========================================\n'
    printf ' Arch Installer shell\n'
    printf '========================================\n'
    printf '\n'
    printf 'Type "exit" to return to the installer.\n'
    printf '\n'

    /bin/bash
    rc=$?

    printf '\n'
    printf 'Returning to Arch Installer...\n'

    sleep 1

    if ! declare -F tui_start >/dev/null 2>&1
    then
        menu_main_log_error \
            "tui_start() is not available"

        return 1
    fi

    if ! tui_start
    then
        menu_main_log_error \
            "tui_start() failed"

        return 1
    fi

    return "$rc"
}

#============================================================
# Exit
#============================================================

menu_main_exit()
{
    if ! declare -F dialog_confirm >/dev/null 2>&1
    then
        menu_main_log_warn \
            "dialog_confirm() is not available"

        return 1
    fi

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
    local i
    local row

    box_height=$((item_count + 4))

    menu_main_header || return 1

    if ! declare -F draw_box >/dev/null 2>&1
    then
        menu_main_log_error \
            "draw_box() is not available"

        return 1
    fi

    draw_box \
        6 \
        5 \
        "$((TUI_COLS - 10))" \
        "$box_height" || return 1

    for i in "${!items_ref[@]}"
    do
        row=$((8 + i))

        if (( row >= TUI_ROWS - 1 ))
        then
            break
        fi

        tui_move \
            "$row" \
            8 || return 1

        if (( i == selected ))
        then
            if declare -F color_selected >/dev/null 2>&1
            then
                color_selected \
                    "> ${items_ref[i]}"
            else
                tui_print \
                    "> ${items_ref[i]}"
            fi
        else
            tui_print \
                "  ${items_ref[i]}"
        fi
    done

    if declare -F statusbar_draw >/dev/null 2>&1
    then
        statusbar_draw \
            '↑↓ Navigate   Home/End   Enter Select   Esc Exit' \
            || return 1
    fi

    screen_refresh \
        2>/dev/null \
        || true

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

        case "${TUI_EVENT:-}" in

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

                    #----------------------------------------
                    # Full installation
                    #----------------------------------------

                    0)
                        if ! menu_main_install
                        then
                            menu_main_log_warn \
                                "Full installation returned failure"
                        fi
                        ;;

                    #----------------------------------------
                    # Partition
                    #----------------------------------------

                    1)
                        if ! menu_main_partition
                        then
                            menu_main_log_warn \
                                "Partition operation failed"
                        fi
                        ;;

                    #----------------------------------------
                    # Filesystem
                    #----------------------------------------

                    2)
                        if ! menu_main_filesystem
                        then
                            menu_main_log_warn \
                                "Filesystem operation failed"
                        fi
                        ;;

                    #----------------------------------------
                    # Mount
                    #----------------------------------------

                    3)
                        if ! menu_main_mount
                        then
                            menu_main_log_warn \
                                "Mount operation failed"
                        fi
                        ;;

                    #----------------------------------------
                    # Packages
                    #----------------------------------------

                    4)
                        if ! menu_main_packages
                        then
                            menu_main_log_warn \
                                "Package operation failed"
                        fi
                        ;;

                    #----------------------------------------
                    # Bootloader
                    #----------------------------------------

                    5)
                        if ! menu_main_bootloader
                        then
                            menu_main_log_warn \
                                "Bootloader operation failed"
                        fi
                        ;;

                    #----------------------------------------
                    # System information
                    #----------------------------------------

                    6)
                        if ! menu_main_system_info
                        then
                            menu_main_log_warn \
                                "System information failed"
                        fi
                        ;;

                    #----------------------------------------
                    # Shell
                    #----------------------------------------

                    7)
                        if ! menu_main_shell
                        then
                            menu_main_log_warn \
                                "Installer shell failed"
                        fi
                        ;;

                    #----------------------------------------
                    # Exit
                    #----------------------------------------

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
