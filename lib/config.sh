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

[[ -n "${CONFIG_SH_LOADED:-}" ]] && return

readonly CONFIG_SH_LOADED=1

#------------------------------------------------------------
# Configuration file
#------------------------------------------------------------

CONFIG_FILE="${CONFIG_FILE:-/tmp/arch-installer.conf}"

#------------------------------------------------------------
# Configuration storage
#------------------------------------------------------------

declare -gA CONFIG=()

#------------------------------------------------------------
# Key order
#------------------------------------------------------------

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

#------------------------------------------------------------
# Validate key
#------------------------------------------------------------

config_valid_key()
{
    local key="${1:-}"

    [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]
}

config_require_key()
{
    local key="${1:-}"

    if ! config_valid_key "$key"
    then
        logger_error \
            "Invalid configuration key: ${key}"

        return 1
    fi
}

#------------------------------------------------------------
# Initialize defaults
#------------------------------------------------------------

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
}

#------------------------------------------------------------
# Get value
#------------------------------------------------------------

config_get()
{
    local key="${1:-}"

    config_require_key "$key" || \
        return 1

    [[ -v "CONFIG[$key]" ]] || \
        return 1

    printf '%s' \
        "${CONFIG[$key]}"
}

#------------------------------------------------------------
# Set value
#------------------------------------------------------------

config_set()
{
    local key="${1:-}"
    local value="${2-}"

    config_require_key "$key" || \
        return 1

    CONFIG["$key"]="$value"
}

#------------------------------------------------------------
# Check key
#------------------------------------------------------------

config_exists()
{
    local key="${1:-}"

    config_require_key "$key" || \
        return 1

    [[ -v "CONFIG[$key]" ]]
}

#------------------------------------------------------------
# Clear value
#------------------------------------------------------------

config_unset()
{
    local key="${1:-}"

    config_require_key "$key" || \
        return 1

    CONFIG["$key"]=""
}

#------------------------------------------------------------
# Encode value
#------------------------------------------------------------

config_encode()
{
    local value="${1-}"

    printf '%s' \
        "$value" |
        base64 \
            -w 0
}

#------------------------------------------------------------
# Decode value
#------------------------------------------------------------

config_decode()
{
    local value="${1-}"

    printf '%s' \
        "$value" |
        base64 \
            -d \
            2>/dev/null
}

#------------------------------------------------------------
# Save configuration
#------------------------------------------------------------

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

            printf \
                '%s=%s\n' \
                "$key" \
                "$encoded"
        done
    } > "$tmp_file"

    chmod 600 \
        "$tmp_file"

    mv \
        -f \
        "$tmp_file" \
        "$CONFIG_FILE"

    logger_info \
        "Configuration saved"
}

#------------------------------------------------------------
# Load configuration
#------------------------------------------------------------

config_load()
{
    local line
    local key
    local encoded
    local value

    [[ -f "$CONFIG_FILE" ]] || \
        return 0

    logger_info \
        "Loading configuration: ${CONFIG_FILE}"

    while IFS= read -r line
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

        config_valid_key "$key" || {
            logger_warn \
                "Ignoring invalid configuration key: ${key}"

            continue
        }

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
}

#------------------------------------------------------------
# Export
#------------------------------------------------------------

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
}

#------------------------------------------------------------
# Dump
#------------------------------------------------------------

config_dump()
{
    local key

    printf '%s\n' \
        'Installer configuration'

    printf '%s\n' \
        '-----------------------'

    for key in "${CONFIG_KEYS[@]}"
    do
        printf \
            '%-24s : %s\n' \
            "$key" \
            "${CONFIG[$key]}"
    done
}

#------------------------------------------------------------
# Reset
#------------------------------------------------------------

config_reset()
{
    logger_warn \
        "Resetting configuration"

    config_init
}

#------------------------------------------------------------
# Validation helpers
#------------------------------------------------------------

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

#------------------------------------------------------------
# Validate enum-like values
#------------------------------------------------------------

config_validate_boot_mode()
{
    case "$(config_get BOOT_MODE)" in
        UEFI|BIOS)
            ;;
        *)
            logger_error \
                "Invalid BOOT_MODE"

            return 1
            ;;
    esac
}

config_validate_partition_table()
{
    case "$(config_get PARTITION_TABLE)" in
        GPT|MBR)
            ;;
        *)
            logger_error \
                "Invalid PARTITION_TABLE"

            return 1
            ;;
    esac
}

config_validate_filesystem()
{
    case "$(config_get FILESYSTEM)" in
        ext4|btrfs|xfs|f2fs)
            ;;
        *)
            logger_error \
                "Invalid FILESYSTEM"

            return 1
            ;;
    esac
}

config_validate_swap()
{
    case "$(config_get SWAP_TYPE)" in
        none|partition|file)
            ;;
        *)
            logger_error \
                "Invalid SWAP_TYPE"

            return 1
            ;;
    esac
}

config_validate_boolean()
{
    local key="$1"
    local value

    value="$(config_get "$key")"

    case "$value" in
        0|1)
            ;;
        *)
            logger_error \
                "Invalid boolean ${key}: ${value}"

            return 1
            ;;
    esac
}

config_validate_user()
{
    local user

    user="$(config_get USER_NAME)"

    [[ -n "$user" ]] || \
        return 1

    [[ "$user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]
}

config_validate_hostname()
{
    local hostname

    hostname="$(config_get HOSTNAME)"

    [[ -n "$hostname" ]] || \
        return 1

    [[ "$hostname" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]
}

#------------------------------------------------------------
# Full validation
#------------------------------------------------------------

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

    if [[ "$(config_get BOOT_MODE)" == "UEFI" &&
          "$(config_get PARTITION_TABLE)" != "GPT" ]]
    then
        logger_error \
            "UEFI requires GPT"

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
}

#------------------------------------------------------------
# Initialize from file
#------------------------------------------------------------

config_init_load()
{
    config_init

    config_load
}

#------------------------------------------------------------
# End
#------------------------------------------------------------