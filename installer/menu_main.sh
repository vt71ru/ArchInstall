#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# installer/menu_main.sh
#
# Главное меню установщика.
#
#============================================================

#============================================================
# STATE
#============================================================

MENU_MAIN_SELECTED="${MENU_MAIN_SELECTED:-0}"

#============================================================
# LOGGING
#============================================================

menu_main_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$*" || true
    else
        printf '[INFO] %s\n' "$*" >&2
    fi

    return 0
}

menu_main_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$*" || true
    else
        printf '[WARN] %s\n' "$*" >&2
    fi

    return 0
}

menu_main_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$*" || true
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
    local function_name=""
    local missing=0

    menu_main_log_info \
        "Checking installer controller API"

    for function_name in \
        installer_full_install \
        installer_run_stage \
        installer_get_stage_title
    do
        if ! declare -F "$function_name" >/dev/null 2>&1
        then
            menu_main_log_error \
                "Missing controller function: ${function_name}"

            missing=1
        else
            menu_main_log_info \
                "Controller function OK: ${function_name}"
        fi
    done

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
    tui_clear || return 1

    titlebar_draw \
        "Arch Linux Installer" || return 1

    tui_move 3 5 || return 1

    color_info \
        "Arch Linux Installation System" || return 1

    tui_move 4 5 || return 1

    tui_print \
        "Use Up/Down to navigate and Enter to select." \
        || return 1

    return 0
}

#============================================================
# READ EVENT
#============================================================

menu_main_read_event()
{
    TUI_EVENT="${EVENT_NONE:-NONE}"
    TUI_EVENT_CHAR=""

    if ! event_read
    then
        menu_main_log_error \
            "event_read() failed"

        return 1
    fi

    menu_main_log_info \
        "EVENT=[${TUI_EVENT:-EMPTY}]"

    if [[ "${TUI_EVENT:-}" == "${EVENT_CHAR:-CHAR}" ]]
    then
        menu_main_log_info \
            "EVENT_CHAR=[${TUI_EVENT_CHAR:-EMPTY}]"
    fi

    return 0
}

#============================================================
# WAIT
#============================================================

menu_main_wait()
{
    while true
    do
        if ! menu_main_read_event
        then
            return 1
        fi

        case "${TUI_EVENT:-}" in
            "$EVENT_SELECT"|"$EVENT_BACK")
                return 0
                ;;
        esac
    done
}

#============================================================
# OPERATION ERROR
#============================================================

menu_main_operation_failed()
{
    local title="${1:-Operation failed}"
    local message="${2:-Unknown error}"

    menu_main_log_error \
        "${title}: ${message}"

    if declare -F dialog_error >/dev/null 2>&1
    then
        dialog_error \
            "$title" \
            "$message" || true

        return 0
    fi

    tui_clear || true

    titlebar_draw \
        "$title" || true

    tui_move 7 5 || true

    color_error \
        "$message" || true

    tui_move 10 5 || true

    color_info \
        "Press Enter or Esc to continue." || true

    screen_refresh 2>/dev/null || true

    menu_main_wait || true

    return 0
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
            "Stage name is empty."

        return 1
    fi

    if ! title="$(
        installer_get_stage_title "$stage" 2>/dev/null
    )"
    then
        title="$stage"
    fi

    [[ -n "$title" ]] || title="$stage"

    menu_main_log_info \
        "Running stage: ${stage}"

    tui_clear || return 1

    titlebar_draw \
        "Arch Linux Installer" || return 1

    tui_move 5 5 || return 1

    color_info \
        "Starting: ${title}" || return 1

    tui_move 7 5 || return 1

    tui_print \
        "Stage: ${stage}" || return 1

    tui_move 9 5 || return 1

    tui_print \
        "Please wait..." || return 1

    screen_refresh 2>/dev/null || true

    menu_main_log_info \
        "Calling installer_run_stage(${stage})"

    if installer_run_stage "$stage"
    then
        rc=0
    else
        rc=$?
    fi

    menu_main_log_info \
        "installer_run_stage(${stage}) returned rc=${rc}"

    if (( rc != 0 ))
    then
        menu_main_operation_failed \
            "$title" \
            "Stage failed. Return code: ${rc}" || true

        return "$rc"
    fi

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
    local stage=""

    menu_main_log_info \
        "### NEW MENU_MAIN_INSTALL ###"

    menu_main_log_info \
        "FULL INSTALLATION SELECTED"

    menu_main_log_info \
        "CHECK installer_full_install()"

    if ! declare -F installer_full_install >/dev/null 2>&1
    then
        menu_main_log_error \
            "installer_full_install() is NOT loaded"

        menu_main_operation_failed \
            "Controller error" \
            "installer_full_install() is not available." || true

        return 127
    fi

    menu_main_log_info \
        "installer_full_install() is available"

    menu_main_log_info \
        "FUNCTION=$(declare -F installer_full_install)"

    if ! tui_clear
    then
        menu_main_log_error \
            "tui_clear() failed"

        return 1
    fi

    if ! titlebar_draw \
        "Full Installation"
    then
        menu_main_log_error \
            "titlebar_draw() failed"

        return 1
    fi

    tui_move 5 5 || return 1

    color_info \
        "FULL INSTALLATION" || return 1

    tui_move 7 5 || return 1

    tui_print \
        "All installation stages will be executed sequentially." \
        || return 1

    tui_move 9 5 || return 1

    tui_print \
        "Starting installer controller..." \
        || return 1

    tui_move 11 5 || return 1

    tui_print \
        "Please wait..." \
        || return 1

    screen_refresh 2>/dev/null || true

    menu_main_log_info \
        "ACTION=[FULL_INSTALLATION]"

    menu_main_log_info \
        "CALL=[installer_full_install]"

    #
    # Прямой диагностический маркер.
    #

    printf '%s\n' \
        "================ CALL=[installer_full_install]" \
        >/dev/tty 2>/dev/null || true

    if installer_full_install
    then
        rc=0
    else
        rc=$?
    fi

    menu_main_log_info \
        "RETURN=[installer_full_install] RC=${rc}"

    if (( rc != 0 ))
    then
        stage="${INSTALLER_STAGE:-unknown}"

        menu_main_log_error \
            "FULL INSTALLATION FAILED"

        menu_main_log_error \
            "STAGE=[${stage}]"

        menu_main_log_error \
            "RC=[${rc}]"

        menu_main_operation_failed \
            "Installation failed" \
            "Stage: ${stage}, return code: ${rc}" || true

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
    local kernel="unknown"
    local arch="unknown"
    local memory="unknown"
    local cpu="unknown"

    if command -v uname >/dev/null 2>&1
    then
        kernel="$(uname -r 2>/dev/null || printf '%s' 'unknown')"
        arch="$(uname -m 2>/dev/null || printf '%s' 'unknown')"
    fi

    if command -v free >/dev/null 2>&1
    then
        memory="$(
            free -h 2>/dev/null |
            awk '
                /^Mem:/ {
                    print $2 " total, " \
                          $3 " used, " \
                          $7 " available"
                    found=1
                    exit
                }

                END {
                    if (!found)
                        print "unknown"
                }
            '
        )"
    fi

    if command -v nproc >/dev/null 2>&1
    then
        cpu="$(nproc 2>/dev/null || printf '%s' 'unknown')"
    fi

    tui_clear || return 1

    titlebar_draw \
        "System Information" || return 1

    tui_move 5 5 || return 1

    color_info "Kernel:" || return 1
    tui_print " ${kernel}" || return 1

    tui_move 7 5 || return 1

    color_info "Architecture:" || return 1
    tui_print " ${arch}" || return 1

    tui_move 9 5 || return 1

    color_info "Memory:" || return 1
    tui_print " ${memory}" || return 1

    tui_move 11 5 || return 1

    color_info "CPU cores:" || return 1
    tui_print " ${cpu}" || return 1

    tui_move \
        "$((TUI_ROWS - 2))" \
        5 || return 1

    color_info \
        "Press Enter or Esc to return." || return 1

    screen_refresh 2>/dev/null || true

    menu_main_wait

    return $?
}

#============================================================
# OPEN SHELL
#============================================================

menu_main_shell()
{
    local rc=0

    menu_main_log_info \
        "Opening interactive shell"

    tui_restore || true

    printf '\n'
    printf 'Arch Installer shell\n'
    printf 'Type "exit" to return to the installer.\n\n'

    /bin/bash

    rc=$?

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
    if declare -F dialog_confirm >/dev/null 2>&1
    then
        if dialog_confirm \
            "Exit Arch Installer?"
        then
            menu_main_log_info \
                "Exit confirmed"

            return 0
        fi

        return 1
    fi

    menu_main_log_warn \
        "dialog_confirm() unavailable; exiting"

    return 0
}

#============================================================
# DRAW MENU
#============================================================

menu_main_draw()
{
    local -n items_ref="$1"

    local selected="${2:-0}"
    local item_count="${#items_ref[@]}"

    local box_row=6
    local box_col=5
    local box_height
    local box_width
    local row
    local i

    if (( item_count == 0 ))
    then
        menu_main_log_error \
            "menu_main_draw(): empty menu"

        return 1
    fi

    if ! [[ "$selected" =~ ^[0-9]+$ ]]
    then
        selected=0
    fi

    if (( selected >= item_count ))
    then
        selected=$((item_count - 1))
    fi

    tui_update_size || true

    box_height=$((item_count + 4))
    box_width=$((TUI_COLS - 10))

    if (( box_width < 40 ))
    then
        box_width=40
    fi

    if (( box_height > TUI_ROWS - 2 ))
    then
        box_height=$((TUI_ROWS - 2))
    fi

    if (( box_width > TUI_COLS - 2 ))
    then
        box_width=$((TUI_COLS - 2))
    fi

    if (( box_width < 2 || box_height < 2 ))
    then
        menu_main_log_error \
            "Terminal is too small for main menu"

        return 1
    fi

    menu_main_header || return 1

    draw_box \
        "$box_row" \
        "$box_col" \
        "$box_height" \
        "$box_width" \
        "Main Menu" || return 1

    row=$((box_row + 2))

    for ((i = 0; i < item_count; i++))
    do
        if (( row >= TUI_ROWS - 1 ))
        then
            break
        fi

        tui_move \
            "$row" \
            "$((box_col + 3))" || return 1

        if (( i == selected ))
        then
            color_selected \
                "> ${items_ref[i]}" || return 1
        else
            tui_print \
                "  ${items_ref[i]}" || return 1
        fi

        row=$((row + 1))
    done

    statusbar_draw \
        "↑↓ Navigate   Home/End Move   Enter Select   Esc Exit" \
        || return 1

    screen_refresh 2>/dev/null || true

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

    local item_count="${#items[@]}"
    local selected="${MENU_MAIN_SELECTED:-0}"
    local operation_rc=0

    menu_main_log_info \
        "============================================================"

    menu_main_log_info \
        "Entering main menu"

    if ! menu_main_check_controller
    then
        menu_main_operation_failed \
            "Controller error" \
            "Required installer controller functions are not loaded." \
            || true

        return 1
    fi

    if ! [[ "$selected" =~ ^[0-9]+$ ]]
    then
        selected=0
    fi

    if (( selected >= item_count ))
    then
        selected=0
    fi

    MENU_MAIN_SELECTED="$selected"

    menu_main_log_info \
        "Initial selection index=${selected}"

    menu_main_log_info \
        "Initial selection item=${items[selected]}"

    while true
    do
        if ! menu_main_draw \
            items \
            "$selected"
        then
            menu_main_log_error \
                "menu_main_draw() failed"

            return 1
        fi

        if ! menu_main_read_event
        then
            return 1
        fi

        menu_main_log_info \
            "EVENT=[${TUI_EVENT:-EMPTY}]"

        menu_main_log_info \
            "SELECTED=[${selected}]"

        menu_main_log_info \
            "ITEM=[${items[selected]}]"

        case "${TUI_EVENT:-}" in
            "$EVENT_UP")
                if (( selected > 0 ))
                then
                    selected=$((selected - 1))
                else
                    selected=$((item_count - 1))
                fi

                MENU_MAIN_SELECTED="$selected"
                ;;

            "$EVENT_DOWN")
                if (( selected < item_count - 1 ))
                then
                    selected=$((selected + 1))
                else
                    selected=0
                fi

                MENU_MAIN_SELECTED="$selected"
                ;;

            "$EVENT_HOME")
                selected=0
                MENU_MAIN_SELECTED=0
                ;;

            "$EVENT_END")
                selected=$((item_count - 1))
                MENU_MAIN_SELECTED="$selected"
                ;;

            "$EVENT_SELECT")
                MENU_MAIN_SELECTED="$selected"
                operation_rc=0

                menu_main_log_info \
                    "ENTER PRESSED"

                menu_main_log_info \
                    "SELECTED INDEX=[${selected}]"

                menu_main_log_info \
                    "SELECTED ITEM=[${items[selected]}]"

                case "$selected"
                in
                    0)
                        menu_main_log_info \
                            "ACTION=[FULL_INSTALLATION]"

                        menu_main_log_info \
                            "DISPATCH -> menu_main_install"

                        if menu_main_install
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi

                        menu_main_log_info \
                            "DISPATCH <- menu_main_install RC=${operation_rc}"
                        ;;

                    1)
                        menu_main_log_info \
                            "ACTION=[PARTITION]"

                        if menu_main_partition
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    2)
                        menu_main_log_info \
                            "ACTION=[FILESYSTEM]"

                        if menu_main_filesystem
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    3)
                        menu_main_log_info \
                            "ACTION=[MOUNT]"

                        if menu_main_mount
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    4)
                        menu_main_log_info \
                            "ACTION=[PACKAGES]"

                        if menu_main_packages
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    5)
                        menu_main_log_info \
                            "ACTION=[BOOTLOADER]"

                        if menu_main_bootloader
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    6)
                        menu_main_log_info \
                            "ACTION=[SYSTEM_INFORMATION]"

                        if menu_main_system_info
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    7)
                        menu_main_log_info \
                            "ACTION=[SHELL]"

                        if menu_main_shell
                        then
                            operation_rc=0
                        else
                            operation_rc=$?
                        fi
                        ;;

                    8)
                        menu_main_log_info \
                            "ACTION=[EXIT]"

                        if menu_main_exit
                        then
                            menu_main_log_info \
                                "EXIT CONFIRMED"

                            return 0
                        fi

                        operation_rc=1
                        ;;
                esac

                if (( operation_rc == 0 ))
                then
                    menu_main_log_info \
                        "MENU ACTION RESULT=[SUCCESS]"
                else
                    menu_main_log_error \
                        "MENU ACTION RESULT=[FAILED] RC=${operation_rc}"
                fi
                ;;

            "$EVENT_BACK")
                menu_main_log_info \
                    "ESC PRESSED"

                if menu_main_exit
                then
                    menu_main_log_info \
                        "EXIT CONFIRMED BY ESC"

                    return 0
                fi

                menu_main_log_info \
                    "EXIT CANCELLED BY ESC"
                ;;

            "$EVENT_NONE"|"")
                ;;

            "$EVENT_CHAR")
                menu_main_log_info \
                    "Ignoring character event: [${TUI_EVENT_CHAR:-empty}]"
                ;;

            *)
                menu_main_log_warn \
                    "Unhandled event: [${TUI_EVENT:-empty}]"
                ;;
        esac
    done
}

#============================================================
# DIRECT EXECUTION
#============================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
    menu_main
    exit $?
fi
