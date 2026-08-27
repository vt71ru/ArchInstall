#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  desktop.sh
#
#  Настройка графической среды установленной системы.
#
#  Ответственность:
#   • Проверка выбранного desktop
#   • Проверка установленных пакетов
#   • Определение display manager
#   • Отключение конфликтующих display manager
#   • Включение выбранного display manager
#   • Настройка graphical.target
#   • Проверка конфигурации
#   • Сохранение состояния
#
#  Не выполняет:
#   • Установку desktop
#   • Установку пакетов через pacman
#   • Настройку GPU-драйвера
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
#   arch-chroot здесь не используется.
#============================================================
[[ -n "${DESKTOP_SH_LOADED:-}" ]] && return
readonly DESKTOP_SH_LOADED=1
#============================================================
# State
#============================================================
DESKTOP_NAME=""
DISPLAY_MANAGER=""
#============================================================
# Constants
#============================================================
readonly DESKTOP_TARGET="/mnt"
#============================================================
# Supported desktops
#============================================================
desktop_is_supported()
{
    case "$1" in
        gnome|kde|xfce)
            return 0
            ;;
        "")
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}
#============================================================
# Determine display manager
#============================================================
desktop_get_display_manager()
{
    local desktop="$1"
    case "$desktop" in
        gnome)
            printf '%s\n' "gdm"
            ;;
        kde)
            printf '%s\n' "sddm"
            ;;
        xfce)
            printf '%s\n' "lightdm"
            ;;
        *)
            return 1
            ;;
    esac
}
#============================================================
# systemctl helper
#============================================================
desktop_systemctl()
{
    systemctl \
        --root="${DESKTOP_TARGET}" \
        "$@"
}
#============================================================
# Load configuration
#============================================================
desktop_load_config()
{
    DESKTOP_NAME=""
    if [[ -v "CONFIG[DESKTOP]" ]]
    then
        DESKTOP_NAME="$(config_get DESKTOP)"
    fi
    case "$DESKTOP_NAME" in
        gnome|kde|xfce)
            ;;
        "")
            logger_info \
                "Desktop environment not selected"
            return 0
            ;;
        *)
            dialog_error \
                "Unsupported desktop: ${DESKTOP_NAME}"
            return 1
            ;;
    esac
    DISPLAY_MANAGER="$(
        desktop_get_display_manager \
            "$DESKTOP_NAME"
    )" || {
        logger_error \
            "Unable to determine display manager"
        return 1
    }
    logger_info \
        "Desktop: ${DESKTOP_NAME}"
    logger_info \
        "Display manager: ${DISPLAY_MANAGER}"
    return 0
}
#============================================================
# Validate target
#============================================================
desktop_check_target()
{
    logger_info \
        "Checking target system: ${DESKTOP_TARGET}"
    if [[ ! -d "${DESKTOP_TARGET}" ]]
    then
        dialog_error \
            "Target directory does not exist: ${DESKTOP_TARGET}"
        return 1
    fi
    if [[ ! -d "${DESKTOP_TARGET}/etc" ]]
    then
        dialog_error \
            "Target system is not installed"
        return 1
    fi
    if [[ ! -x "${DESKTOP_TARGET}/usr/bin/bash" ]]
    then
        dialog_error \
            "Target system is incomplete"
        return 1
    fi
    if [[ ! -x "${DESKTOP_TARGET}/usr/bin/systemctl" ]]
    then
        dialog_error \
            "systemctl is missing in target system"
        return 1
    fi
    if [[ ! -d "${DESKTOP_TARGET}/usr/lib/systemd" ]]
    then
        dialog_error \
            "systemd is missing in target system"
        return 1
    fi
    return 0
}
#============================================================
# Check systemctl in installer
#============================================================
desktop_check_systemctl()
{
    if [[ ! -x /usr/bin/systemctl ]]
    then
        logger_error \
            "systemctl is missing in installer environment"
        dialog_error \
            "systemctl is unavailable"
        return 1
    fi
    return 0
}
#============================================================
# Check package in target
#============================================================
desktop_check_package()
{
    local package="$1"
    if [[ -z "$package" ]]
    then
        logger_error \
            "Package name is empty"
        return 1
    fi
    if ! pacman \
        --root="${DESKTOP_TARGET}" \
        --dbpath="${DESKTOP_TARGET}/var/lib/pacman" \
        -Q \
        "$package" \
        >/dev/null 2>&1
    then
        logger_error \
            "Package missing in target: ${package}"
        dialog_error \
            "Required package is missing: ${package}"
        return 1
    fi
    logger_debug \
        "Package verified: ${package}"
    return 0
}
#============================================================
# Check selected desktop packages
#============================================================
desktop_check_packages()
{
    case "$DESKTOP_NAME" in
        gnome)
            desktop_check_package \
                gnome-shell || \
                return 1
            desktop_check_package \
                gdm || \
                return 1
            ;;
        kde)
            desktop_check_package \
                plasma-workspace || \
                return 1
            desktop_check_package \
                sddm || \
                return 1
            ;;
        xfce)
            desktop_check_package \
                xfce4-session || \
                return 1
            desktop_check_package \
                lightdm || \
                return 1
            ;;
        "")
            return 0
            ;;
        *)
            logger_error \
                "Unsupported desktop: ${DESKTOP_NAME}"
            return 1
            ;;
    esac
    return 0
}
#============================================================
# Check desktop environment
#============================================================
desktop_check_environment()
{
    case "$DESKTOP_NAME" in
        gnome)
            if [[ ! -d "${DESKTOP_TARGET}/usr/share/gnome-session" ]]
            then
                dialog_error \
                    "GNOME session files are missing"
                return 1
            fi
            ;;
        kde)
            if [[ ! -d "${DESKTOP_TARGET}/usr/share/plasma" ]]
            then
                dialog_error \
                    "Plasma files are missing"
                return 1
            fi
            ;;
        xfce)
            if [[ ! -d "${DESKTOP_TARGET}/usr/share/xfce4" ]]
            then
                dialog_error \
                    "Xfce files are missing"
                return 1
            fi
            ;;
        "")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
    logger_info \
        "Desktop environment check passed"
    return 0
}
#============================================================
# Check display manager unit
#============================================================
desktop_check_display_manager_unit()
{
    local service="${DISPLAY_MANAGER}.service"
    logger_info \
        "Checking display manager unit: ${service}"
    if ! desktop_systemctl \
        cat \
        "$service" \
        >/dev/null 2>&1
    then
        logger_error \
            "Display manager unit is unavailable: ${service}"
        dialog_error \
            "Display manager service is missing: ${service}"
        return 1
    fi
    return 0
}
#============================================================
# Disable conflicting display managers
#============================================================
desktop_disable_other_display_managers()
{
    local manager
    local state
    for manager in \
        gdm \
        sddm \
        lightdm
    do
        if [[ "$manager" == "$DISPLAY_MANAGER" ]]
        then
            continue
        fi
        state="$(
            desktop_systemctl \
                is-enabled \
                "${manager}.service" \
                2>/dev/null
        )" || true
        case "$state" in
            enabled)
                logger_warn \
                    "Disabling conflicting display manager: ${manager}"
                if ! desktop_systemctl \
                    disable \
                    "${manager}.service"
                then
                    logger_error \
                        "Failed disabling ${manager}"
                    return 1
                fi
                ;;
            *)
                ;;
        esac
    done
    return 0
}
#============================================================
# Enable display manager
#============================================================
desktop_enable_display_manager()
{
    local service="${DISPLAY_MANAGER}.service"
    logger_info \
        "Enabling display manager: ${service}"
    if ! desktop_systemctl \
        enable \
        "$service"
    then
        logger_error \
            "Failed enabling ${service}"
        return 1
    fi
    return 0
}
#============================================================
# Set graphical target as default
#============================================================
desktop_set_graphical_target()
{
    logger_info \
        "Setting graphical.target as default"
    if ! desktop_systemctl \
        set-default \
        graphical.target
    then
        logger_error \
            "Failed setting graphical.target as default"
        return 1
    fi
    return 0
}
#============================================================
# Check graphical target
#============================================================
desktop_check_graphical_target()
{
    local actual
    actual="$(
        desktop_systemctl \
            get-default \
            2>/dev/null
    )" || {
        logger_error \
            "Unable to determine default target"
        return 1
    }
    if [[ "$actual" != "graphical.target" ]]
    then
        logger_error \
            "Invalid default target: expected=graphical.target actual=${actual}"
        dialog_error \
            "graphical.target is not the default system target"
        return 1
    fi
    logger_info \
        "graphical.target verification passed"
    return 0
}
#============================================================
# Check display manager
#============================================================
desktop_check_display_manager()
{
    local service="${DISPLAY_MANAGER}.service"
    local state
    state="$(
        desktop_systemctl \
            is-enabled \
            "$service" \
            2>/dev/null
    )" || {
        dialog_error \
            "Unable to determine display manager state: ${service}"
        return 1
    }
    if [[ "$state" != "enabled" ]]
    then
        dialog_error \
            "Display manager is not enabled: ${service}"
        logger_error \
            "Display manager state: ${state}"
        return 1
    fi
    logger_info \
        "Display manager enabled: ${service}"
    return 0
}
#============================================================
# Check display manager conflicts
#============================================================
desktop_check_display_manager_conflicts()
{
    local manager
    local state
    for manager in \
        gdm \
        sddm \
        lightdm
    do
        if [[ "$manager" == "$DISPLAY_MANAGER" ]]
        then
            continue
        fi
        state="$(
            desktop_systemctl \
                is-enabled \
                "${manager}.service" \
                2>/dev/null
        )" || true
        if [[ "$state" == "enabled" ]]
        then
            logger_error \
                "Conflicting display manager remains enabled: ${manager}"
            return 1
        fi
    done
    logger_info \
        "Display manager conflict check passed"
    return 0
}
#============================================================
# Save state
#============================================================
desktop_save()
{
    if ! config_save
    then
        logger_error \
            "Failed saving desktop configuration"
        return 1
    fi
    logger_info \
        "Desktop configuration saved"
    return 0
}
#============================================================
# No desktop selected
#============================================================
desktop_none()
{
    dialog_message \
        "Desktop" \
        "No desktop environment selected"
    logger_info \
        "Desktop configuration skipped"
    return 0
}
#============================================================
# Main
#============================================================
desktop()
{
    logger_info \
        "Desktop configuration started"
    desktop_load_config || \
        return 1
    if [[ -z "$DESKTOP_NAME" ]]
    then
        desktop_none
        return 0
    fi
    desktop_check_target || \
        return 1
    desktop_check_systemctl || \
        return 1
    desktop_check_packages || \
        return 1
    desktop_check_environment || \
        return 1
    desktop_check_display_manager_unit || \
        return 1
    desktop_disable_other_display_managers || \
        return 1
    desktop_enable_display_manager || \
        return 1
    desktop_set_graphical_target || \
        return 1
    desktop_check_display_manager || \
        return 1
    desktop_check_display_manager_conflicts || \
        return 1
    desktop_check_graphical_target || \
        return 1
    desktop_save || \
        return 1
    dialog_message \
        "Desktop" \
        "${DESKTOP_NAME} configured successfully"
    logger_info \
        "Desktop configuration finished"
    return 0
}