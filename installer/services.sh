```bash
#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  services.sh
#
#  Настройка системных systemd-сервисов.
#
#  Ответственность:
#   • Проверка target system
#   • Настройка hostname
#   • Настройка /etc/hosts
#   • Включение NetworkManager
#   • Включение/отключение SSH
#   • Настройка systemd default target
#   • Проверка конфигурации
#   • Сохранение состояния
#
#  Не выполняет:
#   • Установку пакетов
#   • Настройку desktop environment
#   • Установку display manager
#   • Установку загрузчика
#
#  ВАЖНО:
#   Все операции выполняются над offline target:
#
#       /mnt
#
#   Для systemd используется:
#
#       systemctl --root=/mnt
#
#   arch-chroot здесь не требуется.
#============================================================


#------------------------------------------------------------
# Prevent double loading
#------------------------------------------------------------

[[ -n "${SERVICES_SH_LOADED:-}" ]] && return

readonly SERVICES_SH_LOADED=1


#============================================================
# State
#============================================================

SERVICES_HOSTNAME=""
SERVICES_SSH_ENABLED="0"


#============================================================
# Constants
#============================================================

readonly SERVICES_TARGET="/mnt"

readonly SERVICES_HOSTNAME_FILE="/mnt/etc/hostname"
readonly SERVICES_HOSTS_FILE="/mnt/etc/hosts"


#============================================================
# Internal helpers
#============================================================

#------------------------------------------------------------
# Check systemctl
#------------------------------------------------------------

services_systemctl_available()
{
    if [[ ! -x /usr/bin/systemctl ]]
    then
        logger_error \
            "systemctl is not available in installer environment"

        return 1
    fi

    if [[ ! -x "${SERVICES_TARGET}/usr/bin/systemctl" ]]
    then
        logger_error \
            "systemctl is not available in target system"

        return 1
    fi

    return 0
}


#------------------------------------------------------------
# Run systemctl against target
#------------------------------------------------------------

services_systemctl()
{
    systemctl \
        --root="${SERVICES_TARGET}" \
        "$@"
}


#============================================================
# Load configuration
#============================================================

services_load_config()
{
    if [[ -v "CONFIG[HOSTNAME]" ]]
    then
        SERVICES_HOSTNAME="$(config_get HOSTNAME)"
    else
        SERVICES_HOSTNAME="archlinux"

        config_set \
            HOSTNAME \
            "$SERVICES_HOSTNAME"
    fi


    if [[ -v "CONFIG[SSH_ENABLED]" ]]
    then
        SERVICES_SSH_ENABLED="$(config_get SSH_ENABLED)"
    else
        SERVICES_SSH_ENABLED="0"

        config_set \
            SSH_ENABLED \
            "$SERVICES_SSH_ENABLED"
    fi


    logger_info \
        "Hostname: ${SERVICES_HOSTNAME}"

    logger_info \
        "SSH enabled: ${SERVICES_SSH_ENABLED}"
}


#============================================================
# Validate target
#============================================================

services_check_target()
{
    logger_info \
        "Checking target system: ${SERVICES_TARGET}"


    if [[ ! -d "${SERVICES_TARGET}" ]]
    then
        dialog_error \
            "Target directory does not exist: ${SERVICES_TARGET}"

        return 1
    fi


    if [[ ! -d "${SERVICES_TARGET}/etc" ]]
    then
        dialog_error \
            "Target system is not installed"

        return 1
    fi


    if [[ ! -f "${SERVICES_TARGET}/etc/passwd" ]]
    then
        dialog_error \
            "Target passwd database is missing"

        return 1
    fi


    services_systemctl_available || {
        dialog_error \
            "systemd is not available in target system"

        return 1
    }


    return 0
}


#============================================================
# Validate hostname
#============================================================

services_validate_hostname()
{
    local hostname="$SERVICES_HOSTNAME"
    local label


    if [[ -z "$hostname" ]]
    then
        dialog_error \
            "Hostname is empty"

        return 1
    fi


    if [[ ${#hostname} -gt 253 ]]
    then
        dialog_error \
            "Hostname is too long"

        return 1
    fi


    # Hostname must contain only:
    #
    #   A-Z
    #   a-z
    #   0-9
    #   -
    #   .
    #
    if [[ "$hostname" =~ [^a-zA-Z0-9.-] ]]
    then
        dialog_error \
            "Invalid hostname: ${hostname}"

        return 1
    fi


    # Must not begin/end with dot.
    if [[ "$hostname" == .* ||
          "$hostname" == *. ]]
    then
        dialog_error \
            "Hostname cannot start or end with a dot"

        return 1
    fi


    # Validate every DNS label.
    IFS='.' read -ra labels <<< "$hostname"


    for label in "${labels[@]}"
    do
        if [[ -z "$label" ]]
        then
            dialog_error \
                "Hostname contains an empty label"

            return 1
        fi


        if [[ ${#label} -gt 63 ]]
        then
            dialog_error \
                "Hostname label is too long: ${label}"

            return 1
        fi


        if [[ "$label" == -* ||
              "$label" == *- ]]
        then
            dialog_error \
                "Hostname label cannot start or end with '-': ${label}"

            return 1
        fi
    done


    return 0
}


#============================================================
# Validate SSH option
#============================================================

services_validate_ssh()
{
    case "$SERVICES_SSH_ENABLED" in

        0|1)
            return 0
            ;;

        *)
            dialog_error \
                "Invalid SSH_ENABLED: ${SERVICES_SSH_ENABLED}"

            return 1
            ;;
    esac
}


#============================================================
# Check service unit
#============================================================

services_check_service()
{
    local service="$1"


    if [[ -z "$service" ]]
    then
        logger_error \
            "Service name is empty"

        return 1
    fi


    logger_info \
        "Checking service unit: ${service}.service"


    if ! services_systemctl \
        cat \
        "${service}.service" \
        >/dev/null 2>&1
    then
        logger_error \
            "Service is not available in target: ${service}"

        return 1
    fi


    return 0
}


#============================================================
# Enable service
#============================================================

services_enable()
{
    local service="$1"


    services_check_service \
        "$service" || {

        dialog_error \
            "Service is unavailable: ${service}"

        return 1
    }


    logger_info \
        "Enabling service: ${service}"


    if ! services_systemctl \
        enable \
        "${service}.service"
    then
        logger_error \
            "Failed enabling service: ${service}"

        return 1
    fi


    return 0
}


#============================================================
# Disable service
#============================================================

services_disable()
{
    local service="$1"


    if ! services_check_service \
        "$service"
    then
        logger_error \
            "Cannot disable unavailable service: ${service}"

        return 1
    fi


    logger_info \
        "Disabling service: ${service}"


    if ! services_systemctl \
        disable \
        "${service}.service" \
        >/dev/null 2>&1
    then
        # systemctl disable may return non-zero when the
        # service was not enabled. That is not necessarily
        # an error.
        logger_info \
            "Service was not enabled or could not be disabled: ${service}"
    fi


    return 0
}


#============================================================
# Configure hostname
#============================================================

services_configure_hostname()
{
    logger_info \
        "Configuring hostname: ${SERVICES_HOSTNAME}"


    if ! printf '%s\n' \
        "$SERVICES_HOSTNAME" \
        > "${SERVICES_HOSTNAME_FILE}"
    then
        logger_error \
            "Failed writing ${SERVICES_HOSTNAME_FILE}"

        return 1
    fi


    if ! chmod 644 \
        "${SERVICES_HOSTNAME_FILE}"
    then
        logger_error \
            "Failed setting permissions on ${SERVICES_HOSTNAME_FILE}"

        return 1
    fi


    logger_info \
        "Hostname configured"


    return 0
}


#============================================================
# Configure /etc/hosts
#============================================================

services_configure_hosts()
{
    logger_info \
        "Configuring ${SERVICES_HOSTS_FILE}"


    if ! cat > "${SERVICES_HOSTS_FILE}" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${SERVICES_HOSTNAME}.localdomain ${SERVICES_HOSTNAME}
EOF
    then
        logger_error \
            "Failed writing ${SERVICES_HOSTS_FILE}"

        return 1
    fi


    if ! chmod 644 \
        "${SERVICES_HOSTS_FILE}"
    then
        logger_error \
            "Failed setting permissions on ${SERVICES_HOSTS_FILE}"

        return 1
    fi


    logger_info \
        "/etc/hosts configured"


    return 0
}


#============================================================
# Configure NetworkManager
#============================================================

services_network()
{
    logger_info \
        "Configuring NetworkManager"


    services_enable \
        NetworkManager || \
        return 1


    return 0
}


#============================================================
# Configure SSH
#============================================================

services_ssh()
{
    if [[ "$SERVICES_SSH_ENABLED" == "1" ]]
    then
        logger_info \
            "SSH is enabled in configuration"

        services_enable \
            sshd || \
            return 1
    else
        logger_info \
            "SSH is disabled in configuration"

        services_disable \
            sshd || \
            return 1
    fi


    return 0
}


#============================================================
# Configure default target
#============================================================

services_graphical_target()
{
    local desktop=""
    local target


    if [[ -v "CONFIG[DESKTOP]" ]]
    then
        desktop="$(config_get DESKTOP)"
    fi


    if [[ -n "$desktop" ]]
    then
        target="graphical.target"

        logger_info \
            "Desktop selected: ${desktop}"

        logger_info \
            "Setting default target: ${target}"
    else
        target="multi-user.target"

        logger_info \
            "No desktop selected"

        logger_info \
            "Setting default target: ${target}"
    fi


    if ! services_systemctl \
        set-default \
        "$target"
    then
        logger_error \
            "Failed setting default target: ${target}"

        return 1
    fi


    return 0
}


#============================================================
# Check service state
#============================================================

services_check_enabled()
{
    local service="$1"
    local state


    state="$(
        services_systemctl \
            is-enabled \
            "${service}.service" \
            2>/dev/null
    )" || {

        logger_error \
            "Unable to determine service state: ${service}"

        return 1
    }


    if [[ "$state" != "enabled" ]]
    then
        logger_error \
            "Service is not enabled: ${service} (state=${state})"

        return 1
    fi


    logger_info \
        "Service enabled: ${service}"


    return 0
}


#============================================================
# Check service disabled
#============================================================

services_check_disabled()
{
    local service="$1"
    local state


    state="$(
        services_systemctl \
            is-enabled \
            "${service}.service" \
            2>/dev/null
    )" || true


    case "$state" in

        disabled|static|indirect)
            logger_info \
                "Service disabled: ${service} (state=${state})"
            ;;

        "")
            logger_info \
                "Service is not enabled: ${service}"
            ;;

        *)
            logger_error \
                "Unexpected service state: ${service} (state=${state})"

            return 1
            ;;
    esac


    return 0
}


#============================================================
# Check NetworkManager
#============================================================

services_check_network()
{
    services_check_enabled \
        NetworkManager
}


#============================================================
# Check SSH
#============================================================

services_check_ssh()
{
    if [[ "$SERVICES_SSH_ENABLED" != "1" ]]
    then
        services_check_disabled \
            sshd

        return $?
    fi


    services_check_enabled \
        sshd
}


#============================================================
# Check hostname
#============================================================

services_check_hostname()
{
    local current


    if [[ ! -f "${SERVICES_HOSTNAME_FILE}" ]]
    then
        logger_error \
            "Hostname file is missing"

        return 1
    fi


    current="$(
        < "${SERVICES_HOSTNAME_FILE}"
    )"


    # Remove CR/LF.
    current="${current//$'\r'/}"
    current="${current//$'\n'/}"


    if [[ "$current" != "$SERVICES_HOSTNAME" ]]
    then
        logger_error \
            "Hostname verification failed: expected=${SERVICES_HOSTNAME} actual=${current}"

        return 1
    fi


    logger_info \
        "Hostname verification passed"


    return 0
}


#============================================================
# Check /etc/hosts
#============================================================

services_check_hosts()
{
    if [[ ! -f "${SERVICES_HOSTS_FILE}" ]]
    then
        logger_error \
            "/etc/hosts is missing"

        return 1
    fi


    if ! grep -Fqx \
        "127.0.0.1   localhost" \
        "${SERVICES_HOSTS_FILE}"
    then
        logger_error \
            "Missing localhost IPv4 entry"

        return 1
    fi


    if ! grep -Fqx \
        "::1         localhost" \
        "${SERVICES_HOSTS_FILE}"
    then
        logger_error \
            "Missing localhost IPv6 entry"

        return 1
    fi


    if ! grep -Fqx \
        "127.0.1.1   ${SERVICES_HOSTNAME}.localdomain ${SERVICES_HOSTNAME}" \
        "${SERVICES_HOSTS_FILE}"
    then
        logger_error \
            "Missing hostname entry in /etc/hosts"

        return 1
    fi


    logger_info \
        "/etc/hosts verification passed"


    return 0
}


#============================================================
# Check default target
#============================================================

services_check_target_mode()
{
    local desktop=""
    local expected
    local actual


    if [[ -v "CONFIG[DESKTOP]" ]]
    then
        desktop="$(config_get DESKTOP)"
    fi


    if [[ -n "$desktop" ]]
    then
        expected="graphical.target"
    else
        expected="multi-user.target"
    fi


    actual="$(
        services_systemctl \
            get-default \
            2>/dev/null
    )" || {

        logger_error \
            "Unable to determine default systemd target"

        return 1
    }


    if [[ "$actual" != "$expected" ]]
    then
        logger_error \
            "Invalid default target: expected=${expected} actual=${actual}"

        return 1
    fi


    logger_info \
        "Default target verification passed: ${actual}"


    return 0
}


#============================================================
# Save state
#============================================================

services_save()
{
    if ! config_save
    then
        logger_error \
            "Failed saving service configuration"

        return 1
    fi


    logger_info \
        "Service configuration saved"


    return 0
}


#============================================================
# Main
#============================================================

services()
{
    logger_info \
        "System service configuration started"


    #--------------------------------------------------------
    # Target
    #--------------------------------------------------------

    services_check_target || \
        return 1


    #--------------------------------------------------------
    # Configuration
    #--------------------------------------------------------

    services_load_config


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

    dialog_message \
        "Services" \
        "System services configured successfully"


    logger_info \
        "System service configuration finished"


    return 0
}
```
