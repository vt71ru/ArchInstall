#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# installer/menu_main.sh
#
# Главное меню установщика.
#
# Ответственность:
#   • отображение главного меню
#   • навигация клавиатурой
#   • запуск полной установки
#   • запуск отдельных этапов
#   • системная информация
#   • открытие shell
#   • выход
#
# Не содержит:
#   • реализацию этапов установки
#   • partition logic
#   • filesystem logic
#   • mount logic
#   • package logic
#   • bootloader logic
#
#============================================================

#============================================================
# LOAD GUARD
#============================================================
if [[ -n "${MENU_MAIN_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi
MENU_MAIN_SH_LOADED=1
export MENU_MAIN_SH_LOADED
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
        logger_info "$@" || true
    elif declare -F log_info >/dev/null 2>&1
    then
        log_info "$@" || true
    else
        printf '[INFO] %s\n' "$*" >&2
    fi

    return 0
}
menu_main_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@" || true
    elif declare -F log_warn >/dev/null 2>&1
    then
        log_warn "$@" || true
    else
        printf '[WARN] %s\n' "$*" >&2
    fi

    return 0
}
menu_main_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@" || true
    elif declare -F log_error >/dev/null 2>&1
    then
        log_error "$@" || true
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
    local function_name

    menu_main_log_info \
        "Checking installer controller API"

    for function_name in \
        installer_run \
        installer_full_install \
        installer_run_stage \
        installer_get_stage_title \
        installer_check_stage \
        installer_check_all_stages
    do
        if ! declare -F "$function_name" >/dev/null 2>&1
        then
            menu_main_log_error \
                "Missing controller function: ${function_name}"

            missing=1
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
    if ! tui_clear
    then
        menu_main_log_error \
            "tui_clear() failed"

        return 1
    fi

    if ! titlebar_draw \
        "Arch Linux Installer"
    then
        menu_main_log_error \
            "titlebar_draw() failed"

        return 1
    fi

    if ! tui_move \
        3 \
        5
    then
        return 1
    fi

    if ! color_info \
        "Arch Linux Installation System"
    then
        return 1
    fi

    if ! tui_move \
        4 \
        5
    then
        return 1
    fi

    if ! tui_print \
        "Use Up/Down to navigate and Enter to select."
    then
        return 1
    fi

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

            "$EVENT_SELECT")
                return 0
                ;;

            "$EVENT_BACK")
                return 0
                ;;

            "$EVENT_NONE"|"")
                ;;

            "$EVENT_CHAR")
                ;;

            *)
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

    if ! tui_clear
    then
        return 1
    fi

    titlebar_draw \
        "$title" || true

    tui_move \
        7 \
        5 || true

    color_error \
        "$message" || true

    tui_move \
        10 \
        5 || true

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

    #--------------------------------------------------------
    # Prepare screen
    #--------------------------------------------------------

    if ! tui_clear
    then
        return 1
    fi

    if ! titlebar_draw \
        "Arch Linux Installer"
    then
        return 1
    fi

    if ! tui_move \
        5 \
        5
    then
        return 1
    fi

    if ! color_info \
        "Starting: ${title}"
    then
        return 1
    fi

    if ! tui_move \
        7 \
        5
    then
        return 1
    fi

    if ! tui_print \
        "Stage: ${stage}"
    then
        return 1
    fi

    if ! tui_move \
        9 \
        5
    then
        return 1
    fi

    if ! tui_print \
        "Please wait..."
    then
        return 1
    fi

    screen_refresh 2>/dev/null || true

    #--------------------------------------------------------
    # Call controller
    #--------------------------------------------------------

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

    #--------------------------------------------------------
    # Failure
    #--------------------------------------------------------

    if (( rc != 0 ))
    then
        menu_main_operation_failed \
            "$title" \
            "Stage failed. Return code: ${rc}" || true

        return "$rc"
    fi

    #--------------------------------------------------------
    # Success
    #--------------------------------------------------------

    menu_main_log_info \
        "Stage completed successfully: ${stage}"

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
    local total=""
    local progress=""

    menu_main_log_info \
        "============================================================"

    menu_main_log_info \
        "FULL INSTALLATION SELECTED"

    menu_main_log_info \
        "Checking installer_full_install()"

    #--------------------------------------------------------
    # Controller check
    #--------------------------------------------------------

    if ! declare -F installer_full_install >/dev/null 2>&1
    then
        menu_main_log_error \
            "installer_full_install() is not loaded"

        menu_main_operation_failed \
            "Controller error" \
            "installer_full_install() is not available." || true

        return 127
    fi

    menu_main_log_info \
        "installer_full_install() is available"

    #--------------------------------------------------------
    # Read total stage count when possible
    #--------------------------------------------------------

    if declare -p INSTALLER_STAGES >/dev/null 2>&1
    then
        total="${#INSTALLER_STAGES[@]}"
    fi

    if [[ -z "$total" || ! "$total" =~ ^[0-9]+$ ]]
    then
        total="?"
    fi

    progress="Starting full installation (${total} stages)"

    #--------------------------------------------------------
    # Display
    #--------------------------------------------------------

    if ! tui_clear
    then
        return 1
    fi

    if ! titlebar_draw \
        "Full Installation"
    then
        return 1
    fi

    if ! tui_move \
        5 \
        5
    then
        return 1
    fi

    if ! color_info \
        "FULL INSTALLATION"
    then
        return 1
    fi

    if ! tui_move \
        7 \
        5
    then
        return 1
    fi

    if ! tui_print \
        "All installation stages will be executed sequentially."
    then
        return 1
    fi

    if ! tui_move \
        9 \
        5
    then
        return 1
    fi

    if ! tui_print \
        "$progress"
    then
        return 1
    fi

    if ! tui_move \
        11 \
        5
    then
        return 1
    fi

    if ! tui_print \
        "Starting installer controller..."
    then
        return 1
    fi

    if ! tui_move \
        13 \
        5
    then
        return 1
    fi

    if ! tui_print \
        "Please wait..."
    then
        return 1
    fi

    screen_refresh 2>/dev/null || true

    #--------------------------------------------------------
    # Call controller
    #--------------------------------------------------------

    menu_main_log_info \
        "ACTION=[FULL_INSTALLATION]"

    menu_main_log_info \
        "CALL=[installer_full_install]"

    if installer_full_install
    then
        rc=0
    else
        rc=$?
    fi

    menu_main_log_info \
        "RETURN=[installer_full_install] RC=${rc}"

    #--------------------------------------------------------
    # Failure
    #--------------------------------------------------------

    if (( rc != 0 ))
    then
        stage="${INSTALLER_STAGE:-unknown}"

        menu_main_log_error \
            "FULL INSTALLATION FAILED"

        menu_main_log_error \
            "FAILED STAGE=[${stage}]"

        menu_main_log_error \
            "RETURN CODE=[${rc}]"

        menu_main_operation_failed \
            "Installation failed" \
            "Stage: ${stage}\nReturn code: ${rc}" || true

        return "$rc"
    fi

    #--------------------------------------------------------
    # Success
    #--------------------------------------------------------

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

    kernel="$(
        uname -r 2>/dev/null ||
        printf '%s' 'unknown'
    )"

    arch="$(
        uname -m 2>/dev/null ||
        printf '%s' 'unknown'
    )"

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

    [[ -n "$memory" ]] || \
        memory="unknown"

    if command -v nproc >/dev/null 2>&1
    then
        cpu="$(
            nproc 2>/dev/null || true
        )"
    fi

    [[ -n "$cpu" ]] || \
        cpu="unknown"

    if ! tui_clear
    then
        return 1
    fi

    if ! titlebar_draw \
        "System Information"
    then
        return 1
    fi

    tui_move 5 5 || return 1

    color_info \
        "Kernel:" || return 1

    tui_print \
        " ${kernel}" || return 1

    tui_move 7 5 || return 1

    color_info \
        "Architecture:" || return 1

    tui_print \
        " ${arch}" || return 1

    tui_move 9 5 || return 1

    color_info \
        "Memory:" || return 1

    tui_print \
        " ${memory}" || return 1

    tui_move 11 5 || return 1

    color_info \
        "CPU cores:" || return 1

    tui_print \
        " ${cpu}" || return 1

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

    if ! tui_restore
    then
        menu_main_log_warn \
            "tui_restore() returned failure"
    fi

    printf '\n'
    printf 'Arch Installer shell\n'
    printf 'Type "exit" to return to the installer.\n\n'

    /bin/bash
    rc=$?

    printf '\n'
    printf 'Returning to Arch Installer...\n'

    sleep 1

    menu_main_log_info \
        "Restarting TUI"

    if ! tui_start
    then
        menu_main_log_error \
            "Failed to restart TUI after shell"

        return 1
    fi

    menu_main_log_info \
        "TUI restarted"

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
                "Exit confirmed"

            return 0
        fi

        menu_main_log_info \
            "Exit cancelled"

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
    local box_height=0
    local box_width=0
    local row=0
    local i=0

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

    if (( selected < 0 ))
    then
        selected=0
    fi

    if (( selected >= item_count ))
    then
        selected=$((item_count - 1))
    fi

    if declare -F tui_update_size >/dev/null 2>&1
    then
        tui_update_size || true
    fi

    #--------------------------------------------------------
    # Terminal dimensions
    #--------------------------------------------------------

    if [[ -n "${TUI_COLS:-}" && "$TUI_COLS" =~ ^[0-9]+$ ]]
    then
        box_width=$((TUI_COLS - 10))
    else
        box_width=60
    fi

    if [[ -n "${TUI_ROWS:-}" && "$TUI_ROWS" =~ ^[0-9]+$ ]]
    then
        box_height=$((item_count + 4))

        if (( box_height > TUI_ROWS - 2 ))
        then
            box_height=$((TUI_ROWS - 2))
        fi
    else
        box_height=$((item_count + 4))
    fi

    if (( box_width < 40 ))
    then
        box_width=40
    fi

    if [[ -n "${TUI_COLS:-}" && "$TUI_COLS" =~ ^[0-9]+$ ]]
    then
        if (( box_width > TUI_COLS - 2 ))
        then
            box_width=$((TUI_COLS - 2))
        fi
    fi

    if (( box_height < 2 || box_width < 2 ))
    then
        menu_main_log_error \
            "Terminal is too small for main menu"

        return 1
    fi

    #--------------------------------------------------------
    # Header
    #--------------------------------------------------------

    if ! menu_main_header
    then
        return 1
    fi

    #--------------------------------------------------------
    # Main box
    #
    # Existing draw_box API in this project uses:
    #
    #   draw_box row col height width title
    #
    #--------------------------------------------------------

    if ! draw_box \
        "$box_row" \
        "$box_col" \
        "$box_height" \
        "$box_width" \
        "Main Menu"
    then
        menu_main_log_error \
            "draw_box() failed"

        return 1
    fi

    #--------------------------------------------------------
    # Menu items
    #--------------------------------------------------------

    row=$((box_row + 2))

    for ((i = 0; i < item_count; i++))
    do
        # Don't draw beyond available terminal area.
        if [[ -n "${TUI_ROWS:-}" && "$TUI_ROWS" =~ ^[0-9]+$ ]]
        then
            if (( row >= TUI_ROWS - 1 ))
            then
                break
            fi
        fi

        if ! tui_move \
            "$row" \
            "$((box_col + 3))"
        then
            return 1
        fi

        if (( i == selected ))
        then
            if ! color_selected \
                "> ${items_ref[i]}"
            then
                return 1
            fi
        else
            if ! tui_print \
                "  ${items_ref[i]}"
            then
                return 1
            fi
        fi

        row=$((row + 1))
    done

    #--------------------------------------------------------
    # Status bar
    #--------------------------------------------------------

    if ! statusbar_draw \
        "↑↓ Navigate   Home/End Move   Enter Select   Esc Exit"
    then
        return 1
    fi

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

    #--------------------------------------------------------
    # Controller API
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
    # Normalize selection
    #--------------------------------------------------------

    if ! [[ "$selected" =~ ^[0-9]+$ ]]
    then
        selected=0
    fi

    if (( selected < 0 || selected >= item_count ))
    then
        selected=0
    fi

    MENU_MAIN_SELECTED="$selected"

    menu_main_log_info \
        "Initial selection index=${selected}"

    menu_main_log_info \
        "Initial selection item=${items[selected]}"

    #========================================================
    # MENU LOOP
    #========================================================

    while true
    do
        #----------------------------------------------------
        # Draw
        #----------------------------------------------------

        if ! menu_main_draw \
            items \
            "$selected"
        then
            menu_main_log_error \
                "menu_main_draw() failed"

            return 1
        fi

        #----------------------------------------------------
        # Read keyboard
        #----------------------------------------------------

        if ! menu_main_read_event
        then
            return 1
        fi

        menu_main_log_info \
            "EVENT=[${TUI_EVENT:-EMPTY}] SELECTED=[${selected}] ITEM=[${items[selected]}]"

        #====================================================
        # EVENT DISPATCH
        #====================================================

        case "${TUI_EVENT:-}" in

            #------------------------------------------------
            # UP
            #------------------------------------------------

            "$EVENT_UP")

                if (( selected > 0 ))
                then
                    selected=$((selected - 1))
                else
                    selected=$((item_count - 1))
                fi

                MENU_MAIN_SELECTED="$selected"

                menu_main_log_info \
                    "Selection moved UP: index=${selected}"

                ;;

            #------------------------------------------------
            # DOWN
            #------------------------------------------------

            "$EVENT_DOWN")

                if (( selected < item_count - 1 ))
                then
                    selected=$((selected + 1))
                else
                    selected=0
                fi

                MENU_MAIN_SELECTED="$selected"

                menu_main_log_info \
                    "Selection moved DOWN: index=${selected}"

                ;;

            #------------------------------------------------
            # HOME
            #------------------------------------------------

            "$EVENT_HOME")

                selected=0
                MENU_MAIN_SELECTED=0

                menu_main_log_info \
                    "Selection moved HOME"

                ;;

            #------------------------------------------------
            # END
            #------------------------------------------------

            "$EVENT_END")

                selected=$((item_count - 1))
                MENU_MAIN_SELECTED="$selected"

                menu_main_log_info \
                    "Selection moved END"

                ;;

            #------------------------------------------------
            # SELECT
            #------------------------------------------------

            "$EVENT_SELECT")

                MENU_MAIN_SELECTED="$selected"

                operation_rc=0

                menu_main_log_info \
                    "============================================================"

                menu_main_log_info \
                    "ENTER PRESSED"

                menu_main_log_info \
                    "SELECTED INDEX=[${selected}]"

                menu_main_log_info \
                    "SELECTED ITEM=[${items[selected]}]"

                #============================================
                # 0 - FULL INSTALLATION
                #============================================

                if (( selected == 0 ))
                then
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
                fi

                #============================================
                # 1 - PARTITION
                #============================================

                if (( selected == 1 ))
                then
                    menu_main_log_info \
                        "ACTION=[PARTITION]"

                    if menu_main_partition
                    then
                        operation_rc=0
                    else
                        operation_rc=$?
                    fi

                    menu_main_log_info \
                        "PARTITION RESULT RC=${operation_rc}"
                fi

                #============================================
                # 2 - FILESYSTEM
                #============================================

                if (( selected == 2 ))
                then
                    menu_main_log_info \
                        "ACTION=[FILESYSTEM]"

                    if menu_main_filesystem
                    then
                        operation_rc=0
                    else
                        operation_rc=$?
                    fi

                    menu_main_log_info \
                        "FILESYSTEM RESULT RC=${operation_rc}"
                fi

                #============================================
                # 3 - MOUNT
                #============================================

                if (( selected == 3 ))
                then
                    menu_main_log_info \
                        "ACTION=[MOUNT]"

                    if menu_main_mount
                    then
                        operation_rc=0
                    else
                        operation_rc=$?
                    fi

                    menu_main_log_info \
                        "MOUNT RESULT RC=${operation_rc}"
                fi

                #============================================
                # 4 - PACKAGES
                #============================================

                if (( selected == 4 ))
                then
                    menu_main_log_info \
                        "ACTION=[PACKAGES]"

                    if menu_main_packages
                    then
                        operation_rc=0
                    else
                        operation_rc=$?
                    fi

                    menu_main_log_info \
                        "PACKAGES RESULT RC=${operation_rc}"
                fi

                #============================================
                # 5 - BOOTLOADER
                #============================================

                if (( selected == 5 ))
                then
                    menu_main_log_info \
                        "ACTION=[BOOTLOADER]"

                    if menu_main_bootloader
                    then
                        operation_rc=0
                    else
                        operation_rc=$?
                    fi

                    menu_main_log_info \
                        "BOOTLOADER RESULT RC=${operation_rc}"
                fi

                #============================================
                # 6 - SYSTEM INFORMATION
                #============================================

                if (( selected == 6 ))
                then
                    menu_main_log_info \
                        "ACTION=[SYSTEM_INFORMATION]"

                    if menu_main_system_info
                    then
                        operation_rc=0
                    else
                        operation_rc=$?
                    fi

                    menu_main_log_info \
                        "SYSTEM_INFORMATION RESULT RC=${operation_rc}"
                fi

                #============================================
                # 7 - SHELL
                #============================================

                if (( selected == 7 ))
                then
                    menu_main_log_info \
                        "ACTION=[SHELL]"

                    if menu_main_shell
                    then
                        operation_rc=0
                    else
                        operation_rc=$?
                    fi

                    menu_main_log_info \
                        "SHELL RESULT RC=${operation_rc}"
                fi

                #============================================
                # 8 - EXIT
                #============================================

                if (( selected == 8 ))
                then
                    menu_main_log_info \
                        "ACTION=[EXIT]"

                    if menu_main_exit
                    then
                        menu_main_log_info \
                            "EXIT CONFIRMED"

                        MENU_MAIN_SELECTED="$selected"

                        return 0
                    fi

                    menu_main_log_info \
                        "EXIT CANCELLED"

                    operation_rc=1
                fi

                #------------------------------------------------
                # Action result
                #------------------------------------------------

                if (( operation_rc == 0 ))
                then
                    menu_main_log_info \
                        "MENU ACTION RESULT=[SUCCESS]"
                else
                    menu_main_log_error \
                        "MENU ACTION RESULT=[FAILED] RC=${operation_rc}"
                fi

                ;;

            #------------------------------------------------
            # ESC
            #------------------------------------------------

            "$EVENT_BACK")

                menu_main_log_info \
                    "ESC PRESSED"

                if menu_main_exit
                then
                    menu_main_log_info \
                        "EXIT CONFIRMED BY ESC"

                    MENU_MAIN_SELECTED="$selected"

                    return 0
                fi

                menu_main_log_info \
                    "EXIT CANCELLED BY ESC"

                ;;

            #------------------------------------------------
            # NONE
            #------------------------------------------------

            "$EVENT_NONE"|"")

                ;;

            #------------------------------------------------
            # CHARACTER
            #------------------------------------------------

            "$EVENT_CHAR")

                menu_main_log_info \
                    "Ignoring character event: [${TUI_EVENT_CHAR:-empty}]"

                ;;

            #------------------------------------------------
            # UNKNOWN
            #------------------------------------------------

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
