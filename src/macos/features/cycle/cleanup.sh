    if [ "$FOUND_NEW_DATA" = true ]; then mv -f "$TEMP_SCAN_FILE" "$LAST_SCAN_FILE"; fi
    
    prune_history
    
    if [ "$CONFIG_CHANGED" = true ]; then write_lttc_config; fi
    
    cd "$HOME" || exit
    start_spinner "Cleaning up temp files & old logs..."
    
    if [ -f "$LOG_FILE" ]; then
        cutoff_date=$(date -v-3d '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
        
        if [ -n "$cutoff_date" ]; then
            awk -v cutoff="$cutoff_date" '
            BEGIN { keep = 0 }
            /^\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]/ {
                log_date = substr($0, 2, 19)
                keep = (log_date >= cutoff) ? 1 : 0
            }
            {
                if (keep) print $0
            }' "$LOG_FILE" > "$TEMP_DIR_ROOT/log_prune.tmp" 2>/dev/null
            
            if [ -f "$TEMP_DIR_ROOT/log_prune.tmp" ]; then
                cat "$TEMP_DIR_ROOT/log_prune.tmp" > "$LOG_FILE"
                rm -f "$TEMP_DIR_ROOT/log_prune.tmp"
            fi
        fi
    fi
    
    DEL_COUNT=0
    CLEAN_LOG="$TEMP_DIR_ROOT/cleanup.log"
    > "$CLEAN_LOG"
    
    for target in "$TEMP_DIR" "$TEMP_DIR_ROOT"/*.tmp "$TEMP_DIR_ROOT"/*.out \
                  "$TEMP_DIR_ROOT"/*.zip "$TEMP_DIR_ROOT"/ESOHub_Extracted \
                  "$TEMP_DIR_ROOT"/lttc_upload.* "$TEMP_DIR_ROOT"/DB_Update; do
        if [ -e "$target" ]; then
            find "$target" -type f -o -type d 2>/dev/null >> "$CLEAN_LOG"
            rm -rf "$target" 2>/dev/null
        fi
    done
    
    if [ -f "$CLEAN_LOG" ]; then
    DEL_COUNT=$(wc -l < "$CLEAN_LOG" | tr -d ' ')
    
    if [ "$LOG_MODE" = "detailed" ] && [ "$DEL_COUNT" -gt 0 ]; then
        d_time=$(date '+%Y-%m-%d %H:%M:%S')
        awk -v dt="$d_time" '{
            print "["dt"] [ITEM] Deleted Temporary File/Folder: " $0
        }' "$CLEAN_LOG" >> "$LOG_FILE"
    fi
fi
    
    stop_spinner 0 "Cleanup complete ($DEL_COUNT items removed)"
    
    if [ "$DEL_COUNT" -gt 0 ] && [ "$SILENT" = false ]; then
        cat "$CLEAN_LOG" | while IFS= read -r f_path; do
            ui_echo " \e[90m-> Deleted: $f_path\e[0m"
        done
        echo ""
    fi
    rm -f "$CLEAN_LOG" 2>/dev/null
    
    if [ "$ENABLE_NOTIFS" = true ]; then
        notif_msg="TTC: $NOTIF_TTC\nESO-Hub: $NOTIF_EH\nHarvestMap: $NOTIF_HM"
        [ -n "$NOTIF_ADDONS" ] && notif_msg="$notif_msg\nAdd-ons: $NOTIF_ADDONS"
        push_sys_notif "$notif_msg"
    fi
    
