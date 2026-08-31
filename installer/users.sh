```bash
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
#   • Установка пароля root
#   • Установка пароля пользователя
#   • Проверка результата
#   • Сохранение конфигурации
#
#  Пароли:
#   • Никогда не сохраняются в config.sh
#   • Никогда не записываются в лог
#
#  Public entry point:
#
#       users()
#
#============================================================

#============================================================
# Prevent double loading
#============================================================

if [[ -n "${USERS_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

readonly USERS_SH_LOADED=1

#============================================================
# Configuration
#============================================================

readonly USERS_DEFAULT_NAME="user"

#============================================================
# Load configuration
#============================================================

users_load_config()
{
    local user_name=""

    if [[ -v "CONFIG[USER_NAME]" ]]
    then
        user_name="$(
            config_get USER_NAME \
                2>/dev/null \
                || true
        )
    fi

    if [[ -z "$user_name" ]]
    then
        user_name="$USERS_DEFAULT_NAME"

        if ! config_set \
            USER_NAME \
            "$user_name"
        then
            logger_error \
                "Failed to initialize USER_NAME"

            return 1
        fi
    fi

    logger_info \
        "User configuration loaded: ${user_name}"

    return 0
}

#============================================================
# Validate target system
#============================================================

users_check_target()
{
    if [[ ! -d /mnt ]]
    then
        dialog_error \
            "Target directory /mnt is missing"

        return 1
    fi

    if [[ ! -d /mnt/etc ]]
    then
        dialog_error \
            "Target system is not installed: /mnt/etc is missing"

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
            "Target Bash is missing: /mnt/usr/bin/bash"

        return 1
    fi

    logger_info \
        "Target user database detected"

    return 0
}

#============================================================
# Check required host tools
#============================================================

users_check_tools()
{
    local required=(
        arch-chroot
        passwd
        awk
        grep
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

    return 0
}

#============================================================
# Check target tools
#============================================================

users_check_target_tools()
{
    if ! arch-chroot \
        /mnt \
        command -v useradd \
        >/dev/null 2>&1
    then
        dialog_error \
            "useradd is missing in target system"

        return 1
    fi

    if ! arch-chroot \
        /mnt \
        command -v usermod \
        >/dev/null 2>&1
    then
        dialog_error \
            "usermod is missing in target system"

        return 1
    fi

    if ! arch-chroot \
        /mnt \
        command -v groupadd \
        >/dev/null 2>&1
    then
        dialog_error \
            "groupadd is missing in target system"

        return 1
    fi

    if ! arch-chroot \
        /mnt \
        command -v getent \
        >/dev/null 2>&1
    then
        dialog_error \
            "getent is missing in target system"

        return 1
    fi

    if ! arch-chroot \
        /mnt \
        command -v id \
        >/dev/null 2>&1
    then
        dialog_error \
            "id is missing in target system"

        return 1
    fi

    return 0
}

#============================================================
# Check sudo
#============================================================

users_check_sudo()
{
    if [[ -x /mnt/usr/bin/sudo ]]
    then
        logger_info \
            "Target sudo detected"

        return 0
    fi

    if [[ -x /mnt/usr/bin/sudo-rs ]]
    then
        logger_info \
            "Target sudo-rs detected"

        return 0
    fi

    dialog_error \
        "sudo is not installed in target system"

    return 1
}

#============================================================
# Validate username
#============================================================

users_validate_name()
{
    local user_name=""

    user_name="$(
        config_get USER_NAME \
            2>/dev/null \
            || true
    )"

    if [[ -z "$user_name" ]]
    then
        dialog_error \
            "User name is empty"

        return 1
    fi

    if [[ ${#user_name} -gt 32 ]]
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

    logger_info \
        "User name validated: ${user_name}"

    return 0
}

#============================================================
# Check existing user
#============================================================

users_exists()
{
    local user_name=""

    user_name="$(
        config_get USER_NAME
    )"

    if arch-chroot \
        /mnt \
        getent passwd "$user_name" \
        >/dev/null 2>&1
    then
        return 0
    fi

    return 1
}

#============================================================
# Create user
#============================================================

users_create()
{
    local user_name=""

    user_name="$(
        config_get USER_NAME
    )"

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

    logger_info \
        "Wheel group created"

    return 0
}

#============================================================
# Add user to wheel
#============================================================

users_add_wheel()
{
    local user_name=""

    user_name="$(
        config_get USER_NAME
    )"

    users_ensure_wheel || \
        return 1

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

    logger_info \
        "User added to wheel: ${user_name}"

    return 0
}

#============================================================
# Configure sudo
#============================================================

users_configure_sudo()
{
    local sudoers_dir="/mnt/etc/sudoers.d"
    local sudoers_file="${sudoers_dir}/10-wheel"
    local validator=""

    users_check_sudo || \
        return 1

    mkdir -p \
        "$sudoers_dir" || {
        logger_error \
            "Failed creating sudoers.d"

        return 1
    }

    #
    # Use the validator available in target system.
    #

    if [[ -x /mnt/usr/bin/visudo ]]
    then
        validator="visudo"
    elif [[ -x /mnt/usr/bin/visudo-rs ]]
    then
        validator="visudo-rs"
    else
        dialog_error \
            "Neither visudo nor visudo-rs exists in target system"

        return 1
    fi

    #
    # Do not overwrite an existing custom configuration
    # unnecessarily. The file belongs to this installer.
    #

    if ! printf '%s\n' \
        '%wheel ALL=(ALL:ALL) ALL' \
        > "$sudoers_file"
    then
        logger_error \
            "Failed writing sudoers configuration"

        return 1
    fi

    chmod 440 \
        "$sudoers_file" || {
        rm -f "$sudoers_file"

        logger_error \
            "Failed setting sudoers permissions"

        return 1
    }

    chown root:root \
        "$sudoers_file" || {
        rm -f "$sudoers_file"

        logger_error \
            "Failed setting sudoers ownership"

        return 1
    }

    #
    # Validate complete sudo configuration.
    #

    if ! arch-chroot \
        /mnt \
        "$validator" \
        -cf \
        /etc/sudoers
    then
        rm -f \
            "$sudoers_file"

        logger_error \
            "sudoers validation failed"

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
    printf '\n%s\n' \
        "Set root password for installed system."

    logger_info \
        "Waiting for root password input"

    #
    # Password is entered interactively.
    # It is never stored in a variable.
    #

    if ! arch-chroot \
        /mnt \
        passwd
    then
        logger_error \
            "Failed setting root password"

        return 1
    fi

    logger_info \
        "Root password configured"

    return 0
}

#============================================================
# Set user password
#============================================================

users_set_user_password()
{
    local user_name=""

    user_name="$(
        config_get USER_NAME
    )"

    printf '\n%s\n' \
        "Set password for user ${user_name}."

    logger_info \
        "Waiting for user password input: ${user_name}"

    #
    # Password is entered interactively.
    # It is never stored in a variable.
    #

    if ! arch-chroot \
        /mnt \
        passwd \
        "$user_name"
    then
        logger_error \
            "Failed setting user password"

        return 1
    fi

    logger_info \
        "User password configured"

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

    user_name="$(
        config_get USER_NAME
    )"

    #
    # User must exist.
    #

    if ! users_exists
    then
        dialog_error \
            "User was not created: ${user_name}"

        return 1
    fi

    #
    # Check login shell.
    #

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
            "Unexpected login shell for ${user_name}: ${shell}"

        return 1
    fi

    #
    # Check wheel membership.
    #

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

    #
    # Check sudoers file.
    #

    if [[ ! -f /mnt/etc/sudoers.d/10-wheel ]]
    then
        dialog_error \
            "sudo wheel configuration is missing"

        return 1
    fi

    #
    # Check permissions.
    #

    if [[ "$(stat -c '%a' /mnt/etc/sudoers.d/10-wheel 2>/dev/null)" != "440" ]]
    then
        dialog_error \
            "Invalid permissions on sudoers.d/10-wheel"

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
            "Failed saving user configuration"

        return 1
    fi

    logger_info \
        "User configuration saved"

    return 0
}

#============================================================
# Main entry point
#============================================================

users()
{
    logger_info \
        "User configuration started"

    #
    # Target system.
    #

    users_check_target || \
        return 1

    #
    # Host tools.
    #

    users_check_tools || \
        return 1

    #
    # Target tools.
    #

    users_check_target_tools || \
        return 1

    #
    # Load configuration.
    #

    users_load_config || \
        return 1

    #
    # Validate username.
    #

    users_validate_name || \
        return 1

    #
    # Create user.
    #

    users_create || \
        return 1

    #
    # Wheel group.
    #

    users_add_wheel || \
        return 1

    #
    # Sudo.
    #

    users_configure_sudo || \
        return 1

    #
    # Passwords.
    #
    # These are intentionally interactive.
    #

    users_set_root_password || \
        return 1

    users_set_user_password || \
        return 1

    #
    # Final verification.
    #

    users_check_result || \
        return 1

    #
    # Save configuration.
    #

    users_save || \
        return 1

    dialog_message \
        "Users" \
        "User configuration completed successfully"

    logger_info \
        "User configuration finished"

    return 0
}

#============================================================
# End of users.sh
#============================================================
```
