#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  mirrors.sh
#
#  Настройка зеркал Arch Linux.
#
#  Ответственность:
#   • Проверка сетевого соединения
#   • Проверка Reflector
#   • Выбор страны
#   • Генерация mirrorlist
#   • Резервный mirrorlist
#
#  Не выполняет:
#   • Управление CONFIG
#   • Разметку диска
#   • Установку пакетов
#   • Настройку NetworkManager
#============================================================

[[ -n "${MIRRORS_SH_LOADED:-}" ]] && return

readonly MIRRORS_SH_LOADED=1

#------------------------------------------------------------
# State
#------------------------------------------------------------

declare -a MIRROR_COUNTRIES=()

MIRROR_SELECTED=0
MIRROR_COUNTRY=""
MIRROR_LATEST=10
MIRROR_AGE=24
MIRROR_PROTOCOL="https"
MIRROR_SORT="rate"

readonly MIRRORLIST_FILE="/etc/pacman.d/mirrorlist"
readonly MIRRORLIST_BACKUP="/etc/pacman.d/mirrorlist.archinstaller.bak"

#------------------------------------------------------------
# Dependencies
#------------------------------------------------------------

mirrors_check_dependencies()
{
    local required=(
        ping
        grep
        sed
        cp
        mv
    )

    local cmd

    for cmd in "${required[@]}"
    do
        if ! command -v "$cmd" >/dev/null 2>&1
        then
            dialog_error \
                "Required program not found: ${cmd}"

            return 1
        fi
    done
}

#------------------------------------------------------------
# Check network
#------------------------------------------------------------

mirrors_check_network()
{
    logger_info \
        "Checking network connectivity for mirror selection"

    if getent \
        hosts \
        archlinux.org \
        >/dev/null 2>&1
    then
        logger_info \
            "DNS resolution available"
    else
        logger_warn \
            "DNS resolution unavailable"

        return 1
    fi

    if ping \
        -c 1 \
        -W 3 \
        archlinux.org \
        >/dev/null 2>&1
    then
        logger_info \
            "Network available"

        return 0
    fi

    logger_warn \
        "Network unavailable"

    return 1
}

#------------------------------------------------------------
# Check reflector
#------------------------------------------------------------

mirrors_check_reflector()
{
    if ! command -v reflector >/dev/null 2>&1
    then
        logger_warn \
            "Reflector is not installed"

        return 1
    fi

    logger_info \
        "Reflector detected: $(command -v reflector)"
}

#------------------------------------------------------------
# Load country list
#------------------------------------------------------------

mirrors_load_countries()
{
    MIRROR_COUNTRIES=()
    MIRROR_SELECTED=0

    if ! mirrors_check_reflector
    then
        return 1
    fi

    mapfile -t MIRROR_COUNTRIES < <(
        reflector \
            --list-countries 2>/dev/null |
        sed \
            -n \
            '/^[[:space:]]*[A-Za-z]/p' |
        sed \
            -E \
            's/^[[:space:]]+//'
    )

    if (( ${#MIRROR_COUNTRIES[@]} == 0 ))
    then
        logger_warn \
            "Reflector returned no countries"

        return 1
    fi

    logger_info \
        "Loaded ${#MIRROR_COUNTRIES[@]} countries"
}

#------------------------------------------------------------
# Draw country selector
#------------------------------------------------------------

mirrors_draw()
{
    local row=5
    local index

    tui_clear

    titlebar_draw \
        "Mirror selection"

    draw_panel \
        "Select country" \
        3 \
        5 \
        20 \
        65

    for (( index=0; index<${#MIRROR_COUNTRIES[@]} && index<12; index++ ))
    do
        cursor_move \
            "$row" \
            8

        if (( index == MIRROR_SELECTED ))
        then
            printf \
                '> %s' \
                "${MIRROR_COUNTRIES[index]}"
        else
            printf \
                '  %s' \
                "${MIRROR_COUNTRIES[index]}"
        fi

        ((row += 1))
    done

    statusbar_draw \
        "↑↓ Select   Enter Apply   Esc Back"

    screen_refresh
}

#------------------------------------------------------------
# Country navigation
#------------------------------------------------------------

mirrors_previous()
{
    if (( MIRROR_SELECTED > 0 ))
    then
        ((MIRROR_SELECTED -= 1))
    else
        MIRROR_SELECTED=$(( ${#MIRROR_COUNTRIES[@]} - 1 ))
    fi
}

mirrors_next()
{
    if (( MIRROR_SELECTED < ${#MIRROR_COUNTRIES[@]} - 1 ))
    then
        ((MIRROR_SELECTED += 1))
    else
        MIRROR_SELECTED=0
    fi
}

#------------------------------------------------------------
# Select country
#------------------------------------------------------------

mirrors_select_country()
{
    local event

    while true
    do
        mirrors_draw

        event="$(
            event_read
        )"

        case "$event" in
            "$EVENT_UP")
                mirrors_previous
                ;;
            "$EVENT_DOWN")
                mirrors_next
                ;;
            "$EVENT_SELECT")
                MIRROR_COUNTRY="${MIRROR_COUNTRIES[MIRROR_SELECTED]}"

                logger_info \
                    "Mirror country selected: ${MIRROR_COUNTRY}"

                return 0
                ;;
            "$EVENT_BACK")
                return 1
                ;;
        esac
    done
}

#------------------------------------------------------------
# Backup mirrorlist
#------------------------------------------------------------

mirrors_backup()
{
    if [[ ! -f "$MIRRORLIST_FILE" ]]
    then
        logger_warn \
            "Current mirrorlist does not exist"

        return 0
    fi

    cp \
        -f \
        "$MIRRORLIST_FILE" \
        "$MIRRORLIST_BACKUP" \
        || {
            logger_error \
                "Failed creating mirrorlist backup"

            return 1
        }

    logger_info \
        "Mirrorlist backup created: ${MIRRORLIST_BACKUP}"
}

#------------------------------------------------------------
# Validate generated mirrorlist
#------------------------------------------------------------

mirrors_validate()
{
    local file="$1"

    if [[ ! -f "$file" ]]
    then
        logger_error \
            "Mirrorlist was not created: ${file}"

        return 1
    fi

    if [[ ! -s "$file" ]]
    then
        logger_error \
            "Mirrorlist is empty: ${file}"

        return 1
    fi

    if ! grep -Eq \
        '^[[:space:]]*Server[[:space:]]*=' \
        "$file"
    then
        logger_error \
            "Mirrorlist contains no active Server entries"

        return 1
    fi

    logger_info \
        "Mirrorlist validation passed: ${file}"
}

#------------------------------------------------------------
# Generate mirrorlist
#------------------------------------------------------------

mirrors_generate()
{
    local tmp_file

    tmp_file="${MIRRORLIST_FILE}.tmp.$$"

    logger_info \
        "Generating mirrorlist"

    if [[ -n "$MIRROR_COUNTRY" ]]
    then
        reflector \
            --country "$MIRROR_COUNTRY" \
            --latest "$MIRROR_LATEST" \
            --age "$MIRROR_AGE" \
            --protocol "$MIRROR_PROTOCOL" \
            --sort "$MIRROR_SORT" \
            --save "$tmp_file" \
            || {
                rm -f \
                    "$tmp_file"

                logger_error \
                    "Reflector failed"

                return 1
            }
    else
        reflector \
            --latest "$MIRROR_LATEST" \
            --age "$MIRROR_AGE" \
            --protocol "$MIRROR_PROTOCOL" \
            --sort "$MIRROR_SORT" \
            --save "$tmp_file" \
            || {
                rm -f \
                    "$tmp_file"

                logger_error \
                    "Reflector failed"

                return 1
            }
    fi

    mirrors_validate \
        "$tmp_file" || {
        rm -f \
            "$tmp_file"

        return 1
    }

    mv \
        -f \
        "$tmp_file" \
        "$MIRRORLIST_FILE" \
        || {
            rm -f \
                "$tmp_file"

            logger_error \
                "Failed installing generated mirrorlist"

            return 1
        }

    logger_info \
        "Mirrorlist generated: ${MIRRORLIST_FILE}"
}

#------------------------------------------------------------
# Fallback mirrorlist
#------------------------------------------------------------

mirrors_fallback()
{
    logger_warn \
        "Using fallback mirrorlist"

    if [[ -f /etc/pacman.d/mirrorlist.pacnew ]]
    then
        cp \
            -f \
            /etc/pacman.d/mirrorlist.pacnew \
            "$MIRRORLIST_FILE" \
            || {
                logger_error \
                    "Failed restoring mirrorlist.pacnew"

                return 1
            }

        mirrors_validate \
            "$MIRRORLIST_FILE" || \
            return 1

        return 0
    fi

    if [[ -f "$MIRRORLIST_BACKUP" ]]
    then
        cp \
            -f \
            "$MIRRORLIST_BACKUP" \
            "$MIRRORLIST_FILE" \
            || {
                logger_error \
                    "Failed restoring mirrorlist backup"

                return 1
            }

        mirrors_validate \
            "$MIRRORLIST_FILE" || \
            return 1

        return 0
    fi

    if [[ ! -f "$MIRRORLIST_FILE" ]]
    then
        logger_error \
            "No fallback mirrorlist available"

        return 1
    fi

    mirrors_validate \
        "$MIRRORLIST_FILE"
}

#------------------------------------------------------------
# Final test
#------------------------------------------------------------

mirrors_test()
{
    local server

    server="$(
        grep \
            -m 1 \
            -E \
            '^[[:space:]]*Server[[:space:]]*=' \
            "$MIRRORLIST_FILE" |
        sed \
            -E \
            's/^[[:space:]]*Server[[:space:]]*=[[:space:]]*//'
    )"

    if [[ -z "$server" ]]
    then
        logger_error \
            "Unable to determine mirror server"

        return 1
    fi

    logger_info \
        "Testing mirror: ${server}"

    return 0
}

#------------------------------------------------------------
# Save state
#------------------------------------------------------------

mirrors_save()
{
    config_set \
        MIRROR_COUNTRY \
        "$MIRROR_COUNTRY"

    config_set \
        MIRROR_LATEST \
        "$MIRROR_LATEST"

    config_set \
        MIRROR_AGE \
        "$MIRROR_AGE"

    config_set \
        MIRROR_PROTOCOL \
        "$MIRROR_PROTOCOL"

    config_set \
        MIRROR_SORT \
        "$MIRROR_SORT"

    config_save
}

#------------------------------------------------------------
# Main
#------------------------------------------------------------

mirrors()
{
    local install_reflector

    logger_info \
        "Mirror configuration started"

    install_reflector="$(
        config_get INSTALL_REFLECTOR
    )"

    if [[ "$install_reflector" != "1" ]]
    then
        logger_info \
            "Reflector disabled"

        return 0
    fi

    mirrors_check_dependencies || \
        return 1

    if ! mirrors_check_network
    then
        mirrors_fallback || \
            return 1

        dialog_message \
            "Mirrors" \
            "Network unavailable; fallback mirrorlist retained"

        return 0
    fi

    if ! mirrors_check_reflector
    then
        mirrors_fallback || \
            return 1

        dialog_message \
            "Mirrors" \
            "Reflector unavailable; fallback mirrorlist retained"

        return 0
    fi

    mirrors_backup || \
        return 1

    mirrors_load_countries || \
        return 1

    mirrors_select_country || {
        logger_warn \
            "Mirror country selection cancelled"

        mirrors_fallback || \
            return 1

        return 0
    }

    mirrors_generate || {
        logger_error \
            "Reflector generation failed"

        mirrors_fallback || \
            return 1

        return 1
    }

    mirrors_test || {
        logger_error \
            "Mirrorlist test failed"

        return 1
    }

    mirrors_save || \
        return 1

    dialog_message \
        "Mirrors" \
        "Mirrorlist configured successfully"

    logger_info \
        "Mirror configuration finished"
}