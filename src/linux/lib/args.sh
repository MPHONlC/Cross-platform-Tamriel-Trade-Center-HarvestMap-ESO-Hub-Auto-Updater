IS_DESKTOP=false; FORCE_SETUP=false
if [ "$#" -gt 0 ]; then HAS_ARGS=true; fi
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --silent) SILENT=true; IS_TASK=true ;;
        --auto) AUTO_PATH=true ;;
        --na) AUTO_SRV="1" ;;
        --eu) AUTO_SRV="2" ;;
        --both) AUTO_SRV="3" ;;
        --loop) AUTO_MODE="2" ;;
        --once) AUTO_MODE="1" ;;
        --task) IS_TASK=true; SILENT=true ;;
        --steam) IS_STEAM_LAUNCH=true ;;
        --addon-dir) shift; ADDON_DIR="$1" ;;
        --setup) rm -f "$CONFIG_FILE"; SETUP_COMPLETE=false; FORCE_SETUP=true ;;
        --desktop) IS_DESKTOP=true ;;
    esac
    shift
done

if [ "$IS_STEAM_LAUNCH" = false ] && [ "$IS_TASK" = false ]; then SILENT=false; fi
if [ "$IS_STEAM_LAUNCH" = true ] && [ "$SILENT" = true ]; then ENABLE_NOTIFS=true; fi

