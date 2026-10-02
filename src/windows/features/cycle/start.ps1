    Invoke-SelfUpdateCheck
    $global:CONFIG_CHANGED = $false
    $TEMP_DIR_USED = $false
    $CURRENT_TIME = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    
    $notifTTC = "Up-to-date"
    $notifEH = "Up-to-date"
    $notifHM = "Up-to-date"
    $global:notifAddons = ""
    $FOUND_NEW_DATA = $false
    $TEMP_SCAN_FILE = "$TEMP_DIR_ROOT\WTTC_TempScan.log"
    Out-File -FilePath $TEMP_SCAN_FILE -InputObject "" -Encoding UTF8
    Out-File -FilePath $UI_STATE_FILE -InputObject "" -Encoding UTF8

    Log-Event "INFO" "Main loop iteration started. Current time: $CURRENT_TIME"

    $shuffledUAs = @($USER_AGENTS | Get-Random -Count $USER_AGENTS.Count)
    $RAND_UA = $shuffledUAs[0]

    if (!$SILENT) {
        Clear-Host
        Write-Host "$ESC[0;92m===========================================================================$ESC[0m"
        Write-Host "$ESC[1m$ESC[0;94m                         $APP_TITLE$ESC[0m"
        Write-Host "$ESC[0;97m         Cross-Platform Auto-Updater for TTC, HarvestMap, ESO-Hub & ESOUI$ESC[0m"
        Write-Host "$ESC[0;90m                            Created by @APHONIC$ESC[0m"
        Write-Host "$ESC[0;92m===========================================================================`n$ESC[0m"
        Write-Host "Target AddOn Directory: $ESC[35m$ADDON_DIR$ESC[0m`n"
    }

    if (!(Test-Path $TEMP_DIR)) { New-Item -ItemType Directory -Force -Path $TEMP_DIR | Out-Null }
    Set-Location $TEMP_DIR

    $ADDON_SETTINGS_FILE = (Get-Item $ADDON_DIR).Parent.FullName + "\AddOnSettings.txt"
    $addonSettingsText = if (Test-Path $ADDON_SETTINGS_FILE) { Get-Content $ADDON_SETTINGS_FILE -Raw } else { "" }

    function Check-Addon-Enabled($addonName) {
        if (!(Test-Path "$ADDON_DIR\$addonName")) { return $false }
        if ($addonSettingsText) { return ($addonSettingsText -match "\b$([regex]::Escape($addonName))\b") }
        return $true
    }

    function Ensure-Missing-Addon($a_name, $a_id, $skip_var) {
        $skipVal = Get-Variable -Name $skip_var -ValueOnly -ErrorAction SilentlyContinue
        if ($skipVal -eq "True" -or $skipVal -eq $true) { return $false }
        
        $addonPath = Join-Path $global:ADDON_DIR $a_name
        if (!(Test-Path $addonPath)) {
            Write-Host " `n$ESC[33m[?] $a_name is missing. Do you want to download it? (y/N)$ESC[0m"
            $ans = Read-Host "Choice"
            if ([string]::IsNullOrWhiteSpace($ans)) { $ans = "n" }
            
            if ($ans -match '^[Yy]$') {
                Start-Spinner "Downloading $a_name from ESOUI..."
                Log-Event "INFO" "Attempting to download missing addon: $a_name"
                
                try {
                    $zipPath = "$TEMP_DIR_ROOT\${a_name}.zip"
                    if ((Invoke-EsouiDownload $a_id $zipPath) -eq 0) {
                        Expand-Archive -Path $zipPath -DestinationPath $global:ADDON_DIR -Force
                        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                        
                        if ($a_name -eq "LibEsoHubPrices") {
                            $ehApi = (& curl.exe -s -X POST -H "User-Agent: ESOHubClient/1.0.9" -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" "https://data.eso-hub.com/v1/api/get-addon-versions" 2>$null) -join ""
                            $ehBlock = @($ehApi.Replace('{"folder_name"', "`n{`"folder_name`"") -split "`n" | Where-Object { $_ -match '"folder_name":"LibEsoHubPrices"' })
                            if ($ehBlock.Count -gt 0 -and $ehBlock[0] -match '"version":\{[^}]*"string":"([^"]+)"') {
                                $global:EH_LOC_7 = $matches[1]
                                $global:CONFIG_CHANGED = $true
                            }
                        }

                        if ($a_name -eq "TamrielTradeCentre") {
                            Remove-Item "$TEMP_DIR_ROOT\ttc_last_dl.txt" -Force -ErrorAction SilentlyContinue
                            $global:TTC_NA_VERSION = 0
                            $global:TTC_EU_VERSION = 0
                            $global:CONFIG_CHANGED = $true
                        }
                        
                        Stop-Spinner 0 "$a_name installed"
                        Log-Event "INFO" "Addon $a_name automatically downloaded and installed."
                        
                        $settings_file = (Get-Item $global:ADDON_DIR).Parent.FullName + "\AddOnSettings.txt"
                        if (Test-Path $settings_file) {
                            $sText = [System.IO.File]::ReadAllText($settings_file)
                            if ($a_name -eq "HarvestMap" -or $a_name -eq "HarvestMapData") {
                                $sText = [regex]::Replace($sText, '(?im)^HarvestMap 0', 'HarvestMap 1')
                                $sText = [regex]::Replace($sText, '(?im)^HarvestMapData 0', 'HarvestMapData 1')
                                if ($sText -notmatch '(?im)^HarvestMap ') { $sText += "`nHarvestMap 1" }
                                if ($sText -notmatch '(?im)^HarvestMapData ') { $sText += "`nHarvestMapData 1" }
                            } else {
                                $sText = [regex]::Replace($sText, "(?im)^$a_name 0", "$a_name 1")
                                if ($sText -notmatch "(?im)^$a_name ") { $sText += "`n$a_name 1" }
                            }
                            $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
                            [System.IO.File]::WriteAllText($settings_file, $sText, $Utf8NoBomEncoding)
                        }
                        return $true
                    } else {
                        Stop-Spinner 1 "$a_name download failed"
                        Log-Event "ERROR" "Download failed for missing addon: $a_name"
                        return $false
                    }
                } catch {
                    Stop-Spinner 1 "$a_name download failed"
                    return $false
                }
            } else {
                UIEcho " $ESC[90mUser Declined download of $a_name. Will not ask again.$ESC[0m"
                Log-Event "WARN" "User declined download for $a_name. Setting skip flag."
                Set-Variable -Name $skip_var -Value "True" -Scope Global
                save_config
                return $false
            }
        }
        return $true
    }

    Ensure-Missing-Addon "TamrielTradeCentre" "1245" "SKIP_DL_TTC" | Out-Null
    Ensure-Missing-Addon "HarvestMap" "57" "SKIP_DL_HM" | Out-Null
    Ensure-Missing-Addon "HarvestMapData" "3034" "SKIP_DL_HM" | Out-Null
    Ensure-Missing-Addon "LibEsoHubPrices" "4095" "SKIP_DL_EH" | Out-Null

    if ($global:SKIP_DL_EH -ne "True" -and $global:SKIP_DL_EH -ne $true) {
        if (!(Test-Path "$ADDON_DIR\EsoTradingHub") -or !(Test-Path "$ADDON_DIR\EsoHubScanner")) {
            Write-Host " `n$ESC[33m[?] ESO-Hub Addons are missing. Do you want to download them? (y/N)$ESC[0m"
            $ans = Read-Host "Choice"
            if ([string]::IsNullOrWhiteSpace($ans)) { $ans = "n" }
            if ($ans -match '^[Yy]$') {
                Start-Spinner "Downloading ESO-Hub Addons..."
                $api_resp = (& curl.exe -s -X POST -H "User-Agent: ESOHubClient/1.0.9" -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" "https://data.eso-hub.com/v1/api/get-addon-versions") -join ""
                
                $api_resp = $api_resp.Replace('{"folder_name"', "`n{`"folder_name`"")
                $lines = $api_resp -split "`n"
                foreach ($line in $lines) {
                    if ($line -match '"folder_name"\s*:\s*"([^"]+)"') {
                        $fname = $matches[1]
                        if ($fname -eq "LibEsoHubPrices") { continue } 
                        
                        $dl_url = if ($line -match '"file"\s*:\s*"([^"]+)"') { $matches[1].Replace('\/','/') } else { "" }
                        $srv_ver = if ($line -match '"version"\s*:\s*\{[^}]*"string"\s*:\s*"([^"]+)"') { $matches[1] } elseif ($line -match '"version"\s*:\s*"([^"]+)"') { $matches[1] } else { "" }
                        $id_num = if ($dl_url -match '(\d+)$') { $matches[1] } else { "0" }
                        
                        if ($fname -and $dl_url) {
                            Stop-Spinner 0 "Fetching $fname"
                            Start-Spinner "Downloading $fname..."
                            & curl.exe -s -f -m 30 -L -A "ESOHubClient/1.0.9" -o "$TEMP_DIR_ROOT\${fname}.zip" $dl_url
                            if ($LASTEXITCODE -eq 0) {
                                Expand-Archive -Path "$TEMP_DIR_ROOT\${fname}.zip" -DestinationPath $global:ADDON_DIR -Force
                                Remove-Item "$TEMP_DIR_ROOT\${fname}.zip" -Force
                                
                                Stop-Spinner 0 "$fname installed"
                                $var_name = "EH_LOC_$id_num"
                                Set-Variable -Name $var_name -Value $srv_ver -Scope Global
                                $global:CONFIG_CHANGED = $true
                                
                                $settings_file = (Get-Item $global:ADDON_DIR).Parent.FullName + "\AddOnSettings.txt"
                                if (Test-Path $settings_file) {
                                    $sText = [System.IO.File]::ReadAllText($settings_file)
                                    $sText = [regex]::Replace($sText, "(?im)^$fname 0", "$fname 1")
                                    if ($sText -notmatch "(?im)^$fname ") { $sText += "`n$fname 1" }
                                    $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
                                    [System.IO.File]::WriteAllText($settings_file, $sText, $Utf8NoBomEncoding)
                                }
                            } else {
                                Stop-Spinner 1 "Download failed for $fname"
                            }
                        }
                    }
                }
            } else {
                UIEcho " $ESC[90mUser Declined ESO-Hub downloads.$ESC[0m"
                $global:SKIP_DL_EH = "True"
                save_config
            }
        }
    }

