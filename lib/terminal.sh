#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  terminal.sh
#
#  Управление терминалом.
#
#  Ответственность:
#   • Сохранение исходного состояния stty
#   • Переключение терминала в TUI mode
#   • Включение/выключение alternate screen
#   • Скрытие/показ курсора
#   • Установка title
#   • Полное восстановление терминала
#
#  Не содержит:
#   • Логику меню
#   • Обработку клавиш
#   • Отрисовку widgets
#============================================================

[[ -n "${TERMINAL_SH_LOADED:-}" ]] && return

readonly TERMINAL_SH_LOADED=1

#------------------------------------------------------------
# State
#------------------------------------------------------------

TERMINAL_INITIALIZED=0
TERMINAL_RAW=0
TERMINAL_ALT_SCREEN=0
TERMINAL_CURSOR_HIDDEN=0

TERMINAL_STTY_STATE=""

#------------------------------------------------------------
# Save terminal state
#------------------------------------------------------------

terminal_save_state()
{
    if [[ ! -t 0 ]]
    then
        logger_error \
            "stdin is not a terminal"

        return 1
    fi

    TERMINAL_STTY_STATE="$(
        stty -g
    )"

    if [[ -z "$TERMINAL_STTY_STATE" ]]
    then
        logger_error \
            "Failed to save terminal state"

        return 1
    fi

    logger_debug \
        "Terminal state saved"
}

#------------------------------------------------------------
# Enter raw mode
#------------------------------------------------------------

terminal_raw()
{
    if (( TERMINAL_RAW ))
    then
        return 0
    fi

    stty \
        -echo \
        -echonl \
        -icanon \
        min 1 \
        time 0

    TERMINAL_RAW=1

    logger_debug \
        "Terminal raw mode enabled"
}

#------------------------------------------------------------
# Leave raw mode
#------------------------------------------------------------

terminal_cooked()
{
    if (( ! TERMINAL_RAW ))
    then
        return 0
    fi

    if [[ -n "$TERMINAL_STTY_STATE" ]]
    then
        stty \
            "$TERMINAL_STTY_STATE"
    else
        stty \
            sane
    fi

    TERMINAL_RAW=0

    logger_debug \
        "Terminal input mode restored"
}

#------------------------------------------------------------
# Enter alternate screen
#------------------------------------------------------------

terminal_enter_alt_screen()
{
    if (( TERMINAL_ALT_SCREEN ))
    then
        return 0
    fi

    printf '\033[?1049h'
    printf '\033[H'

    TERMINAL_ALT_SCREEN=1

    logger_debug \
        "Alternate screen enabled"
}

#------------------------------------------------------------
# Leave alternate screen
#------------------------------------------------------------

terminal_leave_alt_screen()
{
    if (( ! TERMINAL_ALT_SCREEN ))
    then
        return 0
    fi

    printf '\033[?1049l'

    TERMINAL_ALT_SCREEN=0

    logger_debug \
        "Alternate screen disabled"
}

#------------------------------------------------------------
# Hide cursor
#------------------------------------------------------------

terminal_hide_cursor()
{
    if (( TERMINAL_CURSOR_HIDDEN ))
    then
        return 0
    fi

    printf '\033[?25l'

    TERMINAL_CURSOR_HIDDEN=1
}

#------------------------------------------------------------
# Show cursor
#------------------------------------------------------------

terminal_show_cursor()
{
    if (( ! TERMINAL_CURSOR_HIDDEN ))
    then
        return 0
    fi

    printf '\033[?25h'

    TERMINAL_CURSOR_HIDDEN=0
}

#------------------------------------------------------------
# Set terminal title
#------------------------------------------------------------

terminal_title()
{
    local title="${1:-Arch Installer}"

    printf \
        '\033]0;%s\007' \
        "$title"
}

#------------------------------------------------------------
# Reset title
#------------------------------------------------------------

terminal_reset_title()
{
    printf \
        '\033]0;\007'
}

#------------------------------------------------------------
# Initialize
#------------------------------------------------------------

terminal_init()
{
    if (( TERMINAL_INITIALIZED ))
    then
        return 0
    fi

    if ! [[ -t 0 && -t 1 ]]
    then
        logger_error \
            "TUI requires interactive stdin/stdout"

        return 1
    fi

    terminal_save_state || \
        return 1

    terminal_enter_alt_screen

    terminal_raw || {
        terminal_leave_alt_screen || true
        return 1
    }

    terminal_hide_cursor

    TERMINAL_INITIALIZED=1

    logger_info \
        "Terminal initialized"
}

#------------------------------------------------------------
# Flush terminal output
#------------------------------------------------------------

terminal_flush()
{
    printf ''
}

#------------------------------------------------------------
# Restore terminal
#------------------------------------------------------------

terminal_restore()
{
    #
    # Reverse order of initialization.
    #

    terminal_show_cursor || true

    terminal_cooked || true

    terminal_leave_alt_screen || true

    terminal_reset_title || true

    TERMINAL_INITIALIZED=0

    logger_debug \
        "Terminal restored"
}

#------------------------------------------------------------
# Resize / window size
#------------------------------------------------------------

terminal_rows()
{
    local rows

    rows="$(
        tput lines 2>/dev/null \
            || printf '0'
    )"

    printf '%s' \
        "$rows"
}

terminal_cols()
{
    local cols

    cols="$(
        tput cols 2>/dev/null \
            || printf '0'
    )"

    printf '%s' \
        "$cols"
}

#------------------------------------------------------------
# Check minimum terminal size
#------------------------------------------------------------

terminal_check_size()
{
    local rows
    local cols

    rows="$(
        terminal_rows
    )"

    cols="$(
        terminal_cols
    )"

    [[ "$rows" =~ ^[0-9]+$ ]] || \
        return 1

    [[ "$cols" =~ ^[0-9]+$ ]] || \
        return 1

    if (( rows < 20 ||
          cols < 70 ))
    then
        logger_warn \
            "Terminal too small: ${cols}x${rows}"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Suspend TUI
#------------------------------------------------------------

terminal_suspend()
{
    terminal_restore
}

#------------------------------------------------------------
# Resume TUI
#------------------------------------------------------------

terminal_resume()
{
    if (( TERMINAL_INITIALIZED ))
    then
        return 0
    fi

    terminal_init
}