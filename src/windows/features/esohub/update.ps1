    UIEcho "$ESC[1m$ESC[97m [3/4] Updating ESO-Hub Prices & Uploading Scans $ESC[0m"
    UIEcho " $ESC[36mFetching latest ESO-Hub version data...$ESC[0m"

    Import-EsoHubCf
    $global:EH_LAST_CHECK = $CURRENT_TIME; $global:CONFIG_CHANGED = $true
    $ehUploadCount = 0; $ehUpdateCount = 0

    $ehFetched = [bool](Get-EsoHubAddons)
    if (!$ehFetched -and $global:ESOHUB_BLOCKED) {
        if (Invoke-EsoHubCfAskNow) {
            UIEcho " $ESC[36mFetching latest ESO-Hub version data...$ESC[0m"
            if (Get-EsoHubAddons) {
                $ehFetched = $true; $global:ESOHUB_CF_ASKED = $false
                Log-Event "INFO" "ESO-Hub accepted the browser check."
            } elseif ($global:ESOHUB_BLOCKED) {
                UIEcho " $ESC[31m[-] ESO-Hub still answers with a Cloudflare check. Copy cf_clearance from the browser that opened, on this PC and network.$ESC[0m"
            }
        } elseif ($global:ESOHUB_CF_HINT) {
            UIEcho " $ESC[90m$($global:ESOHUB_CF_HINT)$ESC[0m"
        }
    }

    if (!$ehFetched) {
        if ($global:ESOHUB_BLOCKED) {
            $notifEH = "Skipped (ESO-Hub server check)"
            UIEcho " $ESC[35mSkipping ESO-Hub this cycle.$ESC[0m $ESC[90m($global:ESOHUB_FAIL)$ESC[0m`n"
            Log-Event "WARN" "ESO-Hub skipped: Cloudflare check instead of data ($global:ESOHUB_FAIL)."
        } else {
            $notifEH = "Download Error"
            UIEcho " $ESC[31m[-] Could not fetch ESO-Hub data.$ESC[0m $ESC[90m($global:ESOHUB_FAIL)$ESC[0m`n"
            Log-Event "ERROR" "Could not fetch ESO-Hub data ($global:ESOHUB_FAIL)."
        }
    } else {
        $EH_TIME_DIFF = $CURRENT_TIME - (To-Num $global:EH_LAST_DOWNLOAD)
        $EH_DOWNLOAD_OCCURRED = $false

        foreach ($rec in @($global:ESOHUB_RECORDS)) {
            $f = "$rec".Split('|')
            if ($f.Count -lt 7) { continue }
            $ID_NUM = $f[0]; $FNAME = $f[1]; $SRV_VER = $f[2]; $DL_URL = $f[3]; $DL_SUM = $f[4]; $UP_EP = $f[5]; $SV_LIST = $f[6]
            if (!$FNAME) { continue }

            if (!(Check-Addon-Enabled $FNAME)) {
                UIEcho " $ESC[31m[-] $FNAME missing. $ESC[35mSkipping.$ESC[0m"
                continue
            }

            $PREFIX = switch ($FNAME) { "EsoTradingHub" { "ETH5" } "LibEsoHubPrices" { "LEHP7" } "EsoHubScanner" { "EHS" } default { $FNAME } }

            $VAR_LOC_NAME = "EH_LOC_$ID_NUM"
            $LOC_VER = Get-EsoHubLocalVersion (Join-Path $ADDON_DIR $FNAME) $FNAME
            if ($LOC_VER) {
                if ("$(Get-Variable -Name $VAR_LOC_NAME -Scope Global -ValueOnly -ErrorAction SilentlyContinue)" -ne $LOC_VER) {
                    Set-Variable -Name $VAR_LOC_NAME -Value $LOC_VER -Scope Global
                    $global:CONFIG_CHANGED = $true
                }
            } else {
                $LOC_VER = "$(Get-Variable -Name $VAR_LOC_NAME -Scope Global -ValueOnly -ErrorAction SilentlyContinue)"
                if (!$LOC_VER) { $LOC_VER = "0" }
                if ($LOC_VER -eq "0" -and (Test-Path -LiteralPath (Join-Path $ADDON_DIR $FNAME))) {
                    $LOC_VER = $SRV_VER
                    Set-Variable -Name $VAR_LOC_NAME -Value $SRV_VER -Scope Global
                    $global:CONFIG_CHANGED = $true
                }
            }

            $ehNewer = Test-EsoHubNewer $SRV_VER $LOC_VER
            $ehSrvCol = "$ESC[92m"; $ehLocCol = if ($ehNewer) { "$ESC[31m" } else { "$ESC[92m" }
            UIEcho " $ESC[33mChecking server for $FNAME.zip...$ESC[0m"
            UIEcho "`t$ESC[90m${PREFIX}_Server_Version= ${ehSrvCol}$SRV_VER$ESC[0m"
            UIEcho "`t$ESC[90m${PREFIX}_Local_Version= ${ehLocCol}$LOC_VER$ESC[0m"

            $ehSend = New-Object System.Collections.Generic.List[string]
            $ehSnaps = New-Object System.Collections.Generic.List[string]
            $ehAll = New-Object System.Collections.Generic.List[string]
            if ($UP_EP -and $SV_LIST) {
                foreach ($SV_NAME in @($SV_LIST.Split(';') | Where-Object { $_ })) {
                    $svPath = Join-Path $SAVED_VAR_DIR $SV_NAME
                    if (!(Test-Path -LiteralPath $svPath)) { continue }
                    $ehAll.Add($SV_NAME)
                    $UP_SNAP = Join-Path $SNAP_DIR "lttc_eh_$($SV_NAME.ToLower().Replace('.lua', ''))_snapshot.lua"

                    if (!(Test-FileNewer $svPath $UP_SNAP)) {
                        UIEcho " $ESC[90mNo changes detected in $SV_NAME. $ESC[35mSkipping upload.$ESC[0m"
                        continue
                    }

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

                        Merge-HistoryReport $res.History
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
                        $ehSend.Add($SV_NAME); $ehSnaps.Add($UP_SNAP)
                    }
                }
            }

            if ($ehSend.Count -gt 0) {
                $ehSendShown = $ehSend -join ', '
                Start-Spinner "Uploading local scan data ($ehSendShown)..."
                if (Send-EsoHubUpload $global:ESOHUB_API_USED $UP_EP ($ehSend -join ';') ($ehAll -join ';')) {
                    for ($i = 0; $i -lt $ehSend.Count; $i++) {
                        Copy-Item -LiteralPath (Join-Path $SAVED_VAR_DIR $ehSend[$i]) -Destination $ehSnaps[$i] -Force -ErrorAction SilentlyContinue
                    }
                    $ehUploadCount++
                    Stop-Spinner 0 "Upload finished ($ehSendShown)"
                } else {
                    Stop-Spinner 1 "Upload failed ($ehSendShown)"
                    Log-Event "ERROR" "ESO-Hub upload of $ehSendShown failed on both API versions."
                }
            }

            if ($DL_URL) {
                if (!$ehNewer) {
                    UIEcho " $ESC[90mNo changes detected. $ESC[92m($FNAME.zip) is up-to-date. $ESC[35mSkipping download.$ESC[0m"
                } elseif ($global:ENABLE_LOCAL_MODE) {
                    UIEcho " $ESC[90m[Local Mode] Skipping Download for $FNAME.zip.$ESC[0m"
                } elseif ($EH_TIME_DIFF -lt 3600 -and $EH_TIME_DIFF -ge 0) {
                    $WAIT_MINS = [math]::Floor((3600 - $EH_TIME_DIFF) / 60)
                    UIEcho " $ESC[33mNew $FNAME.zip available, but download is on cooldown for $WAIT_MINS more minutes. $ESC[35mSkipping.$ESC[0m"
                } else {
                    Start-Spinner "Downloading $FNAME.zip..."
                    $TEMP_DIR_USED = $true
                    $zipPath = Join-Path $TEMP_DIR_ROOT "EH_$ID_NUM.zip"
                    $ehExtractDir = Join-Path $TEMP_DIR_ROOT "ESOHub_Extracted"
                    $ehDlRc = Get-EsoHubFile $DL_URL $zipPath $DL_SUM

                    if ($ehDlRc -eq 0) {
                        Remove-Item -LiteralPath $ehExtractDir -Recurse -Force -ErrorAction SilentlyContinue
                        Expand-Archive -LiteralPath $zipPath -DestinationPath $ehExtractDir -Force
                        Copy-Item -Path (Join-Path $ehExtractDir "*") -Destination $ADDON_DIR -Recurse -Force
                        $ehNewLoc = Get-EsoHubLocalVersion (Join-Path $ADDON_DIR $FNAME) $FNAME
                        Set-Variable -Name $VAR_LOC_NAME -Value $(if ($ehNewLoc) { $ehNewLoc } else { $SRV_VER }) -Scope Global
                        $global:CONFIG_CHANGED = $true; $EH_DOWNLOAD_OCCURRED = $true; $ehUpdateCount++
                        Stop-Spinner 0 "$FNAME.zip updated successfully"
                    } elseif ($ehDlRc -eq 2) {
                        Stop-Spinner 1 "Error: $FNAME.zip failed its checksum, not installed"
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
