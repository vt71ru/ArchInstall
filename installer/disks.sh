#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  disks.sh
#
#  Выбор диска установки.
#
#  Ответственность:
#   • Поиск физических дисков
#   • Отображение размера/модели/интерфейса
#   • Проверка состояния диска
#   • Выбор целевого диска
#   • Сохранение TARGET_DISK в config.sh
#
#  Не выполняет:
#   • Разметку
#   • Форматирование
#   • Монтирование
#============================================================

[[ -n "${DISKS_SH_LOADED:-}" ]] && return

readonly DISKS_SH_LOADED=1

#------------------------------------------------------------
# State
#------------------------------------------------------------

declare -a DISK_LIST=()

DISK_SELECTED=0
DISK_OFFSET=0

readonly DISK_PAGE_SIZE=12

#------------------------------------------------------------
# Load disks
#------------------------------------------------------------

disks_load()
{
    DISK_LIST=()
    DISK_SELECTED=0
    DISK_OFFSET=0

    local name
    local size
    local type
    local model
    local tran

    while read -r name size type model tran
    do
        [[ "$type" == "disk" ]] || \
            continue

        if [[ "${HIDE_USB_INSTALL_MEDIA:-0}" == "1" &&
              "$tran" == "usb" ]]
        then
            continue
        fi

        DISK_LIST+=(
            "/dev/${name}|${size}|${model}|${tran:-unknown}"
        )
    done < <(
        lsblk \
            -dn \
            -o NAME,SIZE,TYPE,MODEL,TRAN
    )

    if (( ${#DISK_LIST[@]} == 0 ))
    then
        dialog_error \
            "No installation disks found"

        return 1
    fi

    logger_info \
        "Detected ${#DISK_LIST[@]} installation disk(s)"
}

#------------------------------------------------------------
# Draw
#------------------------------------------------------------

disks_draw()
{
    local row=6
    local shown=0
    local index

    tui_clear

    titlebar_draw \
        "Disk selection"

    draw_panel \
        "Installation target" \
        3 \
        4 \
        22 \
        78

    draw_text \
        4 \
        8 \
        "Boot mode: $(config_get BOOT_MODE)"

    for index in "${!DISK_LIST[@]}"
    do
        (( index < DISK_OFFSET )) && \
            continue

        (( shown >= DISK_PAGE_SIZE )) && \
            break

        local item
        local disk
        local size
        local model
        local tran

        item="${DISK_LIST[index]}"

        IFS='|' read -r \
            disk \
            size \
            model \
            tran <<< "$item"

        cursor_move \
            "$row" \
            6

        if (( index == DISK_SELECTED ))
        then
            printf '> '
        else
            printf '  '
        fi

        printf \
            "%-16s %-8s %-8s %s" \
            "$disk" \
            "$size" \
            "${tran:-unknown}" \
            "$model"

        ((row += 1))
        ((shown += 1))
    done

    statusbar_draw \
        "↑↓ Select   Enter Choose   Esc Back"

    screen_refresh
}

#------------------------------------------------------------
# Navigation
#------------------------------------------------------------

disks_previous()
{
    if (( DISK_SELECTED > 0 ))
    then
        ((DISK_SELECTED -= 1))
    else
        return 0
    fi

    if (( DISK_SELECTED < DISK_OFFSET ))
    then
        ((DISK_OFFSET -= 1))
    fi
}

disks_next()
{
    local last=$(( ${#DISK_LIST[@]} - 1 ))

    if (( DISK_SELECTED < last ))
    then
        ((DISK_SELECTED += 1))
    else
        return 0
    fi

    if (( DISK_SELECTED >= DISK_OFFSET + DISK_PAGE_SIZE ))
    then
        ((DISK_OFFSET += 1))
    fi
}

#------------------------------------------------------------
# Check block device
#------------------------------------------------------------

disks_check_device()
{
    local disk="$1"

    if [[ ! -b "$disk" ]]
    then
        dialog_error \
            "Device does not exist: ${disk}"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Check mounted partitions
#------------------------------------------------------------

disks_check_mounts()
{
    local disk="$1"

    if lsblk \
        -nr \
        -o MOUNTPOINT \
        "$disk" |
        grep -q '[^[:space:]]'
    then
        dialog_error \
            "One or more partitions on ${disk} are mounted"

        logger_error \
            "Refusing disk selection because ${disk} has mounted partitions"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Check disk is not current target
#------------------------------------------------------------

disks_check_target()
{
    local disk="$1"
    local current

    current="$(
        config_get TARGET_DISK \
            2>/dev/null \
            || true
    )"

    if [[ -n "$current" &&
          "$current" == "$disk" ]]
    then
        logger_info \
            "Disk already selected: ${disk}"

        return 0
    fi

    return 0
}

#------------------------------------------------------------
# Check disk properties
#------------------------------------------------------------

disks_check()
{
    local disk="$1"
    local size
    local sectors

    disks_check_device \
        "$disk" || \
        return 1

    disks_check_mounts \
        "$disk" || \
        return 1

    size="$(
        lsblk \
            -dn \
            -o SIZE \
            "$disk"
    )"

    if [[ -z "$size" ]]
    then
        dialog_error \
            "Unable to determine disk size: ${disk}"

        return 1
    fi

    sectors="$(
        blockdev \
            --getsz \
            "$disk" \
            2>/dev/null \
            || true
    )"

    if [[ -z "$sectors" ||
          "$sectors" == "0" ]]
    then
        dialog_error \
            "Unable to read disk geometry: ${disk}"

        return 1
    fi

    disks_check_target \
        "$disk"

    return 0
}

#------------------------------------------------------------
# Confirmation
#------------------------------------------------------------

disks_confirm()
{
    local disk="$1"

    dialog_confirm \
        "WARNING

ALL DATA ON

${disk}

WILL BE PERMANENTLY ERASED.

THIS ACTION CANNOT BE UNDONE.

Continue?"
}

#------------------------------------------------------------
# Apply
#------------------------------------------------------------

disks_apply()
{
    local item
    local disk
    local size
    local model
    local tran

    if (( ${#DISK_LIST[@]} == 0 ))
    then
        dialog_error \
            "No disks available"

        return 1
    fi

    item="${DISK_LIST[DISK_SELECTED]}"

    IFS='|' read -r \
        disk \
        size \
        model \
        tran <<< "$item"

    disks_check \
        "$disk" || \
        return 1

    disks_confirm \
        "$disk" || \
        return 0

    config_set \
        TARGET_DISK \
        "$disk"

    config_set \
        TARGET_DISK_SIZE \
        "$size"

    config_set \
        TARGET_DISK_MODEL \
        "$model"

    config_set \
        TARGET_DISK_SERIAL \
        "$(
            lsblk \
                -dn \
                -o SERIAL \
                "$disk" \
                2>/dev/null \
                || true
        )"

    config_set \
        TARGET_DISK_TRAN \
        "${tran:-unknown}"

    logger_info \
        "Selected disk: ${disk} (${size}, ${model}, ${tran:-unknown})"

    config_save

    dialog_message \
        "Disk selected" \
        "${disk}\n${size}\n${model}\n${tran:-unknown}"

    return 0
}

#------------------------------------------------------------
# Verify current selection
#------------------------------------------------------------

disks_validate_selection()
{
    local disk

    disk="$(config_get TARGET_DISK)"

    if [[ -z "$disk" ]]
    then
        dialog_error \
            "No target disk selected"

        return 1
    fi

    if [[ ! -b "$disk" ]]
    then
        dialog_error \
            "Selected disk no longer exists: ${disk}"

        return 1
    fi

    if ! disks_check_mounts "$disk"
    then
        return 1
    fi

    logger_info \
        "Target disk validation passed: ${disk}"
}

#------------------------------------------------------------
# Main
#------------------------------------------------------------

disks()
{
    local event

    logger_info \
        "Disk selection started"

    disks_load || \
        return 1

    while true
    do
        disks_draw

        event="$(
            event_read
        )"

        case "$event" in
            "$EVENT_UP")
                disks_previous
                ;;
            "$EVENT_DOWN")
                disks_next
                ;;
            "$EVENT_SELECT")
                if disks_apply
                then
                    break
                fi
                ;;
            "$EVENT_BACK")
                return 0
                ;;
        esac
    done

    disks_validate_selection || \
        return 1

    logger_info \
        "Disk selection finished"
}