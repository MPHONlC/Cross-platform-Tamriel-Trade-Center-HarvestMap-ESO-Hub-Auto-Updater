find_eso_paths() {
    declare -a game_paths=()
    game_paths=(
        "$HOME/.local/share/Steam/steamapps/common/Zenimax Online/The Elder Scrolls Online/game/client"
        "$HOME/.steam/steam/steamapps/common/Zenimax Online/The Elder Scrolls Online/game/client"
        "$HOME/.var/app/com.valvesoftware.Steam/.steam/root/steamapps/common/Zenimax Online/The Elder Scrolls Online/game/client"
        "/var/lib/flatpak/app/com.valvesoftware.Steam/.steam/root/steamapps/common/Zenimax Online/The Elder Scrolls Online/game/client"
    )
    for p in "${game_paths[@]}"; do
        if [ -f "$p/eso64.exe" ]; then
            echo "$p"; return 0
        fi
    done
    FOUND_ZOS=$(find "$HOME" /run/media /mnt /media -maxdepth 6 -type d -name "Zenimax Online" 2>/dev/null | head -n 1)
    if [ -n "$FOUND_ZOS" ] && [ -f "$FOUND_ZOS/The Elder Scrolls Online/game/client/eso64.exe" ]; then
        echo "$FOUND_ZOS/The Elder Scrolls Online/game/client"; return 0
    fi
    echo ""
}

is_eso_running() {
    if pgrep -i -f 'eso64\.exe|steam_app_306130|Bethesda\.net_Launcher' > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

