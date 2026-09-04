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
# Load guard
#============================================================

if [[ -n "${MENU_MAIN_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

MENU_MAIN_SH_LOADED=1
export MENU_MAIN_SH_LOADED

#============================================================
# State
#============================================================

MENU_MAIN_SELECTED="${MENU_MAIN_SELECTED:-0}"

#============================================================
# Logging
#============================================================

menu_main_log_info()
{
    if declare -F log_info >/dev/null 2>&1
    then
        log_info "$@" || true
    elif declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@" || true
    else
        printf '[INFO] %s\n' "$*" >&2
    fi

    return 0
}

menu_main_log_warn()
{
    if declare -F log_warn >/dev/null 2>&1
    then
        log_warn "$@" || true
    elif declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@" || true
    else
        printf '[WARN] %s\n' "$*" >&2
    fi

    return 0
}

menu_main_log_error()
{
    if declare -F log_error >/dev/null 2>&1
    then
        log_error "$@" || true
    elif declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@" || true
    else
        printf '[ERROR] %s\n' "$*" >&2
    fi

    return 0
}

#============================================================
# CONTROLLER CHECK
#============================================================

menu_main_check_controller()
{
    local missing=0

    menu_main_log_info \
        "Checking installer controller API"

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

    if (( missing != 0 ))
    then
        menu_main_log_error \
            "Installer controller API check FAILED"
        return 1
    fi

    menu_main_log_info \
        "Installer controller API: OK"

    return 0
}

#============================================================
# HEADER
#============================================================

menu_main_header()
{
    if declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear || return 1
    else
        printf '\033[2J\033[H'
    fi

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "Arch Linux Installer" ||
            return 1
    fi

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move 3 5 || return 1

        if declare -F color_info >/dev/null 2>&1
        then
            color_info \
                "Arch Linux Installation System" ||
                return 1
        else
            tui_print \
                "Arch Linux Installation System" ||
                return 1
        fi

        tui_move 4 5 || return 1

        tui_print \
            "Select an operation using ↑ ↓ and press Enter." ||
            return 1
    else
        printf '\n'
        printf 'Arch Linux Installation System\n'
        printf 'Select an operation using Up/Down and press Enter.\n'
    fi

    return 0
}

#============================================================
# WAIT FOR EVENT
#============================================================

menu_main_read_event()
{
    TUI_EVENT=""

    if ! declare -F event_read >/dev/null 2>&1
    then
        menu_main_log_error \
            "event_read() is not available"
        return 1
    fi

    if ! event_read
    then
        menu_main_log_error \
            "event_read() failed"
        return 1
    fi

    return 0
}

#============================================================
# OPERATION ERROR
#============================================================

menu_main_operation_failed()
{
    local title="${1:-Operation failed}"
    local message="${2:-Unknown error}"
    local event=""

    menu_main_log_error \
        "${title}: ${message}"

    if declare -F dialog_error >/dev/null 2>&1
    then
        dialog_error \
            "$title" \
            "$message" || true

        return 0
    fi

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move \
            "$(( TUI_ROWS / 2 ))" \
            5 || true
    fi

    if declare -F color_error >/dev/null 2>&1
    then
        color_error \
            "$title" || true
    else
        printf '%s' "$title"
    fi

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move \
            "$(( TUI_ROWS / 2 + 1 ))" \
            5 || true
    fi

    if declare -F tui_print >/dev/null 2>&1
    then
        tui_print \
            "$message" || true
    else
        printf '%s' "$message"
    fi

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move \
            "$(( TUI_ROWS / 2 + 3 ))" \
            5 || true
    fi

    if declare -F color_info >/dev/null 2>&1
    then
        color_info \
            "Press Enter or Esc to continue." || true
    fi

    while true
    do
        if ! menu_main_read_event
        then
            return 1
        fi

        event="${TUI_EVENT:-}"

        case "$event" in
            "$EVENT_SELECT"|"$EVENT_BACK")
                return 0
                ;;

            "$EVENT_NONE"|"")
                ;;

            *)
                ;;
        esac
    done
}

#============================================================
# RUN SINGLE STAGE
#============================================================

menu_main_run_stage()
{
    local stage="${1:-}"
    local title=""
    local rc=0

    if [[ -z "$stage" ]]
    then
        menu_main_operation_failed \
            "Invalid stage" \
            "No installation stage was specified."

        return 1
    fi

    if ! title="$(
        installer_get_stage_title "$stage"
    )"
    then
        menu_main_operation_failed \
            "Unknown stage" \
            "Cannot determine title for stage: ${stage}"

        return 1
    fi

    menu_main_log_info \
        "Starting installation stage: $stage"

    if declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear || return 1
    fi

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "Arch Linux Installer" ||
            return 1
    fi

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move 4 5 || return 1

        if declare -F color_info >/dev/null 2>&1
        then
            color_info \
                "Starting: $title" ||
                return 1
        else
            tui_print \
                "Starting: $title" ||
                return 1
        fi

        tui_move 6 5 || return 1

        tui_print \
            "Stage: $stage" ||
            return 1

        tui_move 8 5 || return 1

        tui_print \
            "Please wait..." ||
            return 1
    fi

    menu_main_log_info \
        "Calling installer_run_stage($stage)"

    if installer_run_stage "$stage"
    then
        rc=0
    else
        rc=$?
    fi

    menu_main_log_info \
        "installer_run_stage($stage) returned rc=$rc"

    if (( rc != 0 ))
    then
        menu_main_operation_failed \
            "$title" \
            "Stage failed with return code: $rc" || true

        return "$rc"
    fi

    menu_main_log_info \
        "Installation stage completed: $stage"

    if declare -F dialog_info >/dev/null 2>&1
    then
        dialog_info \
            "$title" \
            "Stage completed successfully." || true
    fi

    return 0
}

#============================================================
# FULL INSTALLATION
#============================================================

menu_main_install()
{
    local rc=0

    menu_main_log_info \
        "================================================"

    menu_main_log_info \
        "FULL INSTALLATION SELECTED"

    menu_main_log_info \
        "Checking installer_full_install()"

    if ! declare -F installer_full_install >/dev/null 2>&1
    then
        menu_main_log_error \
            "installer_full_install() is not available"

        menu_main_operation_failed \
            "Controller error" \
            "installer_full_install() is not available." || true

        return 1
    fi

    menu_main_log_info \
        "installer_full_install() is available"

    if declare -F tui_clear >/dev/null 2>&1
    then
        if ! tui_clear
        then
            menu_main_log_error \
                "tui_clear() failed before full installation"
            return 1
        fi
    fi

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        if ! titlebar_draw \
            "Full Installation"
        then
            menu_main_log_error \
                "titlebar_draw() failed"
            return 1
        fi
    fi

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move 5 5 || return 1

        if declare -F color_info >/dev/null 2>&1
        then
            color_info \
                "Starting full Arch Linux installation..." ||
                return 1
        else
            tui_print \
                "Starting full Arch Linux installation..." ||
                return 1
        fi

        tui_move 7 5 || return 1

        tui_print \
            "All installation stages will be executed sequentially." ||
            return 1

        tui_move 9 5 || return 1

        tui_print \
            "Please wait..." ||
            return 1

        tui_move 11 5 || return 1

        tui_print \
            "Controller: installer_full_install()" ||
            return 1
    fi

    if declare -F tui_flush >/dev/null 2>&1
    then
        tui_flush || true
    elif declare -F screen_refresh >/dev/null 2>&1
    then
        screen_refresh || true
    fi

    menu_main_log_info \
        "Calling installer_full_install()"

    if installer_full_install
    then
        rc=0
    else
        rc=$?
    fi

    menu_main_log_info \
        "installer_full_install() returned rc=$rc"

    if (( rc != 0 ))
    then
        menu_main_log_error \
            "FULL INSTALLATION FAILED: rc=$rc"

        menu_main_operation_failed \
            "Installation failed" \
            "Full installation failed. Return code: $rc" || true

        return "$rc"
    fi

    menu_main_log_info \
        "FULL INSTALLATION COMPLETED SUCCESSFULLY"

    if declare -F dialog_info >/dev/null 2>&1
    then
        dialog_info \
            "Installation complete" \
            "Full Arch Linux installation completed successfully." || true
    fi

    return 0
}

#============================================================
# MANUAL STAGES
#============================================================

menu_main_partition()
{
    menu_main_run_stage \
        "partition"
}

menu_main_filesystem()
{
    menu_main_run_stage \
        "filesystem"
}

menu_main_mount()
{
    menu_main_run_stage \
        "mount"
}

menu_main_packages()
{
    menu_main_run_stage \
        "packages"
}

menu_main_bootloader()
{
    menu_main_run_stage \
        "bootloader"
}

#============================================================
# SYSTEM INFORMATION
#============================================================

menu_main_system_info()
{
    local kernel=""
    local arch=""
    local memory=""
    local cpu=""
    local event=""

    if declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear || return 1
    else
        printf '\033[2J\033[H'
    fi

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "System Information" ||
            return 1
    fi

    kernel="$(
        uname -r \
            2>/dev/null \
            || printf '%s' 'unknown'
    )"

    arch="$(
        uname -m \
            2>/dev/null \
            || printf '%s' 'unknown'
    )"

    if command -v free >/dev/null 2>&1
    then
        memory="$(
            free -h \
                2>/dev/null |
            awk '
                /^Mem:/ {
                    print $2 " total, " \
                          $3 " used, " \
                          $7 " available"
                }
            '
        )"
    fi

    [[ -n "$memory" ]] || memory="unknown"

    if command -v nproc >/dev/null 2>&1
    then
        cpu="$(
            nproc \
                2>/dev/null \
                || true
        )"
    fi

    [[ -n "$cpu" ]] || cpu="unknown"

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move 5 5 || return 1

        if declare -F color_info >/dev/null 2>&1
        then
            color_info "Kernel:" || return 1
        else
            tui_print "Kernel:" || return 1
        fi

        tui_print " ${kernel}" || return 1

        tui_move 7 5 || return 1

        if declare -F color_info >/dev/null 2>&1
        then
            color_info "Architecture:" || return 1
        else
            tui_print "Architecture:" || return 1
        fi

        tui_print " ${arch}" || return 1

        tui_move 9 5 || return 1

        if declare -F color_info >/dev/null 2>&1
        then
            color_info "Memory:" || return 1
        else
            tui_print "Memory:" || return 1
        fi

        tui_print " ${memory}" || return 1

        tui_move 11 5 || return 1

        if declare -F color_info >/dev/null 2>&1
        then
            color_info "CPU cores:" || return 1
        else
            tui_print "CPU cores:" || return 1
        fi

        tui_print " ${cpu}" || return 1

        tui_move \
            "$(( TUI_ROWS - 2 ))" \
            5 || return 1

        if declare -F color_info >/dev/null 2>&1
        then
            color_info \
                "Press Enter or Esc to return." ||
                return 1
        else
            tui_print \
                "Press Enter or Esc to return." ||
                return 1
        fi
    else
        printf '\n'
        printf 'Kernel: %s\n' "$kernel"
        printf 'Architecture: %s\n' "$arch"
        printf 'Memory: %s\n' "$memory"
        printf 'CPU cores: %s\n' "$cpu"
        printf '\nPress Enter or Esc to return.\n'
    fi

    if declare -F screen_refresh >/dev/null 2>&1
    then
        screen_refresh || true
    elif declare -F tui_flush >/dev/null 2>&1
    then
        tui_flush || true
    fi

    while true
    do
        if ! menu_main_read_event
        then
            menu_main_log_error \
                "event_read() failed in system information"
            return 1
        fi

        event="${TUI_EVENT:-}"

        case "$event" in

            "$EVENT_SELECT")
                return 0
                ;;

            "$EVENT_BACK")
                return 0
                ;;

            "$EVENT_NONE"|"")
                ;;

            *)
                ;;
        esac
    done
}

#============================================================
# OPEN SHELL
#============================================================

menu_main_shell()
{
    local rc=0

    menu_main_log_info \
        "Opening interactive shell"

    #--------------------------------------------------------
    # Restore terminal before starting shell.
    #--------------------------------------------------------

    if declare -F tui_restore >/dev/null 2>&1
    then
        tui_restore || true
    fi

    printf '\n'
    printf 'Arch Installer shell\n'
    printf 'Type "exit" to return to the installer.\n'
    printf '\n'

    if /bin/bash
    then
        rc=0
    else
        rc=$?
    fi

    printf '\n'
    printf 'Returning to Arch Installer...\n'

    sleep 1

    menu_main_log_info \
        "Restarting TUI after shell"

    if declare -F tui_start >/dev/null 2>&1
    then
        if ! tui_start
        then
            menu_main_log_error \
                "Failed to restart TUI after shell"
            return 1
        fi
    elif declare -F tui_init >/dev/null 2>&1
    then
        if ! tui_init
        then
            menu_main_log_error \
                "Failed to initialize TUI after shell"
            return 1
        fi
    fi

    menu_main_log_info \
        "TUI restarted after shell"

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
        if dialog_confirm \
            "Exit Arch Installer?"
        then
            menu_main_log_info \
                "User confirmed exit"
            return 0
        fi

        menu_main_log_info \
            "User cancelled exit"

        return 1
    fi

    #--------------------------------------------------------
    # No confirmation dialog available.
    #--------------------------------------------------------

    menu_main_log_warn \
        "dialog_confirm() is unavailable; exiting"

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
    local width=0
    local height=0
    local box_row=6
    local box_col=5
    local i=0
    local row=0

    if (( item_count == 0 ))
    then
        menu_main_log_error \
            "menu_main_draw(): empty menu"
        return 1
    fi

    if declare -F tui_update_size >/dev/null 2>&1
    then
        tui_update_size || true
    fi

    width=$(( TUI_COLS - 10 ))
    height=$(( item_count + 4 ))

    if (( width < 40 ))
    then
        width=40
    fi

    menu_main_header || return 1

    if declare -F draw_box >/dev/null 2>&1
    then
        draw_box \
            "$box_row" \
            "$box_col" \
            "$height" \
            "$width" \
            "Main Menu" ||
            return 1
    fi

    row=$(( box_row + 2 ))

    for (( i=0; i<item_count; i++ ))
    do
        if declare -F tui_move >/dev/null 2>&1
        then
            tui_move \
                "$row" \
                "$(( box_col + 3 ))" ||
                return 1
        fi

        if (( i == selected ))
        then
            if declare -F color_selected >/dev/null 2>&1
            then
                color_selected \
                    "> ${items_ref[i]}" ||
                    return 1
            elif declare -F tui_print >/dev/null 2>&1
            then
                tui_print \
                    "> ${items_ref[i]}" ||
                    return 1
            else
                printf '> %s' \
                    "${items_ref[i]}"
            fi
        else
            if declare -F tui_print >/dev/null 2>&1
            then
                tui_print \
                    "  ${items_ref[i]}" ||
                    return 1
            else
                printf '  %s' \
                    "${items_ref[i]}"
            fi
        fi

        row=$(( row + 1 ))
    done

    if declare -F statusbar_draw >/dev/null 2>&1
    then
        statusbar_draw \
            "↑↓ Navigate   Home/End Move   Enter Select   Esc Exit" ||
            return 1
    fi

    if declare -F screen_refresh >/dev/null 2>&1
    then
        screen_refresh || return 1
    elif declare -F tui_flush >/dev/null 2>&1
    then
        tui_flush || return 1
    fi

    return 0
}

#============================================================
# MAIN MENU
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

    local selected="${MENU_MAIN_SELECTED:-0}"
    local item_count="${#items[@]}"
    local operation_rc=0

    menu_main_log_info \
        "========================================"

    menu_main_log_info \
        "Entering main menu"

    #--------------------------------------------------------
    # Controller validation
    #--------------------------------------------------------

    if ! menu_main_check_controller
    then
        menu_main_operation_failed \
            "Controller error" \
            "Required installer controller functions are not loaded." \
            || true

        return 1
    fi

    #--------------------------------------------------------
    # Validate selected index
    #--------------------------------------------------------

    if ! [[ "$selected" =~ ^[0-9]+$ ]]
    then
        selected=0
    fi

    if (( selected < 0 ))
    then
        selected=0
    fi

    if (( selected >= item_count ))
    then
        selected=$(( item_count - 1 ))
    fi

    MENU_MAIN_SELECTED="$selected"

    menu_main_log_info \
        "Main menu started"

    #========================================================
    # MENU LOOP
    #========================================================

    while true
    do
        #----------------------------------------------------
        # Draw menu
        #----------------------------------------------------

        if ! menu_main_draw \
            items \
            "$selected"
        then
            menu_main_log_error \
                "Failed to draw main menu"
            return 1
        fi

        #----------------------------------------------------
        # Read event
        #----------------------------------------------------

        if ! menu_main_read_event
        then
            menu_main_log_error \
                "Unable to read menu event"
            return 1
        fi

        menu_main_log_info \
            "EVENT=${TUI_EVENT:-NONE} SELECTED=$selected"

        #====================================================
        # Process event
        #====================================================

        case "${TUI_EVENT:-}" in

            #------------------------------------------------
            # UP
            #------------------------------------------------

            "$EVENT_UP")

                if (( selected > 0 ))
                then
                    selected=$(( selected - 1 ))
                else
                    selected=$(( item_count - 1 ))
                fi

                MENU_MAIN_SELECTED="$selected"
                ;;

            #------------------------------------------------
            # DOWN
            #------------------------------------------------

            "$EVENT_DOWN")

                if (( selected < item_count - 1 ))
                then
                    selected=$(( selected + 1 ))
                else
                    selected=0
                fi

                MENU_MAIN_SELECTED="$selected"
                ;;

            #------------------------------------------------
            # HOME
            #------------------------------------------------

            "$EVENT_HOME")

                selected=0
                MENU_MAIN_SELECTED="$selected"
                ;;

            #------------------------------------------------
            # END
            #------------------------------------------------

            "$EVENT_END")

                selected=$(( item_count - 1 ))
                MENU_MAIN_SELECTED="$selected"
                ;;

            #------------------------------------------------
            # ENTER
            #------------------------------------------------

            "$EVENT_SELECT")

                MENU_MAIN_SELECTED="$selected"

                menu_main_log_info \
                    "SELECT event: index=$selected item=${items[selected]}"

                operation_rc=0

                case "$selected" in

                    #----------------------------------------
                    # FULL INSTALLATION
                    #----------------------------------------

                    0)

                        menu_main_log_info \
                            "ENTER -> FULL INSTALLATION"

                        if menu_main_install
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi

                        menu_main_log_info \
                            "FULL INSTALLATION finished with rc=$operation_rc"
                        ;;

                    #----------------------------------------
                    # PARTITION
                    #----------------------------------------

                    1)

                        menu_main_log_info \
                            "ENTER -> PARTITION"

                        if menu_main_partition
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    #----------------------------------------
                    # FILESYSTEM
                    #----------------------------------------

                    2)

                        menu_main_log_info \
                            "ENTER -> FILESYSTEM"

                        if menu_main_filesystem
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    #----------------------------------------
                    # MOUNT
                    #----------------------------------------

                    3)

                        menu_main_log_info \
                            "ENTER -> MOUNT"

                        if menu_main_mount
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    #----------------------------------------
                    # PACKAGES
                    #----------------------------------------

                    4)

                        menu_main_log_info \
                            "ENTER -> PACKAGES"

                        if menu_main_packages
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    #----------------------------------------
                    # BOOTLOADER
                    #----------------------------------------

                    5)

                        menu_main_log_info \
                            "ENTER -> BOOTLOADER"

                        if menu_main_bootloader
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    #----------------------------------------
                    # SYSTEM INFORMATION
                    #----------------------------------------

                    6)

                        menu_main_log_info \
                            "ENTER -> SYSTEM INFORMATION"

                        if menu_main_system_info
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    #----------------------------------------
                    # SHELL
                    #----------------------------------------

                    7)

                        menu_main_log_info \
                            "ENTER -> SHELL"

                        if menu_main_shell
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    #----------------------------------------
                    # EXIT
                    #----------------------------------------

                    8)

                        menu_main_log_info \
                            "ENTER -> EXIT"

                        if menu_main_exit
                        then
                            menu_main_log_info \
                                "Main menu exiting"

                            MENU_MAIN_SELECTED="$selected"

                            return 0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    #----------------------------------------
                    # INVALID
                    #----------------------------------------

                    *)

                        menu_main_log_error \
                            "Invalid menu index: $selected"

                        operation_rc=1
                        ;;
                esac

                if (( operation_rc != 0 ))
                then
                    menu_main_log_error \
                        "Menu operation failed: index=$selected rc=$operation_rc"
                else
                    menu_main_log_info \
                        "Menu operation completed: index=$selected"
                fi
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

                menu_main_log_info \
                    "ESC cancelled by user"

                selected="${MENU_MAIN_SELECTED:-$selected}"

                if ! [[ "$selected" =~ ^[0-9]+$ ]]
                then
                    selected=0
                fi

                if (( selected >= item_count ))
                then
                    selected=$(( item_count - 1 ))
                fi
                ;;

            #------------------------------------------------
            # NO EVENT
            #------------------------------------------------

            "$EVENT_NONE"|"")
                menu_main_log_info \
                    "No actionable event"
                ;;

            #------------------------------------------------
            # UNKNOWN
            #------------------------------------------------

            *)

                menu_main_log_warn \
                    "Unhandled TUI event: ${TUI_EVENT:-unknown}"
                ;;
        esac
    done
}

#============================================================
# Direct execution
#============================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
    menu_main
    exit $?
fi
