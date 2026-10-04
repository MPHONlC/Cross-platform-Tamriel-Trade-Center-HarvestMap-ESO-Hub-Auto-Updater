$FULL_SCRIPT_PATH = $env:SCRIPT_FULL_PATH
if ([string]::IsNullOrEmpty($FULL_SCRIPT_PATH)) { $FULL_SCRIPT_PATH = "Windows_Tamriel_Trade_Center.bat" }
$CURRENT_DIR = Split-Path $FULL_SCRIPT_PATH
$SCRIPT_NAME = Split-Path $FULL_SCRIPT_PATH -Leaf

function Load-Config($path) {
    if (Test-Path $path) {
        Get-Content $path | ForEach-Object {
            if ($_ -match '^\s*([^=]+)\s*=\s*(.*)$') {
                $key = $matches[1].Trim()
                $val = $matches[2].Trim().Trim('"').Trim("'")
                Set-Variable -Name $key -Value $val -Scope Global
            }
        }
    }
}

if (Test-Path $CONFIG_FILE) { Load-Config $CONFIG_FILE }

$global:SILENT = $false
$global:AUTO_PATH = if ($AUTO_PATH -eq 'true') {$true} else {$false}
$global:SETUP_COMPLETE = if ($SETUP_COMPLETE -eq 'true') {$true} else {$false}
$global:ENABLE_NOTIFS = if ($ENABLE_NOTIFS -eq 'true') {$true} else {$false}
$global:ENABLE_DISPLAY = if ($ENABLE_DISPLAY -eq 'false') {$false} else {$true}
$global:ENABLE_LOCAL_MODE = if ($ENABLE_LOCAL_MODE -eq 'true') {$true} else {$false}
if (!$STARTUP_MODE) { $global:STARTUP_MODE = "0" }
if (!$LOG_MODE) { $global:LOG_MODE = "simple" }

if (!$TTC_LAST_SALE) { $global:TTC_LAST_SALE = 0 }
if (!$TTC_LAST_DOWNLOAD) { $global:TTC_LAST_DOWNLOAD = 0 }
if (!$TTC_LAST_CHECK) { $global:TTC_LAST_CHECK = 0 }
if (!$TTC_NA_VERSION) { $global:TTC_NA_VERSION = 0 }
if (!$TTC_EU_VERSION) { $global:TTC_EU_VERSION = 0 }
if (!$EH_LAST_SALE) { $global:EH_LAST_SALE = 0 }
if (!$EH_LAST_DOWNLOAD) { $global:EH_LAST_DOWNLOAD = 0 }
if (!$EH_LAST_CHECK) { $global:EH_LAST_CHECK = 0 }
if (!$EH_LOC_5) { $global:EH_LOC_5 = 0 }
if (!$EH_LOC_7) { $global:EH_LOC_7 = 0 }
if (!$EH_LOC_9) { $global:EH_LOC_9 = 0 }
if (!$HM_LAST_DOWNLOAD) { $global:HM_LAST_DOWNLOAD = 0 }
if (!$HM_LAST_CHECK) { $global:HM_LAST_CHECK = 0 }
if (!$EH_USER_TOKEN) { $global:EH_USER_TOKEN = "" }
if (!$TTC_CLIENT_ID) { $global:TTC_CLIENT_ID = "" }
if (!$TARGET_RUN_TIME) { $global:TARGET_RUN_TIME = 0 }
if (!$TARGET_USERNAME) { $global:TARGET_USERNAME = "" }
$global:ENABLE_ADDON_UPDATES = if ($ENABLE_ADDON_UPDATES -eq 'true') {$true} else {$false}
$global:AUTO_SELF_UPDATE = if ($AUTO_SELF_UPDATE -eq 'false') {$false} else {$true}
if (!$ADDON_LAST_CHECK) { $global:ADDON_LAST_CHECK = 0 }
if (!$SELF_LAST_CHECK) { $global:SELF_LAST_CHECK = 0 }
if (!$ADDON_UPDATE_SKIP) { $global:ADDON_UPDATE_SKIP = "" }

function save_config {
    $c = @"
AUTO_SRV="$AUTO_SRV"
SILENT=$($SILENT.ToString().ToLower())
AUTO_MODE="$AUTO_MODE"
ADDON_DIR="$ADDON_DIR"
SETUP_COMPLETE=$($SETUP_COMPLETE.ToString().ToLower())
ENABLE_NOTIFS=$($ENABLE_NOTIFS.ToString().ToLower())
ENABLE_DISPLAY=$($ENABLE_DISPLAY.ToString().ToLower())
ENABLE_LOCAL_MODE=$($ENABLE_LOCAL_MODE.ToString().ToLower())
LOG_MODE="$LOG_MODE"
STARTUP_MODE="$STARTUP_MODE"
TTC_LAST_SALE="$TTC_LAST_SALE"
TTC_LAST_DOWNLOAD="$TTC_LAST_DOWNLOAD"
TTC_LAST_CHECK="$TTC_LAST_CHECK"
TTC_NA_VERSION="$TTC_NA_VERSION"
TTC_EU_VERSION="$TTC_EU_VERSION"
EH_LAST_SALE="$EH_LAST_SALE"
EH_LAST_DOWNLOAD="$EH_LAST_DOWNLOAD"
EH_LAST_CHECK="$EH_LAST_CHECK"
EH_LOC_5="$EH_LOC_5"
EH_LOC_7="$EH_LOC_7"
EH_LOC_9="$EH_LOC_9"
HM_LAST_DOWNLOAD="$HM_LAST_DOWNLOAD"
HM_LAST_CHECK="$HM_LAST_CHECK"
EH_USER_TOKEN="$EH_USER_TOKEN"
TTC_CLIENT_ID="$TTC_CLIENT_ID"
TARGET_RUN_TIME="$TARGET_RUN_TIME"
TARGET_USERNAME="$TARGET_USERNAME"
SKIP_DL_TTC="$SKIP_DL_TTC"
SKIP_DL_HM="$SKIP_DL_HM"
SKIP_DL_EH="$SKIP_DL_EH"
ENABLE_ADDON_UPDATES=$($ENABLE_ADDON_UPDATES.ToString().ToLower())
ADDON_LAST_CHECK="$ADDON_LAST_CHECK"
ADDON_UPDATE_SKIP="$ADDON_UPDATE_SKIP"
AUTO_SELF_UPDATE=$($AUTO_SELF_UPDATE.ToString().ToLower())
SELF_LAST_CHECK="$SELF_LAST_CHECK"
"@
    $c | Out-File -FilePath $CONFIG_FILE -Encoding UTF8 -Force
    Log-Event "INFO" "Configuration saved to lttc_updater.conf"
}

