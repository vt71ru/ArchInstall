#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# installer/locale.sh
#
# Выбор локалей системы.
#
# Ответственность:
#   • чтение /etc/locale.gen
#   • выбор одной или нескольких UTF-8 локалей
#   • выбор LANG
#   • сохранение LOCALES
#   • сохранение LOCALE
#
# Генерация локалей выполняется locale_generate.sh.
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

declare -gi LOCALE_SELECTED=0
declare -gi LOCALE_OFFSET=0

declare -g LOCALE_DEFAULT_SELECTED=""

readonly LOCALE_VISIBLE=12

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
        dialog_error \
            "Missing locale.gen: ${file}"

        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]
    do
        line="${line#"${line%%[![:space:]]*}"}"

        [[ -z "$line" ]] && continue

        # Ignore comments which are not locale definitions.
        if [[ "$line" == \#* ]]
        then
            line="${line#\#}"
            line="${line#"${line%%[![:space:]]*}"}"
        fi

        # Ignore malformed lines.
        [[ "$line" == \#* ]] && continue

        locale_name="${line%%[[:space:]]*}"

        [[ -n "$locale_name" ]] || continue

        # Only UTF-8 locales.
        [[ "$locale_name" == *.UTF-8 ]] || continue

        # The locale.gen entry must explicitly contain UTF-8.
        if [[ ! "$line" =~ [[:space:]]+UTF-8([[:space:]]*)$ ]]
        then
            continue
        fi

        if [[ -v "LOCALE_ENABLED[$locale_name]" ]]
        then
            continue
        fi

        LOCALE_LIST+=(
            "$locale_name"
        )

        LOCALE_ENABLED["$locale_name"]=0

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

    return 0
}

#============================================================
# Restore configuration
#============================================================

locale_restore_config()
{
    local configured=""
    local default_locale=""
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

    if (( LOCALE_SELECTED >= LOCALE_OFFSET + LOCALE_VISIBLE ))
    then
        LOCALE_OFFSET=$(
            LOCALE_SELECTED - LOCALE_VISIBLE + 1
        )
    fi

    (( LOCALE_OFFSET >= 0 )) || LOCALE_OFFSET=0

    return 0
}

#============================================================
# Navigation
#============================================================

locale_previous()
{
    local count="${#LOCALE_LIST[@]}"

    (( count > 0 )) || return 1

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

    (( count > 0 )) || return 1

    if (( LOCALE_SELECTED < count - 1 ))
    then
        LOCALE_SELECTED=$((LOCALE_SELECTED + 1))
    else
        LOCALE_SELECTED=0
    fi

    if (( LOCALE_SELECTED >= LOCALE_OFFSET + LOCALE_VISIBLE ))
    then
        LOCALE_OFFSET=$(
            LOCALE_SELECTED - LOCALE_VISIBLE + 1
        )
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

    (( ${#LOCALE_LIST[@]} > 0 )) || return 1

    locale="${LOCALE_LIST[LOCALE_SELECTED]}"

    if [[ "${LOCALE_ENABLED[$locale]:-0}" == "1" ]]
    then
        LOCALE_ENABLED["$locale"]=0
    else
        LOCALE_ENABLED["$locale"]=1
    fi

    logger_debug \
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

    screen_prepare || return 1

    titlebar_draw \
        "Locale selection" || return 1

    draw_panel \
        "Select locales (Space Toggle)" \
        3 \
        5 \
        18 \
        65 || return 1

    end=$((LOCALE_OFFSET + LOCALE_VISIBLE))

    for (( index=LOCALE_OFFSET; index<end; index++ ))
    do
        (( index < ${#LOCALE_LIST[@]} )) || break

        locale="${LOCALE_LIST[index]}"

        if [[ "${LOCALE_ENABLED[$locale]:-0}" == "1" ]]
        then
            mark="x"
        else
            mark=" "
        fi

        cursor_move \
            "$row" \
            8 || return 1

        if (( index == LOCALE_SELECTED ))
        then
            printf '> [%s] %s' \
                "$mark" \
                "$locale"
        else
            printf '  [%s] %s' \
                "$mark" \
                "$locale"
        fi

        row=$((row + 1))
    done

    cursor_move 20 8 || return 1

    printf '%d/%d' \
        "$((LOCALE_SELECTED + 1))" \
        "${#LOCALE_LIST[@]}"

    statusbar_draw \
        "↑↓ Move  Space Toggle  Enter Continue  Esc Back" \
        || return 1

    screen_refresh || return 1

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
            printf '%s\n' "$locale"
        fi
    done

    return 0
}

#============================================================
# Select default locale
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
    local event

    mapfile -t locales < <(
        locale_get_selected
    )

    if (( ${#locales[@]} == 0 ))
    then
        dialog_error \
            "No locales selected"

        return 1
    fi

    if [[ -n "$LOCALE_DEFAULT_SELECTED" ]]
    then
        for index in "${!locales[@]}"
        do
            if [[ "${locales[index]}" ==
                  "$LOCALE_DEFAULT_SELECTED" ]]
            then
                selected="$index"
                break
            fi
        done
    fi

    while true
    do
        screen_prepare || return 1

        titlebar_draw \
            "Default system locale" || return 1

        draw_panel \
            "Select LANG locale" \
            3 \
            5 \
            18 \
            65 || return 1

        row=5
        end=$((offset + visible))

        for (( index=offset; index<end; index++ ))
        do
            (( index < ${#locales[@]} )) || break

            cursor_move \
                "$row" \
                8 || return 1

            if (( index == selected ))
            then
                printf '> %s' \
                    "${locales[index]}"
            else
                printf '  %s' \
                    "${locales[index]}"
            fi

            row=$((row + 1))
        done

        statusbar_draw \
            "↑↓ Select  Enter Choose  Esc Back" \
            || return 1

        screen_refresh || return 1

        event="$(
            event_read
        )"

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
                return 0
                ;;

            "$EVENT_BACK")
                return 1
                ;;

            *)
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

    if (( count == 1 ))
    then
        default_locale="${selected[0]}"
    else
        if [[ -z "$LOCALE_DEFAULT_SELECTED" ]]
        then
            LOCALE_DEFAULT_SELECTED="$(
                config_get LOCALE \
                    2>/dev/null \
                    || true
            )"
        fi

        locale_select_default || return 1

        default_locale="$LOCALE_DEFAULT_SELECTED"
    fi

    if [[ -z "$default_locale" ]]
    then
        dialog_error \
            "Default locale was not selected"

        return 1
    fi

    if ! printf '%s\n' "${selected[@]}" |
        grep -Fxq "$default_locale"
    then
        dialog_error \
            "Default locale is not among selected locales"

        return 1
    fi

    if ! config_set LOCALES "$locale_list"
    then
        logger_error \
            "Failed to store LOCALES"

        return 1
    fi

    if ! config_set LOCALE "$default_locale"
    then
        logger_error \
            "Failed to store LOCALE"

        return 1
    fi

    if ! config_save
    then
        dialog_error \
            "Failed to save locale configuration"

        return 1
    fi

    logger_info \
        "Locales selected: ${locale_list}"

    logger_info \
        "Default locale: ${default_locale}"

    if declare -F dialog_message >/dev/null 2>&1
    then
        dialog_message \
            "Locale" \
            "LANG=${default_locale}" || true
    fi

    return 0
}

#============================================================
# Main
#============================================================

locale()
{
    local event

    logger_info \
        "Locale configuration started"

    locale_load || return 1

    locale_restore_config || return 1

    while true
    do
        locale_draw || return 1

        event="$(
            event_read
        )"

        case "$event"
        in
            "$EVENT_UP")
                locale_previous || return 1
                ;;

            "$EVENT_DOWN")
                locale_next || return 1
                ;;

            "$EVENT_SPACE")
                locale_toggle || return 1
                ;;

            "$EVENT_SELECT")
                if locale_apply
                then
                    logger_info \
                        "Locale configuration completed"

                    return 0
                fi
                ;;

            "$EVENT_BACK")
                logger_info \
                    "Locale configuration cancelled"

                return 0
                ;;

            *)
                ;;
        esac
    done
}

