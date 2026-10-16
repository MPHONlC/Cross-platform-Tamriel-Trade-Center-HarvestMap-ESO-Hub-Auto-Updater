push_sys_notif() {
    local msg="$1"
    if [ "$ENABLE_NOTIFS" = "false" ]; then return; fi
    local safe_msg="${msg//\"/\\\"}" safe_title="${APP_TITLE//\"/\\\"}"
    osascript -e "display notification \"$safe_msg\" with title \"$safe_title\"" 2>/dev/null \
        || write_ttc_log "WARN" "macOS notification failed; allow notifications for Script Editor in System Settings"
}

get_active_terminal() {
    echo "Terminal"
}

find_addon_folder() {
    local p
    p="$HOME/Documents/Elder Scrolls Online/live/AddOns"
    if [ -d "$p" ]; then echo "$p"; return 0; fi
    echo ""
}

