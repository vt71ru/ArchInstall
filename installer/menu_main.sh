#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# installer/menu_main.sh
#
# Главное меню установщика.
#
#============================================================

#============================================================
# STATE
#============================================================

MENU_MAIN_SELECTED="${MENU_MAIN_SELECTED:-0}"

#============================================================
# LOGGING
#============================================================

menu_main_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$*" || true
    else
        printf '[INFO] %s\n' "$*" >&2
    fi

    return 0
}

menu_main_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$*" || true
    else
        printf '[WARN] %s\n' "$*" >&2
    fi

    return 0
}

menu_main_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$*" || true
    else
        printf '[ERROR] %s\n' "$*" >&2
    fi

    return 0
}

#============================================================
# CONTROLLER CHECK
#============================================================

menu_main_check_controller()
{
    local function_name=""
    local missing=0

    menu_main_log_info \
        "Checking installer controller API"

    for function_name in \
        installer_full_install \
        installer_run_stage \
        installer_get_stage_title
    do
        if ! declare -F "$function_name" >/dev/null 2>&1
        then
            menu_main_log_error \
                "Missing controller function: ${function_name}"

            missing=1
        else
            menu_main_log_info \
                "Controller function OK: ${function_name}"
        fi
    done

    if (( missing != 0 ))
    then
        menu_main_log_error \
            "Installer controller API check FAILED"

        return 1
    fi

    menu_main_log_info \
        "Installer controller API: OK"

    return 0
}

#============================================================
# HEADER
#============================================================

menu_main_header()
{
    tui_clear || return 1

    titlebar_draw \
        "Arch Linux Installer" || return 1

    tui_move 3 5 || return 1

    color_info \
        "Arch Linux Installation System" || return 1

    tui_move 4 5 || return 1

    tui_print \
        "Use Up/Down to navigate and Enter to select." \
        || return 1

    return 0
}

#============================================================
# READ EVENT
#============================================================

menu_main_read_event()
{
    TUI_EVENT="${EVENT_NONE:-NONE}"
    TUI_EVENT_CHAR=""

    if ! event_read
    then
        menu_main_log_error \
            "event_read() failed"

        return 1
    fi

    menu_main_log_info \
        "EVENT=[${TUI_EVENT:-EMPTY}]"

    if [[ "${TUI_EVENT:-}" == "${EVENT_CHAR:-CHAR}" ]]
    then
        menu_main_log_info \
            "EVENT_CHAR=[${TUI_EVENT_CHAR:-EMPTY}]"
    fi

    return 0
}

#============================================================
# WAIT
#============================================================

menu_main_wait()
{
    while true
    do
        if ! menu_main_read_event
        then
            return 1
        fi

        case "${TUI_EVENT:-}" in
            "$EVENT_SELECT"|"$EVENT_BACK")
                return 0
                ;;
        esac
    done
}

#============================================================
# OPERATION ERROR
#============================================================

menu_main_operation_failed()
{
    local title="${1:-Operation failed}"
    local message="${2:-Unknown error}"

    menu_main_log_error \
        "${title}: ${message}"

    if declare -F dialog_error >/dev/null 2>&1
    then
        dialog_error \
            "$title" \
            "$message" || true

        return 0
    fi

    tui_clear || true

    titlebar_draw \
        "$title" || true

    tui_move 7 5 || true

    color_error \
        "$message" || true

    tui_move 10 5 || true

    color_info \
        "Press Enter or Esc to continue." || true

    screen_refresh 2>/dev/null || true

    menu_main_wait || true

    return 0
}

#============================================================
# RUN SINGLE STAGE
#============================================================

menu_main_run_stage()
{
    local stage="${1:-}"
    local title=""
    local rc=0

    if [[ -z "$stage" ]]
    then
        menu_main_operation_failed \
            "Invalid stage" \
            "Stage name is empty."

        return 1
    fi

    if ! title="$(
        installer_get_stage_title "$stage" 2>/dev/null
    )"
    then
        title="$stage"
    fi

    [[ -n "$title" ]] || title="$stage"

    menu_main_log_info \
        "Running stage: ${stage}"

    tui_clear || return 1

    titlebar_draw \
        "Arch Linux Installer" || return 1

    tui_move 5 5 || return 1

    color_info \
        "Starting: ${title}" || return 1

    tui_move 7 5 || return 1

    tui_print \
        "Stage: ${stage}" || return 1

    t
