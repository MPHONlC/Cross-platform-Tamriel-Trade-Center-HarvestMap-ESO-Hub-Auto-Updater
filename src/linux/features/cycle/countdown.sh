    if [ "$AUTO_MODE" == "1" ]; then exit 0; fi
    
    if [ "$CURRENT_TIME" -ge "${TARGET_RUN_TIME:-0}" ]; then
        TARGET_RUN_TIME=$((CURRENT_TIME + 3600))
        write_lttc_config
    fi
    target_time=$TARGET_RUN_TIME
    last_eso_check=$(date +%s)
    
    if [ "$IS_STEAM_LAUNCH" = true ]; then
        if [ "$SILENT" = true ]; then
            while [ $(date +%s) -lt $target_time ]; do
                read -t 1 -n 1 -s key 2>/dev/null || true
                current_loop_time=$(date +%s)
                if (( current_loop_time - last_eso_check >= 10 )); then
                    last_eso_check=$current_loop_time
                    if ! is_eso_running; then exit 0; fi
                fi
            done 2>/dev/null
        else
            echo -e " \e[1;97;101m Restarting Sequence in 60 minutes... (Steam Mode) \e[0m\n"
            while [ $(date +%s) -lt $target_time ]; do
                rem_sec=$((target_time - $(date +%s)))
                min=$(( rem_sec / 60 )); sec=$(( rem_sec % 60 ))
                
                printf " \e[1;97;101m Countdown: %02d:%02d \e[0m \e[0;90m(Press 'b' to browse)\e[0m \033[0K\r" \
                       "$min" "$sec"
                
                read -t 1 -n 1 -s key 2>/dev/null || true
                if [[ "$key" == "b" || "$key" == "B" ]]; then
                    browse_database
                    echo -e "\n\e[0;36mResuming countdown...\e[0m"
                fi
                
                current_loop_time=$(date +%s)
                if (( current_loop_time - last_eso_check >= 5 )); then
                    last_eso_check=$current_loop_time
                    if ! is_eso_running; then
                        echo -e "\n\n \e[33mGame closed. Terminating updater...\e[0m"
                        exit 0
                    fi
                fi
            done 2>/dev/null
        fi
    else
        if [ "$SILENT" = true ]; then
            while [ $(date +%s) -lt $target_time ]; do
                sleep 5 & wait $!
            done
        else
            echo -e " \e[1;97;101m Restarting Sequence in 60 minutes... (Standalone Mode) \e[0m\n"
            while [ $(date +%s) -lt $target_time ]; do
                rem_sec=$((target_time - $(date +%s)))
                min=$(( rem_sec / 60 )); sec=$(( rem_sec % 60 ))
                
                printf " \e[1;97;101m Countdown: %02d:%02d \e[0m \e[0;90m(Press 'b' to browse)\e[0m \033[0K\r" \
                       "$min" "$sec"
                
                read -t 1 -n 1 -s key 2>/dev/null || true
                if [[ "$key" == "b" || "$key" == "B" ]]; then
                    browse_database
                    echo -e "\n\e[0;36mResuming countdown...\e[0m"
                fi
            done 2>/dev/null
        fi
    fi
