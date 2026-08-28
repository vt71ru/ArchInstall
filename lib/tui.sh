#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  tui.sh
#
#  Координация TUI.
#
#  Ответственность:
#   • Инициализация TUI
#   • Запуск TUI
#   • Очистка экрана
#   • Обновление вывода
#   • Восстановление TUI
#   • Проверка состояния TUI
#
#  Не содержит:
#   • stty
#   • alternate screen
#   • управление курсором
#   • обработку клавиш
#   • логику меню
#   • отрисовку widgets
#   • installer logic
#
#  Зависит от:
#   • terminal.sh
#============================================================

if [[ -n "${TUI_SH_LOADED:-}" ]]
then
    return 0
fi

readonly TUI_SH_LOADED=1

#============================================================
# State
#============================================================

TUI_INITIALIZED=0
TUI_ACTIVE=0

#============================================================
# Initialization
#============================================================

tui_init()
{
    if (( TUI_INITIALIZED ))
    then
        return 0
    fi

    if ! declare -F terminal_init >/dev/null 2>&1
    then
        logger_error \
            "terminal_init() is not available"

        return 1
    fi

    if ! declare -F terminal_restore >/dev/null 2>&1
    then
        logger_error \
            "terminal_restore() is not available"

        return 1
    fi

    if ! terminal_init
    then
        logger_error \
            "Failed to initialize terminal"

        return 1
    fi

    TUI_INITIALIZED=1

    logger_debug \
        "TUI initialized"

    return 0
}

#============================================================
# Start TUI
#============================================================

tui_start()
{
    if (( TUI_ACTIVE ))
    then
        return 0
    fi

    if (( ! TUI_INITIALIZED ))
    then
        tui_init || \
            return 1
    fi

    TUI_ACTIVE=1

    logger_debug \
        "TUI started"

    return 0
}

#============================================================
# Clear screen
#============================================================

tui_clear()
{
    if (( ! TUI_INITIALIZED ))
    then
        tui_init || \
            return 1
    fi

    if declare -F screen_clear >/dev/null 2>&1
    then
        screen_clear
        return $?
    fi

    printf \
        '\033[2J\033[H'

    return 0
}

#============================================================
# Clear line
#============================================================

tui_clear_line()
{
    printf \
        '\033[2K'
}

#============================================================
# Move cursor
#============================================================

tui_move_to()
{
    local row="${1:-1}"
    local col="${2:-1}"

    if [[ ! "$row" =~ ^[0-9]+$ ||
          ! "$col" =~ ^[0-9]+$ ]]
    then
        logger_error \
            "Invalid cursor position: row=${row}, col=${col}"

        return 1
    fi

    printf \
        '\033[%s;%sH' \
        "$row" \
        "$col"
}

#============================================================
# Flush
#============================================================

tui_flush()
{
    if declare -F terminal_flush >/dev/null 2>&1
    then
        terminal_flush
        return $?
    fi

    printf ''
}

#============================================================
# Check active state
#============================================================

tui_is_active()
{
    (( TUI_ACTIVE ))
}

#============================================================
# Check initialized state
#============================================================

tui_is_initialized()
{
    (( TUI_INITIALIZED ))
}

#============================================================
# Refresh
#============================================================

tui_refresh()
{
    tui_flush
}

#============================================================
# Stop TUI
#============================================================

tui_stop()
{
    if (( ! TUI_ACTIVE ))
    then
        return 0
    fi

    TUI_ACTIVE=0

    logger_debug \
        "TUI stopped"

    return 0
}

#============================================================
# Restore TUI
#============================================================

tui_restore()
{
    local failed=0

    tui_stop || \
        failed=1

    if (( TUI_INITIALIZED ))
    then
        if declare -F terminal_restore >/dev/null 2>&1
        then
            if ! terminal_restore
            then
                failed=1
            fi
        else
            logger_error \
                "terminal_restore() is not available"

            failed=1
        fi
    fi

    TUI_INITIALIZED=0
    TUI_ACTIVE=0

    if (( failed ))
    then
        logger_error \
            "TUI restoration completed with errors"

        return 1
    fi

    logger_debug \
        "TUI restored"

    return 0
}

#============================================================
# Shutdown
#============================================================

tui_shutdown()
{
    tui_restore
}

#============================================================
# End
#============================================================
