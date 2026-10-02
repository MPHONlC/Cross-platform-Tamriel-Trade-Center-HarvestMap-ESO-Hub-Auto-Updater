LOG_MODE="simple"
write_ttc_log() {
    local level="$1"; local message="$2"
    if [ "$level" == "ITEM" ] && [ "$LOG_MODE" != "detailed" ]; then return; fi
    clean_msg=$(printf '%s\n' "$message" | sed "s/$(printf '\033')\[[0-9;]*m//g")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $clean_msg" >> "$LOG_FILE"
}

