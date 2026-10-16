INSTALLED_SCRIPT="$TARGET_DIR/$SCRIPT_NAME"
if [ "$FORCE_SETUP" = true ]; then
    write_ttc_log "INFO" "Setup requested with --setup."
    wizard_first_run
elif [ "$SETUP_COMPLETE" = "true" ] && [ "$HAS_ARGS" = false ]; then
    if [ -f "$INSTALLED_SCRIPT" ] && [ -f "$CONFIG_FILE" ]; then
        clear
        echo -e "\e[0;32m[+] Configuration found! Using saved settings.\e[0m"
        echo -e "\e[0;36m-> Press 'y' to re-run setup, or wait 5 seconds...\e[0m\n"
        read -t 5 -p "Setup done, do you want to re-run setup? (y/N): " rerun_setup
        if [[ "$rerun_setup" =~ ^[Yy]$ ]]; then
            write_ttc_log "INFO" "User triggered setup wizard from startup."
            wizard_first_run
        else
            write_ttc_log "INFO" "Startup prompt timed out. Proceeding."
            if [ "$CURRENT_DIR" != "$TARGET_DIR" ]; then
                cp "$LTTC_SELF" "$TARGET_DIR/$SCRIPT_NAME" 2>/dev/null
            fi
        fi
    else
        write_ttc_log "WARN" "Config missing but flag true. Forcing setup."
        wizard_first_run
    fi
elif [ "$SETUP_COMPLETE" != "true" ] && [ "$HAS_ARGS" = false ]; then
    write_ttc_log "INFO" "No config found. Initiating setup."
    wizard_first_run
fi

