#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  locale.sh
#
#  Выбор локалей системы.
#
#  Ответственность:
#   • Чтение /etc/locale.gen Live ISO
#   • Выбор одной или нескольких локалей
#   • Выбор LANG
#   • Сохранение LOCALES и LOCALE
#   • Возврат управления controller после выбора
#
#  Генерация локалей выполняется locale_generate.sh.
#
#  Не изменяет /etc/locale.gen.
#
#============================================================

if [[ -n "${LOCALE_SH_LOADED:-}" ]]
then
    return 0
fi

readonly LOCALE_SH_LOADED=1

#============================================================
# State
#============================================================

declare -ga LOCALE_LIST=()
declare -gA LOCALE_ENABLED=()

LOCALE_SELECTED=0
LOCALE_OFFSET=0
LOCALE_DEFAULT_SELECTED=""

readonly LOCALE_VISIBLE=12

#============================================================
# Logging
#============================================================

locale_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@"
    fi

    return 0
}

locale_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@"
    fi

    return 0
}

locale_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@"
    fi

    return 0
}

#============================================================
# Load locales
#============================================================

locale_load()
{
    local file="/etc/locale.gen"
    local line
    local locale_name

    LOCALE_LIST=()
    LOCALE_ENABLED=()

    if [[ ! -f "$file" ]]
    then
        if declare -F dialog_error >/dev/null 2>&1
        then
            dialog_error \
                "Locale" \
                "Missing locale.gen: ${file}"
        fi

        locale_log_error \
            "Missing locale.gen: ${file}"

        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]
    do
        #----------------------------------------------------
        # Remove leading whitespace
        #----------------------------------------------------

        line="${line#"${line%%[![:space:]]*}"}"

        [[ -z "$line" ]] && continue

        #----------------------------------------------------
        # Ignore comments that are not locale definitions.
        #
        # Accept both:
        #
        #   en_US.UTF-8 UTF-8
        #
        # and:
        #
        #   #en_US.UTF-8 UTF-8
        #----------------------------------------------------

        if [[ "$line" == \#* ]]
        then
            line="${line#\#}"

            line="${line#"${line%%[![:space:]]*}"}"
        fi

        [[ -z "$line" ]] && continue

        #----------------------------------------------------
        # First whitespace-separated field
        #----------------------------------------------------

        locale_name="${line%%[[:space:]]*}"

        [[ -z "$locale_name" ]] && continue

        #----------------------------------------------------
        # Only UTF-8 locales
        #----------------------------------------------------

        if [[ "$locale_name" != *.UTF-8 ]]
        then
            continue
        fi

        #----------------------------------------------------
        # The locale.gen line must explicitly specify UTF-8.
        #----------------------------------------------------

        if [[ ! "$line" =~ [[:space:]]+UTF-8([[:space:]]*)$ ]]
        then
            continue
        fi

        #----------------------------------------------------
        # Avoid duplicates
        #----------------------------------------------------

        if [[ -v "LOCALE_ENABLED[$locale_name]" ]]
        then
            continue
        fi

        LOCALE_LIST+=(
            "$locale_name"
        )

        LOCALE_ENABLED["$locale_name"]=0

    done < "$file"

    #--------------------------------------------------------
    # Validate result
    #--------------------------------------------------------

    if (( ${#LOCALE_LIST[@]} == 0 ))
    then
        if declare -F dialog_error >/dev/null 2>&1
        then
            dialog_error \
                "Locale" \
                "No UTF-8 locales found in ${file}"
        fi

        locale_log_error \
            "No UTF-8 locales found"

        return 1
    fi

    LOCALE_SELECTED=0
    LOCALE_OFFSET=0
    LOCALE_DEFAULT_SELECTED=""

    locale_log_info \
        "Locales loaded: ${#LOCALE_LIST[@]}"

    return 0
}

#============================================================
# Restore saved selection
#============================================================

locale_restore_config()
{
    local configured=""
    local default_locale=""
    local locale
    local index

    #--------------------------------------------------------
    # Restore selected locales
    #--------------------------------------------------------

    if declare -F config_get >/dev/null 2>&1
    then
        configured="$(
            config_get \
                LOCALES \
                2>/dev/null \
                || true
        )"
    fi

    # LOCALES is stored as a space-separated list.
    for locale in $configured
    do
        if [[ -v "LOCALE_ENABLED[$locale]" ]]
        then
            LOCALE_ENABLED["$locale"]=1
        fi
    done

    #--------------------------------------------------------
    # Restore default LANG
    #--------------------------------------------------------

    if declare -F config_get >/dev/null 2>&1
    then
        default_locale="$(
            config_get \
                LOCALE \
                2>/dev/null \
                || true
        )"
    fi

    LOCALE_DEFAULT_SELECTED="$default_locale"

    #--------------------------------------------------------
    # Position cursor on saved default locale
    #--------------------------------------------------------

    if [[ -n "$default_locale" ]]
    then
        for index in "${!LOCALE_LIST[@]}"
        do
            if [[ "${LOCALE_LIST[index]}" == "$default_locale" ]]
            then
                LOCALE_SELECTED="$index"
                break
            fi
        done
    fi

    #--------------------------------------------------------
    # Keep selected item inside visible window
    #--------------------------------------------------------

    if (( LOCALE_SELECTED >= LOCALE_OFFSET + LOCALE_VISIBLE ))
    then
        LOCALE_OFFSET=$(
            (
                LOCALE_SELECTED - LOCALE_VISIBLE + 1
            )
        )
    fi

    if (( LOCALE_OFFSET < 0 ))
    then
        LOCALE_OFFSET=0
    fi

    return 0
}

#============================================================
# Navigation
#============================================================

locale_previous()
{
    local count="${#LOCALE_LIST[@]}"

    if (( count == 0 ))
    then
        return 1
    fi

    if (( LOCALE_SELECTED > 0 ))
    then
        LOCALE_SELECTED=$((LOCALE_SELECTED - 1))
    else
        LOCALE_SELECTED=$((count - 1))
    fi

    if (( LOCALE_SELECTED < LOCALE_OFFSET ))
    then
        LOCALE_OFFSET="$LOCALE_SELECTED"
    fi

    if (( LOCALE_SELECTED == count - 1 ))
    then
        LOCALE_OFFSET=$((count - LOCALE_VISIBLE))

        if (( LOCALE_OFFSET < 0 ))
        then
            LOCALE_OFFSET=0
        fi
    fi

    return 0
}

locale_next()
{
    local count="${#LOCALE_LIST[@]}"

    if (( count == 0 ))
    then
        return 1
    fi

    if (( LOCALE_SELECTED < count - 1 ))
    then
        LOCALE_SELECTED=$((LOCALE_SELECTED + 1))
    else
        LOCALE_SELECTED=0
    fi

    if (( LOCALE_SELECTED >= LOCALE_OFFSET + LOCALE_VISIBLE ))
    then
        LOCALE_OFFSET=$((LOCALE_SELECTED - LOCALE_VISIBLE + 1))
    fi

    if (( LOCALE_SELECTED == 0 ))
    then
        LOCALE_OFFSET=0
    fi

    return 0
}

#============================================================
# Toggle
#============================================================

locale_toggle()
{
    local locale

    if (( ${#LOCALE_LIST[@]} == 0 ))
    then
        return 1
    fi

    locale="${LOCALE_LIST[LOCALE_SELECTED]}"

    if [[ "${LOCALE_ENABLED[$locale]:-0}" == "1" ]]
    then
        LOCALE_ENABLED["$locale"]=0
    else
        LOCALE_ENABLED["$locale"]=1
    fi

    locale_log_info \
        "Locale ${locale}: ${LOCALE_ENABLED[$locale]}"

    return 0
}

#============================================================
# Draw
#============================================================

locale_draw()
{
    local row=5
    local index
    local end
    local locale
    local mark

    if declare -F screen_prepare >/dev/null 2>&1
    then
        screen_prepare || return 1
    elif declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear || return 1
    fi

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "Locale selection" || return 1
    fi

    if declare -F draw_panel >/dev/null 2>&1
    then
        draw_panel \
            "Select locales (Space Toggle)" \
            3 \
            5 \
            18 \
            65 || return 1
    fi

    end=$((LOCALE_OFFSET + LOCALE_VISIBLE))

    for (( index=LOCALE_OFFSET; index<end; index++ ))
    do
        if (( index >= ${#LOCALE_LIST[@]} ))
        then
            break
        fi

        locale="${LOCALE_LIST[index]}"

        if [[ "${LOCALE_ENABLED[$locale]:-0}" == "1" ]]
        then
            mark="x"
        else
            mark=" "
        fi

        if declare -F tui_move >/dev/null 2>&1
        then
            tui_move \
                "$row" \
                8 || return 1
        elif declare -F cursor_move >/dev/null 2>&1
        then
            cursor_move \
                "$row" \
                8 || return 1
        fi

        if (( index == LOCALE_SELECTED ))
        then
            if declare -F color_selected >/dev/null 2>&1
            then
                color_selected \
                    "> [${mark}] ${locale}"
            else
                printf \
                    '> [%s] %s' \
                    "$mark" \
                    "$locale"
            fi
        else
            if declare -F tui_print >/dev/null 2>&1
            then
                tui_print \
                    "  [${mark}] ${locale}"
            else
                printf \
                    '  [%s] %s' \
                    "$mark" \
                    "$locale"
            fi
        fi

        row=$((row + 1))
    done

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move \
            20 \
            8 || return 1
    elif declare -F cursor_move >/dev/null 2>&1
    then
        cursor_move \
            20 \
            8 || return 1
    fi

    printf \
        '%d/%d' \
        "$((LOCALE_SELECTED + 1))" \
        "${#LOCALE_LIST[@]}"

    if declare -F statusbar_draw >/dev/null 2>&1
    then
        statusbar_draw \
            "↑↓ Move  Space Toggle  Enter Continue  Esc Back" \
            || return 1
    fi

    if declare -F screen_refresh >/dev/null 2>&1
    then
        screen_refresh \
            2>/dev/null \
            || true
    fi

    return 0
}

#============================================================
# Selected locales
#============================================================

locale_get_selected()
{
    local locale

    for locale in "${LOCALE_LIST[@]}"
    do
        if [[ "${LOCALE_ENABLED[$locale]:-0}" == "1" ]]
        then
            printf '%s\n' \
                "$locale"
        fi
    done

    return 0
}

#============================================================
# Default locale selector
#============================================================

locale_select_default()
{
    local locales=()
    local locale
    local selected=0
    local offset=0
    local visible="$LOCALE_VISIBLE"
    local row
    local index
    local end
    local event=""

    #--------------------------------------------------------
    # Build selected locale list
    #--------------------------------------------------------

    while IFS= read -r locale
    do
        [[ -n "$locale" ]] &&
            locales+=(
                "$locale"
            )
    done < <(
        locale_get_selected
    )

    if (( ${#locales[@]} == 0 ))
    then
        if declare -F dialog_error >/dev/null 2>&1
        then
            dialog_error \
                "Locale" \
                "No locales selected"
        fi

        return 1
    fi

    #--------------------------------------------------------
    # Restore previous default
    #--------------------------------------------------------

    if [[ -n "$LOCALE_DEFAULT_SELECTED" ]]
    then
        for index in "${!locales[@]}"
        do
            if [[ "${locales[index]}" == "$LOCALE_DEFAULT_SELECTED" ]]
            then
                selected="$index"
                break
            fi
        done
    fi

    #========================================================
    # Default locale loop
    #========================================================

    while true
    do
        if declare -F screen_prepare >/dev/null 2>&1
        then
            screen_prepare || return 1
        elif declare -F tui_clear >/dev/null 2>&1
        then
            tui_clear || return 1
        fi

        if declare -F titlebar_draw >/dev/null 2>&1
        then
            titlebar_draw \
                "Default system locale" || return 1
        fi

        if declare -F draw_panel >/dev/null 2>&1
        then
            draw_panel \
                "Select LANG locale" \
                3 \
                5 \
                18 \
                65 || return 1
        fi

        row=5
        end=$((offset + visible))

        for (( index=offset; index<end; index++ ))
        do
            if (( index >= ${#locales[@]} ))
            then
                break
            fi

            if declare -F tui_move >/dev/null 2>&1
            then
                tui_move \
                    "$row" \
                    8 || return 1
            elif declare -F cursor_move >/dev/null 2>&1
            then
                cursor_move \
                    "$row" \
                    8 || return 1
            fi

            if (( index == selected ))
            then
                if declare -F color_selected >/dev/null 2>&1
                then
                    color_selected \
                        "> ${locales[index]}"
                else
                    printf \
                        '> %s' \
                        "${locales[index]}"
                fi
            else
                if declare -F tui_print >/dev/null 2>&1
                then
                    tui_print \
                        "  ${locales[index]}"
                else
                    printf \
                        '  %s' \
                        "${locales[index]}"
                fi
            fi

            row=$((row + 1))
        done

        if declare -F statusbar_draw >/dev/null 2>&1
        then
            statusbar_draw \
                "↑↓ Select  Enter Choose  Esc Back" \
                || return 1
        fi

        if declare -F screen_refresh >/dev/null 2>&1
        then
            screen_refresh \
                2>/dev/null \
                || true
        fi

        #----------------------------------------------------
        # IMPORTANT:
        # event_read() writes to TUI_EVENT.
        #----------------------------------------------------

        if ! event_read
        then
            locale_log_error \
                "event_read() failed while selecting default locale"

            return 1
        fi

        event="${TUI_EVENT:-}"

        case "$event"
        in

            "$EVENT_UP")

                if (( selected > 0 ))
                then
                    selected=$((selected - 1))
                else
                    selected=$(( ${#locales[@]} - 1 ))
                fi

                if (( selected < offset ))
                then
                    offset="$selected"
                fi

                if (( selected == ${#locales[@]} - 1 ))
                then
                    offset=$(( ${#locales[@]} - visible ))

                    if (( offset < 0 ))
                    then
                        offset=0
                    fi
                fi

                ;;

            "$EVENT_DOWN")

                if (( selected < ${#locales[@]} - 1 ))
                then
                    selected=$((selected + 1))
                else
                    selected=0
                fi

                if (( selected >= offset + visible ))
                then
                    offset=$((selected - visible + 1))
                fi

                if (( selected == 0 ))
                then
                    offset=0
                fi

                ;;

            "$EVENT_SELECT")

                LOCALE_DEFAULT_SELECTED="${locales[selected]}"

                locale_log_info \
                    "Default locale selected: ${LOCALE_DEFAULT_SELECTED}"

                return 0
                ;;

            "$EVENT_BACK")

                locale_log_warn \
                    "Default locale selection cancelled"

                return 1
                ;;

            *)
                locale_log_warn \
                    "Unknown locale event: ${event:-<empty>}"
                ;;
        esac
    done
}

#============================================================
# Apply
#============================================================

locale_apply()
{
    local selected=()
    local locale
    local locale_list
    local count
    local default_locale

    #--------------------------------------------------------
    # Get selected locales
    #--------------------------------------------------------

    mapfile -t selected < <(
        locale_get_selected
    )

    count="${#selected[@]}"

    if (( count == 0 ))
    then
        if declare -F dialog_error >/dev/null 2>&1
        then
            dialog_error \
                "Locale" \
                "Select at least one locale"
        fi

        return 1
    fi

    locale_list="${selected[*]}"

    #========================================================
    # Determine default LANG
    #========================================================

    if (( count == 1 ))
    then
        default_locale="${selected[0]}"
    else
        default_locale="$(
            config_get \
                LOCALE \
                2>/dev/null \
                || true
        )"

        LOCALE_DEFAULT_SELECTED="$default_locale"

        if ! locale_select_default
        then
            return 1
        fi

        default_locale="$LOCALE_DEFAULT_SELECTED"
    fi

    if [[ -z "$default_locale" ]]
    then
        if declare -F dialog_error >/dev/null 2>&1
        then
            dialog_error \
                "Locale" \
                "Default locale was not selected"
        fi

        return 1
    fi

    #--------------------------------------------------------
    # Verify LANG belongs to selected locales
    #--------------------------------------------------------

    if ! printf '%s\n' \
        "${selected[@]}" |
        grep -Fxq \
            "$default_locale"
    then
        if declare -F dialog_error >/dev/null 2>&1
        then
            dialog_error \
                "Locale" \
                "Default locale is not among selected locales"
        fi

        return 1
    fi

    #========================================================
    # Save LOCALES
    #========================================================

    if ! config_set \
        LOCALES \
        "$locale_list"
    then
        locale_log_error \
            "Failed to store LOCALES"

        return 1
    fi

    #========================================================
    # Save LANG
    #========================================================

    if ! config_set \
        LOCALE \
        "$default_locale"
    then
        locale_log_error \
            "Failed to store LOCALE"

        return 1
    fi

    #========================================================
    # Save configuration
    #========================================================

    if ! config_save
    then
        if declare -F dialog_error >/dev/null 2>&1
        then
            dialog_error \
                "Locale" \
                "Failed to save locale configuration"
        fi

        return 1
    fi

    locale_log_info \
        "Locales selected: ${locale_list}"

    locale_log_info \
        "Default locale: ${default_locale}"

    #--------------------------------------------------------
    # Optional informational dialog.
    #
    # Do not make this dialog part of the control flow.
    # The caller must continue immediately after success.
    #--------------------------------------------------------

    if declare -F dialog_message >/dev/null 2>&1
    then
        dialog_message \
            "Locale" \
            "LANG=${default_locale}" \
            || true
    fi

    return 0
}

#============================================================
# Main
#============================================================

locale()
{
    local event=""

    locale_log_info \
        "Locale configuration started"

    #--------------------------------------------------------
    # Load /etc/locale.gen
    #--------------------------------------------------------

    if ! locale_load
    then
        locale_log_error \
            "locale_load() failed"

        return 1
    fi

    #--------------------------------------------------------
    # Restore saved values
    #--------------------------------------------------------

    if ! locale_restore_config
    then
        locale_log_error \
            "locale_restore_config() failed"

        return 1
    fi

    #========================================================
    # Selection loop
    #========================================================

    while true
    do
        if ! locale_draw
        then
            locale_log_error \
                "locale_draw() failed"

            return 1
        fi

        #----------------------------------------------------
        # IMPORTANT:
        # event_read() writes the event to TUI_EVENT.
        #----------------------------------------------------

        if ! event_read
        then
            locale_log_error \
                "event_read() failed"

            return 1
        fi

        event="${TUI_EVENT:-}"

        case "$event"
        in

            #------------------------------------------------
            # Up
            #------------------------------------------------

            "$EVENT_UP")

                locale_previous

                ;;

            #------------------------------------------------
            # Down
            #------------------------------------------------

            "$EVENT_DOWN")

                locale_next

                ;;

            #------------------------------------------------
            # Space
            #------------------------------------------------

            "$EVENT_SPACE")

                locale_toggle

                ;;

            #------------------------------------------------
            # Enter
            #
            # IMPORTANT:
            # Successful Apply MUST return from locale().
            # This gives control back to installer controller.
            #------------------------------------------------

            "$EVENT_SELECT")

                if ! locale_apply
                then
                    locale_log_warn \
                        "Locale selection was not applied"

                    continue
                fi

                locale_log_info \
                    "Locale configuration completed"

                return 0

                ;;

            #------------------------------------------------
            # Escape
            #------------------------------------------------

            "$EVENT_BACK")

                locale_log_warn \
                    "Locale configuration cancelled"

                return 1

                ;;

            #------------------------------------------------
            # Unknown event
            #------------------------------------------------

            *)

                locale_log_warn \
                    "Unknown locale event: ${event:-<empty>}"

                ;;
        esac
    done
}

