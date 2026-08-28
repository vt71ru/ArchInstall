#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  welcome.sh
#
#  Стартовый экран установщика.
#
#  Ответственность:
#   • Приветствие пользователя
#   • Отображение версии
#   • Краткая информация
#
#  Не содержит:
#   • Логику установки
#   • Работу с дисками
#   • Настройку системы
#============================================================

if [[ -n "${WELCOME_SH_LOADED:-}" ]]
then
    return 0
fi

readonly WELCOME_SH_LOADED=1

#============================================================
# Main
#============================================================

welcome()
{
    logger_info \
        "Welcome screen started"

    tui_clear

    titlebar_draw \
        "Arch Installer ${APP_VERSION}"

    draw_box \
        4 \
        5 \
        "$(( TUI_COLS - 10 ))" \
        12

    tui_move \
        7 \
        8

    color_title \
        "Welcome to Arch Installer"

    tui_move \
        9 \
        8

    printf '%s' \
        "Interactive Arch Linux installation tool."

    tui_move \
        11 \
        8

    printf '%s' \
        "Use ↑ ↓ to navigate, Enter to select, Esc to go back."

    tui_move \
        13 \
        8

    printf '%s' \
        "Version: %s" \
        "$APP_VERSION"

    statusbar_draw \
        "Enter Continue   Esc Back"

    tui_flush

    while true
    do
        case "$(
            event_read
        )"
        in
            "$EVENT_SELECT")
                logger_info \
                    "Welcome screen completed"

                return 0
                ;;

            "$EVENT_BACK")
                logger_info \
                    "Welcome screen cancelled"

                return 1
                ;;
        esac
    done
}

#============================================================
# End
#============================================================
