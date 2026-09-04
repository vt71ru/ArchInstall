#============================================================
# Main installer stage
#============================================================

services_configure()
{
    logger_info \
        "System service configuration started"

    #--------------------------------------------------------
    # Target
    #--------------------------------------------------------

    services_check_target || \
        return 1

    #--------------------------------------------------------
    # Configuration
    #--------------------------------------------------------

    services_load_config || \
        return 1

    services_validate_hostname || \
        return 1

    services_validate_ssh || \
        return 1

    #--------------------------------------------------------
    # Files
    #--------------------------------------------------------

    services_configure_hostname || \
        return 1

    services_configure_hosts || \
        return 1

    #--------------------------------------------------------
    # Services
    #--------------------------------------------------------

    services_network || \
        return 1

    services_ssh || \
        return 1

    #--------------------------------------------------------
    # systemd target
    #--------------------------------------------------------

    services_graphical_target || \
        return 1

    #--------------------------------------------------------
    # Verification
    #--------------------------------------------------------

    services_check_hostname || \
        return 1

    services_check_hosts || \
        return 1

    services_check_network || \
        return 1

    services_check_ssh || \
        return 1

    services_check_target_mode || \
        return 1

    #--------------------------------------------------------
    # Save
    #--------------------------------------------------------

    services_save || \
        return 1

    #--------------------------------------------------------
    # Finished
    #--------------------------------------------------------

    dialog_message \
        "Services" \
        "System services configured successfully"

    logger_info \
        "System service configuration finished"

    return 0
}

#============================================================
# END
#============================================================
