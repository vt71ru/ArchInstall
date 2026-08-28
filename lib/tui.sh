#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  tui.sh
#
#  Базовый слой TUI.
#
#  Ответственность:
#   • Инициализация TUI
#   • Очистка экрана
#   • Сохранение/восстановление состояния терминала
#   • Управление режимом альтернативного экрана
#   • Базовые операции вывода
#
#  Не содержит:
#   • Логику меню
#   • Обработку пунктов меню
#   • Installer logic
#   • Конкретные виджеты
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
TUI_ALT_SCREEN=0
TUI_SAVED_STTY=''

#============================================================
# Escape sequences
#============================================================

TUI_ESC=$'\033'

TUI_CURSOR_HIDE="${TUI_ESC}[?25l"
TUI_CURSOR_SHOW="${TUI_ESC}[?25h"

TUI_ALT_ENTER="${TUI_ESC}[?1049h"
TUI_ALT_EXIT="${TUI_ESC}[?1049l"

TUI_CLEAR="${TUI_ESC}[2J${TUI_ESC}[H"
TUI_CLEAR_LINE="${TUI_ESC}[2K"

#============================================================
# Initialization
#============================================================

tui_init()
{
    if (( TUI_INITIALIZED ))
    then
        return 0
    fi

    if ! [[ -t 0 && -t 1 ]]
    then
        logger_error \
            "TUI requires interactive stdin/stdout"

        return 1
    fi

    TUI_INITIALIZED=1

    logger_debug \
        "TUI initialized"

    return 0
}

#============================================================
# Save terminal state
#============================================================

tui_save_terminal()
{
    if ! [[ -t 0 ]]
    then
        logger_error \
            "Cannot save terminal state: stdin is not a TTY"

        return 1
    fi

    TUI_SAVED_STTY="$(
        stty -g
    )" || {
        logger_error \
            "Failed to save terminal state"

        return 1
    }

    logger_debug \
        "Terminal state saved"

    return 0
}

#============================================================
# Restore terminal state
#============================================================

tui_restore_terminal()
{
    if [[ -n "${TUI_SAVED_STTY:-}" ]]
    then
        stty \
            "$TUI_SAVED_STTY" \
            2>/dev/null \
            || true
    fi

    return 0
}

#============================================================
# Enter alternate screen
#============================================================

tui_enter_alt_screen()
{
    if (( TUI_ALT_SCREEN ))
    then
        return 0
    fi

    printf '%s' \
        "$TUI_ALT_ENTER"

    TUI_ALT_SCREEN=1

    logger_debug \
        "Entered alternate screen"

    return 0
}

#============================================================
# Leave alternate screen
#============================================================

tui_leave_alt_screen()
{
    if (( ! TUI_ALT_SCREEN ))
    then
        return 0
    fi

    printf '%s' \
        "$TUI_ALT_EXIT"

    TUI_ALT_SCREEN=0

    logger_debug \
        "Left alternate screen"

    return 0
}

#============================================================
# Activate TUI
#============================================================

tui_start()
{
    tui_init || \
        return 1

    tui_save_terminal || \
        return 1

    tui_enter_alt_screen

    printf '%s' \
        "$TUI_CURSOR_HIDE"

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

    printf '%s' \
        "$TUI_CLEAR"

    return 0
}

#============================================================
# Clear current line
#============================================================

tui_clear_line()
{
    printf '%s' \
        "$TUI_CLEAR_LINE"
}

#============================================================
# Cursor
#============================================================

tui_hide_cursor()
{
    printf '%s' \
        "$TUI_CURSOR_HIDE"
}

tui_show_cursor()
{
    printf '%s' \
        "$TUI_CURSOR_SHOW"
}

#============================================================
# Flush output
#============================================================

tui_flush()
{
    printf ''
}

#============================================================
# Restore TUI
#============================================================

tui_restore()
{
    if (( ! TUI_ACTIVE ))
    then
        return 0
    fi

    tui_show_cursor

    tui_leave_alt_screen

    tui_restore_terminal

    TUI_ACTIVE=0

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

    TUI_INITIALIZED=0

    logger_debug \
        "TUI shutdown"

    return 0
}

#============================================================
# End
#============================================================
