```bash
#!/usr/bin/env bash
#
#============================================================
#  Arch Installer
#------------------------------------------------------------
#  installer/installer.sh
#
#  Центральный controller установки.
#
#  Ответственность:
#   • запуск главного меню
#   • запуск отдельных этапов
#   • запуск полной установки
#   • контроль порядка этапов
#   • проверка entry point
#   • хранение состояния controller
#   • обработка ошибок
#   • возврат кодов завершения
#
#  НЕ отвечает за:
#   • загрузку библиотек
#   • загрузку installer-модулей
#   • проверку Arch Linux
#   • проверку root
#   • инициализацию TUI
#   • хранение конфигурации
#
#============================================================

#============================================================
# Protection against repeated loading
#============================================================

if [[ -n "${ARCH_INSTALLER_INSTALLER_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

readonly ARCH_INSTALLER_INSTALLER_SH_LOADED=1


#============================================================
# Controller state
#============================================================

INSTALLER_CURRENT_STAGE=""
INSTALLER_LAST_FUNCTION=""
INSTALLER_LAST_MESSAGE=""
INSTALLER_LAST_RC=0


#============================================================
# Logging
#============================================================

installer_log()
{
    local message="${1:-}"

    if declare -F tui_log >/dev/null 2>&1
    then
        tui_log "$message"
    else
        printf '%s\n' "$message"
    fi

    return 0
}


installer_log_info()
{
    local message="${1:-}"

    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$message"
        return 0
    fi

    if declare -F tui_log_info >/dev/null 2>&1
    then
        tui_log_info "$message"
        return 0
    fi

    printf '[INFO] %s\n' "$message"

    return 0
}


installer_log_warn()
{
    local message="${1:-}"

    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$message"
        return 0
    fi

    if declare -F tui_log_warn >/dev/null 2>&1
    then
        tui_log_warn "$message"
        return 0
    fi

    printf '[WARN] %s\n' "$message" >&2

    return 0
}


installer_log_error()
{
    local message="${1:-}"

    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$message"
        return 0
    fi

    if declare -F tui_log_error >/dev/null 2>&1
    then
        tui_log_error "$message"
        return 0
    fi

    printf '[ERROR] %s\n' "$message" >&2

    return 0
}


#============================================================
# Controller state getters
#============================================================

installer_get_stage()
{
    printf '%s\n' \
        "${INSTALLER_CURRENT_STAGE:-unknown}"

    return 0
}


installer_get_last_function()
{
    printf '%s\n' \
        "${INSTALLER_LAST_FUNCTION:-unknown}"

    return 0
}


installer_get_last_message()
{
    printf '%s\n' \
        "${INSTALLER_LAST_MESSAGE:-unknown}"

    return 0
}


installer_get_last_rc()
{
    printf '%s\n' \
        "${INSTALLER_LAST_RC:-0}"

    return 0
}


#============================================================
# Reset controller state
#============================================================

installer_reset_state()
{
    INSTALLER_CURRENT_STAGE=""
    INSTALLER_LAST_FUNCTION=""
    INSTALLER_LAST_MESSAGE=""
    INSTALLER_LAST_RC=0

    return 0
}


#============================================================
# Stage -> function mapping
#============================================================

installer_get_stage_function()
{
    local stage="${1:-}"

    case "$stage"
    in

        keyboard)
            printf '%s\n' 'keyboard_configure'
            ;;

        locale)
            printf '%s\n' 'locale_configure'
            ;;

        network)
            printf '%s\n' 'network_configure'
            ;;

        mirrors)
            printf '%s\n' 'mirrors_configure'
            ;;

        disks)
            printf '%s\n' 'disks_select'
            ;;

        partition)
            printf '%s\n' 'partition'
            ;;

        filesystem)
            printf '%s\n' 'filesystem'
            ;;

        mount)
            printf '%s\n' 'mount'
            ;;

        packages)
            printf '%s\n' 'packages'
            ;;

        users)
            printf '%s\n' 'users'
            ;;

        desktop)
            printf '%s\n' 'desktop'
            ;;

        services)
            printf '%s\n' 'services'
            ;;

        bootloader)
            printf '%s\n' 'bootloader'
            ;;

        summary)
            printf '%s\n' 'summary'
            ;;

        *)
            return 1
            ;;

    esac

    return 0
}


#============================================================
# Stage titles
#============================================================

installer_get_stage_title()
{
    local stage="${1:-}"

    case "$stage"
    in

        keyboard)
            printf '%s\n' 'Keyboard configuration'
            ;;

        locale)
            printf '%s\n' 'Locale configuration'
            ;;

        network)
            printf '%s\n' 'Network configuration'
            ;;

        mirrors)
            printf '%s\n' 'Mirror configuration'
            ;;

        disks)
            printf '%s\n' 'Disk selection'
            ;;

        partition)
            printf '%s\n' 'Disk partitioning'
            ;;

        filesystem)
            printf '%s\n' 'Filesystem creation'
            ;;

        mount)
            printf '%s\n' 'Mount filesystems'
            ;;

        packages)
            printf '%s\n' 'Package installation'
            ;;

        users)
            printf '%s\n' 'User configuration'
            ;;

        desktop)
            printf '%s\n' 'Desktop installation'
            ;;

        services)
            printf '%s\n' 'Service configuration'
            ;;

        bootloader)
            printf '%s\n' 'Bootloader installation'
            ;;

        summary)
            printf '%s\n' 'Installation summary'
            ;;

        *)
            printf '%s\n' "${stage:-unknown}"
            ;;

    esac

    return 0
}


#============================================================
# Full installation stage list
#============================================================

installer_full_installation_stages()
{
    cat <<'EOF'
keyboard
locale
network
mirrors
disks
partition
filesystem
mount
packages
users
desktop
services
bootloader
summary
EOF

    return 0
}


#============================================================
# Check one stage
#============================================================

installer_check_stage()
{
    local stage="${1:-}"
    local function_name=""

    if [[ -z "$stage" ]]
    then
        installer_log_error \
            "installer_check_stage: empty stage"

        return 1
    fi

    function_name="$(
        installer_get_stage_function "$stage"
    )"

    if [[ -z "$function_name" ]]
    then
        installer_log_error \
            "Unknown installer stage: ${stage}"

        return 1
    fi

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        installer_log_error \
            "Stage function is not loaded: ${function_name}"

        return 127
    fi

    return 0
}


#============================================================
# Check all stages
#============================================================

installer_check_all_stages()
{
    local stage=""

    while IFS= read -r stage
    do
        [[ -z "$stage" ]] && continue

        if ! installer_check_stage "$stage"
        then
            installer_log_error \
                "Stage check failed: ${stage}"

            return 1
        fi

    done < <(
        installer_full_installation_stages
    )

    return 0
}


#============================================================
# Run one stage
#============================================================

installer_run_stage()
{
    local stage="${1:-}"
    local function_name=""
    local title=""
    local rc=0

    INSTALLER_CURRENT_STAGE="${stage:-unknown}"
    INSTALLER_LAST_FUNCTION=""
    INSTALLER_LAST_MESSAGE=""
    INSTALLER_LAST_RC=0

    if [[ -z "$stage" ]]
    then
        INSTALLER_LAST_MESSAGE="Empty installer stage"
        INSTALLER_LAST_RC=1

        installer_log_error \
            "installer_run_stage: empty stage"

        return 1
    fi

    function_name="$(
        installer_get_stage_function "$stage"
    )"

    if [[ -z "$function_name" ]]
    then
        INSTALLER_LAST_MESSAGE="Unknown installer stage: ${stage}"
        INSTALLER_LAST_RC=1

        installer_log_error \
            "Unknown installer stage: ${stage}"

        return 1
    fi

    INSTALLER_LAST_FUNCTION="$function_name"

    title="$(
        installer_get_stage_title "$stage"
    )"

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        INSTALLER_LAST_MESSAGE="Function not loaded: ${function_name}"
        INSTALLER_LAST_RC=127

        installer_log_error \
            "Function not found: ${function_name}"

        return 127
    fi

    installer_log_info \
        "Starting: ${title}"

    "$function_name"
    rc=$?

    INSTALLER_LAST_RC="$rc"

    if (( rc != 0 ))
    then
        INSTALLER_LAST_MESSAGE="Stage failed: ${title}"

        installer_log_error \
            "Stage failed: ${title} (exit code ${rc})"

        return "$rc"
    fi

    INSTALLER_LAST_MESSAGE="Stage completed successfully"

    installer_log_info \
        "Completed: ${title}"

    return 0
}


#============================================================
# Full installation
#============================================================

installer_full_install()
{
    local stage=""
    local title=""
    local rc=0
    local step=0
    local total=0

    installer_reset_state

    installer_log_info \
        "=========================================="

    installer_log_info \
        "Starting full installation"

    installer_log_info \
        "=========================================="

    #--------------------------------------------------------
    # Check every stage before starting destructive work
    #--------------------------------------------------------

    if ! installer_check_all_stages
    then
        INSTALLER_LAST_MESSAGE="One or more installer stages are missing"
        INSTALLER_LAST_RC=1

        installer_log_error \
            "Full installation cannot start"

        installer_log_error \
            "One or more installer stages are missing"

        return 1
    fi

    total="$(
        installer_full_installation_stages |
            grep -c '.'
    )"

    while IFS= read -r stage
    do
        [[ -z "$stage" ]] && continue

        step=$((step + 1))

        INSTALLER_CURRENT_STAGE="$stage"

        title="$(
            installer_get_stage_title "$stage"
        )"

        installer_log_info \
            "STEP ${step}/${total}: ${title}"

        #----------------------------------------------------
        # Do not use:
        #
        # if ! installer_run_stage "$stage"
        # then
        #     rc=$?
        # fi
        #
        # because ! changes the return status.
        #----------------------------------------------------

        installer_run_stage "$stage"
        rc=$?

        if (( rc != 0 ))
        then
            INSTALLER_LAST_RC="$rc"

            installer_log_error \
                "=========================================="

            installer_log_error \
                "Full installation FAILED"

            installer_log_error \
                "Failed stage: ${title}"

            installer_log_error \
                "Function: ${INSTALLER_LAST_FUNCTION:-unknown}"

            installer_log_error \
                "Exit code: ${rc}"

            installer_log_error \
                "Message: ${INSTALLER_LAST_MESSAGE:-unknown}"

            installer_log_error \
                "=========================================="

            return "$rc"
        fi

    done < <(
        installer_full_installation_stages
    )

    INSTALLER_CURRENT_STAGE="complete"
    INSTALLER_LAST_FUNCTION=""
    INSTALLER_LAST_MESSAGE="Full installation completed successfully"
    INSTALLER_LAST_RC=0

    installer_log_info \
        "=========================================="

    installer_log_info \
        "Full installation completed successfully"

    installer_log_info \
        "=========================================="

    return 0
}


#============================================================
# Individual controller entry points
#============================================================

installer_keyboard()
{
    installer_run_stage keyboard
}


installer_locale()
{
    installer_run_stage locale
}


installer_network()
{
    installer_run_stage network
}


installer_mirrors()
{
    installer_run_stage mirrors
}


installer_disks()
{
    installer_run_stage disks
}


installer_partition()
{
    installer_run_stage partition
}


installer_filesystem()
{
    installer_run_stage filesystem
}


installer_mount()
{
    installer_run_stage mount
}


installer_packages()
{
    installer_run_stage packages
}


installer_users()
{
    installer_run_stage users
}


installer_desktop()
{
    installer_run_stage desktop
}


installer_services()
{
    installer_run_stage services
}


installer_bootloader()
{
    installer_run_stage bootloader
}


installer_summary()
{
    installer_run_stage summary
}


#============================================================
# Generic operation dispatcher
#
# IMPORTANT:
# No argument means FULL installation.
#
# This is required by menu_main.sh:
#
#     installer_run
#
#============================================================

installer_run()
{
    local operation="${1:-full}"
    local rc=0

    case "$operation"
    in

        full|full_install|install)
            installer_full_install
            rc=$?
            ;;

        keyboard)
            installer_keyboard
            rc=$?
            ;;

        locale)
            installer_locale
            rc=$?
            ;;

        network)
            installer_network
            rc=$?
            ;;

        mirrors)
            installer_mirrors
            rc=$?
            ;;

        disks|disk)
            installer_disks
            rc=$?
            ;;

        partition|part)
            installer_partition
            rc=$?
            ;;

        filesystem|fs)
            installer_filesystem
            rc=$?
            ;;

        mount)
            installer_mount
            rc=$?
            ;;

        packages|pkg)
            installer_packages
            rc=$?
            ;;

        users|user)
            installer_users
            rc=$?
            ;;

        desktop)
            installer_desktop
            rc=$?
            ;;

        services)
            installer_services
            rc=$?
            ;;

        bootloader|boot)
            installer_bootloader
            rc=$?
            ;;

        summary)
            installer_summary
            rc=$?
            ;;

        *)
            INSTALLER_LAST_MESSAGE="Unknown installer operation: ${operation}"
            INSTALLER_LAST_RC=2

            installer_log_error \
                "Unknown installer operation: ${operation:-<empty>}"

            return 2
            ;;

    esac

    return "$rc"
}


#============================================================
# Main menu entry point
#============================================================

installer_start_menu()
{
    if ! declare -F menu_main >/dev/null 2>&1
    then
        installer_log_error \
            "menu_main() is not loaded"

        return 127
    fi

    installer_log_info \
        "Starting main installer menu"

    menu_main
}


#============================================================
# Controller entry point
#============================================================

installer_main()
{
    local operation="${1:-menu}"
    local rc=0

    case "$operation"
    in

        menu)
            installer_start_menu
            rc=$?
            ;;

        full|full_install|install)
            installer_full_install
            rc=$?
            ;;

        *)
            installer_run "$operation"
            rc=$?
            ;;

    esac

    return "$rc"
}


#============================================================
# Public aliases
#============================================================

run_full_installation()
{
    installer_full_install "$@"
}


run_installation_stage()
{
    installer_run_stage "$@"
}


#============================================================
# Direct execution
#============================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
    installer_main "$@"
    exit $?
fi

#============================================================
# End
#============================================================
```
