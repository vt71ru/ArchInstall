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
#
#  Пароли:
#   • Никогда не сохраняются в CONFIG
#   • Никогда не записываются в лог
#
#============================================================

#============================================================
# Include guard
#============================================================

if [[ -n "${USERS_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

USERS_SH_LOADED=1
export USERS_SH_LOADED

#============================================================
# Configuration
#============================================================

readonly USERS_DEFAULT_NAME="user"

#============================================================
# Logging helpers
#============================================================

users_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@" || true
    else
        printf '[INFO] %s\n' "${1:-}"
    fi

    return 0
}

users_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@" || true
    else
        printf '[WARN] %s\n' "${1:-}" >&2
    fi

    return 0
}

users_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@" || true
    else
        printf '[ERROR] %s\n' "${1:-}" >&2
    fi

    return 0
}

#============================================================
# Load configuration
#============================================================

users_load_config()
{
    local user_name=""

    if ! declare -F config_get >/dev/null 2>&1
    then
        users_log_error \
            "config_get() is not available"

        return 1
    fi

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
            users_log_error \
                "Failed to set default USER_NAME"

            return 1
        fi
    fi

    users_log_info \
        "User configuration loaded: ${user_name}"

    return 0
}

#============================================================
# Validate target
#============================================================

users_check_target()
{
    if [[ ! -d /mnt ]]
    then
        users_log_error \
            "Target mountpoint /mnt does not exist"

        return 1
    fi

    if [[ ! -d /mnt/etc ]]
    then
        users_log_error \
            "Target /etc directory is missing"

        return 1
    fi

    if [[ ! -f /mnt/etc/passwd ]]
    then
        users_log_error \
            "Target /etc/passwd is missing"

        return 1
    fi

    if [[ ! -f /mnt/etc/shadow ]]
    then
        users_log_error \
            "Target /etc/shadow is missing"

        return 1
    fi

    if [[ ! -x /mnt/usr/bin/bash ]]
    then
        users_log_error \
            "Target /usr/bin/bash is missing"

        return 1
    fi

    if [[ ! -x /mnt/usr/bin/useradd ]]
    then
        users_log_error \
            "Target /usr/bin/useradd is missing"

        return 1
    fi

    if [[ ! -x /mnt/usr/bin/usermod ]]
    then
        users_log_error \
            "Target /usr/bin/usermod is missing"

        return 1
    fi

    users_log_info \
        "Target system is ready for user configuration"

    return 0
}

#============================================================
# Check required host tools
#============================================================

users_check_host_tools()
{
    local required=(
        arch-chroot
        passwd
    )

    local command_name

    for command_name in "${required[@]}"
    do
        if ! command -v "$command_name" >/dev/null 2>&1
        then
            users_log_error \
                "Required host program not found: ${command_name}"

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
    local required=(
        /usr/bin/useradd
        /usr/bin/usermod
        /usr/bin/groupadd
        /usr/bin/getent
        /usr/bin/id
    )

    local tool

    for tool in "${required[@]}"
    do
        if [[ ! -x "/mnt${tool}" ]]
        then
            users_log_error \
                "Required target program is missing: ${tool}"

            return 1
        fi
    done

    return 0
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
        users_log_error \
            "User name is empty"

        return 1
    fi

    if (( ${#user_name} > 32 ))
    then
        users_log_error \
            "User name is too long"

        return 1
    fi

    if [[ ! "$user_name" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]
    then
        users_log_error \
            "Invalid user name: ${user_name}"

        return 1
    fi

    if [[ "$user_name" == "root" ]]
    then
        users_log_error \
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

    user_name="$(
        config_get USER_NAME \
            2>/dev/null \
            || true
    )"

    [[ -n "$user_name" ]] || return 1

    arch-chroot \
        /mnt \
        getent \
        passwd \
        "$user_name" \
        >/dev/null 2>&1
}

#============================================================
# Create user
#============================================================

users_create()
{
    local user_name=""

    user_name="$(
        config_get USER_NAME \
            2>/dev/null \
            || true
    )"

    if [[ -z "$user_name" ]]
    then
        users_log_error \
            "Cannot create user: USER_NAME is empty"

        return 1
    fi

    if users_exists
    then
        users_log_info \
            "User already exists: ${user_name}"

        return 0
    fi

    users_log_info \
        "Creating user: ${user_name}"

    if ! arch-chroot \
        /mnt \
        useradd \
        --create-home \
        --shell /bin/bash \
        "$user_name"
    then
        users_log_error \
            "Failed creating user: ${user_name}"

        return 1
    fi

    users_log_info \
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
        getent \
        group \
        wheel \
        >/dev/null 2>&1
    then
        return 0
    fi

    users_log_info \
        "Creating wheel group"

    if ! arch-chroot \
        /mnt \
        groupadd \
        wheel
    then
        users_log_error \
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

    user_name="$(
        config_get USER_NAME \
            2>/dev/null \
            || true
    )"

    if [[ -z "$user_name" ]]
    then
        users_log_error \
            "Cannot add user to wheel: USER_NAME is empty"

        return 1
    fi

    users_ensure_wheel || return 1

    users_log_info \
        "Adding ${user_name} to wheel"

    if ! arch-chroot \
        /mnt \
        usermod \
        --append \
        --groups wheel \
        "$user_name"
    then
        users_log_error \
            "Failed adding ${user_name} to wheel"

        return 1
    fi

    return 0
}

#============================================================
# Detect sudo implementation
#============================================================

users_detect_sudo()
{
    if [[ -x /mnt/usr/bin/sudo ]]
    then
        printf '%s\n' sudo
        return 0
    fi

    if [[ -x /mnt/usr/bin/sudo-rs ]]
    then
        printf '%s\n' sudo-rs
        return 0
    fi

    return 1
}

#============================================================
# Configure sudo
#============================================================

users_configure_sudo()
{
    local sudoers_dir="/mnt/etc/sudoers.d"
    local sudoers_file="${sudoers_dir}/10-wheel"
    local sudo_command=""

    sudo_command="$(
        users_detect_sudo \
            2>/dev/null \
            || true
    )"

    if [[ -z "$sudo_command" ]]
    then
        users_log_error \
            "sudo is not installed in target system"

        users_log_error \
            "Expected /usr/bin/sudo or /usr/bin/sudo-rs"

        return 1
    fi

    users_log_info \
        "Detected sudo implementation: ${sudo_command}"

    if ! mkdir -p \
        "$sudoers_dir"
    then
        users_log_error \
            "Failed creating ${sudoers_dir}"

        return 1
    fi

    #--------------------------------------------------------
    # Write wheel rule.
    #
    # This is valid for both sudo and sudo-rs.
    #--------------------------------------------------------

    if ! printf '%s\n' \
        '%wheel ALL=(ALL:ALL) ALL' \
        > "$sudoers_file"
    then
        users_log_error \
            "Failed writing ${sudoers_file}"

        return 1
    fi

    if ! chmod 440 \
        "$sudoers_file"
    then
        users_log_error \
            "Failed setting permissions on ${sudoers_file}"

        rm -f "$sudoers_file"

        return 1
    fi

    if ! chown root:root \
        "$sudoers_file"
    then
        users_log_error \
            "Failed setting owner on ${sudoers_file}"

        rm -f "$sudoers_file"

        return 1
    fi

    #--------------------------------------------------------
    # Validate sudo configuration if validator exists.
    #
    # Do not require visudo to exist. Some target setups
    # may provide sudo functionality without the traditional
    # validator path.
    #--------------------------------------------------------

    if [[ -x /mnt/usr/bin/visudo ]]
    then
        if ! arch-chroot \
            /mnt \
            visudo \
            -cf \
            /etc/sudoers
        then
            users_log_error \
                "sudoers validation failed"

            rm -f "$sudoers_file"

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
            users_log_error \
                "sudo-rs configuration validation failed"

            rm -f "$sudoers_file"

            return 1
        fi

    else
        users_log_warn \
            "No visudo validator found; sudoers file was created"
    fi

    users_log_info \
        "wheel sudo access configured"

    return 0
}

#============================================================
# Set root password
#============================================================

users_set_root_password()
{
    printf '\n'
    printf '%s\n' \
        "Set root password for installed system."
    printf '\n'

    users_log_info \
        "Setting root password"

    if ! arch-chroot \
        /mnt \
        passwd
    then
        users_log_error \
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

    user_name="$(
        config_get USER_NAME \
            2>/dev/null \
            || true
    )"

    if [[ -z "$user_name" ]]
    then
        users_log_error \
            "Cannot set password: USER_NAME is empty"

        return 1
    fi

    printf '\n'
    printf '%s\n' \
        "Set password for user ${user_name}."
    printf '\n'

    users_log_info \
        "Setting password for user: ${user_name}"

    if ! arch-chroot \
        /mnt \
        passwd \
        "$user_name"
    then
        users_log_error \
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

    user_name="$(
        config_get USER_NAME \
            2>/dev/null \
            || true
    )"

    if [[ -z "$user_name" ]]
    then
        users_log_error \
            "USER_NAME is empty during verification"

        return 1
    fi

    #--------------------------------------------------------
    # User exists
    #--------------------------------------------------------

    if ! users_exists
    then
        users_log_error \
            "User was not created: ${user_name}"

        return 1
    fi

    #--------------------------------------------------------
    # Check shell
    #--------------------------------------------------------

    shell="$(
        arch-chroot \
            /mnt \
            getent \
            passwd \
            "$user_name" |
        awk -F: '{print $7}'
    )"

    if [[ "$shell" != "/bin/bash" ]]
    then
        users_log_error \
            "Unexpected login shell for ${user_name}: ${shell}"

        return 1
    fi

    #--------------------------------------------------------
    # Check wheel membership
    #--------------------------------------------------------

    groups="$(
        arch-chroot \
            /mnt \
            id \
            -nG \
            "$user_name" \
            2>/dev/null \
            || true
    )"

    if ! grep -Eq \
        '(^|[[:space:]])wheel($|[[:space:]])' \
        <<< "$groups"
    then
        users_log_error \
            "User ${user_name} is not a member of wheel"

        return 1
    fi

    #--------------------------------------------------------
    # Check sudo configuration
    #--------------------------------------------------------

    if [[ ! -f /mnt/etc/sudoers.d/10-wheel ]]
    then
        users_log_error \
            "sudo wheel configuration is missing"

        return 1
    fi

    users_log_info \
        "User verification passed"

    return 0
}

#============================================================
# Save state
#============================================================

users_save()
{
    if ! declare -F config_save >/dev/null 2>&1
    then
        users_log_warn \
            "config_save() is not available"

        return 0
    fi

    if ! config_save
    then
        users_log_error \
            "Failed saving user configuration"

        return 1
    fi

    users_log_info \
        "User configuration saved"

    return 0
}

#============================================================
# Main
#============================================================

users()
{
    users_log_info \
        "=========================================="

    users_log_info \
        "User configuration started"

    users_log_info \
        "=========================================="

    #--------------------------------------------------------
    # Target
    #--------------------------------------------------------

    if ! users_check_target
    then
        return 1
    fi

    #--------------------------------------------------------
    # Host tools
    #--------------------------------------------------------

    if ! users_check_host_tools
    then
        return 1
    fi

    #--------------------------------------------------------
    # Target tools
    #--------------------------------------------------------

    if ! users_check_target_tools
    then
        return 1
    fi

    #--------------------------------------------------------
    # Configuration
    #--------------------------------------------------------

    if ! users_load_config
    then
        return 1
    fi

    if ! users_validate_name
    then
        return 1
    fi

    #--------------------------------------------------------
    # Create user
    #--------------------------------------------------------

    if ! users_create
    then
        return 1
    fi

    #--------------------------------------------------------
    # Wheel
    #--------------------------------------------------------

    if ! users_add_wheel
    then
        return 1
    fi

    #--------------------------------------------------------
    # Sudo
    #--------------------------------------------------------

    if ! users_configure_sudo
    then
        return 1
    fi

    #--------------------------------------------------------
    # Passwords
    #
    # These are intentionally interactive.
    # Passwords never enter CONFIG or logs.
    #--------------------------------------------------------

    if ! users_set_root_password
    then
        return 1
    fi

    if ! users_set_user_password
    then
        return 1
    fi

    #--------------------------------------------------------
    # Verification
    #--------------------------------------------------------

    if ! users_check_result
    then
        return 1
    fi

    #--------------------------------------------------------
    # Save
    #--------------------------------------------------------

    if ! users_save
    then
        return 1
    fi

    #--------------------------------------------------------
    # Success
    #--------------------------------------------------------

    if declare -F dialog_message >/dev/null 2>&1
    then
        dialog_message \
            "Users" \
            "User configuration completed successfully" \
            || true
    fi

    users_log_info \
        "=========================================="

    users_log_info \
        "User configuration finished successfully"

    users_log_info \
        "=========================================="

    return 0
}

#============================================================
# End
#============================================================
