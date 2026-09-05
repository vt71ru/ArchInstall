#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# installer/services.sh
#
# Настройка системных служб установленной системы.
#
# Ответственность:
#   • проверка /mnt
#   • загрузка конфигурации
#   • проверка hostname / SSH
#   • настройка /etc/hostname
#   • настройка /etc/hosts
#   • выбор сетевой службы
#   • включение SSH
#   • установка graphical.target
#   • проверка результата
#   • сохранение информации о настройке
#
# ВАЖНО:
#   Службы внутри /mnt НЕ запускаются.
#   Выполняется только подготовка установленной системы.
#============================================================

#============================================================
# Include guard
#============================================================

if declare -F services_configure >/dev/null 2>&1
then
    return 0 2>/dev/null || exit 0
fi

ARCH_INSTALLER_SERVICES_SH_LOADED=1

#============================================================
# Constants
#============================================================

readonly SERVICES_TARGET="${SERVICES_TARGET:-/mnt}"
readonly SERVICES_CONFIG_FILE="${SERVICES_CONFIG_FILE:-${SERVICES_TARGET}/etc/arch-installer-services.conf}"

#============================================================
# Runtime state
#============================================================

SERVICES_HOSTNAME=""
SERVICES_ENABLE_SSH=1
SERVICES_NETWORK_SERVICE=""
SERVICES_GRAPHICAL_TARGET="graphical.target"

#============================================================
# Logging compatibility
#============================================================

services_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@"
        return $?
    fi

    printf '[INFO] %s\n' "$*" >&2
}

services_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@"
        return $?
    fi

    printf '[WARN] %s\n' "$*" >&2
}

services_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@"
        return $?
    fi

    printf '[ERROR] %s\n' "$*" >&2
}

#============================================================
# Target checks
#============================================================

services_check_target()
{
    services_log_info \
        "Checking target system: ${SERVICES_TARGET}"

    if [[ ! -d "$SERVICES_TARGET" ]]
    then
        services_log_error \
            "Target directory does not exist: ${SERVICES_TARGET}"

        return 1
    fi

    if [[ ! -d "${SERVICES_TARGET}/etc" ]]
    then
        services_log_error \
            "Target /etc does not exist: ${SERVICES_TARGET}/etc"

        return 1
    fi

    if [[ ! -d "${SERVICES_TARGET}/usr" ]]
    then
        services_log_error \
            "Target /usr does not exist: ${SERVICES_TARGET}/usr"

        return 1
    fi

    return 0
}

#============================================================
# Configuration
#============================================================

services_load_config()
{
    services_log_info \
        "Loading services configuration"

    #--------------------------------------------------------
    # Hostname
    #--------------------------------------------------------

    SERVICES_HOSTNAME=""

    if declare -p CONFIG >/dev/null 2>&1
    then
        if [[ -n "${CONFIG[HOSTNAME]:-}" ]]
        then
            SERVICES_HOSTNAME="${CONFIG[HOSTNAME]}"
        elif [[ -n "${CONFIG[hostname]:-}" ]]
        then
            SERVICES_HOSTNAME="${CONFIG[hostname]}"
        fi
    fi

    if [[ -z "$SERVICES_HOSTNAME" ]]
    then
        if [[ -n "${HOSTNAME:-}" ]]
        then
            SERVICES_HOSTNAME="$HOSTNAME"
        fi
    fi

    if [[ -z "$SERVICES_HOSTNAME" ]]
    then
        SERVICES_HOSTNAME="archlinux"
    fi

    #--------------------------------------------------------
    # SSH
    #--------------------------------------------------------

    SERVICES_ENABLE_SSH=1

    if declare -p CONFIG >/dev/null 2>&1
    then
        if [[ "${CONFIG[SSH_ENABLED]:-1}" == "0" ]]
        then
            SERVICES_ENABLE_SSH=0
        elif [[ "${CONFIG[ssh_enabled]:-1}" == "0" ]]
        then
            SERVICES_ENABLE_SSH=0
        fi
    fi

    #--------------------------------------------------------
    # Network service
    #--------------------------------------------------------

    SERVICES_NETWORK_SERVICE=""

    if declare -p CONFIG >/dev/null 2>&1
    then
        if [[ -n "${CONFIG[NETWORK_SERVICE]:-}" ]]
        then
            SERVICES_NETWORK_SERVICE="${CONFIG[NETWORK_SERVICE]}"
        elif [[ -n "${CONFIG[network_service]:-}" ]]
        then
            SERVICES_NETWORK_SERVICE="${CONFIG[network_service]}"
        fi
    fi

    services_log_info \
        "Hostname: ${SERVICES_HOSTNAME}"

    services_log_info \
        "SSH enabled: ${SERVICES_ENABLE_SSH}"

    if [[ -n "$SERVICES_NETWORK_SERVICE" ]]
    then
        services_log_info \
            "Requested network service: ${SERVICES_NETWORK_SERVICE}"
    fi

    return 0
}

#============================================================
# Validation
#============================================================

services_validate_hostname()
{
    services_log_info \
        "Validating hostname"

    if [[ -z "$SERVICES_HOSTNAME" ]]
    then
        services_log_error \
            "Hostname is empty"

        return 1
    fi

    if ((${#SERVICES_HOSTNAME} > 253))
    then
        services_log_error \
            "Hostname is too long"

        return 1
    fi

    if [[ "$SERVICES_HOSTNAME" == .* ||
          "$SERVICES_HOSTNAME" == *. ||
          "$SERVICES_HOSTNAME" == *..* ]]
    then
        services_log_error \
            "Invalid hostname: ${SERVICES_HOSTNAME}"

        return 1
    fi

    if [[ ! "$SERVICES_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]
    then
        services_log_error \
            "Invalid hostname: ${SERVICES_HOSTNAME}"

        return 1
    fi

    if [[ "$SERVICES_HOSTNAME" =~ (^|[-.])[.-]($|[-.]) ]]
    then
        services_log_error \
            "Invalid hostname: ${SERVICES_HOSTNAME}"

        return 1
    fi

    return 0
}

services_validate_ssh()
{
    services_log_info \
        "Validating SSH configuration"

    if [[ "$SERVICES_ENABLE_SSH" != "1" ]]
    then
        services_log_info \
            "SSH configuration disabled"

        return 0
    fi

    if [[ ! -x "${SERVICES_TARGET}/usr/bin/sshd" ]]
    then
        services_log_warn \
            "sshd is not installed in target system"

        SERVICES_ENABLE_SSH=0

        return 0
    fi

    if [[ ! -f "${SERVICES_TARGET}/etc/ssh/sshd_config" ]]
    then
        services_log_info \
            "Creating default sshd_config"

        mkdir -p \
            "${SERVICES_TARGET}/etc/ssh" || \
            return 1

        cat > "${SERVICES_TARGET}/etc/ssh/sshd_config" <<'EOF'
# Arch Installer generated SSH configuration

Include /etc/ssh/sshd_config.d/*.conf

Port 22
AddressFamily any

PermitRootLogin prohibit-password
PasswordAuthentication yes
KbdInteractiveAuthentication yes
UsePAM yes

X11Forwarding yes
PrintMotd no
Subsystem sftp /usr/lib/ssh/sftp-server
EOF
    fi

    return 0
}

#============================================================
# Hostname
#============================================================

services_configure_hostname()
{
    local hostname_file="${SERVICES_TARGET}/etc/hostname"

    services_log_info \
        "Configuring hostname"

    printf '%s\n' \
        "$SERVICES_HOSTNAME" \
        > "$hostname_file" || \
        return 1

    chmod 0644 "$hostname_file" 2>/dev/null || true

    return 0
}

#============================================================
# Hosts
#============================================================

services_configure_hosts()
{
    local hosts_file="${SERVICES_TARGET}/etc/hosts"
    local current_hosts=""

    services_log_info \
        "Configuring /etc/hosts"

    if [[ -f "$hosts_file" ]]
    then
        current_hosts="$(cat "$hosts_file")" || \
            return 1
    fi

    #--------------------------------------------------------
    # Remove previously generated local hostname entries
    #--------------------------------------------------------

    if [[ -n "$current_hosts" ]]
    then
        current_hosts="$(
            printf '%s\n' "$current_hosts" |
                grep -v \
                    -E \
                    "^[[:space:]]*127\.0\.1\.1[[:space:]]+${SERVICES_HOSTNAME}([[:space:]]|$)" \
                || true
        )"
    fi

    #--------------------------------------------------------
    # Ensure localhost entries
    #--------------------------------------------------------

    if ! printf '%s\n' "$current_hosts" |
        grep -qE '^[[:space:]]*127\.0\.0\.1[[:space:]]+localhost([[:space:]]|$)'
    then
        current_hosts+=$'\n127.0.0.1\tlocalhost'
    fi

    if ! printf '%s\n' "$current_hosts" |
        grep -qE '^[[:space:]]*::1[[:space:]]+localhost([[:space:]]|$)'
    then
        current_hosts+=$'\n::1\tlocalhost'
    fi

    #--------------------------------------------------------
    # Local hostname
    #--------------------------------------------------------

    if ! printf '%s\n' "$current_hosts" |
        grep -qE \
            "^[[:space:]]*127\.0\.1\.1[[:space:]]+${SERVICES_HOSTNAME}([[:space:]]|$)"
    then
        current_hosts+=$'\n127.0.1.1\t'"$SERVICES_HOSTNAME"
    fi

    #--------------------------------------------------------
    # Write
    #--------------------------------------------------------

    printf '%s\n' "$current_hosts" |
        sed '/^[[:space:]]*$/d' |
        awk '!seen[$0]++' \
        > "$hosts_file" || \
        return 1

    chmod 0644 "$hosts_file" 2>/dev/null || true

    return 0
}

#============================================================
# Network service
#============================================================

services_network()
{
    local network_manager=""

    services_log_info \
        "Configuring network service"

    #--------------------------------------------------------
    # Explicit configuration
    #--------------------------------------------------------

    case "$SERVICES_NETWORK_SERVICE" in
        NetworkManager|networkmanager|network-manager)
            network_manager="NetworkManager"
            ;;

        systemd-networkd|systemd_networkd|networkd)
            network_manager="systemd-networkd"
            ;;

        "")
            ;;

        *)
            services_log_warn \
                "Unknown network service: ${SERVICES_NETWORK_SERVICE}"
            ;;
    esac

    #--------------------------------------------------------
    # Automatic detection
    #--------------------------------------------------------

    if [[ -z "$network_manager" ]]
    then
        if [[ -x "${SERVICES_TARGET}/usr/bin/NetworkManager" ]]
        then
            network_manager="NetworkManager"
        elif [[ -x "${SERVICES_TARGET}/usr/lib/systemd/systemd-networkd" ]]
        then
            network_manager="systemd-networkd"
        fi
    fi

    #--------------------------------------------------------
    # NetworkManager
    #--------------------------------------------------------

    if [[ "$network_manager" == "NetworkManager" ]]
    then
        if [[ -e "${SERVICES_TARGET}/usr/lib/systemd/system/NetworkManager.service" ]]
        then
            mkdir -p \
                "${SERVICES_TARGET}/etc/systemd/system/multi-user.target.wants" \
                || return 1

            ln -sf \
                /usr/lib/systemd/system/NetworkManager.service \
                "${SERVICES_TARGET}/etc/systemd/system/multi-user.target.wants/NetworkManager.service" \
                || return 1

            SERVICES_NETWORK_SERVICE="NetworkManager"

            services_log_info \
                "NetworkManager enabled"

            return 0
        fi

        services_log_warn \
            "NetworkManager binary exists but service file was not found"
    fi

    #--------------------------------------------------------
    # systemd-networkd
    #--------------------------------------------------------

    if [[ "$network_manager" == "systemd-networkd" ]]
    then
        if [[ -e "${SERVICES_TARGET}/usr/lib/systemd/system/systemd-networkd.service" ]]
        then
            mkdir -p \
                "${SERVICES_TARGET}/etc/systemd/system/multi-user.target.wants" \
                || return 1

            ln -sf \
                /usr/lib/systemd/system/systemd-networkd.service \
                "${SERVICES_TARGET}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" \
                || return 1

            SERVICES_NETWORK_SERVICE="systemd-networkd"

            services_log_info \
                "systemd-networkd enabled"

            return 0
        fi
    fi

    #--------------------------------------------------------
    # No network manager
    #--------------------------------------------------------

    services_log_warn \
        "No supported network service found"

    SERVICES_NETWORK_SERVICE=""

    return 0
}

#============================================================
# SSH
#============================================================

services_ssh()
{
    local ssh_wants_dir=""

    services_log_info \
        "Configuring SSH service"

    if [[ "$SERVICES_ENABLE_SSH" != "1" ]]
    then
        services_log_info \
            "SSH service configuration skipped"

        return 0
    fi

    if [[ ! -f "${SERVICES_TARGET}/usr/lib/systemd/system/sshd.service" ]]
    then
        services_log_warn \
            "sshd.service not found"

        SERVICES_ENABLE_SSH=0

        return 0
    fi

    ssh_wants_dir="${SERVICES_TARGET}/etc/systemd/system/multi-user.target.wants"

    mkdir -p "$ssh_wants_dir" || \
        return 1

    ln -sf \
        /usr/lib/systemd/system/sshd.service \
        "${ssh_wants_dir}/sshd.service" || \
        return 1

    services_log_info \
        "SSH service enabled"

    return 0
}

#============================================================
# Graphical target
#============================================================

services_graphical_target()
{
    local target_dir=""
    local target_link=""

    services_log_info \
        "Configuring systemd graphical target"

    target_dir="${SERVICES_TARGET}/etc/systemd/system"
    target_link="${target_dir}/default.target"

    mkdir -p "$target_dir" || \
        return 1

    #--------------------------------------------------------
    # Remove old default target
    #--------------------------------------------------------

    if [[ -e "$target_link" ||
          -L "$target_link" ]]
    then
        rm -f "$target_link" || \
            return 1
    fi

    #--------------------------------------------------------
    # Select graphical target
    #--------------------------------------------------------

    ln -sf \
        "/usr/lib/systemd/system/${SERVICES_GRAPHICAL_TARGET}" \
        "$target_link" || \
        return 1

    services_log_info \
        "Default target set to ${SERVICES_GRAPHICAL_TARGET}"

    return 0
}

#============================================================
# Verification
#============================================================

services_check_hostname()
{
    local hostname_file="${SERVICES_TARGET}/etc/hostname"
    local actual_hostname=""

    services_log_info \
        "Checking hostname configuration"

    if [[ ! -f "$hostname_file" ]]
    then
        services_log_error \
            "Hostname file missing"

        return 1
    fi

    actual_hostname="$(tr -d '\r\n' < "$hostname_file")" || \
        return 1

    if [[ "$actual_hostname" != "$SERVICES_HOSTNAME" ]]
    then
        services_log_error \
            "Hostname mismatch"

        services_log_error \
            "Expected: ${SERVICES_HOSTNAME}"

        services_log_error \
            "Actual:   ${actual_hostname}"

        return 1
    fi

    return 0
}

services_check_hosts()
{
    local hosts_file="${SERVICES_TARGET}/etc/hosts"

    services_log_info \
        "Checking /etc/hosts"

    if [[ ! -f "$hosts_file" ]]
    then
        services_log_error \
            "/etc/hosts does not exist"

        return 1
    fi

    if ! grep -qE \
        '^[[:space:]]*127\.0\.0\.1[[:space:]]+localhost([[:space:]]|$)' \
        "$hosts_file"
    then
        services_log_error \
            "127.0.0.1 localhost entry missing"

        return 1
    fi

    if ! grep -qE \
        '^[[:space:]]*::1[[:space:]]+localhost([[:space:]]|$)' \
        "$hosts_file"
    then
        services_log_error \
            "::1 localhost entry missing"

        return 1
    fi

    if ! grep -qE \
        "^[[:space:]]*127\.0\.1\.1[[:space:]]+${SERVICES_HOSTNAME}([[:space:]]|$)" \
        "$hosts_file"
    then
        services_log_error \
            "127.0.1.1 hostname entry missing"

        return 1
    fi

    return 0
}

services_check_network()
{
    local manager=""

    services_log_info \
        "Checking network service"

    #--------------------------------------------------------
    # No service selected is allowed.
    #--------------------------------------------------------

    if [[ -z "$SERVICES_NETWORK_SERVICE" ]]
    then
        services_log_warn \
            "No network service configured"

        return 0
    fi

    manager="$SERVICES_NETWORK_SERVICE"

    case "$manager" in
        NetworkManager)
            if [[ ! -e \
                "${SERVICES_TARGET}/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ]]
            then
                services_log_error \
                    "NetworkManager is not enabled"

                return 1
            fi
            ;;

        systemd-networkd)
            if [[ ! -e \
                "${SERVICES_TARGET}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" ]]
            then
                services_log_error \
                    "systemd-networkd is not enabled"

                return 1
            fi
            ;;

        *)
            services_log_warn \
                "Network verification skipped for: ${manager}"
            ;;
    esac

    return 0
}

services_check_ssh()
{
    services_log_info \
        "Checking SSH service"

    if [[ "$SERVICES_ENABLE_SSH" != "1" ]]
    then
        services_log_info \
            "SSH disabled"

        return 0
    fi

    if [[ ! -e \
        "${SERVICES_TARGET}/etc/systemd/system/multi-user.target.wants/sshd.service" ]]
    then
        services_log_error \
            "sshd.service is not enabled"

        return 1
    fi

    return 0
}

services_check_target_mode()
{
    local target_link="${SERVICES_TARGET}/etc/systemd/system/default.target"
    local expected="/usr/lib/systemd/system/${SERVICES_GRAPHICAL_TARGET}"
    local actual=""

    services_log_info \
        "Checking systemd default target"

    if [[ ! -L "$target_link" ]]
    then
        services_log_error \
            "default.target is not a symbolic link"

        return 1
    fi

    actual="$(readlink "$target_link")" || \
        return 1

    if [[ "$actual" != "$expected" ]]
    then
        services_log_error \
            "Default target mismatch"

        services_log_error \
            "Expected: ${expected}"

        services_log_error \
            "Actual:   ${actual}"

        return 1
    fi

    return 0
}

#============================================================
# Save configuration
#============================================================

services_save()
{
    local config_dir=""

    services_log_info \
        "Saving services configuration"

    config_dir="$(dirname "$SERVICES_CONFIG_FILE")"

    mkdir -p "$config_dir" || \
        return 1

    cat > "$SERVICES_CONFIG_FILE" <<EOF
#============================================================
# Arch Installer
# Services configuration
#============================================================

HOSTNAME='${SERVICES_HOSTNAME}'
SSH_ENABLED='${SERVICES_ENABLE_SSH}'
NETWORK_SERVICE='${SERVICES_NETWORK_SERVICE}'
DEFAULT_TARGET='${SERVICES_GRAPHICAL_TARGET}'
EOF

    chmod 0644 "$SERVICES_CONFIG_FILE" 2>/dev/null || true

    return 0
}

#============================================================
# Main installer stage
#============================================================

services_configure()
{
    services_log_info \
        "System service configuration started"

    #--------------------------------------------------------
    # Target
    #--------------------------------------------------------

    services_check_target || \
        return 1

    #--------------------------------------------------------
    # Configuration
    #--------------------------------------------------------

    services_load_config || \
        return 1

    services_validate_hostname || \
        return 1

    services_validate_ssh || \
        return 1

    #--------------------------------------------------------
    # Files
    #--------------------------------------------------------

    services_configure_hostname || \
        return 1

    services_configure_hosts || \
        return 1

    #--------------------------------------------------------
    # Services
    #--------------------------------------------------------

    services_network || \
        return 1
    services_ssh || \
        return 1
    #--------------------------------------------------------
    # systemd target
    #--------------------------------------------------------
    services_graphical_target || \
        return 1
    #--------------------------------------------------------
    # Verification
    #--------------------------------------------------------
    services_check_hostname || \
        return 1
    services_check_hosts || \
        return 1
    services_check_network || \
        return 1
    services_check_ssh || \
        return 1
    services_check_target_mode || \
        return 1
    #--------------------------------------------------------
    # Save
    #--------------------------------------------------------

    services_save || \
        return 1
    #--------------------------------------------------------
    # Finished
    #--------------------------------------------------------
    if declare -F dialog_message >/dev/null 2>&1
    then
        dialog_message \
            "Services" \
            "System services configured successfully"
    fi

    services_log_info \
        "System service configuration finished"
    return 0
}
#============================================================
# END
#============================================================
