    $HAS_TTC = Check-Addon-Enabled "TamrielTradeCentre"
    $HAS_HM = Check-Addon-Enabled "HarvestMap"

    if (!$global:ENABLE_LOCAL_MODE) {
        UIEcho "$ESC[1m$ESC[97m [0/4] Synchronizing Local Database $ESC[0m"
        UIEcho " $ESC[33mChecking ESOUI for database updates...$ESC[0m"
        
        $SRV_DB_VER = "0.0.0"
        if (Get-EsouiDetails $ESOUI_DB_ID) { $SRV_DB_VER = $script:ESOUI_VERSION }

        $LOC_DB_VER = "0.0.0"
        if (Test-Path $DB_FILE) {
            $firstLine = (Get-Content $DB_FILE -TotalCount 1)
            if ($firstLine -match '([0-9]+(\.[0-9]+)+)') { $LOC_DB_VER = $matches[1] }
        }

        $V_COL = if ($SRV_DB_VER -eq $LOC_DB_VER) {"$ESC[92m"} else {"$ESC[31m"}
        UIEcho "`t$ESC[90mServer_DB_Version= ${V_COL}$SRV_DB_VER$ESC[0m"
        UIEcho "`t$ESC[90mLocal_DB_Version=  ${V_COL}$LOC_DB_VER$ESC[0m"

        $histFirst = if (Test-Path -LiteralPath $HIST_FILE) { "$(Get-Content -LiteralPath $HIST_FILE -TotalCount 1)" } else { "" }
        $histSeeded = $histFirst -like "#HISTORY VERSION:*"
        if ($SRV_DB_VER -ne "0.0.0" -and ((Test-VersionNewer $SRV_DB_VER $LOC_DB_VER) -or !$histSeeded)) {
            UIEcho " $ESC[36mDownloading latest database template...$ESC[0m"
            Log-Event "INFO" "Downloading database update (v$SRV_DB_VER)"
            
            $dbZipPath = Join-Path $TEMP_DIR_ROOT "db.zip"
            try {
                $TEMP_DIR_USED = $true
                if ((Invoke-EsouiDownload $ESOUI_DB_ID $dbZipPath) -eq 0) {
                    $dbUpdateDir = Join-Path $TEMP_DIR_ROOT "DB_Update"
                    Expand-Archive -Path $dbZipPath -DestinationPath $dbUpdateDir -Force
                    
                    $NEW_DB = Get-ChildItem -Path $dbUpdateDir -Filter "LTTC_Database.db" -Recurse | Select-Object -First 1
                    $NEW_HIST = Get-ChildItem -Path $dbUpdateDir -Filter "LTTC_History.db" -Recurse | Select-Object -First 1
                    
                    if ($NEW_DB) {
                        if (!(Test-Path $DB_FILE) -or (Get-Item $DB_FILE).length -eq 0) {
                            $fresh = @("#DATABASE VERSION: $SRV_DB_VER") + @([System.IO.File]::ReadAllLines($NEW_DB.FullName) | Where-Object { !$_.StartsWith("#DATABASE VERSION:") })
                            [System.IO.File]::WriteAllText($DB_FILE, ($fresh -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
                            UIEcho " $ESC[92m[+] Database downloaded and installed!$ESC[0m`n"
                        } else {
                            UIEcho " $ESC[33mMerging new database entries (Preventing Duplicates)...$ESC[0m"
                            $seen = New-Object System.Collections.Hashtable
                            $mergedLines = New-Object System.Collections.ArrayList
                            [void]$mergedLines.Add("#DATABASE VERSION: $SRV_DB_VER")
                            
                            foreach ($file in @($DB_FILE, $NEW_DB.FullName)) {
                                foreach ($line in [System.IO.File]::ReadLines($file)) {
                                    if ($line.StartsWith("#DATABASE VERSION:")) { continue }
                                    $p = $line.Split('|')
                                    $key = if ($p[0] -eq "GUILD") {"GUILD_"+$p[1]} elseif ($p[0] -eq "KIOSK") {"KIOSK_"+$p[1]} elseif ($p[0] -match '^[0-9]+$') {"ITEM_"+$p[0]} else {$line}
                                    if (!$seen.ContainsKey($key)) {
                                        $seen[$key] = $true
                                        [void]$mergedLines.Add($line)
                                    }
                                }
                            }
                            [System.IO.File]::WriteAllText($DB_FILE, ($mergedLines.ToArray() -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
                            UIEcho " $ESC[92m[+] Database successfully merged to v$SRV_DB_VER!$ESC[0m`n"
                        }
                        if ($NEW_HIST) {
                            UIEcho " $ESC[33mMerging shared trade history...$ESC[0m"
                            Merge-TemplateHistory $HIST_FILE $NEW_HIST.FullName $SRV_DB_VER
                            UIEcho " $ESC[92m[+] Shared trade history merged.$ESC[0m`n"
                        } else {
                            $cur = if (Test-Path -LiteralPath $HIST_FILE) { @([System.IO.File]::ReadAllLines($HIST_FILE) | Where-Object { !$_.StartsWith("#HISTORY VERSION:") }) } else { @() }
                            [System.IO.File]::WriteAllText($HIST_FILE, ((@("#HISTORY VERSION: $SRV_DB_VER") + $cur) -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
                        }
                    }
                    Remove-Item -Path $dbUpdateDir -Recurse -Force
                    Remove-Item -LiteralPath $dbZipPath -Force -ErrorAction SilentlyContinue
                } else {
                    UIEcho " $ESC[31m[-] Database download failed (Timeout or Blocked).$ESC[0m`n"
                }
            } catch { UIEcho " $ESC[31m[-] Database download process failed.$ESC[0m`n" }
        } else {
            UIEcho " $ESC[90mNo changes detected. $ESC[92mLocal database is up-to-date. $ESC[35mSkipping download.$ESC[0m`n"
        }
    }

