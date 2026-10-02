push_sys_notif() {
    local msg="$1"
    if [ "$ENABLE_NOTIFS" = "false" ]; then return; fi
    osascript -e "display notification \"$msg\" with title \"$APP_TITLE\"" 2>/dev/null
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

