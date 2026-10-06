    if (!$HAS_HM -or $global:ENABLE_LOCAL_MODE) {
        $notifHM = "Skipped"
        UIEcho "$ESC[1m$ESC[97m [4/4] Updating HarvestMap Data (SKIPPED) $ESC[0m"
        if ($global:ENABLE_LOCAL_MODE) { UIEcho " $ESC[90m[Local Mode] Skipping HarvestMap updates.$ESC[0m`n" }
        else { UIEcho " $ESC[31m[-] HarvestMap not enabled in AddOnSettings.txt. $ESC[35mSkipping...$ESC[0m`n" }
    } else {
        $HM_DIR = "$ADDON_DIR\HarvestMapData"
        $EMPTY_FILE = "$HM_DIR\Main\emptyTable.lua"
        $MAIN_HM_FILE = "$SAVED_VAR_DIR\HarvestMap.lua"
        $HM_SNAP = "$SNAP_DIR\lttc_hm_main_snapshot.lua"

        if (Test-Path $HM_DIR) {
            $HM_CHANGED = $true
            $localHmStatus = "Out-of-Sync"
            if ((Test-Path $MAIN_HM_FILE) -and !(Test-FileNewer $MAIN_HM_FILE $HM_SNAP)) {
                $HM_CHANGED = $false
                $localHmStatus = "Synced"
            }

            $global:HM_LAST_CHECK = $CURRENT_TIME; $global:CONFIG_CHANGED = $true
            $V_COL = if (!$HM_CHANGED) { "$ESC[92m" } else { "$ESC[31m" }

            UIEcho "$ESC[1m$ESC[97m [4/4] Updating HarvestMap Data $ESC[0m"
            UIEcho " $ESC[33mVerifying HarvestMap local data state...$ESC[0m"
            if ((To-Num $global:HM_LAST_DOWNLOAD) -gt 0) { UIEcho "`t$ESC[90mLast_Download= $ESC[92m$(Convert-TimeStr ([long](To-Num $global:HM_LAST_DOWNLOAD)))$ESC[0m" }
            else { UIEcho "`t$ESC[90mLast_Download= $ESC[31mNever$ESC[0m" }
            UIEcho "`t$ESC[90mLocal_Data_Status= ${V_COL}$localHmStatus$ESC[0m"

            if (!$HM_CHANGED) {
                UIEcho " $ESC[90mNo changes detected. $ESC[92mHarvestMap.lua up-to-date.$ESC[0m`n"
            } else {
                $HM_TIME_DIFF = $CURRENT_TIME - (To-Num $global:HM_LAST_DOWNLOAD)
                if ($HM_TIME_DIFF -lt 3600 -and $HM_TIME_DIFF -ge 0) {
                    $WAIT_MINS = [math]::Floor((3600 - $HM_TIME_DIFF) / 60)
                    $notifHM = "Cooldown ($WAIT_MINS min)"
                    UIEcho " $ESC[33mLocal changes detected, but download is on cooldown for"
                    UIEcho " $WAIT_MINS more minutes. $ESC[35mSkipping.$ESC[0m`n"
                } else {
                    if (!(Test-Path $SAVED_VAR_DIR)) { New-Item -ItemType Directory -Force -Path $SAVED_VAR_DIR | Out-Null }
                    $hmFailed = $false
                    $zones = @("AD", "EP", "DC", "DLC", "NF")

                    UIEcho " $ESC[36mTargeting following database chunks for merge:$ESC[0m"
                    foreach ($zone in $zones) { UIEcho " $ESC[90m-> $HM_DIR\Modules\HarvestMap${zone}\HarvestMap${zone}.lua$ESC[0m" }

                    Start-Spinner "Preparing HarvestMap data..."
                    foreach ($zone in $zones) {
                        Update-Spinner "Merging local HarvestMap ${zone} data..."
                        $svfn1 = "$SAVED_VAR_DIR\HarvestMap${zone}.lua"
                        $svfn2 = "${svfn1}~"

                        if (Test-Path -LiteralPath $svfn1) {
                            Move-Item -LiteralPath $svfn1 -Destination $svfn2 -Force
                        } elseif (Test-Path $EMPTY_FILE) {
                            [System.IO.File]::WriteAllText($svfn2, "Harvest${zone}_SavedVars" + [System.IO.File]::ReadAllText($EMPTY_FILE))
                        } else {
                            [System.IO.File]::WriteAllText($svfn2, "Harvest${zone}_SavedVars={[`"data`"]={}}")
                        }

                        $modDir = "$HM_DIR\Modules\HarvestMap${zone}"
                        if (!(Test-Path $modDir)) { New-Item -ItemType Directory -Force -Path $modDir | Out-Null }

                        Update-Spinner "Downloading HarvestMap ${zone} chunk..."
                        & curl.exe -s -f -L -A "$HM_USER_AGENT" -d "@$svfn2" -o "$modDir\HarvestMap${zone}.lua" "http://harvestmap.binaryvector.net:8081" 2>$null
                        if ($LASTEXITCODE -ne 0) {
                            & curl.exe -s -f -L -H "User-Agent: $RAND_UA" -d "@$svfn2" -o "$modDir\HarvestMap${zone}.lua" "http://harvestmap.binaryvector.net:8081" 2>$null
                            if ($LASTEXITCODE -ne 0) { $hmFailed = $true }
                        }
                    }

                    if (!$hmFailed) {
                        if (Test-Path $MAIN_HM_FILE) { Copy-Item -LiteralPath $MAIN_HM_FILE -Destination $HM_SNAP -Force -ErrorAction SilentlyContinue }
                        $global:HM_LAST_DOWNLOAD = $CURRENT_TIME; $global:CONFIG_CHANGED = $true
                        $notifHM = "Updated successfully"
                        Stop-Spinner 0 "HarvestMap Data Successfully Updated"
                    } else {
                        $notifHM = "Error (Server Blocked)"
                        Stop-Spinner 1 "HarvestMap Update Failed"
                    }
                    UIEcho ""
                }
            }
        } else {
            $notifHM = "Not Found (Skipped)"
            UIEcho "$ESC[1m$ESC[97m [4/4] Updating HarvestMap Data (SKIPPED) $ESC[0m"
            UIEcho " $ESC[31m[!] HarvestMapData folder not found in: $ADDON_DIR. $ESC[35mSkipping...$ESC[0m`n"
        }
    }
