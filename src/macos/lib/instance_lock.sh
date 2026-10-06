LOCK_DIR="$TEMP_DIR_ROOT/ttc_updater_dir_$LOCK_ID"
release_instance_lock() {
    if [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then rm -rf "$LOCK_DIR"; fi
}
if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"
else
    OLD_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ "$OLD_PID" != "$$" ]; then manage_old_pid "$OLD_PID"; fi
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null
    echo $$ > "$LOCK_DIR/pid"
fi
mkdir -p "$TARGET_DIR"; CONFIG_FILE="$TARGET_DIR/lttc_updater.conf"
touch "$DB_FILE" 2>/dev/null; touch "$LOG_FILE" 2>/dev/null
touch "$LAST_SCAN_FILE" 2>/dev/null; touch "$UI_STATE_FILE" 2>/dev/null

