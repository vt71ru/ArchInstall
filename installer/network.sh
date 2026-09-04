#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  installer/network.sh
#
#  Настройка сетевого соединения в Arch Linux Live ISO.
#
#  Ответственность:
#   • проверка сетевых утилит
#   • проверка состояния сети
#   • определение интерфейсов
#   • запуск NetworkManager при наличии
#   • проверка DNS
#   • проверка доступа к Internet
#   • сохранение результата в CONFIG
#
#  Важно:
#   Этот этап настраивает сеть Live ISO.
#   Сеть установленной системы настраивается другими модулями.
#
#============================================================

#============================================================
# Load guard
#============================================================

if [[ -n "${NETWORK_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

NETWORK_SH_LOADED=1
export NETWORK_SH_LOADED

#============================================================
# State
#============================================================

NETWORK_INTERFACE=""
NETWORK_CONNECTION=""
NETWORK_ONLINE=0
NETWORK_DNS_OK=0

#============================================================
# Logging
#============================================================

network_log_info()
{
    if declare -F log_info >/dev/null 2>&1
    then
        log_info "$@" || true
    elif declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@" || true
    else
        printf '[INFO] %s\n' "$*" >&2
    fi

    return 0
}

network_log_warn()
{
    if declare -F log_warn >/dev/null 2>&1
    then
        log_warn "$@" || true
    elif declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@" || true
    else
        printf '[WARN] %s\n' "$*" >&2
    fi

    return 0
}

network_log_error()
{
    if declare -F log_error >/dev/null 2>&1
    then
        log_error "$@" || true
    elif declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@" || true
    else
        printf '[ERROR] %s\n' "$*" >&2
    fi

    return 0
}

#============================================================
# Check dependencies
#============================================================

network_check_dependencies()
{
    local required=(
        ip
        ping
        getent
    )

    local cmd

    for cmd in "${required[@]}"
    do
        if ! command -v "$cmd" >/dev/null 2>&1
        then
            network_log_error \
                "Required network program not found: ${cmd}"
            return 1
        fi
    done

    return 0
}

#============================================================
# Check NetworkManager
#============================================================

network_check_networkmanager()
{
    if ! command -v nmcli >/dev/null 2>&1
    then
        network_log_warn \
            "nmcli is not available"

        return 1
    fi

    return 0
}

#============================================================
# Detect interface
#============================================================

network_detect_interface()
{
    local interface=""
    local state=""

    NETWORK_INTERFACE=""

    #--------------------------------------------------------
    # Prefer NetworkManager when available.
    #--------------------------------------------------------

    if command -v nmcli >/dev/null 2>&1
    then
        interface="$(
            nmcli \
                -t \
                -f DEVICE,TYPE,STATE \
                device status \
                2>/dev/null |
            awk -F: '
                $2 != "loopback" &&
                $1 != "lo" &&
                ($3 == "connected" || $3 == "connecting")
                {
                    print $1
                    exit
                }
            '
        )"
    fi

    #--------------------------------------------------------
    # Fallback to iproute2.
    #--------------------------------------------------------

    if [[ -z "$interface" ]]
    then
        while IFS= read -r interface
        do
            [[ -z "$interface" ]] && continue

            [[ "$interface" == "lo" ]] && continue

            state="$(
                ip \
                    -o \
                    link \
                    show \
                    "$interface" \
                    2>/dev/null |
                awk -F': ' '{print $2}' |
                sed -E 's/.*state ([A-Z]+).*/\1/'
            )"

            if [[ "$state" == "UP" ]]
            then
                break
            fi
        done < <(
            ip \
                -o \
                link \
                show \
                2>/dev/null |
            awk -F': ' '{print $2}' |
            cut -d'@' -f1
        )
    fi

    if [[ -z "$interface" ]]
    then
        NETWORK_INTERFACE=""
        network_log_warn \
            "No active network interface detected"
        return 1
    fi

    NETWORK_INTERFACE="$interface"

    network_log_info \
        "Network interface detected: ${NETWORK_INTERFACE}"

    return 0
}

#============================================================
# Check IP address
#============================================================

network_check_ip()
{
    local interface="${NETWORK_INTERFACE:-}"

    if [[ -z "$interface" ]]
    then
        network_log_error \
            "Network interface is not selected"
        return 1
    fi

    if ip \
        -4 \
        addr \
        show \
        dev "$interface" |
        grep -q \
            'inet '
    then
        network_log_info \
            "IPv4 address detected on ${interface}"
        return 0
    fi

    if ip \
        -6 \
        addr \
        show \
        dev "$interface" |
        grep -q \
            'inet6 '
    then
        network_log_info \
            "IPv6 address detected on ${interface}"
        return 0
    fi

    network_log_warn \
        "No IP address detected on ${interface}"

    return 1
}

#============================================================
# Check default route
#============================================================

network_check_route()
{
    if ip \
        route \
        show \
        default |
        grep -q \
            '^default'
    then
        network_log_info \
            "Default network route detected"
        return 0
    fi

    network_log_warn \
        "Default network route is missing"

    return 1
}

#============================================================
# Check DNS
#============================================================

network_check_dns()
{
    local host="${1:-archlinux.org}"

    NETWORK_DNS_OK=0

    if getent \
        hosts \
        "$host" \
        >/dev/null 2>&1
    then
        NETWORK_DNS_OK=1

        network_log_info \
            "DNS resolution works: ${host}"

        return 0
    fi

    network_log_warn \
        "DNS resolution failed: ${host}"

    return 1
}

#============================================================
# Check Internet
#============================================================

network_check_internet()
{
    local host="${1:-archlinux.org}"

    if ping \
        -c 1 \
        -W 3 \
        "$host" \
        >/dev/null 2>&1
    then
        NETWORK_ONLINE=1

        network_log_info \
            "Internet connectivity verified: ${host}"

        return 0
    fi

    NETWORK_ONLINE=0

    network_log_warn \
        "Internet connectivity test failed: ${host}"

    return 1
}

#============================================================
# Start NetworkManager
#============================================================

network_start_networkmanager()
{
    #--------------------------------------------------------
    # NetworkManager may not be installed in minimal
    # environments. Do not treat that as fatal.
    #--------------------------------------------------------

    if ! command -v nmcli >/dev/null 2>&1
    then
        network_log_warn \
            "NetworkManager is unavailable"

        return 1
    fi

    if ! command -v systemctl >/dev/null 2>&1
    then
        network_log_warn \
            "systemctl is unavailable"

        return 1
    fi

    if systemctl \
        is-active \
        --quiet \
        NetworkManager.service
    then
        network_log_info \
            "NetworkManager is already active"

        return 0
    fi

    network_log_info \
        "Starting NetworkManager"

    if systemctl \
        start \
        NetworkManager.service
    then
        network_log_info \
            "NetworkManager started successfully"
        return 0
    fi

    network_log_warn \
        "Failed to start NetworkManager"

    return 1
}

#============================================================
# Refresh connections
#============================================================

network_refresh_connections()
{
    if ! command -v nmcli >/dev/null 2>&1
    then
        return 1
    fi

    nmcli \
        device \
        status \
        >/dev/null 2>&1 \
        || true

    return 0
}

#============================================================
# Try automatic connection
#============================================================

network_autoconnect()
{
    local interface="${NETWORK_INTERFACE:-}"

    if [[ -z "$interface" ]]
    then
        return 1
    fi

    if ! command -v nmcli >/dev/null 2>&1
    then
        return 1
    fi

    #--------------------------------------------------------
    # Already connected.
    #--------------------------------------------------------

    if nmcli \
        -t \
        -f DEVICE,STATE \
        device \
        status \
        2>/dev/null |
        grep -Eq \
            "^${interface}:connected"
    then
        network_log_info \
            "Interface already connected: ${interface}"
        return 0
    fi

    network_log_info \
        "Attempting automatic connection: ${interface}"

    if nmcli \
        device \
        connect \
        "$interface" \
        >/dev/null 2>&1
    then
        network_log_info \
            "Automatic connection succeeded: ${interface}"
        return 0
    fi

    network_log_warn \
        "Automatic connection failed: ${interface}"

    return 1
}

#============================================================
# Save network state
#============================================================

network_save()
{
    if ! declare -F config_set >/dev/null 2>&1
    then
        network_log_warn \
            "config_set() is not available"
        return 0
    fi

    config_set \
        NETWORK_INTERFACE \
        "${NETWORK_INTERFACE:-}" || return 1

    config_set \
        NETWORK_CONNECTION \
        "${NETWORK_CONNECTION:-}" || return 1

    config_set \
        NETWORK_ONLINE \
        "${NETWORK_ONLINE}" || return 1

    config_set \
        NETWORK_DNS_OK \
        "${NETWORK_DNS_OK}" || return 1

    if declare -F config_save >/dev/null 2>&1
    then
        if ! config_save
        then
            network_log_error \
                "Failed to save network configuration"
            return 1
        fi
    fi

    return 0
}

#============================================================
# Draw network status
#============================================================

network_draw()
{
    local interface="${NETWORK_INTERFACE:-none}"
    local online="NO"
    local dns="NO"
    local row=5

    if (( NETWORK_ONLINE == 1 ))
    then
        online="YES"
    fi

    if (( NETWORK_DNS_OK == 1 ))
    then
        dns="YES"
    fi

    #--------------------------------------------------------
    # Clear
    #--------------------------------------------------------

    if declare -F tui_clear >/dev/null 2>&1
    then
        tui_clear || return 1
    else
        printf '\033[2J\033[H'
    fi

    #--------------------------------------------------------
    # Title
    #--------------------------------------------------------

    if declare -F titlebar_draw >/dev/null 2>&1
    then
        titlebar_draw \
            "Network configuration" || return 1
    else
        printf '\nNetwork configuration\n'
    fi

    #--------------------------------------------------------
    # Information
    #--------------------------------------------------------

    if declare -F tui_move >/dev/null 2>&1
    then
        tui_move "$row" 5 || return 1

        tui_print \
            "Interface : ${interface}" || return 1

        row=$((row + 2))

        tui_move "$row" 5 || return 1

        tui_print \
            "Internet  : ${online}" || return 1

        row=$((row + 1))

        tui_move "$row" 5 || return 1

        tui_print \
            "DNS       : ${dns}" || return 1

        row=$((row + 2))

        if (( NETWORK_ONLINE == 1 ))
        then
            color_info \
                "Network connection is available." ||
                return 1
        else
            color_error \
                "Network connection is unavailable." ||
                true
        fi
    else
        printf '\n'
        printf 'Interface : %s\n' "$interface"
        printf 'Internet  : %s\n' "$online"
        printf 'DNS       : %s\n' "$dns"
    fi

    #--------------------------------------------------------
    # Status bar
    #--------------------------------------------------------

    if declare -F statusbar_draw >/dev/null 2>&1
    then
        statusbar_draw \
            "Enter Continue   Esc Back" ||
            return 1
    fi

    if declare -F screen_refresh >/dev/null 2>&1
    then
        screen_refresh || return 1
    elif declare -F tui_flush >/dev/null 2>&1
    then
        tui_flush || return 1
    fi

    return 0
}

#============================================================
# Wait for user
#============================================================

network_wait()
{
    local event=""

    while true
    do
        TUI_EVENT=""

        if ! event_read
        then
            network_log_error \
                "event_read() failed"
            return 1
        fi

        event="${TUI_EVENT:-}"

        case "$event" in

            "$EVENT_SELECT")
                return 0
                ;;

            "$EVENT_BACK")
                return 1
                ;;

            "$EVENT_NONE")
                ;;

            *)
                ;;
        esac
    done
}

#============================================================
# Main network stage
#============================================================

network()
{
    network_log_info \
        "Network configuration started"

    #--------------------------------------------------------
    # Dependencies
    #--------------------------------------------------------

    network_check_dependencies || return 1

    #--------------------------------------------------------
    # Start NetworkManager when possible.
    #--------------------------------------------------------

    network_start_networkmanager || true

    #--------------------------------------------------------
    # Refresh state
    #--------------------------------------------------------

    network_refresh_connections || true

    #--------------------------------------------------------
    # Detect interface
    #--------------------------------------------------------

    if ! network_detect_interface
    then
        network_draw || true
        network_log_error \
            "No active network interface detected"
        network_wait || true
        return 1
    fi

    #--------------------------------------------------------
    # Try automatic connection.
    #--------------------------------------------------------

    network_autoconnect || true

    #--------------------------------------------------------
    # Re-detect after connection attempt.
    #--------------------------------------------------------

    network_detect_interface || true

    #--------------------------------------------------------
    # Check IP.
    #--------------------------------------------------------

    if ! network_check_ip
    then
        network_log_warn \
            "Interface has no configured IP address"
    fi

    #--------------------------------------------------------
    # Check route.
    #--------------------------------------------------------

    if ! network_check_route
    then
        network_log_warn \
            "Default route is not available"
    fi

    #--------------------------------------------------------
    # DNS.
    #--------------------------------------------------------

    if network_check_dns
    then
        NETWORK_DNS_OK=1
    else
        NETWORK_DNS_OK=0
    fi

    #--------------------------------------------------------
    # Internet.
    #--------------------------------------------------------

    if network_check_internet
    then
        NETWORK_ONLINE=1
    else
        NETWORK_ONLINE=0
    fi

    #--------------------------------------------------------
    # Set connection description.
    #--------------------------------------------------------

    if (( NETWORK_ONLINE == 1 ))
    then
        NETWORK_CONNECTION="online"
    elif (( NETWORK_DNS_OK == 1 ))
    then
        NETWORK_CONNECTION="dns-only"
    else
        NETWORK_CONNECTION="offline"
    fi

    #--------------------------------------------------------
    # Save state.
    #--------------------------------------------------------

    network_save || return 1

    #--------------------------------------------------------
    # Display result.
    #--------------------------------------------------------

    network_draw || return 1

    #--------------------------------------------------------
    # Internet is required for the subsequent mirror and
    # package installation stages.
    #--------------------------------------------------------

    if (( NETWORK_ONLINE != 1 ))
    then
        if declare -F dialog_error >/dev/null 2>&1
        then
            dialog_error \
                "Network unavailable" \
                "Internet connectivity could not be established." \
                || true
        fi

        network_log_error \
            "Network configuration failed: Internet unavailable"

        network_wait || true

        return 1
    fi

    if declare -F dialog_message >/dev/null 2>&1
    then
        dialog_message \
            "Network" \
            "Internet connection is available." \
            || true
    fi

    network_log_info \
        "Network configuration completed successfully"

    return 0
}

#============================================================
# Direct execution
#============================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
    network
    exit $?
fi

