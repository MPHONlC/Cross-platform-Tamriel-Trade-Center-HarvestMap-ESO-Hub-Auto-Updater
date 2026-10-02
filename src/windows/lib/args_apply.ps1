$global:IS_DESKTOP = $false; $global:FORCE_SETUP = $false
for ($i = 0; $i -lt $parsedArgs.Count; $i++) {
    switch ($parsedArgs[$i]) {
        "--silent" { $global:SILENT = $true }
        "--auto" { $global:AUTO_PATH = $true }
        "--na" { $global:AUTO_SRV = "1" }
        "--eu" { $global:AUTO_SRV = "2" }
        "--both" { $global:AUTO_SRV = "3" }
        "--loop" { $global:AUTO_MODE = "2" }
        "--once" { $global:AUTO_MODE = "1" }
        "--addon-dir" { if ($i + 1 -lt $parsedArgs.Count) { $i++; $global:ADDON_DIR = $parsedArgs[$i] } }
        "--desktop" { $global:IS_DESKTOP = $true }
        "--setup" {
            Remove-Item -LiteralPath $CONFIG_FILE -Force -ErrorAction SilentlyContinue
            $global:SETUP_COMPLETE = $false; $global:FORCE_SETUP = $true
        }
    }
}

if ($global:IS_STEAM_LAUNCH -and !$parsedArgs.Contains("--silent")) { $global:SILENT = $false }
if (!$IS_STEAM_LAUNCH -and !$IS_TASK) { $global:SILENT = $false }
if ($IS_STEAM_LAUNCH -and $SILENT) { $global:ENABLE_NOTIFS = $true }

