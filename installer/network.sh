#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  network.sh
#
#  Настройка сети в installer Live environment.
#
#  Ответственность:
#   • Обнаружение сетевых интерфейсов
#   • Выбор интерфейса
#   • Проверка link state
#   • Попытка активации интерфейса через NetworkManager
#   • Проверка IP
#   • Проверка DNS
#   • Проверка доступа в Интернет
#   • Сохранение NETWORK_INTERFACE
#
#  Не выполняет:
#   • Установку NetworkManager
#   • Постоянную настройку target system
#   • Настройку firewall
#============================================================

[[ -n "${NETWORK_SH_LOADED:-}" ]] && return

readonly NETWORK_SH_LOADED=1

#------------------------------------------------------------
# State
#------------------------------------------------------------

declare -a NETWORK_INTERFACES=()

NETWORK_SELECTED=0

#------------------------------------------------------------
# Dependency check
#------------------------------------------------------------

network_check_dependencies()
{
    local required=(
        ip
        grep
        ping
    )

    local cmd

    for cmd in "${required[@]}"
    do
        if ! command -v "$cmd" >/dev/null 2>&1
        then
            dialog_error \
                "Required network program not found: ${cmd}"

            return 1
        fi
    done
}

#------------------------------------------------------------
# Load interfaces
#------------------------------------------------------------

network_load_interfaces()
{
    local iface

    NETWORK_INTERFACES=()
    NETWORK_SELECTED=0

    while IFS= read -r iface
    do
        [[ "$iface" == "lo" ]] && \
            continue

        [[ -n "$iface" ]] || \
            continue

        NETWORK_INTERFACES+=(
            "$iface"
        )
    done < <(
        find \
            /sys/class/net \
            -mindepth 1 \
            -maxdepth 1 \
            -printf '%f\n' |
        sort
    )

    if (( ${#NETWORK_INTERFACES[@]} == 0 ))
    then
        dialog_error \
            "No network interfaces found"

        return 1
    fi

    logger_info \
        "Network interfaces found: ${NETWORK_INTERFACES[*]}"
}

#------------------------------------------------------------
# Interface exists
#------------------------------------------------------------

network_check_interface()
{
    local iface="$1"

    if [[ ! -e "/sys/class/net/${iface}" ]]
    then
        logger_error \
            "Network interface does not exist: ${iface}"

        return 1
    fi
}

#------------------------------------------------------------
# Interface state
#------------------------------------------------------------

network_status()
{
    local iface="$1"

    if ip \
        link \
        show \
        "$iface" |
        grep -q 'state UP'
    then
        printf 'UP'
    else
        printf 'DOWN'
    fi
}

#------------------------------------------------------------
# Carrier state
#------------------------------------------------------------

network_carrier()
{
    local iface="$1"
    local carrier_file

    carrier_file="/sys/class/net/${iface}/carrier"

    if [[ -f "$carrier_file" ]]
    then
        if [[ "$(cat "$carrier_file")" == "1" ]]
        then
            printf 'LINK'
            return 0
        fi

        printf 'NO-LINK'
        return 0
    fi

    printf 'UNKNOWN'
}

#------------------------------------------------------------
# IP address
#------------------------------------------------------------

network_ip()
{
    local iface="$1"

    ip \
        -4 \
        -o \
        addr \
        show \
        dev "$iface" |
    awk '{print $4}' |
    head -n 1
}

#------------------------------------------------------------
# Draw
#------------------------------------------------------------

network_draw()
{
    local row=5
    local index
    local iface
    local status
    local carrier
    local address

    tui_clear

    titlebar_draw \
        "Network setup"

    draw_panel \
        "Select interface" \
        3 \
        5 \
        18 \
        72

    for index in "${!NETWORK_INTERFACES[@]}"
    do
        iface="${NETWORK_INTERFACES[index]}"

        status="$(
            network_status \
                "$iface"
        )"

        carrier="$(
            network_carrier \
                "$iface"
        )"

        address="$(
            network_ip \
                "$iface"
        )"

        cursor_move \
            "$row" \
            8

        if (( index == NETWORK_SELECTED ))
        then
            printf '> '
        else
            printf '  '
        fi

        printf \
            '%-12s %-6s %-8s %s' \
            "$iface" \
            "$status" \
            "$carrier" \
            "${address:-no-ip}"

        ((row += 1))
    done

    statusbar_draw \
        "↑↓ Select   Enter Apply   F2 Test   Esc Back"

    screen_refresh
}

#------------------------------------------------------------
# Navigation
#------------------------------------------------------------

network_previous()
{
    if (( NETWORK_SELECTED > 0 ))
    then
        ((NETWORK_SELECTED -= 1))
    else
        NETWORK_SELECTED=$(( ${#NETWORK_INTERFACES[@]} - 1 ))
    fi
}

network_next()
{
    if (( NETWORK_SELECTED < ${#NETWORK_INTERFACES[@]} - 1 ))
    then
        ((NETWORK_SELECTED += 1))
    else
        NETWORK_SELECTED=0
    fi
}

#------------------------------------------------------------
# Bring interface up
#------------------------------------------------------------

network_link_up()
{
    local iface="$1"

    network_check_interface \
        "$iface" || \
        return 1

    logger_info \
        "Bringing interface up: ${iface}"

    ip \
        link \
        set \
        dev "$iface" \
        up \
        || {
            logger_error \
                "Failed to bring interface up: ${iface}"

            return 1
        }
}

#------------------------------------------------------------
# NetworkManager status
#------------------------------------------------------------

network_manager_available()
{
    command -v nmcli >/dev/null 2>&1
}

#------------------------------------------------------------
# Connect through NetworkManager
#------------------------------------------------------------

network_nm_connect()
{
    local iface="$1"

    if ! network_manager_available
    then
        return 0
    fi

    logger_info \
        "Attempting NetworkManager connection: ${iface}"

    nmcli \
        device \
        connect \
        "$iface" \
        >/dev/null 2>&1 \
        || {
            logger_warn \
                "NetworkManager could not activate ${iface}"

            return 1
        }

    return 0
}

#------------------------------------------------------------
# Check IP
#------------------------------------------------------------

network_check_ip()
{
    local iface="$1"
    local address

    address="$(
        network_ip \
            "$iface"
    )"

    if [[ -z "$address" ]]
    then
        logger_error \
            "No IPv4 address assigned to ${iface}"

        return 1
    fi

    logger_info \
        "IPv4 address on ${iface}: ${address}"
}

#------------------------------------------------------------
# Check route
#------------------------------------------------------------

network_check_route()
{
    if ! ip \
        route \
        get \
        1.1.1.1 \
        >/dev/null 2>&1
    then
        logger_error \
            "Default route is unavailable"

        return 1
    fi

    logger_info \
        "Default route is available"
}

#------------------------------------------------------------
# Check DNS
#------------------------------------------------------------

network_check_dns()
{
    if getent \
        hosts \
        archlinux.org \
        >/dev/null 2>&1
    then
        logger_info \
            "DNS resolution is working"

        return 0
    fi

    logger_error \
        "DNS resolution failed"

    return 1
}

#------------------------------------------------------------
# Check Internet
#------------------------------------------------------------

network_check_internet()
{
    logger_info \
        "Checking Internet connectivity"

    network_check_route || \
        return 1

    network_check_dns || \
        return 1

    if ping \
        -c 1 \
        -W 3 \
        archlinux.org \
        >/dev/null 2>&1
    then
        logger_info \
            "Internet connection available"

        dialog_message \
            "Network" \
            "Internet connection available"

        return 0
    fi

    logger_error \
        "Internet connectivity test failed"

    dialog_error \
        "No Internet connection"

    return 1
}

#------------------------------------------------------------
# Apply
#------------------------------------------------------------

network_apply()
{
    local iface

    iface="${NETWORK_INTERFACES[NETWORK_SELECTED]}"

    network_check_interface \
        "$iface" || \
        return 1

    network_link_up \
        "$iface" || \
        return 1

    if network_manager_available
    then
        network_nm_connect \
            "$iface" || true
    fi

    config_set \
        NETWORK_INTERFACE \
        "$iface"

    config_set \
        NETWORK_ENABLED \
        "1"

    config_save

    logger_info \
        "Selected network interface: ${iface}"

    if network_check_ip "$iface"
    then
        dialog_message \
            "Network" \
            "Selected interface: ${iface}"
    else
        dialog_message \
            "Network" \
            "Interface selected: ${iface}\nNo IP address yet"
    fi

    return 0
}

#------------------------------------------------------------
# Test selected interface
#------------------------------------------------------------

network_test()
{
    local iface

    iface="$(config_get NETWORK_INTERFACE)"

    if [[ -z "$iface" ]]
    then
        dialog_error \
            "Network interface is not selected"

        return 1
    fi

    network_check_interface \
        "$iface" || \
        return 1

    network_link_up \
        "$iface" || \
        return 1

    network_check_ip \
        "$iface" || \
        return 1

    network_check_internet || \
        return 1
}

#------------------------------------------------------------
# Restore selection
#------------------------------------------------------------

network_restore_selection()
{
    local configured
    local index

    configured="$(
        config_get NETWORK_INTERFACE \
            2>/dev/null \
            || true
    )"

    [[ -n "$configured" ]] || \
        return 0

    for index in "${!NETWORK_INTERFACES[@]}"
    do
        if [[ "${NETWORK_INTERFACES[index]}" == "$configured" ]]
        then
            NETWORK_SELECTED="$index"
            return 0
        fi
    done
}

#------------------------------------------------------------
# Main
#------------------------------------------------------------

network()
{
    local event

    logger_info \
        "Network configuration started"

    network_check_dependencies || \
        return 1

    network_load_interfaces || \
        return 1

    network_restore_selection

    while true
    do
        network_draw

        event="$(
            event_read
        )"

        case "$event" in
            "$EVENT_UP")
                network_previous
                ;;
            "$EVENT_DOWN")
                network_next
                ;;
            "$EVENT_SELECT")
                network_apply || \
                    continue
                ;;
            "$EVENT_HELP")
                network_test || \
                    true
                ;;
            "$EVENT_BACK")
                break
                ;;
        esac
    done

    logger_info \
        "Network configuration finished"
}