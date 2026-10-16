find_eso_paths() {
    declare -a game_paths=()
    game_paths=(
        "$HOME/Library/Application Support/Steam/steamapps/common/Zenimax Online/The Elder Scrolls Online/game/client"
        "$HOME/Library/Application Support/Steam/steamapps/common/Zenimax Online/The Elder Scrolls Online"
        "/Applications/Zenimax Online/The Elder Scrolls Online/game/client"
    )
    for p in "${game_paths[@]}"; do
        if [ -f "$p/eso.app/Contents/MacOS/eso" ] || [ -d "$p/eso.app" ]; then
            echo "$p"; return 0
        fi
    done
    echo ""
}

is_eso_running() {
    if pgrep -i -f 'eso\.app|steam_app_306130|Bethesda\.net_Launcher' > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

