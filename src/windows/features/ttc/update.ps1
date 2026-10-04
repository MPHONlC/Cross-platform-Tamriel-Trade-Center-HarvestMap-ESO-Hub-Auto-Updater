    if (!$HAS_TTC) {
        UIEcho "$ESC[1m$ESC[97m [1/4] & [2/4] Updating TTC Data (SKIPPED)$ESC[0m"
        UIEcho " $ESC[31m[-] TamrielTradeCentre not enabled.$ESC[0m`n"
        $notifTTC = "Skipped"
    } else {
        UIEcho "$ESC[1m$ESC[97m [1/4] Uploading your Local TTC Data $ESC[0m"
        $ttcSv = "$SAVED_VAR_DIR\TamrielTradeCentre.lua"
        $ttcSnap = "$SNAP_DIR\lttc_ttc_snapshot.lua"

        if (Test-Path $ttcSv) {
            if (!(Test-FileNewer $ttcSv $ttcSnap)) {
                UIEcho " $ESC[90mNo TTC local changes detected. $ESC[35mSkipping upload.$ESC[0m`n"
            } else {
                $ttcExtracted = $false; $ttcRawCount = 0
                if ($global:ENABLE_DISPLAY -and !$global:SILENT) {
                    Start-Spinner "Parsing TamrielTradeCentre.lua..."
                    [System.IO.File]::AppendAllText($TEMP_SCAN_FILE, "`n$ESC[0;35m--- TTC Extracted Data ---$ESC[0m`n", [System.Text.Encoding]::UTF8)
                    $res = Invoke-TtcExtraction $ttcSv $global:TTC_LAST_SALE $CURRENT_TIME
                    Stop-Spinner 0 "Extraction complete"
                    $ttcExtracted = $true; $ttcRawCount = $res.Lines.Count

                    if ($ttcRawCount -gt 0) {
                        $FOUND_NEW_DATA = $true
                        foreach ($l in $res.Lines) {
                            $cut = $l.IndexOf('|'); $ts = $l.Substring(0, $cut); $rest = $l.Substring($cut + 1)
                            $rawLine = if ($ts -eq "0") { " [$ESC[90mListing$ESC[0m]$rest" } else { " [TS:$ts]$rest" }
                            UIEcho $rawLine
                            [System.IO.File]::AppendAllText($TEMP_SCAN_FILE, "$rawLine`n", [System.Text.Encoding]::UTF8)
                        }
                    } else {
                        UIEcho " $ESC[90mNo new TTC items found. Upload skipped.$ESC[0m"
                    }

                    Merge-History $res.History
                    Apply-DB-Updates $res.DbUpdates
                    if ("$($res.MaxTime)" -ne "$global:TTC_LAST_SALE") { $global:TTC_LAST_SALE = $res.MaxTime; $global:CONFIG_CHANGED = $true }
                } else {
                    UIEcho " $ESC[90mExtraction disabled by user. Proceeding instantly...$ESC[0m"
                }

                if ($global:ENABLE_LOCAL_MODE) {
                    UIEcho "`n $ESC[90m[Local Mode] Skipping TTC Upload.$ESC[0m`n"
                    $notifTTC = "Extracted (No Upload)"
                    Copy-Item -LiteralPath $ttcSv -Destination $ttcSnap -Force -ErrorAction SilentlyContinue
                } elseif ($ttcExtracted -and $ttcRawCount -eq 0) {
                    $notifTTC = "No New Data"
                    Copy-Item -LiteralPath $ttcSv -Destination $ttcSnap -Force -ErrorAction SilentlyContinue
                } else {
                    $uploadDomains = if ($AUTO_SRV -eq "3") { @("us.tamrieltradecentre.com", "eu.tamrieltradecentre.com") } else { @($TTC_DOMAIN) }
                    $uploadOk = $true
                    foreach ($upDomain in $uploadDomains) {
                        $upRegion = if ($upDomain.StartsWith("eu.")) { "EU" } else { "NA" }
                        Start-Spinner "Uploading to https://$upDomain..."
                        if (Invoke-TTCUpload $upDomain $upRegion $ttcSv) {
                            if ($global:TTC_UPLOAD_COUNT -gt 0) { Stop-Spinner 0 "Upload finished ($upDomain, $($global:TTC_UPLOAD_COUNT) listings)" }
                            else { Stop-Spinner 0 "Nothing new for $upDomain ($(Get-TTCNothingNewReason))" }
                        } else { $uploadOk = $false; Stop-Spinner 1 "Upload failed ($upDomain)" }
                    }
                    if ($uploadOk) {
                        $notifTTC = "Data Uploaded"
                        Copy-Item -LiteralPath $ttcSv -Destination $ttcSnap -Force -ErrorAction SilentlyContinue
                    } else {
                        $notifTTC = "Upload Failed"
                    }
                }
            }
        } else {
            UIEcho " $ESC[33m[-] No TamrielTradeCentre.lua found. $ESC[35mSkipping.$ESC[0m`n"
        }

        UIEcho "$ESC[1m$ESC[97m [2/4] Updating your Local TTC Data $ESC[0m`n $ESC[33mChecking TTC APIs...$ESC[0m"
        $global:TTC_LAST_CHECK = $CURRENT_TIME; $global:CONFIG_CHANGED = $true

        $srv_list = @()
        if ($AUTO_SRV -eq "1" -or $AUTO_SRV -eq "3") { $srv_list += "NA" }
        if ($AUTO_SRV -eq "2" -or $AUTO_SRV -eq "3") { $srv_list += "EU" }

        $needs_dl = $false; $dl_na = $false; $dl_eu = $false
        $s_ver_na = "0"; $s_ver_eu = "0"

        foreach ($srv in $srv_list) {
            $api_domain = if ($srv -eq "EU") { "eu.tamrieltradecentre.com" } else { "us.tamrieltradecentre.com" }
            $apiResp = (& curl.exe -s -m 10 -A "$TTC_USER_AGENT" "https://$api_domain/api/GetTradeClientVersion" 2>$null) -join ""
            $s_ver = if ($apiResp -match '"PriceTableVersion"\s*:\s*"?([0-9]+)') { $matches[1] } else { "0" }
            if ($s_ver -eq "0") { UIEcho " $ESC[31m[-] Could not fetch TTC version for $srv.$ESC[0m" }

            if ($srv -eq "NA") { $s_ver_na = $s_ver; $loc_ver = "$global:TTC_NA_VERSION" } else { $s_ver_eu = $s_ver; $loc_ver = "$global:TTC_EU_VERSION" }
            if (!$loc_ver) { $loc_ver = "0" }

            $pt_file = "$ADDON_DIR\TamrielTradeCentre\PriceTable${srv}.lua"
            if ($loc_ver -eq "0" -and (Test-Path $pt_file)) {
                foreach ($l in (Get-Content $pt_file -TotalCount 5)) {
                    if ($l -match '(?i)^--Version[ \t]*=[ \t]*([0-9]+)') { $loc_ver = $matches[1]; break }
                }
            }

            $loc_disp = if ($loc_ver -eq "0") { "None" } else { $loc_ver }
            $s_ver_disp = if ($s_ver -eq "0") { "Error" } else { $s_ver }
            $v_col = if ($s_ver -eq $loc_ver) { "$ESC[92m" } else { "$ESC[31m" }
            UIEcho " `t$ESC[90mServer Version ($srv): ${v_col}$s_ver_disp$ESC[0m"
            UIEcho " `t$ESC[90mLocal Version ($srv):  ${v_col}$loc_disp$ESC[0m"

            if ($s_ver -ne "0" -and (To-Num $s_ver) -gt (To-Num $loc_ver)) {
                $needs_dl = $true
                if ($srv -eq "NA") { $dl_na = $true } else { $dl_eu = $true }
            }
        }

        if ($needs_dl) {
            UIEcho " $ESC[92mNew TTC Price Table available $ESC[0m"
            $ttc_diff = $CURRENT_TIME - (To-Num $global:TTC_LAST_DOWNLOAD)

            if ($global:ENABLE_LOCAL_MODE) {
                UIEcho " $ESC[90m[Local Mode] Download Skipped.$ESC[0m`n"
            } elseif ($ttc_diff -lt 3600 -and $ttc_diff -ge 0) {
                $wait_m = [math]::Floor((3600 - $ttc_diff) / 60)
                $notifTTC = if ($notifTTC -eq "Data Uploaded") { "Uploaded (DL Cooldown)" } else { "Download Cooldown" }
                UIEcho " $ESC[33mdownload is on cooldown ($wait_m min). $ESC[35mSkipping.$ESC[0m`n"
            } else {
                $success_all = $true; $TEMP_DIR_USED = $true; $rate_limit = $false

                foreach ($srv in $srv_list) {
                    if ($srv -eq "NA" -and !$dl_na) { continue }
                    if ($srv -eq "EU" -and !$dl_eu) { continue }
                    $dl_url = if ($srv -eq "NA") { "https://us.tamrieltradecentre.com/download/PriceTable" } else { "https://eu.tamrieltradecentre.com/download/PriceTable" }
                    $zipPath = "$TEMP_DIR\TTC-data-${srv}.zip"

                    Start-Spinner "Downloading TTC Price Table ($srv)..."
                    & curl.exe -s -f -A "$TTC_USER_AGENT" -L -o $zipPath "$dl_url" 2>$null
                    $success = $false
                    if ($LASTEXITCODE -eq 22) {
                        $rate_limit = $true
                        Stop-Spinner 1 "TTC Rate Limit reached ($srv)"
                        $success_all = $false; break
                    } elseif ($LASTEXITCODE -eq 0 -and (Test-ZipFile $zipPath)) {
                        $success = $true
                    }

                    if (!$success) {
                        Stop-Spinner 1 "Primary UA blocked ($srv)"
                        Start-Spinner "Retrying with fallback User-Agent ($srv)..."
                        foreach ($ua in $shuffledUAs) {
                            & curl.exe -s -f -H "User-Agent: $ua" -L -o $zipPath "$dl_url" 2>$null
                            if ($LASTEXITCODE -eq 22) { $rate_limit = $true; Stop-Spinner 1 "TTC Rate Limit reached ($srv)"; break }
                            if ($LASTEXITCODE -eq 0 -and (Test-ZipFile $zipPath)) { $success = $true; break }
                        }
                        if ($rate_limit) { $success_all = $false; break }
                    }

                    if ($success) {
                        Expand-Archive -Path $zipPath -DestinationPath "$TEMP_DIR\TTC_Extracted_${srv}" -Force
                        Stop-Spinner 0 "TTC Updated ($srv)"
                    } else {
                        Stop-Spinner 1 "TTC download failed ($srv)"
                        $success_all = $false
                    }
                }

                $has_na = Test-Path "$TEMP_DIR\TTC_Extracted_NA"
                $has_eu = Test-Path "$TEMP_DIR\TTC_Extracted_EU"

                if ($success_all -or $has_na -or $has_eu) {
                    $ttc_dir = "$ADDON_DIR\TamrielTradeCentre"
                    if (!(Test-Path $ttc_dir)) { New-Item -ItemType Directory -Force -Path $ttc_dir | Out-Null }
                    if ($has_na) { Copy-Item -Path "$TEMP_DIR\TTC_Extracted_NA\*" -Destination "$ttc_dir\" -Recurse -Force; $global:TTC_NA_VERSION = $s_ver_na }
                    if ($has_eu) { Copy-Item -Path "$TEMP_DIR\TTC_Extracted_EU\*" -Destination "$ttc_dir\" -Recurse -Force; $global:TTC_EU_VERSION = $s_ver_eu }
                    $global:TTC_LAST_DOWNLOAD = $CURRENT_TIME; $global:CONFIG_CHANGED = $true
                    $notifTTC = if ($notifTTC -eq "Data Uploaded") { "Uploaded & Updated" } else { "Updated" }
                    UIEcho ""
                } elseif (!$rate_limit) {
                    $notifTTC = if ($notifTTC -eq "Data Uploaded") { "Uploaded, DL Failed" } else { "Download Error" }
                }
            }
        } else {
            if ($s_ver_na -ne "0" -and (To-Num $s_ver_na) -ge (To-Num $global:TTC_NA_VERSION)) { $global:TTC_NA_VERSION = $s_ver_na; $global:CONFIG_CHANGED = $true }
            if ($s_ver_eu -ne "0" -and (To-Num $s_ver_eu) -ge (To-Num $global:TTC_EU_VERSION)) { $global:TTC_EU_VERSION = $s_ver_eu; $global:CONFIG_CHANGED = $true }
            UIEcho " $ESC[90mNo changes detected. $ESC[92mLocal PriceTable is up-to-date.$ESC[0m`n"
        }
    }
