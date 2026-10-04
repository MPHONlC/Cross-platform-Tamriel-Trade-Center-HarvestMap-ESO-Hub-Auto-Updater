$TARGET_DIR = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Windows_Tamriel_Trade_Center"
$DB_DIR = "$TARGET_DIR\Database"
$LOG_DIR = "$TARGET_DIR\Logs"
$SNAP_DIR = "$TARGET_DIR\Snapshots"
$TEMP_DIR_ROOT = "$TARGET_DIR\Temp"

foreach ($dir in @($TARGET_DIR, $DB_DIR, $LOG_DIR, $SNAP_DIR, $TEMP_DIR_ROOT)) {
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
}

if (Test-Path "$TARGET_DIR\LTTC_Database.db") { Move-Item "$TARGET_DIR\LTTC_Database.db" "$DB_DIR\" -Force }
if (Test-Path "$TARGET_DIR\LTTC_History.db") { Move-Item "$TARGET_DIR\LTTC_History.db" "$DB_DIR\" -Force }
if (Test-Path "$TARGET_DIR\wttc.logs") { Move-Item "$TARGET_DIR\wttc.logs" "$LOG_DIR\WTTC.log" -Force }
if (Test-Path "$TARGET_DIR\LTTC_LastScan.log") { Move-Item "$TARGET_DIR\LTTC_LastScan.log" "$LOG_DIR\" -Force }
if (Test-Path "$TARGET_DIR\LTTC_Display_State.log") { Move-Item "$TARGET_DIR\LTTC_Display_State.log" "$LOG_DIR\" -Force }
Get-ChildItem -Path $TARGET_DIR -Filter "*_snapshot.lua" | ForEach-Object { Move-Item $_.FullName "$SNAP_DIR\" -Force }
Get-ChildItem -Path $TARGET_DIR -Filter "*.tmp" | Remove-Item -Force
Get-ChildItem -Path $TARGET_DIR -Filter "*.out" | Remove-Item -Force

$CONFIG_FILE = "$TARGET_DIR\lttc_updater.conf"
$ICON_FILE = "$TARGET_DIR\lttc_icon.ico"
$DB_FILE = "$DB_DIR\LTTC_Database.db"
$HIST_FILE = "$DB_DIR\LTTC_History.db"
$LOG_FILE = "$LOG_DIR\WTTC.log"
$LAST_SCAN_FILE = "$LOG_DIR\LTTC_LastScan.log"
$UI_STATE_FILE = "$LOG_DIR\LTTC_Display_State.log"

foreach ($f in @($DB_FILE, $HIST_FILE, $LOG_FILE, $LAST_SCAN_FILE, $UI_STATE_FILE)) {
    if (!(Test-Path $f)) { New-Item -ItemType File -Force -Path $f | Out-Null }
}

if ((Test-Path $ICON_FILE) -and (Get-Item $ICON_FILE).Length -lt 1024) { Remove-Item $ICON_FILE -Force -ErrorAction SilentlyContinue }
if (!(Test-Path $ICON_FILE)) {
    try { & curl.exe -s -f -m 15 -L -o $ICON_FILE (Get-Part "a04556abef9f19a082f8bdeda364aa1f6d6307d88907e5302e1d7ffd60f34d2805fe8f2b740a9843d31629110bde0d3ac8cd733fea7a5492cd5ddb5ec614ab8b2525107ab8805b8c55b77e66766056d62a37d79858f8a7efadec099c79551be5855077cf13a8431fb418dec6d6c2cc329e927de3a934024c0f249b1a9a92674427df8c327f4a" 167) } catch {}
}

