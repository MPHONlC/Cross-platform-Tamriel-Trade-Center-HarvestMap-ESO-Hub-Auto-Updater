unset LD_PRELOAD; unset LD_LIBRARY_PATH; unset STEAM_LD_PRELOAD
APP_VERSION="2026.10.04.19.22"; OS_TYPE=$(uname -s); TARGET_DIR="$HOME/Documents"
LOCK_ID="lttc"
OS_BRAND="Linux"
TARGET_DIR="$TARGET_DIR/${OS_BRAND}_Tamriel_Trade_Center"
SYS_ID="linux"

DB_DIR="$TARGET_DIR/Database"; LOG_DIR="$TARGET_DIR/Logs"
SNAP_DIR="$TARGET_DIR/Snapshots"; TEMP_DIR_ROOT="$TARGET_DIR/Temp"
mkdir -p "$DB_DIR" "$LOG_DIR" "$SNAP_DIR" "$TEMP_DIR_ROOT"

[ -f "$TARGET_DIR/LTTC_Database.db" ] && mv "$TARGET_DIR/LTTC_Database.db" "$DB_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC_History.db" ] && mv "$TARGET_DIR/LTTC_History.db" "$DB_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC.log" ] && mv "$TARGET_DIR/LTTC.log" "$LOG_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC_LastScan.log" ] && mv "$TARGET_DIR/LTTC_LastScan.log" "$LOG_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC_Display_State.log" ] && mv "$TARGET_DIR/LTTC_Display_State.log" "$LOG_DIR/" 2>/dev/null

for snap in "$TARGET_DIR"/*_snapshot.lua; do
    [ -f "$snap" ] && mv "$snap" "$SNAP_DIR/" 2>/dev/null
done
rm -f "$TARGET_DIR"/*.tmp "$TARGET_DIR"/*.out 2>/dev/null

CONFIG_FILE="$TARGET_DIR/lttc_updater.conf"; DB_FILE="$DB_DIR/LTTC_Database.db"
LOG_FILE="$LOG_DIR/LTTC.log"
LAST_SCAN_FILE="$LOG_DIR/LTTC_LastScan.log"; UI_STATE_FILE="$LOG_DIR/LTTC_Display_State.log"
APP_TITLE="$OS_BRAND Tamriel Trade Center v$APP_VERSION"
SCRIPT_NAME="${OS_BRAND}_Tamriel_Trade_Center.sh"
