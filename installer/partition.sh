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
#============================================================

[[ -n "${PARTITION_SH_LOADED:-}" ]] && return

readonly PARTITION_SH_LOADED=1

#------------------------------------------------------------
# State
#------------------------------------------------------------

PARTITION_DISK=""
BOOT_MODE=""
PARTITION_TABLE=""

declare -a PARTITION_LAYOUT=()

EFI_PART=""
BIOS_PART=""
ROOT_PART=""
HOME_PART=""
SWAP_PART=""

#------------------------------------------------------------
# Load configuration
#------------------------------------------------------------

partition_load_config()
{
    PARTITION_DISK="$(config_get TARGET_DISK)"
    BOOT_MODE="$(config_get BOOT_MODE)"
    PARTITION_TABLE="$(config_get PARTITION_TABLE)"

    if [[ -z "$PARTITION_DISK" ]]
    then
        dialog_error \
            "Target disk not selected"

        return 1
    fi

    if [[ ! -b "$PARTITION_DISK" ]]
    then
        dialog_error \
            "Target disk does not exist: ${PARTITION_DISK}"

        return 1
    fi

    case "$BOOT_MODE" in
        UEFI|BIOS)
            ;;
        *)
            dialog_error \
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
                "Unsupported partition table: ${PARTITION_TABLE}"

            return 1
            ;;
    esac

    if [[ "$BOOT_MODE" == "UEFI" &&
          "$PARTITION_TABLE" != "GPT" ]]
    then
        dialog_error \
            "UEFI requires GPT partition table"

        return 1
    fi

    logger_info \
        "Disk: ${PARTITION_DISK}"

    logger_info \
        "Boot mode: ${BOOT_MODE}"

    logger_info \
        "Partition table: ${PARTITION_TABLE}"
}

#------------------------------------------------------------
# Validate configuration
#------------------------------------------------------------

partition_validate_config()
{
    local filesystem
    local swap_type
    local swap_size
    local home_size

    filesystem="$(config_get FILESYSTEM)"
    swap_type="$(config_get SWAP_TYPE)"
    swap_size="$(config_get SWAP_SIZE)"
    home_size="$(config_get HOME_SIZE)"

    case "$filesystem" in
        ext4|btrfs|xfs|f2fs)
            ;;
        *)
            dialog_error \
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
                    "SWAP_SIZE is required for swap partition"

                return 1
            fi
            ;;
        file)
            ;;
        *)
            dialog_error \
                "Unsupported swap type: ${swap_type}"

            return 1
            ;;
    esac

    if [[ "$(config_get CREATE_HOME)" == "1" &&
          -z "$home_size" ]]
    then
        dialog_error \
            "HOME_SIZE is required when home partition is enabled"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Build layout
#------------------------------------------------------------

partition_build_layout()
{
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
            "BIOS|bios_grub|2"
        )
    fi

    if [[ "$(config_get SWAP_TYPE)" == "partition" ]]
    then
        PARTITION_LAYOUT+=(
            "SWAP|swap|$(config_get SWAP_SIZE)"
        )
    fi

    #
    # HOME must be created before AUTO ROOT.
    #

    if [[ "$(config_get CREATE_HOME)" == "1" ]]
    then
        PARTITION_LAYOUT+=(
            "HOME|$(config_get FILESYSTEM)|$(config_get HOME_SIZE)"
        )
    fi

    #
    # ROOT is always last because it consumes
    # all remaining space.
    #

    PARTITION_LAYOUT+=(
        "ROOT|$(config_get FILESYSTEM)|AUTO"
    )

    logger_info \
        "Partition layout created"

    local item

    for item in "${PARTITION_LAYOUT[@]}"
    do
        logger_debug \
            "Layout: ${item}"
    done
}

#------------------------------------------------------------
# Partition name
#------------------------------------------------------------

partition_name()
{
    local disk="$1"
    local number="$2"

    case "$disk" in
        /dev/nvme*|/dev/mmcblk*)
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

#------------------------------------------------------------
# Create partition table
#------------------------------------------------------------

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
                gpt
            ;;
        MBR)
            parted \
                -s \
                "$PARTITION_DISK" \
                mklabel \
                msdos
            ;;
        *)
            dialog_error \
                "Unknown partition table: ${PARTITION_TABLE}"

            return 1
            ;;
    esac
}

#------------------------------------------------------------
# Create single partition
#------------------------------------------------------------

partition_create()
{
    local number="$1"
    local name="$2"
    local type="$3"
    local start_mib="$4"
    local end_mib="$5"

    logger_info \
        "Creating ${name}: ${start_mib}MiB-${end_mib}MiB"

    case "$type" in
        fat32)
            parted \
                -s \
                -a optimal \
                "$PARTITION_DISK" \
                mkpart \
                "$name" \
                fat32 \
                "${start_mib}MiB" \
                "${end_mib}MiB"

            parted \
                -s \
                "$PARTITION_DISK" \
                set \
                "$number" \
                esp \
                on
            ;;
        bios_grub)
            parted \
                -s \
                "$PARTITION_DISK" \
                mkpart \
                "$name" \
                "${start_mib}MiB" \
                "${end_mib}MiB"

            parted \
                -s \
                "$PARTITION_DISK" \
                set \
                "$number" \
                bios_grub \
                on
            ;;
        swap)
            parted \
                -s \
                -a optimal \
                "$PARTITION_DISK" \
                mkpart \
                "$name" \
                linux-swap \
                "${start_mib}MiB" \
                "${end_mib}MiB"
            ;;
        ext4|btrfs|xfs|f2fs)
            parted \
                -s \
                -a optimal \
                "$PARTITION_DISK" \
                mkpart \
                "$name" \
                "$type" \
                "${start_mib}MiB" \
                "${end_mib}MiB"
            ;;
        *)
            dialog_error \
                "Unsupported partition type: ${type}"

            return 1
            ;;
    esac
}

#------------------------------------------------------------
# Create layout
#------------------------------------------------------------

partition_create_layout()
{
    local number=1
    local start_mib=1

    local item
    local name
    local type
    local size

    local end_mib

    for item in "${PARTITION_LAYOUT[@]}"
    do
        IFS='|' read -r \
            name \
            type \
            size <<< "$item"

        if [[ "$size" == "AUTO" ]]
        then
            end_mib=100%

            partition_create \
                "$number" \
                "$name" \
                "$type" \
                "$start_mib" \
                "$end_mib"

        else
            if ! [[ "$size" =~ ^[0-9]+([.][0-9]+)?$ ]]
            then
                dialog_error \
                    "Invalid partition size for ${name}: ${size}"

                return 1
            fi

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
                "$end_mib"
        fi

        case "$name" in
            EFI)
                EFI_PART="$(
                    partition_name \
                        "$PARTITION_DISK" \
                        "$number"
                )
                ;;
            BIOS)
                BIOS_PART="$(
                    partition_name \
                        "$PARTITION_DISK" \
                        "$number"
                )
                ;;
            ROOT)
                ROOT_PART="$(
                    partition_name \
                        "$PARTITION_DISK" \
                        "$number"
                )
                ;;
            HOME)
                HOME_PART="$(
                    partition_name \
                        "$PARTITION_DISK" \
                        "$number"
                )
                ;;
            SWAP)
                SWAP_PART="$(
                    partition_name \
                        "$PARTITION_DISK" \
                        "$number"
                )
                ;;
        esac

        if [[ "$size" == "AUTO" ]]
        then
            break
        fi

        start_mib="$end_mib"

        ((number++))
    done

    logger_info \
        "Partition layout created successfully"
}

#------------------------------------------------------------
# Reload kernel partition table
#------------------------------------------------------------

partition_reload()
{
    logger_info \
        "Reloading kernel partition table"

    partprobe \
        "$PARTITION_DISK"

    udevadm settle

    logger_info \
        "Kernel partition table synchronized"
}

#------------------------------------------------------------
# Prepare swap file
#------------------------------------------------------------

partition_prepare_swap_file()
{
    if [[ "$(config_get SWAP_TYPE)" != "file" ]]
    then
        return 0
    fi

    config_set \
        SWAP_FILE \
        "/swapfile"

    logger_info \
        "Swap file configured: /swapfile"
}

#------------------------------------------------------------
# Save result
#------------------------------------------------------------

partition_save()
{
    config_set \
        EFI_PART \
        "$EFI_PART"

    config_set \
        BIOS_PART \
        "$BIOS_PART"

    config_set \
        ROOT_PART \
        "$ROOT_PART"

    config_set \
        HOME_PART \
        "$HOME_PART"

    config_set \
        SWAP_PART \
        "$SWAP_PART"

    logger_info \
        "Partition state saved to configuration"
}

#------------------------------------------------------------
# Check result
#------------------------------------------------------------

partition_check()
{
    if [[ -z "$ROOT_PART" ||
          ! -b "$ROOT_PART" ]]
    then
        dialog_error \
            "Root partition was not created: ${ROOT_PART:-empty}"

        return 1
    fi

    if [[ "$(config_get CREATE_HOME)" == "1" ]]
    then
        if [[ -z "$HOME_PART" ||
              ! -b "$HOME_PART" ]]
        then
            dialog_error \
                "Home partition was not created: ${HOME_PART:-empty}"

            return 1
        fi
    fi

    if [[ "$(config_get BOOT_MODE)" == "UEFI" ]]
    then
        if [[ -z "$EFI_PART" ||
              ! -b "$EFI_PART" ]]
        then
            dialog_error \
                "EFI partition was not created: ${EFI_PART:-empty}"

            return 1
        fi
    fi

    if [[ "$(config_get SWAP_TYPE)" == "partition" ]]
    then
        if [[ -z "$SWAP_PART" ||
              ! -b "$SWAP_PART" ]]
        then
            dialog_error \
                "Swap partition was not created: ${SWAP_PART:-empty}"

            return 1
        fi
    fi

    logger_info \
        "Partition check passed"
}

#------------------------------------------------------------
# Reset state
#------------------------------------------------------------

partition_reset_state()
{
    PARTITION_LAYOUT=()

    EFI_PART=""
    BIOS_PART=""
    ROOT_PART=""
    HOME_PART=""
    SWAP_PART=""
}

#------------------------------------------------------------
# Main
#------------------------------------------------------------

partition()
{
    logger_info \
        "Partitioning started"

    partition_reset_state

    partition_load_config || \
        return 1

    partition_validate_config || \
        return 1

    dialog_confirm \
        "WARNING

ALL DATA ON

${PARTITION_DISK}

WILL BE PERMANENTLY ERASED.

Continue?" || return 1

    logger_warn \
        "Wiping filesystem signatures on ${PARTITION_DISK}"

    wipefs \
        -af \
        "$PARTITION_DISK"

    partition_build_layout

    partition_create_table || \
        return 1

    partition_create_layout || \
        return 1

    partition_reload || \
        return 1

    partition_check || \
        return 1

    partition_prepare_swap_file

    partition_save

    config_save

    dialog_message \
        "Partitioning" \
        "Completed successfully"

    logger_info \
        "Partitioning finished"
}