if [ "$SILENT" = true ]; then exec >/dev/null 2>&1; fi
exec 3>&2

if [ "$AUTO_SRV" == "2" ]; then
    TTC_DOMAIN="eu.tamrieltradecentre.com"
else
    TTC_DOMAIN="us.tamrieltradecentre.com"
fi
TTC_URL="https://$TTC_DOMAIN/download/PriceTable"
SAVED_VAR_DIR="$(dirname "$ADDON_DIR")/SavedVariables"
repair_missing_names
TEMP_DIR="$TEMP_DIR_ROOT/Downloads"
[ -d "$HOME/Downloads/${OS_BRAND}_Tamriel_Trade_Center_Temp" ] && rm -rf "$HOME/Downloads/${OS_BRAND}_Tamriel_Trade_Center_Temp" 2>/dev/null
TTC_USER_AGENT="TamrielTradeCentreClient/1.0.0"
HM_USER_AGENT="HarvestMapClient/1.0.0"

USER_AGENTS=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.0.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0"
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"
)

ADDON_SETTINGS_FILE="$(dirname "$ADDON_DIR")/AddOnSettings.txt"

LAUNCH_METHOD="Terminal / .sh File"
if [ "$IS_STEAM_LAUNCH" = true ]; then LAUNCH_METHOD="Steam Launch Options"
elif [ "$IS_DESKTOP" = true ]; then LAUNCH_METHOD="Desktop Shortcut"
elif [ "$IS_TASK" = true ]; then LAUNCH_METHOD="Background Task"
fi
write_ttc_log "INFO" "========================================================="
write_ttc_log "INFO" "Script Initiated via: $LAUNCH_METHOD"

