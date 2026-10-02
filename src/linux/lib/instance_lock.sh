release_instance_lock() {
    if [ -n "$LOCK_FILE" ]; then
        exec 200>&- 2>/dev/null
        rm -f "$LOCK_FILE" 2>/dev/null
    elif [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then
        rm -rf "$LOCK_DIR"
    fi
}
if command -v flock >/dev/null 2>&1; then
    LOCK_FILE="/tmp/ttc_updater_$LOCK_ID.lock"
    exec 200<>"$LOCK_FILE"
    if ! flock -n 200; then
        OLD_PID=$(cat "$LOCK_FILE" 2>/dev/null)
        manage_old_pid "$OLD_PID"
        rm -rf /tmp/ttc_updater_*.lock 2>/dev/null
        exec 200<>"$LOCK_FILE"
        if ! flock -n 200; then
            sleep 1
            flock -n 200 || { echo -e "\e[0;31mFailed to acquire lock. Exiting.\e[0m"; exit 1; }
        fi
    fi
    > "$LOCK_FILE"; echo $$ >&200
    write_ttc_log "INFO" "Acquired instance lock ($LOCK_FILE), PID=$$"
else
    LOCK_DIR="/tmp/ttc_updater_dir_$LOCK_ID"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/pid"
    else
        OLD_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null)
        if [ "$OLD_PID" != "$$" ]; then manage_old_pid "$OLD_PID"; fi
        rm -rf "$LOCK_DIR"
        mkdir "$LOCK_DIR" 2>/dev/null
        echo $$ > "$LOCK_DIR/pid"
    fi
fi

mkdir -p "$TARGET_DIR"; CONFIG_FILE="$TARGET_DIR/lttc_updater.conf"
touch "$DB_FILE" 2>/dev/null; touch "$LOG_FILE" 2>/dev/null
touch "$LAST_SCAN_FILE" 2>/dev/null; touch "$UI_STATE_FILE" 2>/dev/null

