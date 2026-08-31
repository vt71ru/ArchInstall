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
#   • запуск отдельных этапов
#   • запуск полной установки
#   • проверка этапов
#   • управление порядком этапов
#   • запуск главного меню
#
#  НЕ отвечает за:
#   • загрузку библиотек
#   • загрузку installer-модулей
#   • проверку root
#   • проверку Arch Linux
#   • инициализацию TUI
#   • хранение CONFIG
#
#============================================================

#============================================================
# Include guard
#============================================================

if [[ -n "${ARCH_INSTALLER_INSTALLER_SH_LOADED:-}" ]]
then
    return 0 2>/dev/null || exit 0
fi

ARCH_INSTALLER_INSTALLER_SH_LOADED=1
export ARCH_INSTALLER_INSTALLER_SH_LOADED

#============================================================
# Logging helpers
#============================================================

installer_log()
{
    local message="${1:-}"

    if declare -F tui_log >/dev/null 2>&1
    then
        tui_log "$message" || true
        return 0
    fi

    printf '%s\n' "$message"
}

installer_log_info()
{
    local message="${1:-}"

    if declare -F logger_info >/dev/null 2>&1
    then
        logger_info "$message" || true
        return 0
    fi

    printf '[INFO] %s\n' "$message"
}

installer_log_warn()
{
    local message="${1:-}"

    if declare -F logger_warn >/dev/null 2>&1
    then
        logger_warn "$message" || true
        return 0
    fi

    printf '[WARN] %s\n' "$message" >&2
}

installer_log_error()
{
    local message="${1:-}"

    if declare -F logger_error >/dev/null 2>&1
    then
        logger_error "$message" || true
        return 0
    fi

    printf '[ERROR] %s\n' "$message" >&2
}

#============================================================
# Stage -> function mapping
#============================================================

installer_get_stage_function()
{
    local stage="${1:-}"

    case "$stage"
    in
        welcome)
            printf '%s\n' 'welcome'
            ;;

        keyboard)
            printf '%s\n' 'keyboard'
            ;;

        locale)
            printf '%s\n' 'locale'
            ;;

        locale_generate)
            printf '%s\n' 'locale_generate'
            ;;

        network)
            printf '%s\n' 'network'
            ;;

        mirrors)
            printf '%s\n' 'mirrors'
            ;;

        disks)
            printf '%s\n' 'disks'
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
            printf '%s\n' 'packages_install'
            ;;

        users)
            printf '%s\n' 'users_configure'
            ;;

        desktop)
            printf '%s\n' 'desktop_install'
            ;;

        services)
            printf '%s\n' 'services_configure'
            ;;

        bootloader)
            printf '%s\n' 'bootloader_install'
            ;;

        summary)
            printf '%s\n' 'summary_show'
            ;;

        *)
            return 1
            ;;
    esac
}

#============================================================
# Stage title
#============================================================

installer_get_stage_title()
{
    local stage="${1:-}"

    case "$stage"
    in
        welcome)
            printf '%s\n' 'Welcome'
            ;;

        keyboard)
            printf '%s\n' 'Keyboard configuration'
            ;;

        locale)
            printf '%s\n' 'Locale configuration'
            ;;

        locale_generate)
            printf '%s\n' 'Locale generation'
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
            printf '%s\n' "$stage"
            ;;
    esac
}

#============================================================
# Full installation stage list
#============================================================

installer_full_installation_stages()
{
    printf '%s\n' \
        keyboard \
        locale \
        locale_generate \
        network \
        mirrors \
        disks \
        partition \
        filesystem \
        mount \
        packages \
        users \
        desktop \
        services \
        bootloader \
        summary
}

#============================================================
# Get total stage count
#============================================================

installer_get_stage_count()
{
    local count=0
    local stage

    while IFS= read -r stage
    do
        [[ -z "$stage" ]] && continue
        count=$((count + 1))
    done < <(
        installer_full_installation_stages
    )

    printf '%s\n' "$count"
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

    if ! function_name="$(
        installer_get_stage_function "$stage"
    )"
    then
        installer_log_error \
            "Unknown installer stage: ${stage}"

        return 1
    fi

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        installer_log_error \
            "Stage function is not loaded: ${function_name} (stage=${stage})"

        return 1
    fi

    return 0
}

#============================================================
# Check all stages
#============================================================

installer_check_all_stages()
{
    local stage
    local failed=0

    installer_log_info \
        "Checking installer stages..."

    while IFS= read -r stage
    do
        [[ -z "$stage" ]] && continue

        installer_log_info \
            "Checking stage: ${stage}"

        if ! installer_check_stage "$stage"
        then
            installer_log_error \
                "Stage check failed: ${stage}"

            failed=1
        fi

    done < <(
        installer_full_installation_stages
    )

    if (( failed != 0 ))
    then
        installer_log_error \
            "One or more installer stages are unavailable"

        return 1
    fi

    installer_log_info \
        "All installer stages are available"

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

    if [[ -z "$stage" ]]
    then
        installer_log_error \
            "installer_run_stage: empty stage"

        return 1
    fi

    if ! function_name="$(
        installer_get_stage_function "$stage"
    )"
    then
        installer_log_error \
            "Unknown installer stage: ${stage}"

        return 1
    fi

    title="$(
        installer_get_stage_title "$stage"
    )"

    if ! declare -F "$function_name" >/dev/null 2>&1
    then
        installer_log_error \
            "Function not found: ${function_name}"

        return 127
    fi

    installer_log_info \
        "Starting stage: ${title}"

    #--------------------------------------------------------
    # IMPORTANT
    #
    # The function call is inside an if statement.
    # This prevents set -e from terminating the controller
    # before we can capture the real return code.
    #--------------------------------------------------------

    if "$function_name"
    then
        rc=0
    else
        rc=$?
    fi

    if (( rc != 0 ))
    then
        installer_log_error \
            "Stage failed: ${title}"

        installer_log_error \
            "Stage name: ${stage}"

        installer_log_error \
            "Function: ${function_name}"

        installer_log_error \
            "Exit code: ${rc}"

        return "$rc"
    fi

    installer_log_info \
        "Stage completed: ${title}"

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

    installer_log_info \
        "=========================================="

    installer_log_info \
        "STARTING FULL INSTALLATION"

    installer_log_info \
        "=========================================="

    #--------------------------------------------------------
    # Verify all stages before starting.
    #--------------------------------------------------------

    if ! installer_check_all_stages
    then
        installer_log_error \
            "Full installation cannot start."

        return 1
    fi

    total="$(
        installer_get_stage_count
    )"

    if [[ -z "$total" || "$total" == "0" ]]
    then
        installer_log_error \
            "No installation stages defined."

        return 1
    fi

    installer_log_info \
        "Total installation stages: ${total}"

    #--------------------------------------------------------
    # Execute stages sequentially.
    #--------------------------------------------------------

    while IFS= read -r stage
    do
        [[ -z "$stage" ]] && continue

        step=$((step + 1))

        title="$(
            installer_get_stage_title "$stage"
        )"

        installer_log_info \
            "------------------------------------------"

        installer_log_info \
            "STEP ${step}/${total}: ${title}"

        installer_log_info \
            "Stage ID: ${stage}"

        installer_log_info \
            "------------------------------------------"

        if installer_run_stage "$stage"
        then
            rc=0
        else
            rc=$?
        fi

        if (( rc != 0 ))
        then
            installer_log_error \
                "=========================================="

            installer_log_error \
                "FULL INSTALLATION FAILED"

            installer_log_error \
                "Failed stage: ${title}"

            installer_log_error \
                "Stage ID: ${stage}"

            installer_log_error \
                "Exit code: ${rc}"

            installer_log_error \
                "=========================================="

            return "$rc"
        fi

    done < <(
        installer_full_installation_stages
    )

    installer_log_info \
        "=========================================="

    installer_log_info \
        "FULL INSTALLATION COMPLETED SUCCESSFULLY"

    installer_log_info \
        "=========================================="

    return 0
}

#============================================================
# Run operation
#============================================================

installer_run()
{
    local operation="${1:-}"

    case "$operation"
    in
        full|full_install|install)
            installer_full_install
            ;;

        welcome)
            installer_run_stage welcome
            ;;

        keyboard)
            installer_run_stage keyboard
            ;;

        locale)
            installer_run_stage locale
            ;;

        locale_generate)
            installer_run_stage locale_generate
            ;;

        network)
            installer_run_stage network
            ;;

        mirrors)
            installer_run_stage mirrors
            ;;

        disks|disk)
            installer_run_stage disks
            ;;

        partition|part)
            installer_run_stage partition
            ;;

        filesystem|fs)
            installer_run_stage filesystem
            ;;

        mount)
            installer_run_stage mount
            ;;

        packages|pkg)
            installer_run_stage packages
            ;;

        users|user)
            installer_run_stage users
            ;;

        desktop)
            installer_run_stage desktop
            ;;

        services)
            installer_run_stage services
            ;;

        bootloader|boot)
            installer_run_stage bootloader
            ;;

        summary)
            installer_run_stage summary
            ;;

        *)
            installer_log_error \
                "Unknown installer operation: ${operation:-<empty>}"

            return 2
            ;;
    esac
}

#============================================================
# Start main menu
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

    if menu_main
    then
        return 0
    fi

    return $?
}

#============================================================
# Controller entry point
#============================================================

installer_main()
{
    local operation="${1:-menu}"

    case "$operation"
    in
        menu)
            installer_start_menu
            ;;

        full|full_install|install)
            installer_full_install
            ;;

        *)
            installer_run "$operation"
            ;;
    esac
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
#
# Normally this file is SOURCED by install.sh.
#
# If somebody runs:
#
#   ./installer/installer.sh
#
# it will attempt to execute the requested operation.
#============================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
    installer_main "$@"
    exit $?
fi
```
