#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# installer/services.sh
#
# Stage: services
#============================================================

#============================================================
# Include guard
#============================================================

if declare -F services_configure >/dev/null 2>&1
then
    return 0 2>/dev/null || exit 0
fi

#============================================================
# State
#============================================================

SERVICES_TARGET="${SERVICES_TARGET:-/mnt}"
SERVICES_CONFIG_FILE="${SERVICES_CONFIG_FILE:-${SERVICES_TARGET}/etc/arch-installer-services.conf}"

SERVICES_HOSTNAME="${SERVICES_HOSTNAME:-archlinux}"
SERVICES_ENABLE_SSH="${SERVICES_ENABLE_SSH:-1}"
SERVICES_NETWORK_SERVICE="${SERVICES_NETWORK_SERVICE:-}"
SERVICES_GRAPHICAL_TARGET="${SERVICES_GRAPHICAL_TARGET:-graphical.target}"

#============================================================
# Logging
#============================================================

services_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@"
    else
        printf '[INFO] %s\n' "$*" >&2
    fi

    return 0
}

services_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@"
    else
        printf '[WARN] %s\n' "$*" >&2
    fi

    return 0
}

services_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@"
    else
        printf '[ERROR] %s\n' "$*" >&2
    fi

    return 0
}

#============================================================
# Target
#============================================================

services_check_target()
{
    services_log_info "Checking target: ${SERVICES_TARGET}"

    [[ -d "$SERVICES_TARGET" ]] || return 1
    [[ -d "${SERVICES_TARGET}/etc" ]] || return 1
    [[ -d "${SERVICES_TARGET}/usr" ]] || return 1

    return 0
}

#============================================================
# Configuration
#============================================================

services_load_config()
{
    if declare -p CONFIG >/dev/null 2>&1
    then
        SERVICES_HOSTNAME="${CONFIG[HOSTNAME]:-${CONFIG[hostname]:-${SERVICES_HOSTNAME}}}"
        SERVICES_ENABLE_SSH="${CONFIG[SSH_ENABLED]:-${CONFIG[ssh_enabled]:-${SERVICES_ENABLE_SSH}}}"
        SERVICES_NETWORK_SERVICE="${CONFIG[NETWORK_SERVICE]:-${CONFIG[network_service]:-${SERVICES_NETWORK_SERVICE}}}"
    fi

    [[ -n "$SERVICES_HOSTNAME" ]] || SERVICES_HOSTNAME="archlinux"

    return 0
}

#============================================================
# Validation
#============================================================

services_validate_hostname()
{
    [[ -n "$SERVICES_HOSTNAME" ]] || return 1

    ((${#SERVICES_HOSTNAME} <= 253)) || return 1

    [[ "$SERVICES_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] ||
        return 1

    return 0
}

services_validate_ssh()
{
    case "$SERVICES_ENABLE_SSH" in
        0|1)
            ;;
        *)
            SERVICES_ENABLE_SSH=1
            ;;
    esac

    return 0
}

#============================================================
# Hostname
#============================================================

services_configure_hostname()
{
    printf '%s\n' "$SERVICES_HOSTNAME" \
        > "${SERVICES_TARGET}/etc/hostname" ||
        return 1

    return 0
}

#============================================================
# Hosts
#============================================================

services_configure_hosts()
{
    local hosts_file="${SERVICES_TARGET}/etc/hosts"

    cat > "$hosts_file" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${SERVICES_HOSTNAME}
EOF

    return 0
}

#============================================================
# Network
#============================================================

services_network()
{
    local wants_dir=""

    wants_dir="${SERVICES_TARGET}/etc/systemd/system/multi-user.target.wants"

    mkdir -p "$wants_dir" || return 1

    if [[ -z "$SERVICES_NETWORK_SERVICE" ]]
    then
        if [[ -e "${SERVICES_TARGET}/usr/lib/systemd/system/NetworkManager.service" ]]
        then
            SERVICES_NETWORK_SERVICE="NetworkManager"
        elif [[ -e "${SERVICES_TARGET}/usr/lib/systemd/system/systemd-networkd.service" ]]
        then
            SERVICES_NETWORK_SERVICE="systemd-networkd"
        else
            SERVICES_NETWORK_SERVICE=""
        fi
    fi

    case "$SERVICES_NETWORK_SERVICE" in

        NetworkManager)
            if [[ -e "${SERVICES_TARGET}/usr/lib/systemd/system/NetworkManager.service" ]]
            then
                ln -sf \
                    /usr/lib/systemd/system/NetworkManager.service \
                    "${wants_dir}/NetworkManager.service"
            fi
            ;;

        systemd-networkd)
            if [[ -e "${SERVICES_TARGET}/usr/lib/systemd/system/systemd-networkd.service" ]]
            then
                ln -sf \
                    /usr/lib/systemd/system/systemd-networkd.service \
                    "${wants_dir}/systemd-networkd.service"
            fi
            ;;

        "")
            services_log_warn "No network service found"
            ;;

        *)
            services_log_warn \
                "Unknown network service: ${SERVICES_NETWORK_SERVICE}"
            ;;
    esac

    return 0
}

#============================================================
# SSH
#============================================================

services_ssh()
{
    local wants_dir="${SERVICES_TARGET}/etc/systemd/system/multi-user.target.wants"

    if [[ "$SERVICES_ENABLE_SSH" != "1" ]]
    then
        return 0
    fi

    if [[ ! -e "${SERVICES_TARGET}/usr/lib/systemd/system/sshd.service" ]]
    then
        services_log_warn "sshd.service not found"
        return 0
    fi

    mkdir -p "$wants_dir" || return 1

    ln -sf \
        /usr/lib/systemd/system/sshd.service \
        "${wants_dir}/sshd.service" ||
        return 1

    return 0
}

#============================================================
# Graphical target
#============================================================

services_graphical_target()
{
    local system_dir="${SERVICES_TARGET}/etc/systemd/system"
    local target="${system_dir}/default.target"

    mkdir -p "$system_dir" || return 1

    rm -f "$target" || return 1

    ln -sf \
        "/usr/lib/systemd/system/${SERVICES_GRAPHICAL_TARGET}" \
        "$target" ||
        return 1

    return 0
}

#============================================================
# Verification
#============================================================

services_check_hostname()
{
    local file="${SERVICES_TARGET}/etc/hostname"

    [[ -f "$file" ]] || return 1

    [[ "$(cat "$file")" == "$SERVICES_HOSTNAME" ]] ||
        return 1

    return 0
}

services_check_hosts()
{
    local file="${SERVICES_TARGET}/etc/hosts"

    [[ -f "$file" ]] || return 1

    grep -qE \
        '^[[:space:]]*127\.0\.0\.1[[:space:]]+localhost' \
        "$file" ||
        return 1

    return 0
}

services_check_network()
{
    case "$SERVICES_NETWORK_SERVICE" in
        NetworkManager)
            [[ -e \
                "${SERVICES_TARGET}/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ]]
            ;;

        systemd-networkd)
            [[ -e \
                "${SERVICES_TARGET}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" ]]
            ;;

        "")
            return 0
            ;;

        *)
            return 0
            ;;
    esac
}

services_check_ssh()
{
    if [[ "$SERVICES_ENABLE_SSH" != "1" ]]
    then
        return 0
    fi

    [[ -e \
        "${SERVICES_TARGET}/etc/systemd/system/multi-user.target.wants/sshd.service" ]]
}

services_check_target_mode()
{
    local target="${SERVICES_TARGET}/etc/systemd/system/default.target"
    local expected="/usr/lib/systemd/system/${SERVICES_GRAPHICAL_TARGET}"
    local actual=""

    [[ -L "$target" ]] || return 1

    actual="$(readlink "$target")" || return 1

    [[ "$actual" == "$expected" ]]
}

#============================================================
# Save
#============================================================

services_save()
{
    local directory

    directory="$(dirname "$SERVICES_CONFIG_FILE")"

    mkdir -p "$directory" || return 1

    cat > "$SERVICES_CONFIG_FILE" <<EOF
HOSTNAME=${SERVICES_HOSTNAME}
SSH_ENABLED=${SERVICES_ENABLE_SSH}
NETWORK_SERVICE=${SERVICES_NETWORK_SERVICE}
DEFAULT_TARGET=${SERVICES_GRAPHICAL_TARGET}
EOF

    return 0
}

#============================================================
# Main stage
#============================================================

services_configure()
{
    services_log_info "System service configuration started"

    services_check_target || return 1
    services_load_config || return 1
    services_validate_hostname || return 1
    services_validate_ssh || return 1

    services_configure_hostname || return 1
    services_configure_hosts || return 1

    services_network || return 1
    services_ssh || return 1

    services_graphical_target || return 1

    services_check_hostname || return 1
    services_check_hosts || return 1
    services_check_network || return 1
    services_check_ssh || return 1
    services_check_target_mode || return 1

    services_save || return 1

    if declare -F dialog_message >/dev/null 2>&1
    then
        dialog_message \
            "Services" \
            "System services configured successfully"
    fi

    services_log_info "System service configuration finished"

    return 0
}

#============================================================
# END
#============================================================
