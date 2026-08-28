```bash
#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  menu_main.sh
#
#  Главное меню установщика.
#
#  Ответственность:
#   • Отображение главного меню
#   • Навигация
#   • Запуск installer-модулей
#   • Отображение текущего состояния конфигурации
#   • Выход из установщика
#
#  Не содержит:
#   • Логику установки
#   • Разметку диска
#   • Форматирование
#   • Монтирование
#   • Установку пакетов
#
#  Зависит от:
#   • config.sh
#   • tui.sh
#============================================================

if [[ -n "${MENU_MAIN_SH_LOADED:-}" ]]
then
    return 0
fi

readonly MENU_MAIN_SH_LOADED=1

#============================================================
# State
#============================================================

MENU_SELECTED=0

#============================================================
# Menu entries
#============================================================

declare -ga MAIN_MENU_ITEMS=(
    "Welcome"
    "Keyboard"
    "Locale"
    "Network"
    "Mirrors"
    "Disk"
    "Partition"
    "Filesystem"
    "Mount"
    "Packages"
    "Users"
    "Desktop"
    "Services"
    "Bootloader"
    "Summary"
    "Install"
    "Exit"
)

#============================================================
# Initialization
#============================================================

menu_main_init()
{
    MENU_SELECTED=0

    return 0
}

#============================================================
# Status helper
#============================================================

menu_main_status()
{
    local key="${1:-}"
    local value

    value="$(
        config_get \
            "$key" \
            2>/dev/null ||
            true
    )"

    [[ -n "$value" ]] || \
        value="-"

    printf '%s' \
        "$value"
}

#============================================================
# Draw configuration summary
#============================================================

menu_main_draw_status()
{
    local row=4

    tui_move \
        "$row" \
        4

    color_title \
        "Current configuration"

    row=$((row + 1))

    tui_move "$row" 4
    printf 'Boot mode      : %s' \
        "$(menu_main_status BOOT_MODE)"

    row=$((row + 1))

    tui_move "$row" 4
    printf 'Partition table: %s' \
        "$(menu_main_status PARTITION_TABLE)"

    row=$((row + 1))

    tui_move "$row" 4
    printf 'Target disk    : %s' \
        "$(menu_main_status TARGET_DISK)"

    row=$((row + 1))

    tui_move "$row" 4
    printf 'Filesystem     : %s' \
        "$(menu_main_status FILESYSTEM)"

    row=$((row + 1))

    tui_move "$row" 4
    printf 'Locale         : %s' \
        "$(menu_main_status LOCALE)"

    row=$((row + 1))

    tui_move "$row" 4
    printf 'User           : %s' \
        "$(menu_main_status USER_NAME)"

    row=$((row + 1))

    tui_move "$row" 4
    printf 'Hostname       : %s' \
        "$(menu_main_status HOSTNAME)"
}

#============================================================
# Draw menu
#============================================================

menu_main_draw()
{
    local start_row=13
    local index

    screen_prepare || \
        return 1

    titlebar_draw \
        "Arch Installer"

    menu_main_draw_status

    draw_box \
        12 \
        2 \
        "$((TUI_COLS - 4))" \
        "$(( ${#MAIN_MENU_ITEMS[@]} + 3 ))"

    for index in "${!MAIN_MENU_ITEMS[@]}"
    do
        tui_move \
            "$((start_row + index))" \
            5

        if (( index == MENU_SELECTED ))
        then
            color_selected \
                "> ${MAIN_MENU_ITEMS[index]}"
        else
            printf \
                '  %s' \
                "${MAIN_MENU_ITEMS[index]}"
        fi
    done

    statusbar_draw \
        "↑↓ Navigate   Enter Select   Esc Exit"

    screen_refresh
}

#============================================================
# Execute selected module
#============================================================

menu_main_execute()
{
    local selected="${MENU_SELECTED}"

    case "$selected"
    in
        0)
            welcome
            ;;

        1)
            keyboard
            ;;

        2)
            locale
            ;;

        3)
            network
            ;;

        4)
            mirrors
            ;;

        5)
            disks
            ;;

        6)
            partition
            ;;

        7)
            filesystem
            ;;

        8)
            mount
            ;;

        9)
            packages
            ;;

        10)
            users
            ;;

        11)
            desktop
            ;;

        12)
            services
            ;;

        13)
            bootloader
            ;;

        14)
            summary
            ;;

        15)
            menu_main_install
            ;;

        16)
            return 1
            ;;

        *)
            logger_error \
                "Unknown main menu index: ${selected}"

            return 1
            ;;
    esac

    return 0
}

#============================================================
# Installation pipeline
#============================================================

menu_main_install()
{
    logger_info \
        "Installation pipeline started"

    #
    # Validate configuration before destructive/install phase.
    #

    if ! config_validate
    then
        dialog_error \
            "Configuration is incomplete or invalid"

        return 1
    fi

    #
    # Target disk must be selected.
    #

    if [[ -z "$(config_get TARGET_DISK)" ]]
    then
        dialog_error \
            "Target disk is not selected"

        return 1
    fi

    #
    # Installation confirmation.
    #

    if ! dialog_confirm \
        "Start installation?

All selected data on the target disk
may be destroyed.

Continue?"
    then
        logger_info \
            "Installation cancelled by user"

        return 0
    fi

    #--------------------------------------------------------
    # Disk
    #--------------------------------------------------------

    if ! partition
    then
        dialog_error \
            "Partitioning failed"

        return 1
    fi

    #--------------------------------------------------------
    # Filesystem
    #--------------------------------------------------------

    if ! filesystem
    then
        dialog_error \
            "Filesystem setup failed"

        return 1
    fi

    #--------------------------------------------------------
    # Mount
    #--------------------------------------------------------

    if ! mount
    then
        dialog_error \
            "Mounting failed"

        return 1
    fi

    #--------------------------------------------------------
    # Packages
    #--------------------------------------------------------

    if ! packages
    then
        dialog_error \
            "Package installation failed"

        return 1
    fi

    #--------------------------------------------------------
    # Users
    #--------------------------------------------------------

    if ! users
    then
        dialog_error \
            "User configuration failed"

        return 1
    fi

    #--------------------------------------------------------
    # Desktop
    #--------------------------------------------------------

    if ! desktop
    then
        dialog_error \
            "Desktop configuration failed"

        return 1
    fi

    #--------------------------------------------------------
    # Services
    #--------------------------------------------------------

    if ! services
    then
        dialog_error \
            "Service configuration failed"

        return 1
    fi

    #--------------------------------------------------------
    # Bootloader
    #--------------------------------------------------------

    if ! bootloader
    then
        dialog_error \
            "Bootloader installation failed"

        return 1
    fi

    #--------------------------------------------------------
    # Summary
    #--------------------------------------------------------

    summary || true

    logger_info \
        "Installation pipeline completed"

    dialog_message \
        "Installation complete" \
        "Arch Linux installation finished successfully."

    return 0
}

#============================================================
# Move selection up
#============================================================

menu_main_up()
{
    if (( MENU_SELECTED > 0 ))
    then
        MENU_SELECTED=$((MENU_SELECTED - 1))
    else
        MENU_SELECTED=$(( ${#MAIN_MENU_ITEMS[@]} - 1 ))
    fi

    return 0
}

#============================================================
# Move selection down
#============================================================

menu_main_down()
{
    if (( MENU_SELECTED < ${#MAIN_MENU_ITEMS[@]} - 1 ))
    then
        MENU_SELECTED=$((MENU_SELECTED + 1))
    else
        MENU_SELECTED=0
    fi

    return 0
}

#============================================================
# Main menu
#============================================================

menu_main()
{
    local event

    logger_info \
        "Main menu started"

    menu_main_init

    while true
    do
        menu_main_draw || \
            return 1

        event="$(
            event_read
        )"

        case "$event"
        in
            "$EVENT_UP")
                menu_main_up
                ;;

            "$EVENT_DOWN")
                menu_main_down
                ;;

            "$EVENT_SELECT")
                if ! menu_main_execute
                then
                    logger_info \
                        "Main menu exit requested"

                    break
                fi
                ;;

            "$EVENT_BACK")
                if dialog_confirm \
                    "Exit Arch Installer?"
                then
                    break
                fi
                ;;

            *)
                ;;
        esac
    done

    logger_info \
        "Main menu stopped"

    return 0
}

#============================================================
# End
#============================================================
