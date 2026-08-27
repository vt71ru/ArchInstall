#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  welcome.sh
#
#  Приветственный экран
#
#  Обязанности:
#   • Информация об установщике
#   • Проверка готовности
#   • Начало процесса установки
#
#  Не содержит логику установки Arch.
#============================================================


[[ -n "${WELCOME_SH_LOADED:-}" ]] && return

readonly WELCOME_SH_LOADED=1


#------------------------------------------------------------
# Welcome screen
#------------------------------------------------------------

welcome_draw()
{
    tui_clear


    titlebar_draw \
        "${APP_NAME}"


    draw_panel \
        "Welcome" \
        3 \
        5 \
        12 \
        75


    draw_text \
        5 \
        8 \
        "Arch Installer"


    draw_text \
        7 \
        8 \
        "Version: ${APP_VERSION}"


    draw_text \
        9 \
        8 \
        "A text based Arch Linux installer"


    statusbar_draw \
        "Enter Continue   Esc Back"


    screen_refresh
}


#------------------------------------------------------------
# Environment information
#------------------------------------------------------------

welcome_check()
{
    logger_info "Running welcome checks"


    if ! command_exists pacman; then

        dialog_error \
            "pacman was not found"

        return 1

    fi


    if [[ ! -f /etc/arch-release ]]; then

        dialog_error \
            "Not running on Arch Linux environment"

        return 1

    fi


    return 0
}


#------------------------------------------------------------
# Main
#------------------------------------------------------------

welcome()
{
    logger_info "Welcome screen"


    welcome_draw


    local event


    while true
    do

        event="$(event_read)"


        case "$event" in


            "$EVENT_SELECT")

                if welcome_check; then

                    dialog_message \
                        "Ready" \
                        "Environment check passed"

                fi

                break

                ;;


            "$EVENT_BACK")

                break

                ;;

        esac

    done
}
