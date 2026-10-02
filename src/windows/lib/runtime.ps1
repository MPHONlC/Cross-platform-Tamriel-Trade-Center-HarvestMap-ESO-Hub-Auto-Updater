$TTC_DOMAIN = if ($AUTO_SRV -eq "1") {"us.tamrieltradecentre.com"} else {"eu.tamrieltradecentre.com"}
$TTC_URL = "https://$TTC_DOMAIN/download/PriceTable"
$SAVED_VAR_DIR = (Get-Item $ADDON_DIR).Parent.FullName + "\SavedVariables"
Auto-Repair-Database
$TEMP_DIR = "$env:USERPROFILE\Downloads\Windows_Tamriel_Trade_Center_Temp"
$TTC_USER_AGENT = "TamrielTradeCentreClient/1.0.0"
$HM_USER_AGENT = "HarvestMapClient/1.0.0"

$LAUNCH_METHOD = "Terminal / .bat File"
if ($global:IS_STEAM_LAUNCH) { $LAUNCH_METHOD = "Steam Launch Options" }
elseif ($global:IS_DESKTOP) { $LAUNCH_METHOD = "Desktop Shortcut" }
elseif ($global:IS_TASK) { $LAUNCH_METHOD = "Background Task" }
Log-Event "INFO" "========================================================="
Log-Event "INFO" "Script Initiated via: $LAUNCH_METHOD"

