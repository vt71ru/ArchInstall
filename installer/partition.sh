#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  partition.sh
#
#  Создание схемы разделов.
#
#  Поддерживает:
#   • UEFI + GPT
#   • BIOS + GPT
#   • BIOS + MBR
#   • root без home
#   • root + home
#   • swap-раздел
#   • swap-файл
#
#  Не форматирует разделы.
#
#  ВАЖНО:
#   Модуль выполняет destructive operations.
#============================================================

if [[ -n "${PARTITION_SH_LOADED:-}" ]]
then
    return 0
fi

readonly PARTITION_SH_LOADED=1

#============================================================
# State
#============================================================

PARTITION_DISK=""
BOOT_MODE=""
PARTITION_TABLE=""

declare -ga PARTITION_LAYOUT=()

EFI_PART=""
BIOS_PART=""
ROOT_PART=""
HOME_PART=""
SWAP_PART=""

#============================================================
# Reset runtime state
#============================================================

partition_reset_state()
{
    PARTITION_DISK=""
    BOOT_MODE=""
    PARTITION_TABLE=""

    PARTITION_LAYOUT=()

    EFI_PART=""
    BIOS_PART=""
    ROOT_PART=""
    HOME_PART=""
    SWAP_PART=""
}

#============================================================
# Validate required tools
#============================================================

partition_check_dependencies()
{
    local command_name

    local required=(
        parted
        wipefs
        partprobe
        udevadm
        lsblk
        findmnt
        swapon
        awk
    )

    for command_name in "${required[@]}"
    do
        if ! command -v "$command_name" >/dev/null 2>&1
        then
            if declare -F dialog_error >/dev/null 2>&1
            then
                dialog_error \
                    "Partition" \
                    "Missing required program: ${command_name}"
            fi

            if declare -F logger_error >/dev/null 2>&1
            then
                logger_error \
                    "Partition dependency missing: ${command_name}"
            fi

            return 1
        fi
    done

    return 0
}

#============================================================
# Load configuration
#============================================================

partition_load_config()
{
    PARTITION_DISK="$(
        config_get TARGET_DISK
    )"

    BOOT_MODE="$(
        config_get BOOT_MODE
    )"

    PARTITION_TABLE="$(
        config_get PARTITION_TABLE
    )"

    if [[ -z "$PARTITION_DISK" ]]
    then
        dialog_error \
            "Partition" \
            "Target disk not selected"

        return 1
    fi

    if [[ ! -b "$PARTITION_DISK" ]]
    then
        dialog_error \
            "Partition" \
            "Target disk does not exist: ${PARTITION_DISK}"

        return 1
    fi

    case "$BOOT_MODE" in
        UEFI|BIOS)
            ;;

        *)
            dialog_error \
                "Partition" \
                "Unsupported boot mode: ${BOOT_MODE:-empty}"

            return 1
            ;;
    esac

    case "$PARTITION_TABLE" in

        GPT|MBR)
            ;;

        "")
            if [[ "$BOOT_MODE" == "UEFI" ]]
            then
                PARTITION_TABLE="GPT"
            else
                PARTITION_TABLE="MBR"
            fi

            config_set \
                PARTITION_TABLE \
                "$PARTITION_TABLE"
            ;;

        *)
            dialog_error \
                "Partition" \
                "Unsupported partition table: ${PARTITION_TABLE}"

            return 1
            ;;

    esac

    if [[ "$BOOT_MODE" == "UEFI" &&
          "$PARTITION_TABLE" != "GPT" ]]
    then
        dialog_error \
            "Partition" \
            "UEFI requires GPT partition table"

        return 1
    fi

    logger_info \
        "Disk: ${PARTITION_DISK}"

    logger_info \
        "Boot mode: ${BOOT_MODE}"

    logger_info \
        "Partition table: ${PARTITION_TABLE}"

    return 0
}

#============================================================
# Check disk safety
#============================================================

partition_check_disk_safety()
{
    local mount_source=""
    local swap_device=""

    if findmnt \
        -rn \
        -S "$PARTITION_DISK" \
        >/dev/null 2>&1
    then
        dialog_error \
            "Partition" \
            "Target disk is currently mounted: ${PARTITION_DISK}"

        logger_error \
            "Refusing to partition mounted disk: ${PARTITION_DISK}"

        return 1
    fi

    while IFS= read -r mount_source
    do
        [[ -z "$mount_source" ]] && continue

        if [[ "$mount_source" == "$PARTITION_DISK"* ]]
        then
            dialog_error \
                "Partition" \
                "A partition of target disk is mounted: ${mount_source}"

            logger_error \
                "Mounted target-disk partition: ${mount_source}"

            return 1
        fi

    done < <(
        findmnt \
            -rn \
            -o SOURCE
    )

    while IFS= read -r swap_device
    do
        [[ -z "$swap_device" ]] && continue

        if [[ "$swap_device" == "$PARTITION_DISK"* ]]
        then
            dialog_error \
                "Partition" \
                "Target disk has active swap: ${swap_device}"

            logger_error \
                "Active swap on target disk: ${swap_device}"

            return 1
        fi

    done < <(
        swapon \
            --show=NAME \
            --noheadings \
            2>/dev/null || true
    )

    return 0
}

#============================================================
# Validate configuration
#============================================================

partition_validate_config()
{
    local filesystem=""
    local swap_type=""
    local swap_size=""
    local home_size=""
    local create_home=""

    filesystem="$(config_get FILESYSTEM)"
    swap_type="$(config_get SWAP_TYPE)"
    swap_size="$(config_get SWAP_SIZE)"
    home_size="$(config_get HOME_SIZE)"
    create_home="$(config_get CREATE_HOME)"

    case "$filesystem" in
        ext4|btrfs|xfs|f2fs)
            ;;

        *)
            dialog_error \
                "Partition" \
                "Unsupported filesystem: ${filesystem}"

            return 1
            ;;
    esac

    case "$swap_type" in

        none)
            ;;

        partition)
            if [[ -z "$swap_size" ]]
            then
                dialog_error \
                    "Partition" \
                    "SWAP_SIZE is required for swap partition"

                return 1
            fi

            if ! [[ "$swap_size" =~ ^[0-9]+([.][0-9]+)?$ ]]
            then
                dialog_error \
                    "Partition" \
                    "Invalid SWAP_SIZE: ${swap_size}"

                return 1
            fi
            ;;

        file)
            ;;

        *)
            dialog_error \
                "Partition" \
                "Unsupported swap type: ${swap_type}"

            return 1
            ;;

    esac

    if [[ "$create_home" == "1" ]]
    then
        if [[ -z "$home_size" ]]
        then
            dialog_error \
                "Partition" \
                "HOME_SIZE is required when home partition is enabled"

            return 1
        fi

        if ! [[ "$home_size" =~ ^[0-9]+([.][0-9]+)?$ ]]
        then
            dialog_error \
                "Partition" \
                "Invalid HOME_SIZE: ${home_size}"

            return 1
        fi
    fi

    return 0
}

#============================================================
# Build layout
#============================================================

partition_build_layout()
{
    local filesystem=""
    local swap_type=""
    local create_home=""

    filesystem="$(config_get FILESYSTEM)"
    swap_type="$(config_get SWAP_TYPE)"
    create_home="$(config_get CREATE_HOME)"

    PARTITION_LAYOUT=()

    if [[ "$BOOT_MODE" == "UEFI" ]]
    then
        PARTITION_LAYOUT+=(
            "EFI|fat32|512"
        )
    fi

    if [[ "$BOOT_MODE" == "BIOS" &&
          "$PARTITION_TABLE" == "GPT" ]]
    then
        PARTITION_LAYOUT+=(
            "BIOS|bios_grub|1"
        )
    fi

    if [[ "$swap_type" == "partition" ]]
    then
        PARTITION_LAYOUT+=(
            "SWAP|swap|$(config_get SWAP_SIZE)"
        )
    fi

    if [[ "$create_home" == "1" ]]
    then
        PARTITION_LAYOUT+=(
            "HOME|${filesystem}|$(config_get HOME_SIZE)"
        )
    fi

    PARTITION_LAYOUT+=(
        "ROOT|${filesystem}|AUTO"
    )

    logger_info \
        "Partition layout created"

    local item

    for item in "${PARTITION_LAYOUT[@]}"
    do
        logger_debug \
            "Layout: ${item}"
    done

    return 0
}

#============================================================
# Validate layout
#============================================================

partition_validate_layout()
{
    local item=""
    local name=""
    local type=""
    local size=""

    for item in "${PARTITION_LAYOUT[@]}"
    do
        IFS='|' read -r \
            name \
            type \
            size <<< "$item"

        case "$name" in

            EFI|BIOS|SWAP|HOME)
                ;;

            ROOT)
                if [[ "$size" != "AUTO" ]]
                then
                    logger_error \
                        "ROOT partition must use AUTO size"

                    return 1
                fi
                ;;

            *)
                logger_error \
                    "Unknown partition layout item: ${name}"

                return 1
                ;;

        esac

        case "$type" in
            fat32|bios_grub|swap|ext4|btrfs|xfs|f2fs)
                ;;

            *)
                logger_error \
                    "Unknown partition type: ${type}"

                return 1
                ;;

        esac

        if [[ "$size" != "AUTO" &&
              ! "$size" =~ ^[0-9]+([.][0-9]+)?$ ]]
        then
            logger_error \
                "Invalid partition size: ${name}=${size}"

            return 1
        fi
    done

    return 0
}

#============================================================
# Partition name
#============================================================

partition_name()
{
    local disk="${1:-}"
    local number="${2:-}"

    if [[ -z "$disk" ||
          -z "$number" ]]
    then
        return 1
    fi

    case "$disk" in

        /dev/nvme*|/dev/mmcblk*|/dev/loop*)
            printf '%sp%s' \
                "$disk" \
                "$number"
            ;;

        *)
            printf '%s%s' \
                "$disk" \
                "$number"
            ;;

    esac
}

#============================================================
# Create partition table
#============================================================

partition_create_table()
{
    logger_warn \
        "Creating partition table: ${PARTITION_TABLE}"

    case "$PARTITION_TABLE" in

        GPT)
            parted \
                -s \
                "$PARTITION_DISK" \
                mklabel \
                gpt || return 1
            ;;

        MBR)
            parted \
                -s \
                "$PARTITION_DISK" \
                mklabel \
                msdos || return 1
            ;;

        *)
            dialog_error \
                "Partition" \
                "Unknown partition table: ${PARTITION_TABLE}"

            return 1
            ;;

    esac

    return 0
}

#============================================================
# Create single partition
#============================================================

partition_create()
{
    local number="${1:-}"
    local name="${2:-}"
    local type="${3:-}"
    local start_mib="${4:-}"
    local end_mib="${5:-}"

    if [[ -z "$number" ||
          -z "$name" ||
          -z "$type" ||
          -z "$start_mib" ||
          -z "$end_mib" ]]
    then
        logger_error \
            "Invalid partition_create arguments"

        return 1
    fi

    logger_info \
        "Creating ${name}: ${start_mib}MiB-${end_mib}MiB"

    case "$PARTITION_TABLE:$type" in

        GPT:fat32)
            parted \
                -s \
                -a optimal \
                "$PARTITION_DISK" \
                mkpart \
                "$name" \
                fat32 \
                "${start_mib}MiB" \
                "${end_mib}MiB" || return 1

            parted \
                -s \
                "$PARTITION_DISK" \
                set \
                "$number" \
                esp \
                on || return 1
            ;;

        GPT:bios_grub)
            parted \
                -s \
                "$PARTITION_DISK" \
                mkpart \
                "$name" \
                "${start_mib}MiB" \
                "${end_mib}MiB" || return 1

            parted \
                -s \
                "$PARTITION_DISK" \
                set \
                "$number" \
                bios_grub \
                on || return 1
            ;;

        GPT:swap)
            parted \
                -s \
                -a optimal \
                "$PARTITION_DISK" \
                mkpart \
                "$name" \
                linux-swap \
                "${start_mib}MiB" \
                "${end_mib}MiB" || return 1
            ;;

        GPT:ext4|GPT:btrfs|GPT:xfs|GPT:f2fs)
            parted \
                -s \
                -a optimal \
                "$PARTITION_DISK" \
                mkpart \
                "$name" \
                "$type" \
                "${start_mib}MiB" \
                "${end_mib}MiB" || return 1
            ;;

        MBR:fat32|MBR:swap|MBR:ext4|MBR:btrfs|MBR:xfs|MBR:f2fs)
            parted \
                -s \
                -a optimal \
                "$PARTITION_DISK" \
                mkpart \
                primary \
                "$type" \
                "${start_mib}MiB" \
                "${end_mib}MiB" || return 1
            ;;

        *)
            dialog_error \
                "Partition" \
                "Unsupported partition/table combination: ${PARTITION_TABLE}/${type}"

            return 1
            ;;

    esac

    if [[ "$PARTITION_TABLE" == "MBR" &&
          "$name" == "ROOT" ]]
    then
        parted \
            -s \
            "$PARTITION_DISK" \
            set \
            "$number" \
            boot \
            on || return 1
    fi

    return 0
}

#============================================================
# Create layout
#============================================================

partition_create_layout()
{
    local number=1
    local start_mib="1"

    local item=""
    local name=""
    local type=""
    local size=""
    local end_mib=""

    for item in "${PARTITION_LAYOUT[@]}"
    do
        IFS='|' read -r \
            name \
            type \
            size <<< "$item"

        if [[ "$size" == "AUTO" ]]
        then
            end_mib="100%"

            partition_create \
                "$number" \
                "$name" \
                "$type" \
                "$start_mib" \
                "$end_mib" || return 1
        else
            end_mib="$(
                awk \
                    -v start="$start_mib" \
                    -v size="$size" \
                    'BEGIN { printf "%.3f", start + size }'
            )"

            partition_create \
                "$number" \
                "$name" \
                "$type" \
                "$start_mib" \
                "$end_mib" || return 1
        fi

        case "$name" in

            EFI)
                EFI_PART="$(
                    partition_name \
                        "$PARTITION_DISK" \
                        "$number"
                )"
                ;;

            BIOS)
                BIOS_PART="$(
                    partition_name \
                        "$PARTITION_DISK" \
                        "$number"
                )"
                ;;

            ROOT)
                ROOT_PART="$(
                    partition_name \
                        "$PARTITION_DISK" \
                        "$number"
                )"
                ;;

            HOME)
                HOME_PART="$(
                    partition_name \
                        "$PARTITION_DISK" \
                        "$number"
                )"
                ;;

            SWAP)
                SWAP_PART="$(
                    partition_name \
                        "$PARTITION_DISK" \
                        "$number"
                )"
                ;;

        esac

        if [[ "$size" == "AUTO" ]]
        then
            break
        fi

        start_mib="$end_mib"
        number=$((number + 1))
    done

    logger_info \
        "Partition layout created successfully"

    return 0
}

#============================================================
# Reload kernel partition table
#============================================================

partition_reload()
{
    logger_info \
        "Reloading kernel partition table"

    if ! partprobe "$PARTITION_DISK"
    then
        logger_error \
            "partprobe failed for ${PARTITION_DISK}"

        return 1
    fi

    if ! udevadm settle
    then
        logger_error \
            "udevadm settle failed"

        return 1
    fi

    logger_info \
        "Kernel partition table synchronized"

    return 0
}

#============================================================
# Prepare swap file
#============================================================

partition_prepare_swap_file()
{
    if [[ "$(config_get SWAP_TYPE)" != "file" ]]
    then
        return 0
    fi

    config_set \
        SWAP_FILE \
        "/swapfile" || return 1

    logger_info \
        "Swap file configured: /swapfile"

    return 0
}

#============================================================
# Save result
#============================================================

partition_save()
{
    config_set EFI_PART "$EFI_PART" || return 1
    config_set BIOS_PART "$BIOS_PART" || return 1
    config_set ROOT_PART "$ROOT_PART" || return 1
    config_set HOME_PART "$HOME_PART" || return 1
    config_set SWAP_PART "$SWAP_PART" || return 1

    logger_info \
        "Partition state saved to configuration"

    return 0
}

#============================================================
# Check result
#============================================================

partition_check()
{
    if [[ -z "$ROOT_PART" ||
          ! -b "$ROOT_PART" ]]
    then
        dialog_error \
            "Partition" \
            "Root partition was not created: ${ROOT_PART:-empty}"

        return 1
    fi

    if [[ "$BOOT_MODE" == "UEFI" ]]
    then
        if [[ -z "$EFI_PART" ||
              ! -b "$EFI_PART" ]]
        then
            dialog_error \
                "Partition" \
                "EFI partition was not created: ${EFI_PART:-empty}"

            return 1
        fi
    fi

    if [[ "$BOOT_MODE" == "BIOS" &&
          "$PARTITION_TABLE" == "GPT" ]]
    then
        if [[ -z "$BIOS_PART" ||
              ! -b "$BIOS_PART" ]]
        then
            dialog_error \
                "Partition" \
                "BIOS boot partition was not created: ${BIOS_PART:-empty}"

            return 1
        fi
    fi

    if [[ "$(config_get CREATE_HOME)" == "1" ]]
    then
        if [[ -z "$HOME_PART" ||
              ! -b "$HOME_PART" ]]
        then
            dialog_error \
                "Partition" \
                "Home partition was not created: ${HOME_PART:-empty}"

            return 1
        fi
    fi

    if [[ "$(config_get SWAP_TYPE)" == "partition" ]]
    then
        if [[ -z "$SWAP_PART" ||
              ! -b "$SWAP_PART" ]]
        then
            dialog_error \
                "Partition" \
                "Swap partition was not created: ${SWAP_PART:-empty}"

            return 1
        fi
    fi

    logger_info \
        "Partition check passed"

    return 0
}

#============================================================
# Show resulting layout
#============================================================

partition_show_result()
{
    logger_info \
        "Final partition layout:"

    lsblk \
        -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINTS \
        "$PARTITION_DISK" || true
}

#============================================================
# Main entry point
#============================================================

partition()
{
    logger_info \
        "Partitioning started"

    partition_reset_state

    partition_check_dependencies || return 1
    partition_load_config || return 1
    partition_validate_config || return 1
    partition_check_disk_safety || return 1
    partition_build_layout || return 1
    partition_validate_layout || return 1

    if ! dialog_confirm \
        "WARNING

ALL DATA ON

${PARTITION_DISK}

WILL BE PERMANENTLY ERASED.

Continue?"
    then
        logger_info \
            "Partitioning cancelled by user"

        return 1
    fi

    logger_warn \
        "Wiping filesystem signatures on ${PARTITION_DISK}"

    if ! wipefs \
        -af \
        "$PARTITION_DISK"
    then
        dialog_error \
            "Partition" \
            "Failed to wipe filesystem signatures"

        return 1
    fi

    partition_create_table || return 1
    partition_create_layout || return 1
    partition_reload || return 1
    partition_check || return 1
    partition_prepare_swap_file || return 1
    partition_save || return 1

    if ! config_save
    then
        logger_error \
            "Failed to save partition configuration"

        return 1
    fi

    partition_show_result

    dialog_message \
        "Partitioning" \
        "Completed successfully"

    logger_info \
        "Partitioning finished"

    return 0
}

#============================================================
# End
#============================================================
