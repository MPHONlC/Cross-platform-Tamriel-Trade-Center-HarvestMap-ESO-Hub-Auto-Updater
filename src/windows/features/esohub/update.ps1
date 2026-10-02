    UIEcho "$ESC[1m$ESC[97m [3/4] Updating ESO-Hub Prices & Uploading Scans $ESC[0m"
    UIEcho " $ESC[36mFetching latest ESO-Hub version data...$ESC[0m"

    $global:EH_LAST_CHECK = $CURRENT_TIME; $global:CONFIG_CHANGED = $true
    $ehUploadCount = 0; $ehUpdateCount = 0

    $apiResp = (& curl.exe -s -X POST -H "User-Agent: ESOHubClient/1.0.9" -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" "https://data.eso-hub.com/v1/api/get-addon-versions" 2>$null) -join ""
    $addonBlocks = @($apiResp.Replace('{"folder_name"', "`n{`"folder_name`"") -split "`n" | Where-Object { $_ -match '"folder_name"' })

    if ($addonBlocks.Count -eq 0) {
        $notifEH = "Download Error"
        UIEcho " $ESC[31m[-] Could not fetch ESO-Hub data.$ESC[0m`n"
    } else {
        $EH_TIME_DIFF = $CURRENT_TIME - (To-Num $global:EH_LAST_DOWNLOAD)
        $EH_DOWNLOAD_OCCURRED = $false

        foreach ($line in $addonBlocks) {
            $FNAME = if ($line -match '"folder_name":"([^"]+)"') { $matches[1] } else { "" }
            $SV_NAME = if ($line -match '"sv_file_name":"([^"]+)"') { $matches[1] } else { "" }
            $UP_EP = if ($line -match '"endpoint":"([^"]+)"') { $matches[1].Replace('\', '') } else { "" }
            $DL_URL = if ($line -match '"file":"([^"]+)"') { $matches[1].Replace('\', '') } else { "" }
            if (!$FNAME) { continue }

            if (!(Check-Addon-Enabled $FNAME)) {
                UIEcho " $ESC[31m[-] $FNAME missing. $ESC[35mSkipping.$ESC[0m"
                continue
            }

            $ID_NUM = if ($DL_URL -match '([0-9]+)$') { $matches[1] } else { "0" }
            $SRV_VER = if ($line -match '"version":\{[^}]*"string":"([^"]+)"') { $matches[1] } else { "" }
            $PREFIX = switch ($FNAME) { "EsoTradingHub" { "ETH5" } "LibEsoHubPrices" { "LEHP7" } "EsoHubScanner" { "EHS" } default { $FNAME } }

            $VAR_LOC_NAME = "EH_LOC_$ID_NUM"
            $LOC_VER = "$(Get-Variable -Name $VAR_LOC_NAME -Scope Global -ValueOnly -ErrorAction SilentlyContinue)"
            if (!$LOC_VER) { $LOC_VER = "0" }
            if ($LOC_VER -eq "0" -and (Test-Path "$ADDON_DIR\$FNAME")) {
                $LOC_VER = $SRV_VER
                Set-Variable -Name $VAR_LOC_NAME -Value $SRV_VER -Scope Global
                $global:CONFIG_CHANGED = $true
            }

            $V_COL = if ($SRV_VER -eq $LOC_VER) { "$ESC[92m" } else { "$ESC[31m" }
            UIEcho " $ESC[33mChecking server for $FNAME.zip...$ESC[0m"
            UIEcho "`t$ESC[90m${PREFIX}_Server_Version= ${V_COL}$SRV_VER$ESC[0m"
            UIEcho "`t$ESC[90m${PREFIX}_Local_Version= ${V_COL}$LOC_VER$ESC[0m"

            $svPath = "$SAVED_VAR_DIR\$SV_NAME"
            if ($SV_NAME -and $UP_EP -and (Test-Path -LiteralPath $svPath)) {
                $UP_SNAP = "$SNAP_DIR\lttc_eh_$($SV_NAME.ToLower().Replace('.lua', ''))_snapshot.lua"

                if (!(Test-FileNewer $svPath $UP_SNAP)) {
                    UIEcho " $ESC[90mNo changes detected in $SV_NAME. $ESC[35mSkipping upload.$ESC[0m"
                } else {
                    $ehExtracted = $false; $ehRawCount = 0
                    if ($SV_NAME -eq "EsoTradingHub.lua" -and $global:ENABLE_DISPLAY -and !$global:SILENT) {
                        Start-Spinner "Parsing $SV_NAME..."
                        [System.IO.File]::AppendAllText($TEMP_SCAN_FILE, "`n$ESC[0;35m--- ESO-Hub Extracted Data ---$ESC[0m`n", [System.Text.Encoding]::UTF8)
                        $res = Invoke-EsoHubExtraction $svPath $global:EH_LAST_SALE $CURRENT_TIME
                        Stop-Spinner 0 "Extraction complete"
                        $ehExtracted = $true; $ehRawCount = $res.Lines.Count

                        if ($ehRawCount -gt 0) {
                            $FOUND_NEW_DATA = $true
                            foreach ($l in $res.Lines) {
                                $cut = $l.IndexOf('|'); $ts = $l.Substring(0, $cut); $rest = $l.Substring($cut + 1)
                                $rawLine = if ($ts -eq "0") { " [$ESC[90mListing$ESC[0m]$rest" } else { " [TS:$ts]$rest" }
                                UIEcho $rawLine
                                [System.IO.File]::AppendAllText($TEMP_SCAN_FILE, "$rawLine`n", [System.Text.Encoding]::UTF8)
                            }
                        } else {
                            UIEcho " $ESC[90mNo new ESO-Hub items found. Upload skipped.$ESC[0m"
                        }

                        Merge-History $res.History
                        Apply-DB-Updates $res.DbUpdates
                        if ("$($res.MaxTime)" -ne "$global:EH_LAST_SALE") { $global:EH_LAST_SALE = $res.MaxTime; $global:CONFIG_CHANGED = $true }
                    } elseif ($SV_NAME -eq "EsoTradingHub.lua" -and !$global:ENABLE_DISPLAY -and !$global:SILENT) {
                        UIEcho " $ESC[90mExtraction disabled by user. Proceeding instantly to upload...$ESC[0m"
                    }

                    if ($global:ENABLE_LOCAL_MODE) {
                        UIEcho " $ESC[90m[Local Mode] Skipping ESO-Hub Upload ($SV_NAME).$ESC[0m"
                        Copy-Item -LiteralPath $svPath -Destination $UP_SNAP -Force -ErrorAction SilentlyContinue
                    } elseif ($SV_NAME -eq "EsoTradingHub.lua" -and $ehExtracted -and $ehRawCount -eq 0) {
                        Copy-Item -LiteralPath $svPath -Destination $UP_SNAP -Force -ErrorAction SilentlyContinue
                    } elseif ($SV_NAME -eq "EsoHubScanner.lua" -and !(Select-String -LiteralPath $svPath -Pattern '\|H[0-9a-fA-F]*:item:[0-9]+' -Quiet)) {
                        Copy-Item -LiteralPath $svPath -Destination $UP_SNAP -Force -ErrorAction SilentlyContinue
                    } else {
                        Start-Spinner "Uploading local scan data ($SV_NAME)..."
                        & curl.exe -s -f -m 60 -A "ESOHubClient/1.0.9" -F "file=@$svPath" "https://data.eso-hub.com$UP_EP`?user_token=$global:EH_USER_TOKEN" 2>$null | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Copy-Item -LiteralPath $svPath -Destination $UP_SNAP -Force -ErrorAction SilentlyContinue
                            $ehUploadCount++
                            Stop-Spinner 0 "Upload finished ($SV_NAME)"
                        } else {
                            Stop-Spinner 1 "Upload failed ($SV_NAME)"
                        }
                    }
                }
            }

            if ($DL_URL) {
                if ($SRV_VER -eq $LOC_VER) {
                    UIEcho " $ESC[90mNo changes detected. $ESC[92m($FNAME.zip) is up-to-date. $ESC[35mSkipping download.$ESC[0m"
                } elseif ($global:ENABLE_LOCAL_MODE) {
                    UIEcho " $ESC[90m[Local Mode] Skipping Download for $FNAME.zip.$ESC[0m"
                } elseif ($EH_TIME_DIFF -lt 3600 -and $EH_TIME_DIFF -ge 0) {
                    $WAIT_MINS = [math]::Floor((3600 - $EH_TIME_DIFF) / 60)
                    UIEcho " $ESC[33mNew $FNAME.zip available, but download is on cooldown for $WAIT_MINS more minutes. $ESC[35mSkipping.$ESC[0m"
                } else {
                    Start-Spinner "Downloading $FNAME.zip..."
                    $TEMP_DIR_USED = $true
                    $zipPath = "$TEMP_DIR_ROOT\EH_$ID_NUM.zip"
                    & curl.exe -s -f -L -m 30 -A "ESOHubClient/1.0.9" -o $zipPath "$DL_URL" 2>$null
                    if ($LASTEXITCODE -ne 0) { & curl.exe -s -f -L -m 30 -A "$RAND_UA" -o $zipPath "$DL_URL" 2>$null }

                    if (Test-ZipFile $zipPath) {
                        Expand-Archive -Path $zipPath -DestinationPath "$TEMP_DIR_ROOT\ESOHub_Extracted" -Force
                        Copy-Item -Path "$TEMP_DIR_ROOT\ESOHub_Extracted\*" -Destination "$ADDON_DIR\" -Recurse -Force
                        Set-Variable -Name $VAR_LOC_NAME -Value $SRV_VER -Scope Global
                        $global:CONFIG_CHANGED = $true; $EH_DOWNLOAD_OCCURRED = $true; $ehUpdateCount++
                        Stop-Spinner 0 "$FNAME.zip updated successfully"
                    } else {
                        Stop-Spinner 1 "Error: $FNAME.zip download corrupted"
                    }
                }
            }
        }

        if ($EH_DOWNLOAD_OCCURRED) { $global:EH_LAST_DOWNLOAD = $CURRENT_TIME }
        if ($ehUpdateCount -gt 0 -or $ehUploadCount -gt 0) { $notifEH = "Updated ($ehUpdateCount), Uploaded ($ehUploadCount)" }
        UIEcho ""
    }
