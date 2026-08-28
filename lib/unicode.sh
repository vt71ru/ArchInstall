#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  unicode.sh
#
#  Работа с Unicode-символами TUI.
#
#  Ответственность:
#   • Проверка поддержки Unicode
#   • Предоставление Unicode-символов
#   • ASCII fallback
#
#  Не содержит:
#   • Логику меню
#   • Обработку клавиш
#   • Отрисовку экранов
#   • Installer logic
#============================================================

if [[ -n "${UNICODE_SH_LOADED:-}" ]]
then
    return 0
fi

readonly UNICODE_SH_LOADED=1

#============================================================
# State
#============================================================

UNICODE_ENABLED=1
UNICODE_INITIALIZED=0

#============================================================
# Symbols
#============================================================

UI_ARROW_UP=''
UI_ARROW_DOWN=''
UI_ARROW_LEFT=''
UI_ARROW_RIGHT=''

UI_CHECK=''
UI_CROSS=''
UI_BULLET=''
UI_RADIO_ON=''
UI_RADIO_OFF=''

UI_BORDER_TOP_LEFT=''
UI_BORDER_TOP_RIGHT=''
UI_BORDER_BOTTOM_LEFT=''
UI_BORDER_BOTTOM_RIGHT=''
UI_BORDER_HORIZONTAL=''
UI_BORDER_VERTICAL=''

#============================================================
# Detect Unicode support
#============================================================

unicode_detect()
{
    local locale

    UNICODE_ENABLED=1

    locale="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"

    if [[ "$locale" =~ ^(C|POSIX)(\.|$) ]]
    then
        UNICODE_ENABLED=0
        return 0
    fi

    return 0
}

#============================================================
# ASCII fallback
#============================================================

unicode_set_ascii()
{
    UI_ARROW_UP='^'
    UI_ARROW_DOWN='v'
    UI_ARROW_LEFT='<'
    UI_ARROW_RIGHT='>'

    UI_CHECK='[x]'
    UI_CROSS='[ ]'
    UI_BULLET='*'
    UI_RADIO_ON='(*)'
    UI_RADIO_OFF='( )'

    UI_BORDER_TOP_LEFT='+'
    UI_BORDER_TOP_RIGHT='+'
    UI_BORDER_BOTTOM_LEFT='+'
    UI_BORDER_BOTTOM_RIGHT='+'
    UI_BORDER_HORIZONTAL='-'
    UI_BORDER_VERTICAL='|'
}

#============================================================
# Unicode symbols
#============================================================

unicode_set_unicode()
{
    UI_ARROW_UP='↑'
    UI_ARROW_DOWN='↓'
    UI_ARROW_LEFT='←'
    UI_ARROW_RIGHT='→'

    UI_CHECK='✓'
    UI_CROSS='✗'
    UI_BULLET='•'
    UI_RADIO_ON='●'
    UI_RADIO_OFF='○'

    UI_BORDER_TOP_LEFT='┌'
    UI_BORDER_TOP_RIGHT='┐'
    UI_BORDER_BOTTOM_LEFT='└'
    UI_BORDER_BOTTOM_RIGHT='┘'
    UI_BORDER_HORIZONTAL='─'
    UI_BORDER_VERTICAL='│'
}

#============================================================
# Initialization
#============================================================

unicode_init()
{
    if (( UNICODE_INITIALIZED ))
    then
        return 0
    fi

    unicode_detect

    if (( UNICODE_ENABLED ))
    then
        unicode_set_unicode

        logger_debug \
            "Unicode support enabled"
    else
        unicode_set_ascii

        logger_debug \
            "Unicode support disabled; using ASCII fallback"
    fi

    UNICODE_INITIALIZED=1

    return 0
}

#============================================================
# Enable
#============================================================

unicode_enable()
{
    UNICODE_ENABLED=1
    UNICODE_INITIALIZED=0

    unicode_init
}

#============================================================
# Disable
#============================================================

unicode_disable()
{
    UNICODE_ENABLED=0
    UNICODE_INITIALIZED=0

    unicode_set_ascii

    UNICODE_INITIALIZED=1

    logger_debug \
        "Unicode support disabled"
}

#============================================================
# Check
#============================================================

unicode_is_enabled()
{
    (( UNICODE_ENABLED ))
}

#============================================================
# End
#============================================================
