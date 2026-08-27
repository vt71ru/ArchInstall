#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  locale_generate.sh
#
#  Применение локали и keymap к установленной системе.
#
#  Ответственность:
#   • Проверка target system
#   • Включение выбранных локалей
#   • Запуск locale-gen в target
#   • Создание /etc/locale.conf
#   • Создание /etc/vconsole.conf
#   • Проверка результата
#
#  Live ISO не изменяется.
#============================================================

[[ -n "${LOCALE_GENERATE_SH_LOADED:-}" ]] && return

readonly LOCALE_GENERATE_SH_LOADED=1

LOCALE_TARGET_ROOT="/mnt"

#------------------------------------------------------------
# Set target root
#------------------------------------------------------------

locale_set_root()
{
    local root="${1:-}"

    if [[ -z "$root" ]]
    then
        logger_error \
            "Locale target root is empty"

        return 1
    fi

    if [[ ! -d "$root" ]]
    then
        logger_error \
            "Locale target root does not exist: ${root}"

        return 1
    fi

    LOCALE_TARGET_ROOT="$root"
}

#------------------------------------------------------------
# Validate target
#------------------------------------------------------------

locale_generate_check_target()
{
    local root="$LOCALE_TARGET_ROOT"

    if [[ ! -d "$root/etc" ]]
    then
        dialog_error \
            "Target /etc does not exist: ${root}/etc"

        return 1
    fi

    if [[ ! -f "$root/etc/locale.gen" ]]
    then
        dialog_error \
            "Target locale.gen is missing: ${root}/etc/locale.gen"

        return 1
    fi

    if [[ ! -x "$root/usr/bin/locale-gen" ]]
    then
        dialog_error \
            "locale-gen is missing in target system"

        return 1
    fi

    if ! mountpoint -q "$root"
    then
        dialog_error \
            "Target root is not mounted: ${root}"

        return 1
    fi
}

#------------------------------------------------------------
# Validate locale
#------------------------------------------------------------

locale_generate_validate_locale()
{
    local locale="$1"

    [[ "$locale" =~ ^[A-Za-z_]+\.UTF-8$ ]]
}

#------------------------------------------------------------
# Validate keymap
#------------------------------------------------------------

locale_generate_validate_keymap()
{
    local keymap="$1"

    [[ "$keymap" =~ ^[a-zA-Z0-9_-]+$ ]]
}

#------------------------------------------------------------
# Enable locale in locale.gen
#------------------------------------------------------------

locale_enable_file()
{
    local file="$1"
    local locales
    local locale

    [[ -f "$file" ]] || {
        logger_error \
            "Missing locale file: ${file}"

        return 1
    }

    locales="$(
        config_get LOCALES
    )"

    if [[ -z "$locales" ]]
    then
        logger_error \
            "No locales configured"

        return 1
    fi

    for locale in $locales
    do
        locale_generate_validate_locale \
            "$locale" || {
            logger_error \
                "Invalid locale name: ${locale}"

            return 1
        }

        if ! grep -Eq \
            "^#?[[:space:]]*${locale}[[:space:]]+UTF-8[[:space:]]*$" \
            "$file"
        then
            logger_error \
                "Locale is not available in ${file}: ${locale}"

            return 1
        fi

        sed -i \
            -E \
            "s|^[#[:space:]]*(${locale}[[:space:]]+UTF-8[[:space:]]*)$|\\1|" \
            "$file"
    done
}

#------------------------------------------------------------
# Generate locales
#------------------------------------------------------------

locale_generate_target()
{
    logger_info \
        "Generating target locales"

    arch-chroot \
        "$LOCALE_TARGET_ROOT" \
        locale-gen \
        || {
            logger_error \
                "Target locale generation failed"

            return 1
        }

    logger_info \
        "Target locales generated"
}

#------------------------------------------------------------
# Write locale.conf
#------------------------------------------------------------

locale_write_conf()
{
    local locale
    local file="${LOCALE_TARGET_ROOT}/etc/locale.conf"

    locale="$(
        config_get LOCALE
    )"

    if [[ -z "$locale" ]]
    then
        logger_error \
            "Default locale is not configured"

        return 1
    fi

    locale_generate_validate_locale \
        "$locale" || {
        logger_error \
            "Invalid default locale: ${locale}"

        return 1
    }

    if ! grep -Fxq \
        "$locale" \
        <(
            config_get LOCALES |
            tr ' ' '\n'
        )
    then
        logger_error \
            "Default locale is not in LOCALES: ${locale}"

        return 1
    fi

    printf \
        'LANG=%s\n' \
        "$locale" \
        > "$file"

    chmod 644 \
        "$file"

    logger_info \
        "locale.conf created"
}

#------------------------------------------------------------
# Write vconsole.conf
#------------------------------------------------------------

locale_write_vconsole_conf()
{
    local keymap
    local file="${LOCALE_TARGET_ROOT}/etc/vconsole.conf"

    keymap="$(
        config_get SYSTEM_KEYMAP
    )"

    if [[ -z "$keymap" ]]
    then
        logger_error \
            "SYSTEM_KEYMAP is not configured"

        return 1
    fi

    locale_generate_validate_keymap \
        "$keymap" || {
        logger_error \
            "Invalid keymap: ${keymap}"

        return 1
    }

    printf \
        'KEYMAP=%s\n' \
        "$keymap" \
        > "$file"

    chmod 644 \
        "$file"

    logger_info \
        "vconsole.conf created"
}

#------------------------------------------------------------
# Verify locale.conf
#------------------------------------------------------------

locale_verify_conf()
{
    local expected
    local actual

    expected="$(
        config_get LOCALE
    )"

    actual="$(
        sed \
            -n \
            's/^LANG=//p' \
            "${LOCALE_TARGET_ROOT}/etc/locale.conf" |
        head -n 1
    )"

    if [[ "$actual" != "$expected" ]]
    then
        logger_error \
            "locale.conf verification failed: expected=${expected} actual=${actual:-empty}"

        return 1
    fi

    logger_info \
        "locale.conf verification passed"
}

#------------------------------------------------------------
# Verify vconsole.conf
#------------------------------------------------------------

locale_verify_vconsole()
{
    local expected
    local actual

    expected="$(
        config_get SYSTEM_KEYMAP
    )"

    actual="$(
        sed \
            -n \
            's/^KEYMAP=//p' \
            "${LOCALE_TARGET_ROOT}/etc/vconsole.conf" |
        head -n 1
    )"

    if [[ "$actual" != "$expected" ]]
    then
        logger_error \
            "vconsole.conf verification failed: expected=${expected} actual=${actual:-empty}"

        return 1
    fi

    logger_info \
        "vconsole.conf verification passed"
}

#------------------------------------------------------------
# Verify generated locale
#------------------------------------------------------------

locale_verify_generated()
{
    local locale
    local short_locale
    local available

    locale="$(
        config_get LOCALE
    )"

    short_locale="${locale%.UTF-8}"

    available="$(
        arch-chroot \
            "$LOCALE_TARGET_ROOT" \
            locale \
            -a \
            2>/dev/null \
            || true
    )"

    if grep -Fqi \
        "${short_locale}.utf8" \
        <<< "$available"
    then
        logger_info \
            "Generated locale verified: ${locale}"

        return 0
    fi

    if grep -Fxq \
        "$locale" \
        <<< "$available"
    then
        logger_info \
            "Generated locale verified: ${locale}"

        return 0
    fi

    logger_error \
        "Generated locale not found: ${locale}"

    return 1
}

#------------------------------------------------------------
# Full apply
#------------------------------------------------------------

locale_apply_all()
{
    logger_info \
        "Locale setup started"

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

    config_save

    logger_info \
        "Locale setup completed"
}

#------------------------------------------------------------
# Main
#------------------------------------------------------------

locale_generate()
{
    locale_apply_all
}