#!/usr/bin/env bash
#
# ============================================================
# Arch Installer
# ------------------------------------------------------------
# installer/installer.sh
#
# Центральный controller установки.
#
# ============================================================

# ============================================================
# INSTALLATION STAGES
# ============================================================
#
# locale_generate должен выполняться после packages,
# поскольку он работает с установленной системой /mnt.
#
# ============================================================

declare -ar INSTALLER_STAGES=(
    "keyboard"
    "locale"
    "network"
    "mirrors"
    "disks"
    "partition"
    "filesystem"
    "mount"
    "packages"
    "locale_generate"
    "users"
    "desktop"
    "services"
    "bootloader"
    "summary"
)

# ============================================================
# LOGGING
# ============================================================

installer_log_info()
{
    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$*"
        return 0
    fi

    printf '[INFO] %s\n' "$*" >&2
    return 0
}

installer_log_warn()
{
    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$*"
        return 0
    fi

    printf '[WARN] %s\n' "$*" >&2
    return 0
}

installer_log_error()
{
    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$*"
        return 0
    fi

    printf '[ERROR] %s\n' "$*" >&2
    return 0
}

# ============================================================
# STAGE COUNT
# ============================================================

installer_get_stage_count()
{
    printf '%s\n' "${#INSTALLER_STAGES[@]}"
}

# ============================================================
# STAGE BY INDEX
# ============================================================

installer_get_stage_by_index()
{
    local index="${1:-}"

    if [[ ! "$index" =~ ^[0-9]+$ ]]
    then
        installer_log_error \
            "Invalid stage index: ${index}"

        return 1
    fi

    if (( index >= ${#INSTALLER_STAGES[@]} ))
    then
        installer_log_error \
            "Stage index out of range: ${index}"

        return 1
    fi

    printf '%s\n' \
        "${INSTALLER_STAGES[$index]}"

    return 0
}

# ============================================================
# STAGE TITLE
# ============================================================

installer_get_stage_title()
{
    local stage="${1:-}"

    case "$stage"
    in
        keyboard)
            printf '%s\n' "Keyboard configuration"
            ;;

        locale)
            printf '%s\n' "Locale configuration"
            ;;

        network)
            printf '%s\n' "Network configuration"
            ;;

        mirrors)
            printf '%s\n' "Mirror configuration"
            ;;

        disks)
            printf '%s\n' "Disk detection"
            ;;

        partition)
            printf '%s\n' "Disk partitioning"
            ;;

        filesystem)
            printf '%s\n' "Filesystem creation"
            ;;

        mount)
            printf '%s\n' "Mount filesystems"
            ;;

        packages)
            printf '%s\n' "Install base packages"
            ;;

        locale_generate)
            printf '%s\n' "Generate system locale"
            ;;

        users)
            printf '%s\n' "Configure users"
            ;;

        desktop)
            printf '%s\n' "Install desktop environment"
            ;;

        services)
            printf '%s\n' "Configure system services"
            ;;

        bootloader)
            printf '%s\n' "Install bootloader"
            ;;

        summary)
            printf '%s\n' "Installation summary"
            ;;

        *)
            installer_log_error \
                "Unknown installer stage: ${stage}"

            return 1
            ;;
    esac

    return 0
}

# ============================================================
# STAGE FUNCTION
# ============================================================

installer_get_stage_function()
{
    local stage="${1:-}"

    case "$stage"
    in
        keyboard)
            printf '%s\n' "keyboard"
            ;;

        locale)
            printf '%s\n' "locale"
            ;;

        network)
            printf '%s\n' "network"
            ;;

        mirrors)
            printf '%s\n' "mirrors"
            ;;

        disks)
            printf '%s\n' "disks"
            ;;

        partition)
            printf '%s\n' "partition"
            ;;

        filesystem)
            printf '%s\n' "filesystem"
            ;;

        mount)
            printf '%s\n' "mount_filesystems"
            ;;

        packages)
            printf '%s\n' "packages_install"
            ;;

        locale_generate)
            printf '%s\n' "locale_generate"
            ;;

        users)
            printf '%s\n' "users"
            ;;

        desktop)
            printf '%s\n' "desktop_install"
            ;;

        services)
            printf '%s\n' "services_configure"
            ;;

        bootloader)
            printf '%s\n' "bootloader_install"
            ;;

        summary)
            printf '%s\n' "summary"
            ;;

        *)
            installer_log_error \
                "Unknown installer stage: ${stage}"

            return 1
            ;;
    esac

    return 0
}

# ============================================================
# CHECK ONE STAGE
# ============================================================

installer_check_stage()
{
    local stage="${1:-}"
    local function_name=""

    [[ -n "$stage" ]] || return 1

    if ! function_name="$(
        installer_get_stage_function "$stage"
    )"
    then
        return 1
    fi

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        installer_log_error \
            "Stage function not found: ${function_name}"

        return 1
    fi

    return 0
}

# ============================================================
# CHECK ALL STAGES
# ============================================================

installer_check_all_stages()
{
    local stage=""
    local function_name=""

    installer_log_info \
        "Checking installer stage API"

    for stage in "${INSTALLER_STAGES[@]}"
    do
        if ! function_name="$(
            installer_get_stage_function "$stage"
        )"
        then
            installer_log_error \
                "Failed to resolve stage: ${stage}"

            return 1
        fi

        if ! declare -F "$function_name" >/dev/null 2>&1
        then
            installer_log_error \
                "Missing stage function: ${function_name} (${stage})"

            return 1
        fi

        installer_log_info \
            "Stage available: ${stage} -> ${function_name}"
    done

    installer_log_info \
        "All installer stages are available"

    return 0
}

# ============================================================
# RUN ONE STAGE
# ============================================================

installer_run_stage()
{
    local stage="${1:-}"
    local function_name=""
    local title=""
    local rc=0

    if [[ -z "$stage" ]]
    then
        installer_log_error \
            "installer_run_stage: empty stage"

        return 1
    fi

    if ! title="$(
        installer_get_stage_title "$stage"
    )"
    then
        title="$stage"
    fi

    if ! function_name="$(
        installer_get_stage_function "$stage"
    )"
    then
        installer_log_error \
            "Cannot resolve function for stage: ${stage}"

        return 1
    fi

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        installer_log_error \
            "Function not found: ${function_name}"

        return 127
    fi

    installer_log_info \
        "Starting stage: ${stage}"

    installer_log_info \
        "Stage title: ${title}"

    installer_log_info \
        "Stage function: ${function_name}"

    if "$function_name"
    then
        rc=0
    else
        rc=$?
    fi

    if (( rc == 0 ))
    then
        installer_log_info \
            "Stage completed successfully: ${stage}"
    else
        installer_log_error \
            "Stage failed: ${stage}, rc=${rc}"
    fi

    return "$rc"
}

# ============================================================
# FULL INSTALLATION
# ============================================================

installer_full_install()
{
    local stage=""
    local title=""
    local rc=0
    local index=0
    local total="${#INSTALLER_STAGES[@]}"

    printf '%s\n' \
        ">>> ENTER installer_full_install <<<" \
        >/dev/tty 2>/dev/null || true

    printf 'STAGE_COUNT=%s\n' \
        "$total" \
        >/dev/tty 2>/dev/null || true

    installer_log_info \
        ">>> ENTER installer_full_install <<<"

    installer_log_info \
        "FULL INSTALLATION STARTED"

    installer_log_info \
        "Total stages: ${total}"

    if (( total == 0 ))
    then
        installer_log_error \
            "INSTALLER_STAGES is empty"

        return 1
    fi

    if ! installer_check_all_stages
    then
        installer_log_error \
            "Installer stage API check failed"

        return 1
    fi

    for stage in "${INSTALLER_STAGES[@]}"
    do
        #
        # DO NOT use (( index++ )) with set -e.
        #
        (( index += 1 ))

        INSTALLER_STAGE="$stage"

        if ! title="$(
            installer_get_stage_title "$stage"
        )"
        then
            title="$stage"
        fi

        installer_log_info \
            "========================================"

        installer_log_info \
            "STAGE ${index}/${total}: ${title}"

        installer_log_info \
            "Stage ID: ${stage}"

        installer_log_info \
            "========================================"

        if installer_run_stage "$stage"
        then
            rc=0
        else
            rc=$?
        fi

        if (( rc != 0 ))
        then
            installer_log_error \
                "FULL INSTALLATION STOPPED"

            installer_log_error \
                "Failed stage: ${stage}"

            installer_log_error \
                "Return code: ${rc}"

            return "$rc"
        fi

        installer_log_info \
            "Stage ${index}/${total} completed successfully"
    done

    installer_log_info \
        "========================================"

    installer_log_info \
        "FULL INSTALLATION COMPLETED SUCCESSFULLY"

    installer_log_info \
        "========================================"

    return 0
}

# ============================================================
# GENERIC RUN
# ============================================================

installer_run()
{
    local action="${1:-}"

    shift || true

    case "$action"
    in
        full|full_install|install)
            installer_full_install "$@"
            ;;

        stage)
            if [[ $# -lt 1 ]]
            then
                installer_log_error \
                    "installer_run stage: stage name required"

                return 1
            fi

            installer_run_stage "$1"
            ;;

        menu)
            installer_start_menu "$@"
            ;;

        *)
            installer_log_error \
                "Unknown installer action: ${action}"

            return 1
            ;;
    esac
}

# ============================================================
# START MENU
# ============================================================

installer_start_menu()
{
    if declare -F menu_main >/dev/null 2>&1
    then
        menu_main "$@"
        return $?
    fi

    installer_log_error \
        "menu_main() is not available"

    return 127
}

# ============================================================
# MAIN
# ============================================================

installer_main()
{
    installer_start_menu "$@"
}

# ============================================================
# COMPATIBILITY ALIASES
# ============================================================

installer_install()
{
    installer_full_install "$@"
}

installer_full()
{
    installer_full_install "$@"
}

installer_stage()
{
    installer_run_stage "$@"
}

# ============================================================
# API CHECK
# ============================================================

installer_api_check()
{
    local required_function=""

    for required_function in \
        installer_run \
        installer_full_install \
        installer_run_stage \
        installer_check_stage \
        installer_check_all_stages \
        installer_get_stage_function \
        installer_get_stage_title \
        installer_start_menu \
        installer_main
    do
        if ! declare -F "$required_function" >/dev/null 2>&1
        then
            installer_log_error \
                "Installer API function missing: ${required_function}"

            return 1
        fi
    done

    return 0
}

# ============================================================
# DIRECT EXECUTION
# ============================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
    installer_main "$@"
fi
