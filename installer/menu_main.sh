```bash
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
#   • навигация через TUI API
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

MENU_MAIN_ROOT="${INSTALLER_ROOT:-}"

if [[ -z "$MENU_MAIN_ROOT" ]]
then
    MENU_MAIN_ROOT="$(
        cd \
            "$(dirname "${BASH_SOURCE[0]}")/.." \
            >/dev/null 2>&1 &&
        pwd
    )"
fi

readonly MENU_MAIN_ROOT

MENU_MAIN_INSTALLER="$MENU_MAIN_ROOT/installer"

readonly MENU_MAIN_INSTALLER

#============================================================
# State
#============================================================

MENU_MAIN_INSTALLER_LOADED=0

#============================================================
# Load installer controller
#============================================================

menu_main_load_installer()
{
    local file="$MENU_MAIN_INSTALLER/installer.sh"

    #
    # Already loaded.
    #
    if (( MENU_MAIN_INSTALLER_LOADED ))
    then
        return 0
    fi

    #
    # Check file.
    #
    if [[ ! -f "$file" ]]
    then
        logger_error \
            "Main menu: installer controller not found: $file"

        return 1
    fi

    #
    # Load controller.
    #
    # shellcheck disable=SC1090
    if ! source "$file"
    then
        logger_error \
            "Main menu: failed to load installer controller: $file"

        return 1
    fi

    #
    # Verify required controller API.
    #
    local function

    for function in \
        installer_run \
        installer_partition \
        installer_filesystem \
        installer_mount \
        installer_packages \
        installer_bootloader
    do
        if ! declare -F "$function" >/dev/null 2>&1
        then
            logger_error \
                "Main menu: required function is unavailable: $function"

            return 1
        fi
    done

    MENU_MAIN_INSTALLER_LOADED=1

    logger_debug \
        "Main menu: installer controller loaded"

    return 0
}

#============================================================
# Header
#============================================================

menu_main_header()
{
    tui_clear || return 1

    titlebar_draw \
        "Arch Installer" || return 1

    tui_move \
        3 \
        5 || return 1

    color_info \
        "Arch Linux Installation System"

    tui_move \
        4 \
        5 || return 1

    tui_print \
        "Select an operation"

    return 0
}

#============================================================
# Partition
#============================================================

menu_main_partition()
{
    logger_info \
        "Partition stage selected"

    menu_main_load_installer || \
        return 1

    if installer_partition
    then
        logger_info \
            "Partition stage completed"

        return 0
    fi

    logger_warn \
        "Partition stage cancelled or failed"

    return 1
}

#============================================================
# Filesystem
#============================================================

menu_main_filesystem()
{
    logger_info \
        "Filesystem stage selected"

    menu_main_load_installer || \
        return 1

    if installer_filesystem
    then
        logger_info \
            "Filesystem stage completed"

        return 0
    fi

    logger_warn \
        "Filesystem stage cancelled or failed"

    return 1
}

#============================================================
# Mount
#============================================================

menu_main_mount()
{
    logger_info \
        "Mount stage selected"

    menu_main_load_installer || \
        return 1

    if installer_mount
    then
        logger_info \
            "Mount stage completed"

        return 0
    fi

    logger_warn \
        "Mount stage cancelled or failed"

    return 1
}

#============================================================
# Packages
#============================================================

menu_main_packages()
{
    logger_info \
        "Package stage selected"

    menu_main_load_installer || \
        return 1

    if installer_packages
    then
        logger_info \
            "Package stage completed"

        return 0
    fi

    logger_warn \
        "Package stage cancelled or failed"

    return 1
}

#============================================================
# Bootloader
#============================================================

menu_main_bootloader()
{
    logger_info \
        "Bootloader stage selected"

    menu_main_load_installer || \
        return 1

    if installer_bootloader
    then
        logger_info \
            "Bootloader stage completed"

        return 0
    fi

    logger_warn \
        "Bootloader stage cancelled or failed"

    return 1
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

    #
    # Reset previous result if installer controller
    # provides these variables.
    #
    INSTALLER_STAGE="${INSTALLER_STAGE:-}"
    INSTALLER_LAST_RC="${INSTALLER_LAST_RC:-0}"

    if installer_run
    then
        logger_info \
            "Full installation completed"

        dialog_info \
            "Installation complete" \
            "Arch Linux installation completed successfully."

        return 0
    fi

    local rc="${INSTALLER_LAST_RC:-1}"
    local stage="${INSTALLER_STAGE:-unknown}"

    if ! [[ "$rc" =~ ^[0-9]+$ ]]
    then
        rc=1
    fi

    logger_error \
        "Full installation failed: stage=$stage rc=$rc"

    dialog_warning \
        "Installation failed" \
        "Installation failed at stage: $stage"

    return "$rc"
}

#============================================================
# System information
#============================================================

menu_main_system_info()
{
    local kernel="unknown"
    local arch="unknown"
    local memory="unknown"
    local cpu="unknown"

    #
    # Kernel.
    #
    if command -v uname >/dev/null 2>&1
    then
        kernel="$(uname -r 2>/dev/null || printf '%s' 'unknown')"
        arch="$(uname -m 2>/dev/null || printf '%s' 'unknown')"
    fi

    #
    # Memory.
    #
    if [[ -r /proc/meminfo ]]
    then
        memory="$(
            awk '
                /^MemTotal:/ {
                    printf "%.0f MiB", $2 / 1024
                    found=1
                    exit
                }
                END {
                    if (!found)
                        printf "%s", "unknown"
                }
            ' /proc/meminfo
        )"
    fi

    #
    # CPU.
    #
    if [[ -r /proc/cpuinfo ]]
    then
        cpu="$(
            awk -F: '
                /^model name[[:space:]]*:/ {
                    value=$2
                    sub(/^[[:space:]]+/, "", value)
                    print value
                    found=1
                    exit
                }
            ' /proc/cpuinfo
        )"

        if [[ -z "$cpu" ]]
        then
            cpu="$(
                awk -F: '
                    /^Hardware[[:space:]]*:/ {
                        value=$2
                        sub(/^[[:space:]]+/, "", value)
                        print value
                        found=1
                        exit
                    }
                ' /proc/cpuinfo
            )"
        fi
    fi

    if [[ -z "$cpu" ]]
    then
        cpu="unknown"
    fi

    logger_debug \
        "System information requested"

    tui_clear || return 1

    draw_panel \
        "System Information" \
        4 \
        5 \
        12 \
        "$((TUI_COLS - 10))" || return 1

    tui_move \
        6 \
        8 || return 1

    tui_print \
        "Kernel:  $kernel"

    tui_move \
        7 \
        8 || return 1

    tui_print \
        "Arch:    $arch"

    tui_move \
        8 \
        8 || return 1

    tui_print \
        "Memory:  $memory"

    tui_move \
        9 \
        8 || return 1

    tui_print \
        "CPU:     $cpu"

    tui_move \
        14 \
        8 || return 1

    tui_print \
        "Enter / Esc = Back"

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
    logger_info \
        "Opening interactive shell"

    #
    # Leave TUI before starting an interactive shell.
    #
    if (( TUI_INITIALIZED ))
    then
        tui_restore || \
            return 1
    fi

    printf '\n'
    printf '%s\n' \
        '============================================================'
    printf '%s\n' \
        ' Arch Installer shell'
    printf '%s\n' \
        '============================================================'
    printf '%s\n\n' \
        'Type "exit" to return to the installer.'

    #
    # Explicitly use /bin/bash.
    #
    if ! /bin/bash
    then
        local rc="$?"

        printf '\n'
        printf 'Shell exited with status %s.\n' "$rc"

        logger_warn \
            "Interactive shell exited with rc=$rc"

        printf 'Press Enter to return to the installer...'
        read -r || true

        tui_start || \
            return 1

        return "$rc"
    fi

    printf '\n'
    printf '%s\n' \
        'Returning to Arch Installer...'

    logger_info \
        "Interactive shell closed"

    sleep 1

    #
    # Reinitialize and reactivate TUI.
    #
    if ! tui_start
    then
        logger_error \
            "Failed to restart TUI after shell"

        return 1
    fi

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
            "User confirmed exit"

        return 0
    fi

    logger_debug \
        "User cancelled exit"

    return 1
}

#============================================================
# Operation error dialog
#============================================================

menu_main_operation_failed()
{
    local title="${1:-Operation}"
    local message="${2:-Operation was cancelled or failed.}"

    dialog_warning \
        "$title" \
        "$message" || true

    return 0
}

#============================================================
# Main menu
#============================================================

menu_main()
{
    local selected=0
    local item_count
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

    item_count="${#items[@]}"

    if (( item_count == 0 ))
    then
        logger_error \
            "Main menu: menu contains no items"

        return 1
    fi

    #
    # Validate TUI state.
    #
    if (( ! TUI_INITIALIZED ))
    then
        logger_error \
            "Main menu: TUI is not initialized"

        return 1
    fi

    if (( ! TUI_ACTIVE ))
    then
        logger_error \
            "Main menu: TUI is not active"

        return 1
    fi

    logger_info \
        "Main menu started"

    while true
    do
        #
        #----------------------------------------------------
        # Draw header.
        #----------------------------------------------------
        #
        menu_main_header || \
            return 1

        #
        #----------------------------------------------------
        # Calculate menu height.
        #----------------------------------------------------
        #
        local box_height=$((item_count + 4))

        if (( box_height > TUI_ROWS - 3 ))
        then
            box_height=$((TUI_ROWS - 3))
        fi

        if (( box_height < 4 ))
        then
            logger_error \
                "Main menu: terminal is too small"

            return 1
        fi

        #
        #----------------------------------------------------
        # Draw menu box.
        #----------------------------------------------------
        #
        draw_box \
            6 \
            5 \
            "$((TUI_COLS - 10))" \
            "$box_height" || \
            return 1

        #
        #----------------------------------------------------
        # Draw menu entries.
        #----------------------------------------------------
        #
        for i in "${!items[@]}"
        do
            local row=$((8 + i))

            #
            # Do not draw outside the menu area.
            #
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
                    "> ${items[i]}"
            else
                tui_print \
                    "  ${items[i]}"
            fi
        done

        #
        #----------------------------------------------------
        # Status bar.
        #----------------------------------------------------
        #
        statusbar_draw \
            '↑↓ Navigate   Home/End   Enter Select   Esc Exit' || \
            return 1

        #
        #----------------------------------------------------
        # Read keyboard event.
        #----------------------------------------------------
        #
        event_read

        case "$TUI_EVENT"
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
                    #------------------------------------------------
                    # Full installation
                    #------------------------------------------------
                    0)
                        if ! menu_main_install
                        then
                            #
                            # menu_main_install() already displays
                            # a detailed error dialog.
                            #
                            logger_warn \
                                "Full installation returned failure"
                        fi
                        ;;

                    #------------------------------------------------
                    # Partition
                    #------------------------------------------------
                    1)
                        if ! menu_main_partition
                        then
                            menu_main_operation_failed \
                                "Partition" \
                                "Partitioning was cancelled or failed."
                        fi
                        ;;

                    #------------------------------------------------
                    # Filesystem
                    #------------------------------------------------
                    2)
                        if ! menu_main_filesystem
                        then
                            menu_main_operation_failed \
                                "Filesystem" \
                                "Filesystem stage was cancelled or failed."
                        fi
                        ;;

                    #------------------------------------------------
                    # Mount
                    #------------------------------------------------
                    3)
                        if ! menu_main_mount
                        then
                            menu_main_operation_failed \
                                "Mount" \
                                "Mount stage was cancelled or failed."
                        fi
                        ;;

                    #------------------------------------------------
                    # Packages
                    #------------------------------------------------
                    4)
                        if ! menu_main_packages
                        then
                            menu_main_operation_failed \
                                "Packages" \
                                "Package installation was cancelled or failed."
                        fi
                        ;;

                    #------------------------------------------------
                    # Bootloader
                    #------------------------------------------------
                    5)
                        if ! menu_main_bootloader
                        then
                            menu_main_operation_failed \
                                "Bootloader" \
                                "Bootloader installation was cancelled or failed."
                        fi
                        ;;

                    #------------------------------------------------
                    # System information
                    #------------------------------------------------
                    6)
                        if ! menu_main_system_info
                        then
                            logger_warn \
                                "System information dialog failed"
                        fi
                        ;;

                    #------------------------------------------------
                    # Shell
                    #------------------------------------------------
                    7)
                        if ! menu_main_shell
                        then
                            dialog_error \
                                "Failed to return to TUI" || true

                            #
                            # If TUI cannot be restored there is no
                            # safe way to continue drawing the menu.
                            #
                            if (( ! TUI_ACTIVE ))
                            then
                                logger_error \
                                    "TUI is inactive after shell"

                                return 1
                            fi
                        fi
                        ;;

                    #------------------------------------------------
                    # Exit
                    #------------------------------------------------
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

            "$EVENT_F1"|"$EVENT_HELP")
                dialog_info \
                    "Help" \
                    "Use Up/Down to navigate, Enter to select, Esc to exit." \
                    || true
                ;;

            *)
                #
                # Ignore unsupported keys.
                #
                ;;
        esac
    done
}

#============================================================
# End
#============================================================
```
