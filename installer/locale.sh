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
#
#  Генерация локалей выполняется locale_generate.sh.
#============================================================

[[ -n "${LOCALE_SH_LOADED:-}" ]] && return

readonly LOCALE_SH_LOADED=1

#------------------------------------------------------------
# State
#------------------------------------------------------------

declare -ga LOCALE_LIST=()
declare -gA LOCALE_ENABLED=()

LOCALE_SELECTED=0
LOCALE_OFFSET=0
LOCALE_DEFAULT_SELECTED=""

readonly LOCALE_VISIBLE=12

#------------------------------------------------------------
# Load locales
#------------------------------------------------------------

locale_load()
{
    local file="/etc/locale.gen"
    local line
    local locale

    LOCALE_LIST=()
    LOCALE_ENABLED=()

    if [[ ! -f "$file" ]]
    then
        dialog_error \
            "Missing locale.gen: ${file}"

        return 1
    fi

    while IFS= read -r line
    do
        line="${line#"${line%%[![:space:]]*}"}"

        [[ -z "$line" ]] && \
            continue

        if [[ "$line" == \#* ]]
        then
            line="${line#\#}"
            line="${line#"${line%%[![:space:]]*}"}"
        fi

        if [[ "$line" =~ ^([A-Za-z_]+\.UTF-8)[[:space:]]+UTF-8([[:space:]]*)$ ]]
        then
            locale="${BASH_REMATCH[1]}"

            if [[ -z "${LOCALE_ENABLED[$locale]+x}" ]]
            then
                LOCALE_LIST+=(
                    "$locale"
                )

                LOCALE_ENABLED["$locale"]=0
            fi
        fi
    done < "$file"

    if (( ${#LOCALE_LIST[@]} == 0 ))
    then
        dialog_error \
            "No UTF-8 locales found"

        return 1
    fi

    LOCALE_SELECTED=0
    LOCALE_OFFSET=0
    LOCALE_DEFAULT_SELECTED=""

    logger_info \
        "Locales loaded: ${#LOCALE_LIST[@]}"
}

#------------------------------------------------------------
# Restore saved selection
#------------------------------------------------------------

locale_restore_config()
{
    local configured
    local default_locale
    local locale
    local index

    configured="$(
        config_get LOCALES \
            2>/dev/null \
            || true
    )"

    for locale in $configured
    do
        if [[ -v "LOCALE_ENABLED[$locale]" ]]
        then
            LOCALE_ENABLED["$locale"]=1
        fi
    done

    default_locale="$(
        config_get LOCALE \
            2>/dev/null \
            || true
    )"

    LOCALE_DEFAULT_SELECTED="$default_locale"

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
}

#------------------------------------------------------------
# Navigation
#------------------------------------------------------------

locale_previous()
{
    if (( LOCALE_SELECTED > 0 ))
    then
        ((LOCALE_SELECTED -= 1))
    else
        LOCALE_SELECTED=$(( ${#LOCALE_LIST[@]} - 1 ))
    fi

    if (( LOCALE_SELECTED < LOCALE_OFFSET ))
    then
        LOCALE_OFFSET="$LOCALE_SELECTED"
    fi

    if (( LOCALE_SELECTED == ${#LOCALE_LIST[@]} - 1 ))
    then
        LOCALE_OFFSET=$(( ${#LOCALE_LIST[@]} - LOCALE_VISIBLE ))

        if (( LOCALE_OFFSET < 0 ))
        then
            LOCALE_OFFSET=0
        fi
    fi
}

locale_next()
{
    if (( LOCALE_SELECTED < ${#LOCALE_LIST[@]} - 1 ))
    then
        ((LOCALE_SELECTED += 1))
    else
        LOCALE_SELECTED=0
    fi

    if (( LOCALE_SELECTED >= LOCALE_OFFSET + LOCALE_VISIBLE ))
    then
        LOCALE_OFFSET=$(( LOCALE_SELECTED - LOCALE_VISIBLE + 1 ))
    fi

    if (( LOCALE_SELECTED == 0 ))
    then
        LOCALE_OFFSET=0
    fi
}

#------------------------------------------------------------
# Toggle
#------------------------------------------------------------

locale_toggle()
{
    local locale

    locale="${LOCALE_LIST[LOCALE_SELECTED]}"

    if [[ "${LOCALE_ENABLED[$locale]:-0}" == "1" ]]
    then
        LOCALE_ENABLED["$locale"]=0
    else
        LOCALE_ENABLED["$locale"]=1
    fi

    logger_debug \
        "Locale ${locale}: ${LOCALE_ENABLED[$locale]}"
}

#------------------------------------------------------------
# Draw
#------------------------------------------------------------

locale_draw()
{
    local row=5
    local index
    local end
    local locale
    local mark

    screen_prepare

    titlebar_draw \
        "Locale selection"

    draw_panel \
        "Select locales (Space Toggle)" \
        3 \
        5 \
        18 \
        65

    end=$(( LOCALE_OFFSET + LOCALE_VISIBLE ))

    for (( index=LOCALE_OFFSET; index<end; index++ ))
    do
        (( index >= ${#LOCALE_LIST[@]} )) && \
            break

        locale="${LOCALE_LIST[index]}"

        if [[ "${LOCALE_ENABLED[$locale]:-0}" == "1" ]]
        then
            mark="x"
        else
            mark=" "
        fi

        cursor_move \
            "$row" \
            8

        if (( index == LOCALE_SELECTED ))
        then
            printf \
                '> [%s] %s' \
                "$mark" \
                "$locale"
        else
            printf \
                '  [%s] %s' \
                "$mark" \
                "$locale"
        fi

        ((row += 1))
    done

    cursor_move \
        20 \
        8

    printf \
        '%d/%d' \
        "$((LOCALE_SELECTED + 1))" \
        "${#LOCALE_LIST[@]}"

    statusbar_draw \
        "↑↓ Move  Space Toggle  Enter Continue  Esc Back"

    screen_refresh
}

#------------------------------------------------------------
# Selected locales
#------------------------------------------------------------

locale_get_selected()
{
    local locale

    for locale in "${LOCALE_LIST[@]}"
    do
        if [[ "${LOCALE_ENABLED[$locale]:-0}" == "1" ]]
        then
            printf \
                '%s\n' \
                "$locale"
        fi
    done
}

#------------------------------------------------------------
# Default locale selector
#------------------------------------------------------------

locale_select_default()
{
    local locales=()
    local locale
    local selected=0
    local offset=0
    local visible=12
    local row
    local index
    local end
    local event

    while IFS= read -r locale
    do
        [[ -n "$locale" ]] && \
            locales+=(
                "$locale"
            )
    done < <(
        locale_get_selected
    )

    if (( ${#locales[@]} == 0 ))
    then
        return 1
    fi

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

    while true
    do
        screen_prepare

        titlebar_draw \
            "Default system locale"

        draw_panel \
            "Select LANG locale" \
            3 \
            5 \
            18 \
            65

        row=5
        end=$(( offset + visible ))

        for (( index=offset; index<end; index++ ))
        do
            (( index >= ${#locales[@]} )) && \
                break

            cursor_move \
                "$row" \
                8

            if (( index == selected ))
            then
                printf \
                    '> %s' \
                    "${locales[index]}"
            else
                printf \
                    '  %s' \
                    "${locales[index]}"
            fi

            ((row += 1))
        done

        statusbar_draw \
            "↑↓ Select  Enter Choose  Esc Back"

        screen_refresh

        event="$(
            event_read
        )"

        case "$event" in
            "$EVENT_UP")
                if (( selected > 0 ))
                then
                    ((selected -= 1))
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
                    ((selected += 1))
                else
                    selected=0
                fi

                if (( selected >= offset + visible ))
                then
                    offset=$(( selected - visible + 1 ))
                fi

                if (( selected == 0 ))
                then
                    offset=0
                fi
                ;;
            "$EVENT_SELECT")
                LOCALE_DEFAULT_SELECTED="${locales[selected]}"
                return 0
                ;;
            "$EVENT_BACK")
                return 1
                ;;
        esac
    done
}

#------------------------------------------------------------
# Apply
#------------------------------------------------------------

locale_apply()
{
    local selected=()
    local locale
    local locale_list
    local count
    local default_locale

    mapfile -t selected < <(
        locale_get_selected
    )

    count="${#selected[@]}"

    if (( count == 0 ))
    then
        dialog_error \
            "Select at least one locale"

        return 1
    fi

    locale_list="${selected[*]}"

    #
    # LANG must always be one of the enabled locales.
    #

    if (( count == 1 ))
    then
        default_locale="${selected[0]}"
    else
        LOCALE_DEFAULT_SELECTED="$(
            config_get LOCALE \
                2>/dev/null \
                || true
        )

        locale_select_default || \
            return 1

        default_locale="$LOCALE_DEFAULT_SELECTED"
    fi

    if [[ -z "$default_locale" ]]
    then
        dialog_error \
            "Default locale was not selected"

        return 1
    fi

    if ! printf '%s\n' \
        "${selected[@]}" |
        grep -Fxq \
            "$default_locale"
    then
        dialog_error \
            "Default locale is not among selected locales"

        return 1
    fi

    config_set \
        LOCALES \
        "$locale_list"

    config_set \
        LOCALE \
        "$default_locale"

    config_save

    logger_info \
        "Locales selected: ${locale_list}"

    logger_info \
        "Default locale: ${default_locale}"

    dialog_message \
        "Locale" \
        "LANG=${default_locale}"

    return 0
}

#------------------------------------------------------------
# Main
#------------------------------------------------------------

locale()
{
    local event

    logger_info \
        "Locale configuration started"

    locale_load || \
        return 1

    locale_restore_config

    while true
    do
        locale_draw

        event="$(
            event_read
        )"

        case "$event" in
            "$EVENT_UP")
                locale_previous
                ;;
            "$EVENT_DOWN")
                locale_next
                ;;
            "$EVENT_SPACE")
                locale_toggle
                ;;
            "$EVENT_SELECT")
                locale_apply || \
                    continue
                ;;
            "$EVENT_BACK")
                break
                ;;
        esac
    done

    logger_info \
        "Locale configuration finished"
}