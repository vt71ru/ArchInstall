#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  config.sh
#
#  Центральное хранилище конфигурации installer.
#
#  Ответственность:
#   • Хранение CONFIG[]
#   • Значения по умолчанию
#   • Чтение значений
#   • Запись значений
#   • Сохранение конфигурации
#   • Загрузка конфигурации
#   • Экспорт переменных
#   • Сброс конфигурации
#   • Валидация
#
#  Не выполняет:
#   • TUI
#   • Разметку дисков
#   • Форматирование
#   • Монтирование
#   • Установку пакетов
#   • Настройку systemd
#============================================================
if [[ -n "${CONFIG_SH_LOADED:-}" ]]
then
    return 0
fi
readonly CONFIG_SH_LOADED=1
#============================================================
# Configuration file
#============================================================
CONFIG_FILE="${CONFIG_FILE:-/tmp/arch-installer.conf}"
#============================================================
# Configuration storage
#============================================================
declare -gA CONFIG=()
#============================================================
# Configuration keys
#============================================================
declare -ga CONFIG_KEYS=(
    BOOT_MODE
    PARTITION_TABLE
    TARGET_DISK
    TARGET_DISK_SIZE
    TARGET_DISK_MODEL
    TARGET_DISK_SERIAL
    TARGET_DISK_TRAN
    EFI_PART
    BIOS_PART
    ROOT_PART
    HOME_PART
    SWAP_PART
    FILESYSTEM
    CREATE_HOME
    HOME_SIZE
    SWAP_TYPE
    SWAP_SIZE
    SWAP_FILE
    SYSTEM_KEYMAP
    LOCALES
    LOCALE
    NETWORK_INTERFACE
    NETWORK_ENABLED
    INSTALL_REFLECTOR
    MIRROR_COUNTRY
    MIRROR_LATEST
    MIRROR_AGE
    MIRROR_PROTOCOL
    MIRROR_SORT
    USER_NAME
    HOSTNAME
    SSH_ENABLED
    DESKTOP
    GPU_DRIVER
    BOOTLOADER
)
#============================================================
# Validate key
#============================================================
config_valid_key()
{
    local key="${1:-}"
    [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]
}
#============================================================
# Require valid key
#============================================================
config_require_key()
{
    local key="${1:-}"
    if ! config_valid_key "$key"
    then
        logger_error \
            "Invalid configuration key: ${key}"
        return 1
    fi
    return 0
}
#============================================================
# Initialize defaults
#============================================================
config_init()
{
    CONFIG=()
    CONFIG[BOOT_MODE]=""
    CONFIG[PARTITION_TABLE]=""
    CONFIG[TARGET_DISK]=""
    CONFIG[TARGET_DISK_SIZE]=""
    CONFIG[TARGET_DISK_MODEL]=""
    CONFIG[TARGET_DISK_SERIAL]=""
    CONFIG[TARGET_DISK_TRAN]=""
    CONFIG[EFI_PART]=""
    CONFIG[BIOS_PART]=""
    CONFIG[ROOT_PART]=""
    CONFIG[HOME_PART]=""
    CONFIG[SWAP_PART]=""
    CONFIG[FILESYSTEM]="ext4"
    CONFIG[CREATE_HOME]="0"
    CONFIG[HOME_SIZE]=""
    CONFIG[SWAP_TYPE]="none"
    CONFIG[SWAP_SIZE]=""
    CONFIG[SWAP_FILE]=""
    CONFIG[SYSTEM_KEYMAP]="us"
    CONFIG[LOCALES]="en_US.UTF-8"
    CONFIG[LOCALE]="en_US.UTF-8"
    CONFIG[NETWORK_INTERFACE]=""
    CONFIG[NETWORK_ENABLED]="0"
    CONFIG[INSTALL_REFLECTOR]="0"
    CONFIG[MIRROR_COUNTRY]=""
    CONFIG[MIRROR_LATEST]="10"
    CONFIG[MIRROR_AGE]="24"
    CONFIG[MIRROR_PROTOCOL]="https"
    CONFIG[MIRROR_SORT]="rate"
    CONFIG[USER_NAME]="user"
    CONFIG[HOSTNAME]="archlinux"
    CONFIG[SSH_ENABLED]="0"
    CONFIG[DESKTOP]=""
    CONFIG[GPU_DRIVER]=""
    CONFIG[BOOTLOADER]=""
    logger_debug \
        "Configuration initialized"
    return 0
}
#============================================================
# Get value
#============================================================
config_get()
{
    local key="${1:-}"
    config_require_key "$key" || \
        return 1
    if [[ ! -v "CONFIG[$key]" ]]
    then
        return 1
    fi
    printf '%s' \
        "${CONFIG[$key]}"
}
#============================================================
# Set value
#============================================================
config_set()
{
    local key="${1:-}"
    local value="${2-}"
    config_require_key "$key" || \
        return 1
    CONFIG["$key"]="$value"
    return 0
}
#============================================================
# Check key
#============================================================
config_exists()
{
    local key="${1:-}"
    config_require_key "$key" || \
        return 1
    [[ -v "CONFIG[$key]" ]]
}
#============================================================
# Clear value
#============================================================
config_unset()
{
    local key="${1:-}"
    config_require_key "$key" || \
        return 1
    CONFIG["$key"]=""
    return 0
}
#============================================================
# Encode value
#============================================================
config_encode()
{
    local value="${1-}"
    printf '%s' "$value" |
        base64 -w 0
}
#============================================================
# Decode value
#============================================================
config_decode()
{
    local value="${1-}"
    printf '%s' "$value" |
        base64 -d 2>/dev/null
}
#============================================================
# Save configuration
#============================================================
config_save()
{
    local key
    local encoded
    local tmp_file
    tmp_file="${CONFIG_FILE}.tmp.$$"
    logger_info \
        "Saving configuration: ${CONFIG_FILE}"
    {
        printf '%s\n' \
            '# Arch Installer configuration'
        printf '%s\n' \
            '# Generated automatically'
        printf '%s\n' \
            '# Values are base64 encoded'
        printf '%s\n' \
            ''
        for key in "${CONFIG_KEYS[@]}"
        do
            encoded="$(
                config_encode \
                    "${CONFIG[$key]}"
            )"
            printf '%s=%s\n' \
                "$key" \
                "$encoded"
        done
    } > "$tmp_file" || {
        logger_error \
            "Failed writing temporary configuration"
        rm -f \
            "$tmp_file"
        return 1
    }
    if ! chmod 600 \
        "$tmp_file"
    then
        logger_error \
            "Failed setting configuration permissions"
        rm -f \
            "$tmp_file"
        return 1
    fi
    if ! mv \
        -f \
        "$tmp_file" \
        "$CONFIG_FILE"
    then
        logger_error \
            "Failed installing configuration file"
        rm -f \
            "$tmp_file"
        return 1
    fi
    logger_info \
        "Configuration saved"
    return 0
}
#============================================================
# Load configuration
#============================================================
config_load()
{
    local line
    local key
    local encoded
    local value
    if [[ ! -f "$CONFIG_FILE" ]]
    then
        logger_debug \
            "Configuration file does not exist: ${CONFIG_FILE}"
        return 0
    fi
    logger_info \
        "Loading configuration: ${CONFIG_FILE}"
    while IFS= read -r line || [[ -n "$line" ]]
    do
        [[ -z "$line" ]] && \
            continue
        [[ "$line" == \#* ]] && \
            continue
        if [[ "$line" != *=* ]]
        then
            logger_warn \
                "Ignoring malformed configuration line"
            continue
        fi
        key="${line%%=*}"
        encoded="${line#*=}"
        if ! config_valid_key "$key"
        then
            logger_warn \
                "Ignoring invalid configuration key: ${key}"
            continue
        fi
        if [[ ! "$encoded" =~ ^[A-Za-z0-9+/]*={0,2}$ ]]
        then
            logger_warn \
                "Ignoring invalid encoded value for: ${key}"
            continue
        fi
        if ! value="$(
            config_decode \
                "$encoded"
        )"
        then
            logger_warn \
                "Failed decoding configuration key: ${key}"
            continue
        fi
        CONFIG["$key"]="$value"
    done < "$CONFIG_FILE"
    logger_info \
        "Configuration loaded"
    return 0
}
#============================================================
# Export
#============================================================
config_export()
{
    local key
    for key in "${CONFIG_KEYS[@]}"
    do
        printf -v \
            "$key" \
            '%s' \
            "${CONFIG[$key]}"
        export "$key"
    done
    return 0
}
#============================================================
# Dump
#============================================================
config_dump()
{
    local key
    printf '%s\n' \
        'Installer configuration'
    printf '%s\n' \
        '-----------------------'
    for key in "${CONFIG_KEYS[@]}"
    do
        printf '%-24s : %s\n' \
            "$key" \
            "${CONFIG[$key]}"
    done
}
#============================================================
# Reset
#============================================================
config_reset()
{
    logger_warn \
        "Resetting configuration"
    config_init
}
#============================================================
# Validation helpers
#============================================================
config_has_target_disk()
{
    [[ -n "$(config_get TARGET_DISK)" ]]
}
config_has_root()
{
    [[ -n "$(config_get ROOT_PART)" ]]
}
config_has_home()
{
    [[ -n "$(config_get HOME_PART)" ]]
}
config_has_efi()
{
    [[ -n "$(config_get EFI_PART)" ]]
}
config_has_user()
{
    [[ -n "$(config_get USER_NAME)" ]]
}
#============================================================
# Validate boot mode
#============================================================
config_validate_boot_mode()
{
    case "$(config_get BOOT_MODE)" in
        UEFI|BIOS)
            return 0
            ;;
        *)
            logger_error \
                "Invalid BOOT_MODE"
            return 1
            ;;
    esac
}
#============================================================
# Validate partition table
#============================================================
config_validate_partition_table()
{
    case "$(config_get PARTITION_TABLE)" in
        GPT|MBR)
            return 0
            ;;
        *)
            logger_error \
                "Invalid PARTITION_TABLE"
            return 1
            ;;
    esac
}
#============================================================
# Validate filesystem
#============================================================
config_validate_filesystem()
{
    case "$(config_get FILESYSTEM)" in
        ext4|btrfs|xfs|f2fs)
            return 0
            ;;
        *)
            logger_error \
                "Invalid FILESYSTEM"
            return 1
            ;;
    esac
}
#============================================================
# Validate swap
#============================================================
config_validate_swap()
{
    case "$(config_get SWAP_TYPE)" in
        none|partition|file)
            return 0
            ;;
        *)
            logger_error \
                "Invalid SWAP_TYPE"
            return 1
            ;;
    esac
}
#============================================================
# Validate boolean
#============================================================
config_validate_boolean()
{
    local key="$1"
    local value
    value="$(config_get "$key")"
    case "$value" in
        0|1)
            return 0
            ;;
        *)
            logger_error \
                "Invalid boolean ${key}: ${value}"
            return 1
            ;;
    esac
}
#============================================================
# Validate username
#============================================================
config_validate_user()
{
    local user
    user="$(config_get USER_NAME)"
    if [[ -z "$user" ]]
    then
        return 1
    fi
    [[ "$user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]
}
#============================================================
# Validate hostname
#============================================================
config_validate_hostname()
{
    local hostname
    local label
    local labels
    hostname="$(config_get HOSTNAME)"
    if [[ -z "$hostname" ]]
    then
        return 1
    fi
    if [[ ${#hostname} -gt 253 ]]
    then
        return 1
    fi
    if [[ "$hostname" =~ [^A-Za-z0-9.-] ]]
    then
        return 1
    fi
    if [[ "$hostname" == .* ||
          "$hostname" == *. ]]
    then
        return 1
    fi
    IFS='.' read -ra labels <<< "$hostname"
    for label in "${labels[@]}"
    do
        if [[ -z "$label" ]]
        then
            return 1
        fi
        if [[ ${#label} -gt 63 ]]
        then
            return 1
        fi
        if [[ "$label" == -* ||
              "$label" == *- ]]
        then
            return 1
        fi
    done
    return 0
}
#============================================================
# Validate desktop
#============================================================
config_validate_desktop()
{
    case "$(config_get DESKTOP)" in
        ""|gnome|kde|xfce)
            return 0
            ;;
        *)
            logger_error \
                "Invalid DESKTOP"
            return 1
            ;;
    esac
}
#============================================================
# Validate bootloader
#============================================================
config_validate_bootloader()
{
    case "$(config_get BOOTLOADER)" in
        ""|grub|systemd-boot)
            return 0
            ;;
        *)
            logger_error \
                "Invalid BOOTLOADER"
            return 1
            ;;
    esac
}
#============================================================
# Full validation
#============================================================
config_validate()
{
    config_validate_boot_mode || \
        return 1
    config_validate_partition_table || \
        return 1
    config_validate_filesystem || \
        return 1
    config_validate_swap || \
        return 1
    config_validate_boolean \
        CREATE_HOME || \
        return 1
    config_validate_boolean \
        NETWORK_ENABLED || \
        return 1
    config_validate_boolean \
        INSTALL_REFLECTOR || \
        return 1
    config_validate_boolean \
        SSH_ENABLED || \
        return 1
    config_validate_user || {
        logger_error \
            "Invalid USER_NAME"
        return 1
    }
    config_validate_hostname || {
        logger_error \
            "Invalid HOSTNAME"
        return 1
    }
    config_validate_desktop || \
        return 1
    config_validate_bootloader || \
        return 1
    if [[ "$(config_get BOOT_MODE)" == "UEFI" &&
          "$(config_get PARTITION_TABLE)" != "GPT" ]]
    then
        logger_error \
            "UEFI requires GPT"
        return 1
    fi
    if [[ "$(config_get BOOT_MODE)" == "BIOS" &&
          "$(config_get PARTITION_TABLE)" != "MBR" ]]
    then
        logger_error \
            "BIOS requires MBR"
        return 1
    fi
    if [[ "$(config_get CREATE_HOME)" == "1" &&
          -z "$(config_get HOME_SIZE)" ]]
    then
        logger_error \
            "HOME_SIZE is required when CREATE_HOME=1"
        return 1
    fi
    if [[ "$(config_get SWAP_TYPE)" == "partition" &&
          -z "$(config_get SWAP_SIZE)" ]]
    then
        logger_error \
            "SWAP_SIZE is required for partition swap"
        return 1
    fi
    logger_info \
        "Configuration validation passed"
    return 0
}
#============================================================
# Initialize from file
#============================================================
config_init_load()
{
    config_init
    config_load
}
#============================================================
# End
#============================================================
