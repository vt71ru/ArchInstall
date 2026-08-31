#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# installer/menu_main.sh
#
# Главное меню Arch Installer.
#
# Ответственность:
#   • отображение главного меню
#   • обработка клавиатуры
#   • вызов controller API
#   • отображение ошибок операций
#
# Не отвечает за:
#   • реализацию этапов установки
#   • хранение конфигурации
#   • загрузку модулей
#   • инициализацию TUI
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
# Check controller
#============================================================

menu_main_check_controller()
{
    local function_name

    for function_name in \
        installer_run \
        installer_full_install \
        installer_run_stage \
        installer_get_stage_title
    do
        if ! declare -F "$function_name" >/dev/null 2>&1
        then
            menu_main_log_error \
                "Controller function unavailable: ${function_name}"

            return 1
        fi
    done

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
            "Arch Installer" \
            || return 1
    fi

    tui_move \
        3 \
        5 \
        || return 1

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
        5 \
        || return 1

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
            "$message" \
            || true
    else
        tui_clear 2>/dev/null || true

        printf '\n'
        printf '========================================\n'
        printf ' %s\n' "$stage"
        printf '========================================\n'
        printf '%s\n' "$message"
        printf '\n'

        printf 'Press Enter to continue...\n'

        read -r </dev/tty || true
    fi

    return 0
}

#============================================================
# Run controller stage
#============================================================

menu_main_run_stage()
{
    local stage="${1:-}"
    local title
    local rc

    if [[ -z "$stage" ]]
    then
        menu_main_operation_failed \
            "Installer" \
            "Stage name is empty."

        return 1
    fi

    if ! declare -F installer_run_stage >/dev/null 2>&1
    then
        menu_main_operation_failed \
            "Installer" \
            "installer_run_stage() is not available."

        return 1
    fi

    title="$(
        installer_get_stage_title \
            "$stage" \
            2>/dev/null \
            || printf '%s' "$stage"
    )"

    menu_main_log_info \
        "Manual stage selected: ${stage}"

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
            "Operation failed. Return code: ${rc}"

        return "$rc"
    fi

    return 0
}

#============================================================
# Full installation
#============================================================

menu_main_install()
{
    local rc

    menu_main_log_info \
        "========================================"

    menu_main_log_info \
        "FULL INSTALLATION SELECTED"

    menu_main_log_info \
        "========================================"

    #--------------------------------------------------------
    # Controller check
    #--------------------------------------------------------

    if ! declare -F installer_full_install >/dev/null 2>&1
    then
        menu_main_operation_failed \
            "Installation" \
            "installer_full_install() is not available."

        return 1
    fi

    #--------------------------------------------------------
    # Installation screen
    #--------------------------------------------------------

    tui_clear \
        2>/dev/null \
        || true

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "Full Installation" \
            || true
    fi

    tui_move \
        4 \
        5 \
        2>/dev/null \
        || true

    tui_print \
        "Starting full Arch Linux installation..." \
        2>/dev/null \
        || true

    if declare -F screen_refresh >/dev/null 2>&1
    then
        screen_refresh \
            2>/dev/null \
            || true
    fi

    menu_main_log_info \
        "Calling installer_full_install()"

    #--------------------------------------------------------
    # Run full installation
    #--------------------------------------------------------

    if installer_full_install
    then
        rc=0
    else
        rc=$?
    fi

    #--------------------------------------------------------
    # Result
    #--------------------------------------------------------

    if (( rc == 0 ))
    then
        menu_main_log_info \
            "Full installation completed successfully"

        if declare -F dialog_info >/dev/null 2>&1
        then
            dialog_info \
                "Installation complete" \
                "Full Arch Linux installation completed successfully." \
                || true
        else
            tui_clear \
                2>/dev/null \
                || true

            printf '\n'
            printf '========================================\n'
            printf ' INSTALLATION COMPLETED\n'
            printf '========================================\n'
            printf '\n'
            printf 'Full Arch Linux installation completed.\n'
            printf '\n'
            printf 'Press Enter to return to the main menu...\n'

            read -r </dev/tty || true
        fi

        return 0
    fi

    #--------------------------------------------------------
    # Failure
    #--------------------------------------------------------

    menu_main_log_error \
        "Full installation failed"

    menu_main_log_error \
        "Return code: ${rc}"

    menu_main_operation_failed \
        "Installation failed" \
        "Full installation failed. Return code: ${rc}"

    return "$rc"
}

#============================================================
# Partition
#============================================================

menu_main_partition()
{
    menu_main_run_stage \
        partition
}

#============================================================
# Filesystem
#============================================================

menu_main_filesystem()
{
    menu_main_run_stage \
        filesystem
}

#============================================================
# Mount
#============================================================

menu_main_mount()
{
    menu_main_run_stage \
        mount
}

#============================================================
# Packages
#============================================================

menu_main_packages()
{
    menu_main_run_stage \
        packages
}

#============================================================
# Bootloader
#============================================================

menu_main_bootloader()
{
    menu_main_run_stage \
        bootloader
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

    kernel="$(
        uname -r \
            2>/dev/null \
            || printf '%s' "unknown"
    )"

    arch="$(
        uname -m \
            2>/dev/null \
            || printf '%s' "unknown"
    )"

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

    tui_clear \
        || return 1

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
        8 \
        || return 1

    tui_print \
        "Kernel:  ${kernel}"

    tui_move \
        7 \
        8 \
        || return 1

    tui_print \
        "Arch:    ${arch}"

    tui_move \
        8 \
        8 \
        || return 1

    tui_print \
        "Memory:  ${memory:-unknown}"

    tui_move \
        9 \
        8 \
        || return 1

    tui_print \
        "CPU:     ${cpu:-unknown}"

    tui_move \
        11 \
        8 \
        || return 1

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
    local rc

    menu_main_log_info \
        "Opening installer shell"

    #--------------------------------------------------------
    # Restore terminal before entering interactive shell
    #--------------------------------------------------------

    if declare -F tui_restore >/dev/null 2>&1
    then
        tui_restore \
            || true
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

    #--------------------------------------------------------
    # Restore TUI
    #--------------------------------------------------------

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
    if declare -F dialog_confirm >/dev/null 2>&1
    then
        if dialog_confirm \
            "Exit Arch Installer?"
        then
            menu_main_log_info \
                "User selected exit"

            return 0
        fi

        return 1
    fi

    #--------------------------------------------------------
    # Fallback confirmation
    #--------------------------------------------------------

    printf '\n'
    printf 'Exit Arch Installer? [y/N] '

    local answer

    read -r answer </dev/tty \
        || return 1

    case "${answer,,}"
    in
        y|yes)
            menu_main_log_info \
                "User selected exit"

            return 0
            ;;

        *)
            return 1
            ;;
    esac
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
    local width

    box_height=$((item_count + 4))

    #--------------------------------------------------------
    # Terminal dimensions
    #--------------------------------------------------------

    if [[ -z "${TUI_COLS:-}" ]]
    then
        TUI_COLS=80
    fi

    if [[ -z "${TUI_ROWS:-}" ]]
    then
        TUI_ROWS=24
    fi

    width=$((TUI_COLS - 10))

    if (( width < 20 ))
    then
        width=20
    fi

    #--------------------------------------------------------
    # Header
    #--------------------------------------------------------

    menu_main_header \
        || return 1

    #--------------------------------------------------------
    # Menu box
    #--------------------------------------------------------

    if ! declare -F draw_box >/dev/null 2>&1
    then
        menu_main_log_error \
            "draw_box() is not available"

        return 1
    fi

    draw_box \
        6 \
        5 \
        "$width" \
        "$box_height" \
        || return 1

    #--------------------------------------------------------
    # Items
    #--------------------------------------------------------

    for i in "${!items_ref[@]}"
    do
        row=$((8 + i))

        if (( row >= TUI_ROWS - 1 ))
        then
            break
        fi

        tui_move \
            "$row" \
            8 \
            || return 1

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

    #--------------------------------------------------------
    # Status bar
    #--------------------------------------------------------

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

    #--------------------------------------------------------
    # Controller must already be loaded by install.sh
    #--------------------------------------------------------

    if ! menu_main_check_controller
    then
        menu_main_log_error \
            "Installer controller is incomplete"

        return 1
    fi

    MENU_MAIN_SELECTED=0

    #--------------------------------------------------------
    # Main loop
    #--------------------------------------------------------

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

        #----------------------------------------------------
        # Read keyboard event
        #----------------------------------------------------

        if ! event_read
        then
            menu_main_log_error \
                "event_read() failed"

            return 1
        fi

        #----------------------------------------------------
        # Process event
        #----------------------------------------------------

        case "${TUI_EVENT:-}"
        in

            "$EVENT_UP")

                if (( selected > 0 ))
                then
                    selected=$((selected - 1))
                else
                    selected=$((item_count - 1))
                fi

                ;;

            "$EVENT_DOWN")

                if (( selected < item_count - 1 ))
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

                selected=$((item_count - 1))

                ;;

            "$EVENT_SELECT")

                case "$selected"
                in

                    0)

                        if ! menu_main_install
                        then
                            menu_main_log_warn \
                                "Full installation returned failure"
                        fi

                        ;;

                    1)

                        if ! menu_main_partition
                        then
                            menu_main_log_warn \
                                "Partition operation failed"
                        fi

                        ;;

                    2)

                        if ! menu_main_filesystem
                        then
                            menu_main_log_warn \
                                "Filesystem operation failed"
                        fi

                        ;;

                    3)

                        if ! menu_main_mount
                        then
                            menu_main_log_warn \
                                "Mount operation failed"
                        fi

                        ;;

                    4)

                        if ! menu_main_packages
                        then
                            menu_main_log_warn \
                                "Package operation failed"
                        fi

                        ;;

                    5)

                        if ! menu_main_bootloader
                        then
                            menu_main_log_warn \
                                "Bootloader operation failed"
                        fi

                        ;;

                    6)

                        if ! menu_main_system_info
                        then
                            menu_main_log_warn \
                                "System information failed"
                        fi

                        ;;

                    7)

                        if ! menu_main_shell
                        then
                            menu_main_log_warn \
                                "Installer shell failed"
                        fi

                        ;;

                    8)

                        if menu_main_exit
                        then
                            return 0
                        fi

                        ;;

                esac

                ;;

            "$EVENT_BACK")

                if menu_main_exit
                then
                    return 0
                fi

                ;;

        esac

        MENU_MAIN_SELECTED="$selected"
    done
}
