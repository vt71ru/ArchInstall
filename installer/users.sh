#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  users.sh
#
#  Создание и настройка пользователей target system.
#
#  Ответственность:
#   • Проверка target system
#   • Создание основного пользователя
#   • Добавление пользователя в wheel
#   • Настройка sudo
#   • Установка паролей
#   • Проверка результата
#
#  Пароли:
#   • Никогда не сохраняются в CONFIG
#   • Никогда не записываются в лог
#============================================================

#============================================================
# Include guard
#============================================================

if [[ -n "${USERS_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

readonly USERS_SH_LOADED=1

#============================================================
# Configuration
#============================================================

USERS_DEFAULT_NAME="user"

#============================================================
# Load configuration
#============================================================

users_load_config()
{
    local user_name=""

    if [[ -v "CONFIG[USER_NAME]" ]]
    then
        user_name="$(config_get USER_NAME 2>/dev/null || true)"
    fi

    if [[ -z "$user_name" ]]
    then
        user_name="$USERS_DEFAULT_NAME"

        if ! config_set USER_NAME "$user_name"
        then
            logger_error \
                "Failed to set default USER_NAME"

            return 1
        fi
    fi

    logger_info \
        "User configuration loaded: ${user_name}"

    return 0
}

#============================================================
# Validate target
#============================================================

users_check_target()
{
    if [[ ! -d /mnt/etc ]]
    then
        dialog_error \
            "Target system is not installed"

        return 1
    fi

    if [[ ! -f /mnt/etc/passwd ]]
    then
        dialog_error \
            "Target /etc/passwd is missing"

        return 1
    fi

    if [[ ! -f /mnt/etc/shadow ]]
    then
        dialog_error \
            "Target /etc/shadow is missing"

        return 1
    fi

    if [[ ! -x /mnt/usr/bin/bash ]]
    then
        dialog_error \
            "Target Bash is missing"

        return 1
    fi

    logger_info \
        "Target user database detected"

    return 0
}

#============================================================
# Check required tools
#============================================================

users_check_tools()
{
    local required=(
        arch-chroot
        passwd
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

    if ! arch-chroot /mnt command -v useradd >/dev/null 2>&1
    then
        dialog_error \
            "useradd is missing in target system"

        return 1
    fi

    if ! arch-chroot /mnt command -v usermod >/dev/null 2>&1
    then
        dialog_error \
            "usermod is missing in target system"

        return 1
    fi

    if ! arch-chroot /mnt command -v groupadd >/dev/null 2>&1
    then
        dialog_error \
            "groupadd is missing in target system"

        return 1
    fi

    return 0
}

#============================================================
# Validate username
#============================================================

users_validate_name()
{
    local user_name=""

    user_name="$(config_get USER_NAME 2>/dev/null || true)"

    if [[ -z "$user_name" ]]
    then
        dialog_error \
            "User name is empty"

        return 1
    fi

    if (( ${#user_name} > 32 ))
    then
        dialog_error \
            "User name is too long"

        return 1
    fi

    if [[ ! "$user_name" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]
    then
        dialog_error \
            "Invalid user name: ${user_name}"

        return 1
    fi

    if [[ "$user_name" == "root" ]]
    then
        dialog_error \
            "root cannot be used as normal user"

        return 1
    fi

    return 0
}

#============================================================
# Check existing user
#============================================================

users_exists()
{
    local user_name=""

    user_name="$(config_get USER_NAME 2>/dev/null || true)"

    [[ -n "$user_name" ]] || return 1

    arch-chroot \
        /mnt \
        getent passwd \
        "$user_name" \
        >/dev/null 2>&1
}

#============================================================
# Create user
#============================================================

users_create()
{
    local user_name=""

    user_name="$(config_get USER_NAME)"

    if users_exists
    then
        logger_info \
            "User already exists: ${user_name}"

        return 0
    fi

    logger_info \
        "Creating user: ${user_name}"

    if ! arch-chroot \
        /mnt \
        useradd \
        -m \
        -s /bin/bash \
        "$user_name"
    then
        logger_error \
            "Failed creating user: ${user_name}"

        return 1
    fi

    logger_info \
        "User created: ${user_name}"

    return 0
}

#============================================================
# Ensure wheel group
#============================================================

users_ensure_wheel()
{
    if arch-chroot \
        /mnt \
        getent group wheel \
        >/dev/null 2>&1
    then
        return 0
    fi

    logger_info \
        "Creating wheel group"

    if ! arch-chroot \
        /mnt \
        groupadd \
        wheel
    then
        logger_error \
            "Failed creating wheel group"

        return 1
    fi

    return 0
}

#============================================================
# Add user to wheel
#============================================================

users_add_wheel()
{
    local user_name=""

    user_name="$(config_get USER_NAME)"

    users_ensure_wheel || return 1

    logger_info \
        "Adding ${user_name} to wheel"

    if ! arch-chroot \
        /mnt \
        usermod \
        -aG wheel \
        "$user_name"
    then
        logger_error \
            "Failed adding ${user_name} to wheel"

        return 1
    fi

    return 0
}

#============================================================
# Configure sudo
#============================================================

users_configure_sudo()
{
    local sudoers_dir="/mnt/etc/sudoers.d"
    local sudoers_file="${sudoers_dir}/10-wheel"

    #--------------------------------------------------------
    # Check sudo
    #--------------------------------------------------------

    if [[ ! -x /mnt/usr/bin/sudo &&
          ! -x /mnt/usr/bin/sudo-rs ]]
    then
        dialog_error \
            "sudo is not installed in target system"

        return 1
    fi

    #--------------------------------------------------------
    # Check sudoers directory
    #--------------------------------------------------------

    if ! mkdir -p "$sudoers_dir"
    then
        logger_error \
            "Failed creating ${sudoers_dir}"

        return 1
    fi

    #--------------------------------------------------------
    # Create wheel rule
    #--------------------------------------------------------

    if ! printf '%s\n' \
        '%wheel ALL=(ALL:ALL) ALL' \
        > "$sudoers_file"
    then
        logger_error \
            "Failed writing ${sudoers_file}"

        return 1
    fi

    chmod 440 "$sudoers_file" || {
        logger_error \
            "Failed setting permissions on ${sudoers_file}"

        return 1
    }

    chown root:root "$sudoers_file" || {
        logger_error \
            "Failed setting ownership on ${sudoers_file}"

        return 1
    }

    #--------------------------------------------------------
    # Validate sudoers
    #--------------------------------------------------------

    if [[ -x /mnt/usr/bin/visudo ]]
    then
        if ! arch-chroot \
            /mnt \
            visudo \
            -cf \
            /etc/sudoers
        then
            rm -f "$sudoers_file"

            logger_error \
                "sudoers validation failed"

            return 1
        fi

    elif [[ -x /mnt/usr/bin/visudo-rs ]]
    then
        if ! arch-chroot \
            /mnt \
            visudo-rs \
            -cf \
            /etc/sudoers
        then
            rm -f "$sudoers_file"

            logger_error \
                "sudoers validation failed"

            return 1
        fi

    else
        logger_error \
            "Neither visudo nor visudo-rs exists in target system"

        rm -f "$sudoers_file"

        return 1
    fi

    logger_info \
        "wheel sudo access configured"

    return 0
}

#============================================================
# Set root password
#============================================================

users_set_root_password()
{
    logger_info \
        "Setting root password"

    printf '\n%s\n' \
        "Set root password for installed system."

    if ! arch-chroot \
        /mnt \
        passwd
    then
        logger_error \
            "Failed setting root password"

        return 1
    fi

    return 0
}

#============================================================
# Set user password
#============================================================

users_set_user_password()
{
    local user_name=""

    user_name="$(config_get USER_NAME)"

    logger_info \
        "Setting password for user: ${user_name}"

    printf '\n%s\n' \
        "Set password for user ${user_name}."

    if ! arch-chroot \
        /mnt \
        passwd \
        "$user_name"
    then
        logger_error \
            "Failed setting user password"

        return 1
    fi

    return 0
}

#============================================================
# Verify user
#============================================================

users_check_result()
{
    local user_name=""
    local shell=""
    local groups=""

    user_name="$(config_get USER_NAME)"

    #--------------------------------------------------------
    # User exists
    #--------------------------------------------------------

    if ! users_exists
    then
        dialog_error \
            "User was not created: ${user_name}"

        return 1
    fi

    #--------------------------------------------------------
    # Check shell
    #--------------------------------------------------------

    shell="$(
        arch-chroot \
            /mnt \
            getent passwd \
            "$user_name" |
        awk -F: '{print $7}'
    )"

    if [[ "$shell" != "/bin/bash" ]]
    then
        dialog_error \
            "Unexpected login shell: ${shell}"

        return 1
    fi

    #--------------------------------------------------------
    # Check wheel
    #--------------------------------------------------------

    groups="$(
        arch-chroot \
            /mnt \
            id \
            -nG \
            "$user_name"
    )"

    if ! grep -Eq \
        '(^|[[:space:]])wheel($|[[:space:]])' \
        <<< "$groups"
    then
        dialog_error \
            "User ${user_name} is not a member of wheel"

        return 1
    fi

    #--------------------------------------------------------
    # Check sudoers
    #--------------------------------------------------------

    if [[ ! -f /mnt/etc/sudoers.d/10-wheel ]]
    then
        dialog_error \
            "sudo wheel configuration is missing"

        return 1
    fi

    logger_info \
        "User verification passed"

    return 0
}

#============================================================
# Save state
#============================================================

users_save()
{
    if ! config_save
    then
        logger_error \
            "Failed to save user configuration"

        return 1
    fi

    logger_info \
        "User configuration saved"

    return 0
}

#============================================================
# Main installer entry point
#
# IMPORTANT:
# installer.sh expects:
#
#     users_configure
#
#============================================================

users_configure()
{
    logger_info \
        "User configuration started"

    users_check_target || return 1

    users_check_tools || return 1

    users_load_config || return 1

    users_validate_name || return 1

    users_create || return 1

    users_add_wheel || return 1

    users_configure_sudo || return 1

    users_set_root_password || return 1

    users_set_user_password || return 1

    users_check_result || return 1

    users_save || return 1

    if declare -F dialog_message >/dev/null 2>&1
    then
        dialog_message \
            "Users" \
            "User configuration completed successfully"
    fi

    logger_info \
        "User configuration finished"

    return 0
}

#============================================================
# Compatibility entry point
#============================================================

users()
{
    users_configure "$@"
}
