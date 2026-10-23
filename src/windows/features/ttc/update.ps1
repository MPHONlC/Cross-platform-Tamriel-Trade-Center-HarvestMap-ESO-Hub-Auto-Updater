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

                    Merge-HistoryReport $res.History
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

        $srv_list = @()
        $ttc_checked = $false
        $ttc_check_age = $CURRENT_TIME - (To-Num $global:TTC_LAST_CHECK)
        if ($ttc_check_age -ge 0 -and $ttc_check_age -lt $TTC_CHECK_EVERY) {
            UIEcho "$ESC[1m$ESC[97m [2/4] Updating your Local TTC Data $ESC[0m"
            UIEcho " $ESC[90mTTC's price tables were checked $([math]::Floor($ttc_check_age / 60)) min ago and change about once a day. $ESC[35mNext check in $([math]::Floor(($TTC_CHECK_EVERY - $ttc_check_age + 59) / 60)) min.$ESC[0m`n"
        } else {
            UIEcho "$ESC[1m$ESC[97m [2/4] Updating your Local TTC Data $ESC[0m`n $ESC[33mChecking TTC Server...$ESC[0m"
            $global:TTC_LAST_CHECK = $CURRENT_TIME; $global:CONFIG_CHANGED = $true
            $ttc_checked = $true
            if ($AUTO_SRV -eq "1" -or $AUTO_SRV -eq "3") { $srv_list += "NA" }
            if ($AUTO_SRV -eq "2" -or $AUTO_SRV -eq "3") { $srv_list += "EU" }
        }

        $needs_dl = $false; $dl_na = $false; $dl_eu = $false
        $s_ver_na = "0"; $s_ver_eu = "0"

        foreach ($srv in $srv_list) {
            $api_domain = if ($srv -eq "EU") { "eu.tamrieltradecentre.com" } else { "us.tamrieltradecentre.com" }
            $apiResp = (& curl.exe -s -m 10 -A "$TTC_USER_AGENT" "https://$api_domain/api/GetTradeClientVersion" 2>$null) -join ""
            $s_ver = if ($apiResp -match '"PriceTableVersion"\s*:\s*"?([0-9]+)') { $matches[1] } else { "0" }
            if ($s_ver -eq "0") { UIEcho " $ESC[31m[-] Could not fetch TTC version for $srv.$ESC[0m" }

            if ($srv -eq "NA") { $s_ver_na = $s_ver } else { $s_ver_eu = $s_ver }
            $loc_ver = Get-TTCPriceTableVersion (Join-Path (Join-Path $ADDON_DIR "TamrielTradeCentre") "PriceTable${srv}.lua")

            $loc_disp = if ($loc_ver -eq "0") { "None" } else { $loc_ver }
            $s_ver_disp = if ($s_ver -eq "0") { "Error" } else { $s_ver }
            $s_col = if ($s_ver -eq "0") { "$ESC[31m" } else { "$ESC[92m" }
            $loc_col = if ($s_ver -ne "0" -and $s_ver -ne $loc_ver) { "$ESC[31m" } else { "$ESC[92m" }
            UIEcho " `t$ESC[90mServer Version ($srv): ${s_col}$s_ver_disp$ESC[0m"
            UIEcho " `t$ESC[90mLocal Version ($srv):  ${loc_col}$loc_disp$ESC[0m"

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
                    if ($has_na) { Copy-Item -Path "$TEMP_DIR\TTC_Extracted_NA\*" -Destination "$ttc_dir\" -Recurse -Force }
                    if ($has_eu) { Copy-Item -Path "$TEMP_DIR\TTC_Extracted_EU\*" -Destination "$ttc_dir\" -Recurse -Force }
                    $global:TTC_LAST_DOWNLOAD = $CURRENT_TIME; $global:CONFIG_CHANGED = $true
                    $notifTTC = if ($notifTTC -eq "Data Uploaded") { "Uploaded & Updated" } else { "Updated" }
                    UIEcho ""
                } elseif (!$rate_limit) {
                    $notifTTC = if ($notifTTC -eq "Data Uploaded") { "Uploaded, DL Failed" } else { "Download Error" }
                }
            }
        } elseif ($ttc_checked) {
            UIEcho " $ESC[90mNo changes detected. $ESC[92mLocal PriceTable is up-to-date.$ESC[0m`n"
        }
    }
