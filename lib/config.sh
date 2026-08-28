#!/usr/bin/env bash
#
#============================================================
# Arch Installer
#------------------------------------------------------------
# config.sh
#
# Центральное хранилище конфигурации.
#============================================================

if [[ -n "${CONFIG_SH_LOADED:-}" ]]
then
    return 0
fi

readonly CONFIG_SH_LOADED=1

: "${CONFIG_FILE:=/tmp/arch-installer.conf}"

declare -gA CONFIG=()

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

declare -gA CONFIG_KNOWN_KEYS=()

config_build_key_index()
{
    local key

    CONFIG_KNOWN_KEYS=()

    for key in "${CONFIG_KEYS[@]}"
    do
        CONFIG_KNOWN_KEYS["$key"]=1
    done
}

config_valid_key()
{
    [[ "${1:-}" =~ ^[A-Z][A-Z0-9_]*$ ]]
}

config_known_key()
{
    local key="${1:-}"

    config_valid_key "$key" &&
    [[ -v "CONFIG_KNOWN_KEYS[$key]" ]]
}

config_require_key()
{
    local key="${1:-}"

    if ! config_known_key "$key"
    then
        logger_error \
            "Unknown configuration key: ${key}"

        return 1
    fi
}

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

config_get()
{
    local key="${1:-}"

    config_require_key "$key" || \
        return 1

    printf '%s' \
        "${CONFIG[$key]}"
}

config_set()
{
    local key="${1:-}"
    local value="${2-}"

    config_require_key "$key" || \
        return 1

    CONFIG["$key"]="$value"
}

config_exists()
{
    local key="${1:-}"

    config_require_key "$key" || \
        return 1

    [[ -v "CONFIG[$key]" ]]
}

config_reset()
{
    logger_warn \
        "Configuration reset"

    config_init
}

config_encode()
{
    printf '%s' \
        "${1-}" |
        base64 -w 0
}

config_decode()
{
    printf '%s' \
        "${1-}" |
        base64 -d 2>/dev/null
}

config_save()
{
    local tmp_file
    local key
    local encoded

    tmp_file="$(
        mktemp \
            "${CONFIG_FILE}.tmp.XXXXXX"
    )" || {
        logger_error \
            "Cannot create temporary configuration file"

        return 1
    }

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
            )" || {
                rm -f -- "$tmp_file"
                return 1
            }

            printf '%s=%s\n' \
                "$key" \
                "$encoded"
        done
    } > "$tmp_file" || {
        rm -f -- "$tmp_file"
        return 1
    }

    chmod 600 \
        "$tmp_file" || {
        rm -f -- "$tmp_file"
        return 1
    }

    mv -f \
        "$tmp_file" \
        "$CONFIG_FILE"
}

config_load()
{
    local line
    local key
    local encoded
    local value

    if [[ ! -f "$CONFIG_FILE" ]]
    then
        return 0
    fi

    while IFS= read -r line ||
          [[ -n "$line" ]]
    do
        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue

        if [[ "$line" != *=* ]]
        then
            logger_warn \
                "Ignoring malformed configuration line"

            continue
        fi

        key="${line%%=*}"
        encoded="${line#*=}"

        if ! config_known_key "$key"
        then
            logger_warn \
                "Ignoring unknown configuration key: ${key}"

            continue
        fi

        if [[ ! "$encoded" =~ ^[A-Za-z0-9+/]*={0,2}$ ]]
        then
            logger_warn \
                "Ignoring invalid value for: ${key}"

            continue
        fi

        if ! value="$(
            config_decode "$encoded"
        )"
        then
            logger_warn \
                "Failed decoding: ${key}"

            continue
        fi

        CONFIG["$key"]="$value"

    done < "$CONFIG_FILE"
}

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

config_init_load()
{
    config_build_key_index
    config_init
    config_load
}

config_validate_boolean()
{
    local key="$1"
    local value

    value="$(config_get "$key")"

    [[ "$value" == "0" ||
       "$value" == "1" ]]
}

config_validate_user()
{
    local user

    user="$(config_get USER_NAME)"

    [[ "$user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]
}

config_validate_hostname()
{
    local hostname
    local label
    local labels

    hostname="$(config_get HOSTNAME)"

    if [[ -z "$hostname" ||
          ${#hostname} -gt 253 ]]
    then
        return 1
    fi

    [[ "$hostname" != .* &&
       "$hostname" != *. &&
       ! "$hostname" =~ [^A-Za-z0-9.-] ]] || \
        return 1

    IFS='.' read -ra labels <<< "$hostname"

    for label in "${labels[@]}"
    do
        [[ -n "$label" ]] || return 1
        (( ${#label} <= 63 )) || return 1

        [[ "$label" != -* &&
           "$label" != *- ]] || \
            return 1
    done

    return 0
}

config_validate()
{
    case "$(config_get BOOT_MODE)"
    in
        UEFI|BIOS)
            ;;

        *)
            logger_error "Invalid BOOT_MODE"
            return 1
            ;;
    esac

    case "$(config_get PARTITION_TABLE)"
    in
        GPT|MBR)
            ;;

        *)
            logger_error "Invalid PARTITION_TABLE"
            return 1
            ;;
    esac

    case "$(config_get FILESYSTEM)"
    in
        ext4|btrfs|xfs|f2fs)
            ;;

        *)
            logger_error "Invalid FILESYSTEM"
            return 1
            ;;
    esac

    case "$(config_get SWAP_TYPE)"
    in
        none|partition|file)
            ;;

        *)
            logger_error "Invalid SWAP_TYPE"
            return 1
            ;;
    esac

    config_validate_boolean CREATE_HOME || return 1
    config_validate_boolean NETWORK_ENABLED || return 1
    config_validate_boolean INSTALL_REFLECTOR || return 1
    config_validate_boolean SSH_ENABLED || return 1

    config_validate_user || {
        logger_error "Invalid USER_NAME"
        return 1
    }

    config_validate_hostname || {
        logger_error "Invalid HOSTNAME"
        return 1
    }

    case "$(config_get DESKTOP)"
    in
        ""|gnome|kde|xfce)
            ;;

        *)
            logger_error "Invalid DESKTOP"
            return 1
            ;;
    esac

    case "$(config_get BOOTLOADER)"
    in
        ""|grub|systemd-boot)
            ;;

        *)
            logger_error "Invalid BOOTLOADER"
            return 1
            ;;
    esac

    if [[ "$(config_get BOOT_MODE)" == "UEFI" &&
          "$(config_get PARTITION_TABLE)" != "GPT" ]]
    then
        logger_error \
            "UEFI requires GPT"

        return 1
    fi

    if [[ "$(config_get BOOTLOADER)" == "systemd-boot" &&
          "$(config_get BOOT_MODE)" != "UEFI" ]]
    then
        logger_error \
            "systemd-boot requires UEFI"

        return 1
    fi

    if [[ "$(config_get CREATE_HOME)" == "1" &&
          -z "$(config_get HOME_SIZE)" ]]
    then
        logger_error \
            "HOME_SIZE is required"

        return 1
    fi

    if [[ "$(config_get SWAP_TYPE)" == "partition" &&
          -z "$(config_get SWAP_SIZE)" ]]
    then
        logger_error \
            "SWAP_SIZE is required"

        return 1
    fi

    return 0
}

config_dump()
{
    local key

    for key in "${CONFIG_KEYS[@]}"
    do
        printf \
            '%-24s = %s\n' \
            "$key" \
            "${CONFIG[$key]}"
    done
}
