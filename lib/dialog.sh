#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# dialog.sh
#
# Диалоговые окна TUI
#
# Обязанности:
#  • Message box
#  • Error box
#  • Confirm box
#  • Ожидание ввода
#
# Не содержит логики установки.
#============================================================

[[ -n "${DIALOG_SH_LOADED:-}" ]] && return
readonly DIALOG_SH_LOADED=1

DIALOG_WIDTH=50
DIALOG_HEIGHT=8

dialog_center_position()
{
    local width
    local height

    width="$(screen_width)"
    height="$(screen_height)"

    DIALOG_LEFT=$(( (width - DIALOG_WIDTH) / 2 ))
    DIALOG_TOP=$(( (height - DIALOG_HEIGHT) / 2 ))

    (( DIALOG_LEFT < 1 )) && DIALOG_LEFT=1
    (( DIALOG_TOP < 1 )) && DIALOG_TOP=1
}

dialog_draw()
{
    local title="$1"

    screen_prepare
    dialog_center_position

    draw_panel \
        "$title" \
        "$DIALOG_TOP" \
        "$DIALOG_LEFT" \
        "$(( DIALOG_TOP + DIALOG_HEIGHT ))" \
        "$(( DIALOG_LEFT + DIALOG_WIDTH ))"

    screen_refresh
}

dialog_close()
{
    screen_prepare
    screen_refresh
}

dialog_message()
{
    local title="$1"
    local message="$2"

    dialog_draw "$title"

    draw_text \
        "$(( DIALOG_TOP + 2 ))" \
        "$(( DIALOG_LEFT + 3 ))" \
        "$message"

    draw_text \
        "$(( DIALOG_TOP + DIALOG_HEIGHT - 1 ))" \
        "$(( DIALOG_LEFT + 3 ))" \
        "Press Enter..."

    screen_refresh

    while true
    do
        local event

        event="$(event_read)"

        if event_is_select "$event" ||
           event_is_back "$event"
        then
            break
        fi
    done

    dialog_close
}

dialog_error()
{
    local message="$1"

    dialog_message \
        "Error" \
        "$message"
}

dialog_confirm()
{
    local message="$1"

    dialog_draw "Confirm"

    draw_text \
        "$(( DIALOG_TOP + 2 ))" \
        "$(( DIALOG_LEFT + 3 ))" \
        "$message"

    draw_text \
        "$(( DIALOG_TOP + 4 ))" \
        "$(( DIALOG_LEFT + 3 ))" \
        "[ Enter ] Yes    [ Esc ] No"

    screen_refresh

    while true
    do
        local event

        event="$(event_read)"

        case "$event" in
            "$EVENT_SELECT")
                dialog_close
                return 0
                ;;

            "$EVENT_BACK")
                dialog_close
                return 1
                ;;
        esac
    done
}
