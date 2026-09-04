#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  installer/locale_generate.sh
#
#  Генерация локалей и применение locale/keymap
#  в установленной системе.
#
#  Ответственность:
#   • проверка target system
#   • включение выбранных локалей в locale.gen
#   • запуск locale-gen через arch-chroot
#   • создание /etc/locale.conf
#   • создание /etc/vconsole.conf
#   • проверка результата
#
#  Live ISO не изменяется.
#
#============================================================

#============================================================
# Load guard
#============================================================

if [[ -n "${LOCALE_GENERATE_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

LOCALE_GENERATE_SH_LOADED=1
export LOCALE_GENERATE_SH_LOADED

#============================================================
# State
#============================================================

LOCALE_TARGET_ROOT="${LOCALE_TARGET_ROOT:-/mnt}"

#============================================================
# Logging
#============================================================

locale_generate_log_info()
{
    if declare -F log_info >/dev/null 2>&1
    then
        log_info "$@" || true
    elif declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$@" || true
    else
        printf '[INFO] %s\n' "$*" >&2
    fi

    return 0
}

locale_generate_log_warn()
{
    if declare -F log_warn >/dev/null 2>&1
    then
        log_warn "$@" || true
    elif declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$@" || true
    else
        printf '[WARN] %s\n' "$*" >&2
    fi

    return 0
}

locale_generate_log_error()
{
    if declare -F log_error >/dev/null 2>&1
    then
        log_error "$@" || true
    elif declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$@" || true
    else
        printf '[ERROR] %s\n' "$*" >&2
    fi

    return 0
}

#============================================================
# Set target root
#============================================================

locale_set_root()
{
    local root="${1:-}"

    if [[ -z "$root" ]]
    then
        locale_generate_log_error \
            "Locale target root is empty"
        return 1
    fi

    if [[ ! -d "$root" ]]
    then
        locale_generate_log_error \
            "Locale target root does not exist: ${root}"
        return 1
    fi

    LOCALE_TARGET_ROOT="$root"

    locale_generate_log_info \
        "Locale target root: ${LOCALE_TARGET_ROOT}"

    return 0
}

#============================================================
# Check required commands
#============================================================

locale_generate_check_dependencies()
{
    local required=(
        arch-chroot
        grep
        sed
        chmod
        mountpoint
    )

    local cmd

    for cmd in "${required[@]}"
    do
        if ! command -v "$cmd" >/dev/null 2>&1
        then
            locale_generate_log_error \
                "Required program not found: ${cmd}"
            return 1
        fi
    done

    return 0
}

#============================================================
# Validate target
#============================================================

locale_generate_check_target()
{
    local root="${LOCALE_TARGET_ROOT}"

    if [[ ! -d "$root" ]]
    then
        locale_generate_log_error \
            "Target root does not exist: ${root}"
        return 1
    fi

    if [[ ! -d "${root}/etc" ]]
    then
        locale_generate_log_error \
            "Target /etc does not exist: ${root}/etc"
        return 1
    fi

    if [[ ! -f "${root}/etc/locale.gen" ]]
    then
        locale_generate_log_error \
            "Target locale.gen is missing: ${root}/etc/locale.gen"
        return 1
    fi

    if [[ ! -x "${root}/usr/bin/locale-gen" ]]
    then
        locale_generate_log_error \
            "locale-gen is missing in target system"
        return 1
    fi

    if ! mountpoint -q "$root"
    then
        locale_generate_log_error \
            "Target root is not mounted: ${root}"
        return 1
    fi

    locale_generate_log_info \
        "Target system validation passed"

    return 0
}

#============================================================
# Validate locale
#============================================================

locale_generate_validate_locale()
{
    local locale="${1:-}"

    if [[ -z "$locale" ]]
    then
        return 1
    fi

    [[ "$locale" =~ ^[A-Za-z_]+\.UTF-8$ ]]
}

#============================================================
# Validate keymap
#============================================================

locale_generate_validate_keymap()
{
    local keymap="${1:-}"

    if [[ -z "$keymap" ]]
    then
        return 1
    fi

    [[ "$keymap" =~ ^[a-zA-Z0-9_-]+$ ]]
}

#============================================================
# Get configured locales
#============================================================

locale_generate_get_locales()
{
    local locales=""

    if ! declare -F config_get >/dev/null 2>&1
    then
        locale_generate_log_error \
            "config_get() is not available"
        return 1
    fi

    locales="$(
        config_get LOCALES \
            2>/dev/null \
            || true
    )"

    if [[ -z "$locales" ]]
    then
        locale_generate_log_error \
            "No locales configured"
        return 1
    fi

    printf '%s\n' "$locales"

    return 0
}

#============================================================
# Enable locales in locale.gen
#============================================================

locale_enable_file()
{
    local file="${1:-}"
    local locales=""
    local locale=""
    local found=0

    if [[ -z "$file" ]]
    then
        locale_generate_log_error \
            "locale_enable_file: empty file path"
        return 1
    fi

    if [[ ! -f "$file" ]]
    then
        locale_generate_log_error \
            "Missing locale file: ${file}"
        return 1
    fi

    if ! locales="$(
        locale_generate_get_locales
    )"
    then
        return 1
    fi

    while IFS= read -r locale
    do
        [[ -z "$locale" ]] && continue

        locale_generate_validate_locale "$locale" || {
            locale_generate_log_error \
                "Invalid locale name: ${locale}"
            return 1
        }

        #----------------------------------------------------
        # Check locale exists in locale.gen.
        #
        # Expected forms:
        #
        # en_US.UTF-8 UTF-8
        # #en_US.UTF-8 UTF-8
        # # en_US.UTF-8 UTF-8
        #----------------------------------------------------

        if grep -Eq \
            "^[#[:space:]]*${locale}[[:space:]]+UTF-8([[:space:]]*)$" \
            "$file"
        then
            found=1
        else
            locale_generate_log_error \
                "Locale is not available in ${file}: ${locale}"
            return 1
        fi

        #----------------------------------------------------
        # Remove leading comments/spaces while preserving
        # the actual locale entry.
        #----------------------------------------------------

        if ! sed -i \
            -E \
            "s|^[#[:space:]]*(${locale}[[:space:]]+UTF-8[[:space:]]*)$|\1|" \
            "$file"
        then
            locale_generate_log_error \
                "Failed enabling locale: ${locale}"
            return 1
        fi

        locale_generate_log_info \
            "Locale enabled: ${locale}"

    done <<< "$locales"

    if (( found == 0 ))
    then
        locale_generate_log_error \
            "No valid locales were found"
        return 1
    fi

    return 0
}

#============================================================
# Generate target locales
#============================================================

locale_generate_target()
{
    locale_generate_log_info \
        "Generating target locales"

    if ! arch-chroot \
        "$LOCALE_TARGET_ROOT" \
        /usr/bin/locale-gen
    then
        locale_generate_log_error \
            "Target locale generation failed"
        return 1
    fi

    locale_generate_log_info \
        "Target locales generated"

    return 0
}

#============================================================
# Write locale.conf
#============================================================

locale_write_conf()
{
    local locale=""
    local file="${LOCALE_TARGET_ROOT}/etc/locale.conf"

    if ! declare -F config_get >/dev/null 2>&1
    then
        locale_generate_log_error \
            "config_get() is not available"
        return 1
    fi

    locale="$(
        config_get LOCALE \
            2>/dev/null \
            || true
    )"

    if [[ -z "$locale" ]]
    then
        locale_generate_log_error \
            "Default locale is not configured"
        return 1
    fi

    locale_generate_validate_locale "$locale" || {
        locale_generate_log_error \
            "Invalid default locale: ${locale}"
        return 1
    }

    #--------------------------------------------------------
    # Verify selected locale is present in LOCALES.
    #--------------------------------------------------------

    local configured_locales=""

    configured_locales="$(
        config_get LOCALES \
            2>/dev/null \
            || true
    )"

    if ! grep -Fqx \
        "$locale" \
        <(
            tr ' ' '\n' <<< "$configured_locales"
        )
    then
        locale_generate_log_error \
            "Default locale is not in LOCALES: ${locale}"
        return 1
    fi

    #--------------------------------------------------------
    # Write file atomically.
    #--------------------------------------------------------

    local tmp_file="${file}.tmp.$$"

    if ! printf \
        'LANG=%s\n' \
        "$locale" \
        > "$tmp_file"
    then
        locale_generate_log_error \
            "Failed writing temporary locale.conf"
        rm -f "$tmp_file"
        return 1
    fi

    if ! chmod 644 "$tmp_file"
    then
        locale_generate_log_error \
            "Failed setting permissions on locale.conf"
        rm -f "$tmp_file"
        return 1
    fi

    if ! mv \
        -f \
        "$tmp_file" \
        "$file"
    then
        locale_generate_log_error \
            "Failed installing locale.conf"
        rm -f "$tmp_file"
        return 1
    fi

    locale_generate_log_info \
        "locale.conf created: ${file}"

    return 0
}

#============================================================
# Write vconsole.conf
#============================================================

locale_write_vconsole_conf()
{
    local keymap=""
    local file="${LOCALE_TARGET_ROOT}/etc/vconsole.conf"

    if ! declare -F config_get >/dev/null 2>&1
    then
        locale_generate_log_error \
            "config_get() is not available"
        return 1
    fi

    keymap="$(
        config_get SYSTEM_KEYMAP \
            2>/dev/null \
            || true
    )"

    if [[ -z "$keymap" ]]
    then
        locale_generate_log_error \
            "SYSTEM_KEYMAP is not configured"
        return 1
    fi

    locale_generate_validate_keymap "$keymap" || {
        locale_generate_log_error \
            "Invalid keymap: ${keymap}"
        return 1
    }

    local tmp_file="${file}.tmp.$$"

    if ! printf \
        'KEYMAP=%s\n' \
        "$keymap" \
        > "$tmp_file"
    then
        locale_generate_log_error \
            "Failed writing temporary vconsole.conf"
        rm -f "$tmp_file"
        return 1
    fi

    if ! chmod 644 "$tmp_file"
    then
        locale_generate_log_error \
            "Failed setting permissions on vconsole.conf"
        rm -f "$tmp_file"
        return 1
    fi

    if ! mv \
        -f \
        "$tmp_file" \
        "$file"
    then
        locale_generate_log_error \
            "Failed installing vconsole.conf"
        rm -f "$tmp_file"
        return 1
    fi

    locale_generate_log_info \
        "vconsole.conf created: ${file}"

    return 0
}

#============================================================
# Verify locale.conf
#============================================================

locale_verify_conf()
{
    local expected=""
    local actual=""
    local file="${LOCALE_TARGET_ROOT}/etc/locale.conf"

    expected="$(
        config_get LOCALE \
            2>/dev/null \
            || true
    )"

    actual="$(
        sed \
            -n \
            's/^LANG=//p' \
            "$file" \
            2>/dev/null |
        head -n 1
    )"

    if [[ "$actual" != "$expected" ]]
    then
        locale_generate_log_error \
            "locale.conf verification failed: expected=${expected:-empty} actual=${actual:-empty}"
        return 1
    fi

    locale_generate_log_info \
        "locale.conf verification passed"

    return 0
}

#============================================================
# Verify vconsole.conf
#============================================================

locale_verify_vconsole()
{
    local expected=""
    local actual=""
    local file="${LOCALE_TARGET_ROOT}/etc/vconsole.conf"

    expected="$(
        config_get SYSTEM_KEYMAP \
            2>/dev/null \
            || true
    )"

    actual="$(
        sed \
            -n \
            's/^KEYMAP=//p' \
            "$file" \
            2>/dev/null |
        head -n 1
    )"

    if [[ "$actual" != "$expected" ]]
    then
        locale_generate_log_error \
            "vconsole.conf verification failed: expected=${expected:-empty} actual=${actual:-empty}"
        return 1
    fi

    locale_generate_log_info \
        "vconsole.conf verification passed"

    return 0
}

#============================================================
# Verify generated locale
#============================================================

locale_verify_generated()
{
    local locale=""
    local short_locale=""
    local available=""

    locale="$(
        config_get LOCALE \
            2>/dev/null \
            || true
    )"

    if [[ -z "$locale" ]]
    then
        locale_generate_log_error \
            "Cannot verify generated locale: LOCALE is empty"
        return 1
    fi

    short_locale="${locale%.UTF-8}"

    available="$(
        arch-chroot \
            "$LOCALE_TARGET_ROOT" \
            /usr/bin/locale \
            -a \
            2>/dev/null \
            || true
    )"

    # locale -a commonly returns:
    #
    # en_US.utf8
    # ru_RU.utf8
    #
    # but exact case may differ.
    if grep -Fqi \
        "${short_locale}.utf8" \
        <<< "$available"
    then
        locale_generate_log_info \
            "Generated locale verified: ${locale}"
        return 0
    fi

    if grep -Fqi \
        "$locale" \
        <<< "$available"
    then
        locale_generate_log_info \
            "Generated locale verified: ${locale}"
        return 0
    fi

    locale_generate_log_error \
        "Generated locale not found: ${locale}"

    return 1
}

#============================================================
# Save state
#============================================================

locale_generate_save_state()
{
    if declare -F config_save >/dev/null 2>&1
    then
        if ! config_save
        then
            locale_generate_log_error \
                "Failed to save locale state"
            return 1
        fi
    fi

    return 0
}

#============================================================
# Full apply
#============================================================

locale_apply_all()
{
    locale_generate_log_info \
        "Locale generation started"

    locale_generate_check_dependencies || \
        return 1

    locale_generate_check_target || \
        return 1

    locale_enable_file \
        "${LOCALE_TARGET_ROOT}/etc/locale.gen" || \
        return 1

    locale_generate_target || \
        return 1

    locale_write_conf || \
        return 1

    locale_write_vconsole_conf || \
        return 1

    locale_verify_conf || \
        return 1

    locale_verify_vconsole || \
        return 1

    locale_verify_generated || \
        return 1

    locale_generate_save_state || \
        return 1

    if declare -F dialog_message >/dev/null 2>&1
    then
        dialog_message \
            "Locale" \
            "Locale and keyboard configuration completed" || true
    fi

    locale_generate_log_info \
        "Locale generation completed"

    return 0
}

#============================================================
# Main stage
#============================================================

locale_generate()
{
    locale_apply_all
}

#============================================================
# Direct execution
#============================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
    locale_generate "$@"
    exit $?
fi

