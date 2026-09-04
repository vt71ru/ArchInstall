#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  packages.sh
#
#  Установка базовой системы Arch Linux.
#
#  Ответственность:
#   • Формирование списка пакетов
#   • Добавление desktop-пакетов
#   • Добавление GPU-пакетов
#   • Установка системы через pacstrap
#   • Генерация /etc/fstab
#   • Сохранение списка установленных пакетов
#
#  Не выполняет:
#   • Разметку диска
#   • Форматирование
#   • Монтирование
#   • Установку загрузчика
#============================================================

[[ -n "${PACKAGES_SH_LOADED:-}" ]] && return

readonly PACKAGES_SH_LOADED=1

#------------------------------------------------------------
# State
#------------------------------------------------------------

declare -a BASE_PACKAGES=()
declare -a EXTRA_PACKAGES=()
declare -a PACKAGES_LIST=()

#------------------------------------------------------------
# Dependency check
#------------------------------------------------------------

packages_check_dependencies()
{
    local required=(
        pacstrap
        genfstab
        pacman
        mountpoint
        mkdir
        mv
        rm
        chmod
    )

    local cmd

    for cmd in "${required[@]}"
    do
        if ! command -v "$cmd" >/dev/null 2>&1
        then
            dialog_error \
                "Required program not found: ${cmd}"

            return 1
        fi
    done

    if ! /usr/bin/mountpoint -q /mnt
    then
        dialog_error \
            "/mnt is not mounted"

        return 1
    fi

    return 0
}

#------------------------------------------------------------
# Initialize package list
#------------------------------------------------------------

packages_init()
{
    BASE_PACKAGES=(
        base
        linux
        linux-firmware
        sudo
        vim
        nano
        networkmanager
        openssh
    )

    EXTRA_PACKAGES=()
    PACKAGES_LIST=()

    if [[ "$(config_get INSTALL_REFLECTOR)" == "1" ]]
    then
        BASE_PACKAGES+=(
            reflector
        )
    fi

    logger_info \
        "Base package list initialized"

    return 0
}

#------------------------------------------------------------
# Add package
#------------------------------------------------------------

packages_add()
{
    local package="${1:-}"
    local existing

    [[ -n "$package" ]] || \
        return 0

    for existing in "${EXTRA_PACKAGES[@]}"
    do
        if [[ "$existing" == "$package" ]]
        then
            return 0
        fi
    done

    for existing in "${BASE_PACKAGES[@]}"
    do
        if [[ "$existing" == "$package" ]]
        then
            return 0
        fi
    done

    EXTRA_PACKAGES+=(
        "$package"
    )

    logger_debug \
        "Added package: ${package}"

    return 0
}

#------------------------------------------------------------
# Desktop packages
#------------------------------------------------------------

packages_load_desktop()
{
    local desktop

    desktop="$(
        config_get DESKTOP
    )"

    case "$desktop" in

        gnome)
            packages_add \
                gnome

            packages_add \
                gnome-extra

            packages_add \
                gdm
            ;;

        kde)
            packages_add \
                plasma

            packages_add \
                kde-applications

            packages_add \
                sddm
            ;;

        xfce)
            packages_add \
                xfce4

            packages_add \
                xfce4-goodies

            packages_add \
                lightdm
            ;;

        "")
            ;;

        *)
            logger_warn \
                "Unknown desktop environment: ${desktop}"

            dialog_error \
                "Unsupported desktop: ${desktop}"

            return 1
            ;;
    esac

    return 0
}

#------------------------------------------------------------
# GPU packages
#------------------------------------------------------------

packages_load_gpu()
{
    local gpu

    gpu="$(
        config_get GPU_DRIVER
    )"

    case "$gpu" in

        nvidia)
            packages_add \
                nvidia

            packages_add \
                nvidia-utils
            ;;

        amd)
            packages_add \
                mesa

            packages_add \
                lib32-mesa
            ;;

        intel)
            packages_add \
                mesa

            packages_add \
                lib32-mesa
            ;;

        "")
            ;;

        *)
            logger_warn \
                "Unknown GPU driver: ${gpu}"

            dialog_error \
                "Unsupported GPU driver: ${gpu}"

            return 1
            ;;
    esac

    return 0
}

#------------------------------------------------------------
# Additional system packages
#------------------------------------------------------------

packages_load_system()
{
    packages_add \
        man-db

    packages_add \
        man-pages

    packages_add \
        texinfo

    packages_add \
        bash-completion

    packages_add \
        git

    packages_add \
        curl

    packages_add \
        wget

    packages_add \
        rsync

    packages_add \
        pciutils

    packages_add \
        usbutils

    packages_add \
        htop

    packages_add \
        less

    packages_add \
        which

    packages_add \
        file

    packages_add \
        tar

    packages_add \
        unzip

    packages_add \
        zip

    return 0
}

#------------------------------------------------------------
# Build package list
#------------------------------------------------------------

packages_build_list()
{
    local package
    local existing
    local duplicate

    PACKAGES_LIST=()

    #--------------------------------------------------------
    # Add base packages
    #--------------------------------------------------------

    for package in "${BASE_PACKAGES[@]}"
    do
        duplicate=0

        for existing in "${PACKAGES_LIST[@]}"
        do
            if [[ "$existing" == "$package" ]]
            then
                duplicate=1
                break
            fi
        done

        if (( ! duplicate ))
        then
            PACKAGES_LIST+=(
                "$package"
            )
        fi
    done

    #--------------------------------------------------------
    # Add extra packages
    #--------------------------------------------------------

    for package in "${EXTRA_PACKAGES[@]}"
    do
        duplicate=0

        for existing in "${PACKAGES_LIST[@]}"
        do
            if [[ "$existing" == "$package" ]]
            then
                duplicate=1
                break
            fi
        done

        if (( ! duplicate ))
        then
            PACKAGES_LIST+=(
                "$package"
            )
        fi
    done

    #--------------------------------------------------------
    # Validate
    #--------------------------------------------------------

    if (( ${#PACKAGES_LIST[@]} == 0 ))
    then
        dialog_error \
            "Package list is empty"

        return 1
    fi

    logger_info \
        "Package list contains ${#PACKAGES_LIST[@]} packages"

    for package in "${PACKAGES_LIST[@]}"
    do
        logger_debug \
            "Package: ${package}"
    done

    return 0
}

#------------------------------------------------------------
# Validate target
#------------------------------------------------------------

packages_validate_target()
{
    if [[ ! -d /mnt ]]
    then
        dialog_error \
            "Target root /mnt does not exist"

        return 1
    fi

    if ! /usr/bin/mountpoint -q /mnt
    then
        dialog_error \
            "Target root /mnt is not mounted"

        return 1
    fi

    if [[ ! -d /mnt/etc ]]
    then
        logger_info \
            "/mnt/etc does not exist yet; pacstrap will create it"
    fi

    return 0
}

#------------------------------------------------------------
# Install base system
#------------------------------------------------------------

packages_install_base()
{
    logger_info \
        "Installing base system"

    if ! pacstrap \
        -K \
        /mnt \
        "${PACKAGES_LIST[@]}"
    then
        logger_error \
            "pacstrap failed"

        return 1
    fi

    logger_info \
        "Base system installation completed"

    return 0
}

#------------------------------------------------------------
# Verify installed target
#------------------------------------------------------------

packages_check_target()
{
    local package

    if [[ ! -d /mnt/etc ]]
    then
        logger_error \
            "Target /mnt/etc does not exist after pacstrap"

        return 1
    fi

    if [[ ! -x /mnt/usr/bin/bash ]]
    then
        logger_error \
            "Target system does not contain bash"

        return 1
    fi

    logger_info \
        "Installed target verification passed"

    for package in \
        base \
        linux \
        linux-firmware
    do
        if pacman \
            --root /mnt \
            --query \
            "$package" \
            >/dev/null 2>&1
        then
            logger_debug \
                "Verified package: ${package}"
        else
            logger_error \
                "Required package is missing: ${package}"

            return 1
        fi
    done

    return 0
}

#------------------------------------------------------------
# Generate fstab
#------------------------------------------------------------

packages_generate_fstab()
{
    local fstab
    local tmp_fstab

    fstab="/mnt/etc/fstab"
    tmp_fstab="${fstab}.tmp.$$"

    logger_info \
        "Generating fstab"

    if ! genfstab \
        -U \
        /mnt \
        > "$tmp_fstab"
    then
        rm -f \
            "$tmp_fstab"

        logger_error \
            "Failed generating fstab"

        return 1
    fi

    if [[ ! -s "$tmp_fstab" ]]
    then
        rm -f \
            "$tmp_fstab"

        logger_error \
            "Generated fstab is empty"

        return 1
    fi

    if ! mv \
        -f \
        "$tmp_fstab" \
        "$fstab"
    then
        rm -f \
            "$tmp_fstab"

        logger_error \
            "Failed saving fstab"

        return 1
    fi

    if ! chmod \
        644 \
        "$fstab"
    then
        logger_error \
            "Failed setting fstab permissions"

        return 1
    fi

    logger_info \
        "fstab generated: ${fstab}"

    return 0
}

#------------------------------------------------------------
# Save package list
#------------------------------------------------------------

packages_save_list()
{
    local file

    file="/mnt/root/installed-packages.txt"

    if [[ ! -d /mnt/root ]]
    then
        if ! mkdir -p /mnt/root
        then
            logger_error \
                "Failed to create /mnt/root"

            return 1
        fi
    fi

    logger_info \
        "Saving package list"

    if ! printf '%s\n' \
        "${PACKAGES_LIST[@]}" \
        > "$file"
    then
        logger_error \
            "Failed to save package list"

        return 1
    fi

    if ! chmod \
        600 \
        "$file"
    then
        logger_error \
            "Failed to set package list permissions"

        return 1
    fi

    logger_info \
        "Package list saved: ${file}"

    return 0
}

#------------------------------------------------------------
# Save state
#------------------------------------------------------------

packages_save()
{
    if ! config_save
    then
        logger_error \
            "Failed to save package installation state"

        return 1
    fi

    logger_info \
        "Package installation state saved"

    return 0
}

#------------------------------------------------------------
# Main installer stage
#
# IMPORTANT:
# installer/installer.sh must call:
#
#     packages_install
#
# This is the official entry point for this module.
#------------------------------------------------------------

packages_install()
{
    logger_info \
        "Package installation started"

    packages_check_dependencies || \
        return 1

    packages_validate_target || \
        return 1

    packages_init || \
        return 1

    packages_load_system || \
        return 1

    packages_load_desktop || \
        return 1

    packages_load_gpu || \
        return 1

    packages_build_list || \
        return 1

    packages_install_base || \
        return 1

    packages_check_target || \
        return 1

    packages_generate_fstab || \
        return 1

    packages_save_list || \
        return 1

    packages_save || \
        return 1

    dialog_message \
        "Packages" \
        "Base system installed successfully"

    logger_info \
        "Package installation finished"

    return 0
}

#============================================================
# END
#============================================================

