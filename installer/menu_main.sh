#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  installer/menu_main.sh
#
#  Главное меню установщика.
#
#  Ответственность:
#   • отображение главного меню
#   • навигация клавиатурой
#   • запуск полной установки
#   • запуск отдельных этапов
#   • системная информация
#   • открытие shell
#   • выход
#
#============================================================

if [[ -n "${MENU_MAIN_SH_LOADED:-}" ]]
then
    return 0
fi

MENU_MAIN_SH_LOADED=1

#============================================================
# STATE
#============================================================

MENU_MAIN_SELECTED="${MENU_MAIN_SELECTED:-0}"

#============================================================
# LOGGING
#============================================================

menu_main_log_info()
{
    if declare -F log_info >/dev/null 2>&1
    then
        log_info "$*"
    else
        printf '[INFO] %s\n' "$*" >&2
    fi
}

menu_main_log_warn()
{
    if declare -F log_warn >/dev/null 2>&1
    then
        log_warn "$*"
    else
        printf '[WARN] %s\n' "$*" >&2
    fi
}

menu_main_log_error()
{
    if declare -F log_error >/dev/null 2>&1
    then
        log_error "$*"
    else
        printf '[ERROR] %s\n' "$*" >&2
    fi
}

#============================================================
# CONTROLLER CHECK
#============================================================

menu_main_check_controller()
{
    local missing=0

    if ! declare -F installer_run >/dev/null 2>&1
    then
        menu_main_log_error \
            "Missing controller function: installer_run"
        missing=1
    fi

    if ! declare -F installer_full_install >/dev/null 2>&1
    then
        menu_main_log_error \
            "Missing controller function: installer_full_install"
        missing=1
    fi

    if ! declare -F installer_run_stage >/dev/null 2>&1
    then
        menu_main_log_error \
            "Missing controller function: installer_run_stage"
        missing=1
    fi

    if ! declare -F installer_get_stage_title >/dev/null 2>&1
    then
        menu_main_log_error \
            "Missing controller function: installer_get_stage_title"
        missing=1
    fi

    if (( missing ))
    then
        return 1
    fi

    return 0
}

#============================================================
# HEADER
#============================================================

menu_main_header()
{
    tui_clear

    titlebar_draw "Arch Linux Installer"

    tui_move 3 5
    color_info "Arch Linux Installation System"

    tui_move 4 5
    tui_print "Select an operation using ↑ ↓ and press Enter."

    return 0
}

#============================================================
# OPERATION ERROR
#============================================================

menu_main_operation_failed()
{
    local title="${1:-Operation failed}"
    local message="${2:-Unknown error}"

    menu_main_log_error \
        "$title: $message"

    if declare -F dialog_error >/dev/null 2>&1
    then
        dialog_error \
            "$title" \
            "$message"
    else
        tui_move "$(( TUI_ROWS / 2 ))" 5
        color_error "$title"

        tui_move "$(( TUI_ROWS / 2 + 1 ))" 5
        tui_print "$message"

        tui_move "$(( TUI_ROWS / 2 + 3 ))" 5
        color_info "Press Enter to continue."

        while true
        do
            if ! event_read
            then
                return 1
            fi

            case "${TUI_EVENT:-}" in
                "$EVENT_SELECT"|"$EVENT_BACK")
                    break
                    ;;
            esac
        done
    fi

    return 0
}

#============================================================
# RUN SINGLE STAGE
#============================================================

menu_main_run_stage()
{
    local stage="${1:-}"

    if [[ -z "$stage" ]]
    then
        menu_main_operation_failed \
            "Invalid stage" \
            "No installation stage was specified."

        return 1
    fi

    local title=""

    if ! title="$(installer_get_stage_title "$stage")"
    then
        menu_main_operation_failed \
            "Unknown stage" \
            "Cannot determine title for stage: $stage"

        return 1
    fi

    menu_main_log_info \
        "Starting installation stage: $stage"

    tui_clear

    titlebar_draw "Arch Linux Installer"

    tui_move 4 5
    color_info "Starting: $title"

    tui_move 6 5
    tui_print "Stage: $stage"

    tui_move 8 5
    tui_print "Please wait..."

    local rc=0

    if installer_run_stage "$stage"
    then
        rc=0
    else
        rc=$?
    fi

    if (( rc != 0 ))
    then
        menu_main_operation_failed \
            "$title" \
            "Stage failed with return code: $rc"

        return "$rc"
    fi

    menu_main_log_info \
        "Installation stage completed: $stage"

    if declare -F dialog_info >/dev/null 2>&1
    then
        dialog_info \
            "$title" \
            "Stage completed successfully."
    fi

    return 0
}

#============================================================
# FULL INSTALLATION
#============================================================

menu_main_install()
{
    menu_main_log_info \
        "FULL INSTALLATION SELECTED"

    if ! declare -F installer_full_install >/dev/null 2>&1
    then
        menu_main_operation_failed \
            "Controller error" \
            "installer_full_install() is not available."

        return 1
    fi

    tui_clear

    titlebar_draw "Full Installation"

    tui_move 5 5
    color_info \
        "Starting full Arch Linux installation..."

    tui_move 7 5
    tui_print \
        "All installation stages will be executed sequentially."

    tui_move 9 5
    tui_print \
        "Please wait..."

    menu_main_log_info \
        "Calling installer_full_install"

    local rc=0

    if installer_full_install
    then
        rc=0
    else
        rc=$?
    fi

    menu_main_log_info \
        "installer_full_install returned: $rc"

    if (( rc != 0 ))
    then
        menu_main_operation_failed \
            "Installation failed" \
            "Full installation failed. Return code: $rc"

        return "$rc"
    fi

    menu_main_log_info \
        "FULL INSTALLATION COMPLETED"

    if declare -F dialog_info >/dev/null 2>&1
    then
        dialog_info \
            "Installation complete" \
            "Full Arch Linux installation completed successfully."
    fi

    return 0
}

#============================================================
# MANUAL STAGES
#============================================================

menu_main_partition()
{
    menu_main_run_stage "partition"
}

menu_main_filesystem()
{
    menu_main_run_stage "filesystem"
}

menu_main_mount()
{
    menu_main_run_stage "mount"
}

menu_main_packages()
{
    menu_main_run_stage "packages"
}

menu_main_bootloader()
{
    menu_main_run_stage "bootloader"
}

#============================================================
# SYSTEM INFORMATION
#============================================================

menu_main_system_info()
{
    tui_clear

    titlebar_draw "System Information"

    local kernel=""
    local arch=""
    local memory=""
    local cpu=""

    kernel="$(uname -r 2>/dev/null || printf 'unknown')"
    arch="$(uname -m 2>/dev/null || printf 'unknown')"

    if command -v free >/dev/null 2>&1
    then
        memory="$(
            free -h 2>/dev/null |
                awk '/^Mem:/ {print $2 " total, " $3 " used, " $7 " available"}'
        )"
    fi

    [[ -n "$memory" ]] || memory="unknown"

    if command -v nproc >/dev/null 2>&1
    then
        cpu="$(nproc 2>/dev/null || true)"
    fi

    [[ -n "$cpu" ]] || cpu="unknown"

    tui_move 5 5
    color_info "Kernel:"
    tui_print " $kernel"

    tui_move 7 5
    color_info "Architecture:"
    tui_print " $arch"

    tui_move 9 5
    color_info "Memory:"
    tui_print " $memory"

    tui_move 11 5
    color_info "CPU cores:"
    tui_print " $cpu"

    tui_move "$(( TUI_ROWS - 2 ))" 5
    color_info "Press Enter or Esc to return."

    while true
    do
        if ! event_read
        then
            return 1
        fi

        case "${TUI_EVENT:-}" in

            "$EVENT_SELECT")
                return 0
                ;;

            "$EVENT_BACK")
                return 0
                ;;

        esac
    done
}

#============================================================
# OPEN SHELL
#============================================================

menu_main_shell()
{
    menu_main_log_info \
        "Opening interactive shell"

    tui_restore

    printf '\n'
    printf 'Arch Installer shell\n'
    printf 'Type "exit" to return to the installer.\n'
    printf '\n'

    /bin/bash

    local rc=$?

    printf '\n'
    printf 'Returning to Arch Installer...\n'

    sleep 1

    if ! tui_start
    then
        menu_main_log_error \
            "Failed to restart TUI after shell"

        return 1
    fi

    return "$rc"
}

#============================================================
# EXIT
#============================================================

menu_main_exit()
{
    menu_main_log_info \
        "Exit requested"

    if declare -F dialog_confirm >/dev/null 2>&1
    then
        if dialog_confirm "Exit Arch Installer?"
        then
            menu_main_log_info \
                "User confirmed exit"

            return 0
        fi

        menu_main_log_info \
            "User cancelled exit"

        return 1
    fi

    return 0
}

#============================================================
# MENU DRAW
#============================================================

menu_main_draw()
{
    local -n items_ref="$1"
    local selected="${2:-0}"

    local item_count="${#items_ref[@]}"

    tui_update_size

    local width=$(( TUI_COLS - 10 ))
    local height=$(( item_count + 4 ))

    (( width < 40 )) && width=40

    local box_row=6
    local box_col=5

    menu_main_header

    draw_box \
        "$box_row" \
        "$box_col" \
        "$height" \
        "$width" \
        "Main Menu"

    local i
    local row=$(( box_row + 2 ))

    for (( i=0; i<item_count; i++ ))
    do
        tui_move "$row" "$(( box_col + 3 ))"

        if (( i == selected ))
        then
            color_selected \
                "> ${items_ref[i]}"
        else
            tui_print \
                "  ${items_ref[i]}"
        fi

        (( row++ ))
    done

    statusbar_draw \
        "↑↓ Navigate   Home/End Move   Enter Select   Esc Exit"

    return 0
}

#============================================================
# MAIN MENU
#============================================================

menu_main()
{
    if ! menu_main_check_controller
    then
        menu_main_operation_failed \
            "Controller error" \
            "Required installer controller functions are not loaded."

        return 1
    fi

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

    local selected="${MENU_MAIN_SELECTED:-0}"
    local item_count="${#items[@]}"

    if ! [[ "$selected" =~ ^[0-9]+$ ]]
    then
        selected=0
    fi

    (( selected < 0 )) && selected=0
    (( selected >= item_count )) && selected=$(( item_count - 1 ))

    menu_main_log_info \
        "Main menu started"

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

        #
        # Read exactly one keyboard event.
        #
        if ! event_read
        then
            menu_main_log_error \
                "event_read() failed"

            return 1
        fi

        menu_main_log_info \
            "EVENT=${TUI_EVENT:-NONE} SELECTED=$selected"

        case "${TUI_EVENT:-}" in

            #------------------------------------------------
            # UP
            #------------------------------------------------

            "$EVENT_UP")
                if (( selected > 0 ))
                then
                    (( selected-- ))
                else
                    selected=$(( item_count - 1 ))
                fi
                ;;

            #------------------------------------------------
            # DOWN
            #------------------------------------------------

            "$EVENT_DOWN")
                if (( selected < item_count - 1 ))
                then
                    (( selected++ ))
                else
                    selected=0
                fi
                ;;

            #------------------------------------------------
            # HOME
            #------------------------------------------------

            "$EVENT_HOME")
                selected=0
                ;;

            #------------------------------------------------
            # END
            #------------------------------------------------

            "$EVENT_END")
                selected=$(( item_count - 1 ))
                ;;

            #------------------------------------------------
            # SELECT / ENTER
            #------------------------------------------------

            "$EVENT_SELECT")

                MENU_MAIN_SELECTED="$selected"

                menu_main_log_info \
                    "SELECT event: index=$selected item=${items[selected]}"

                case "$selected" in

                    0)
                        menu_main_install
                        ;;

                    1)
                        menu_main_partition
                        ;;

                    2)
                        menu_main_filesystem
                        ;;

                    3)
                        menu_main_mount
                        ;;

                    4)
                        menu_main_packages
                        ;;

                    5)
                        menu_main_bootloader
                        ;;

                    6)
                        menu_main_system_info
                        ;;

                    7)
                        menu_main_shell
                        ;;

                    8)
                        if menu_main_exit
                        then
                            menu_main_log_info \
                                "Main menu exiting"

                            MENU_MAIN_SELECTED="$selected"

                            return 0
                        fi
                        ;;

                esac
                ;;

            #------------------------------------------------
            # ESC
            #------------------------------------------------

            "$EVENT_BACK")

                menu_main_log_info \
                    "BACK event received"

                if menu_main_exit
                then
                    menu_main_log_info \
                        "Main menu exiting by ESC"

                    MENU_MAIN_SELECTED="$selected"

                    return 0
                fi

                ;;

            #------------------------------------------------
            # UNKNOWN
            #------------------------------------------------

            "$EVENT_NONE")
                ;;

            *)
                menu_main_log_warn \
                    "Unhandled TUI event: ${TUI_EVENT:-unknown}"
                ;;

        esac
    done
}

#============================================================
# END OF installer/menu_main.sh
#============================================================

