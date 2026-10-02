    if ($FOUND_NEW_DATA) { Copy-Item -Path $TEMP_SCAN_FILE -Destination $LAST_SCAN_FILE -Force }

    Prune-History
    if ($global:CONFIG_CHANGED) { save_config }

    Set-Location $env:USERPROFILE
    Start-Spinner "Cleaning up temp files & old logs..."

    try {
        $logCutoff = (Get-Date).AddDays(-3).ToString("yyyy-MM-dd HH:mm:ss"); $keepLog = $false
        $keptLog = @(foreach ($l in [System.IO.File]::ReadAllLines($LOG_FILE)) {
            if ($l -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') { $keepLog = ([string]::CompareOrdinal($matches[1], $logCutoff) -ge 0) }
            if ($keepLog) { $l }
        })
        [System.IO.File]::WriteAllLines($LOG_FILE, [string[]]$keptLog)
    } catch {}

    $deleted = New-Object System.Collections.Generic.List[string]
    foreach ($t in @($TEMP_DIR, "$TEMP_DIR_ROOT\*.tmp", "$TEMP_DIR_ROOT\*.out", "$TEMP_DIR_ROOT\*.zip", "$TEMP_DIR_ROOT\ESOHub_Extracted")) {
        foreach ($it in @(Get-Item -Path $t -ErrorAction SilentlyContinue)) {
            $deleted.Add($it.FullName)
            if ($it.PSIsContainer) { Get-ChildItem -LiteralPath $it.FullName -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $deleted.Add($_.FullName) } }
        }
        Remove-Item -Path $t -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($global:LOG_MODE -eq "detailed") { foreach ($f in $deleted) { Log-Event "ITEM" "Deleted Temporary File/Folder: $f" } }

    Stop-Spinner 0 "Cleanup complete ($($deleted.Count) items removed)"
    if ($deleted.Count -gt 0 -and !$global:SILENT) {
        foreach ($f in $deleted) { UIEcho " $ESC[90m-> Deleted: $f$ESC[0m" }
        UIEcho ""
    }

    if ($global:ENABLE_NOTIFS) {
        $msg = "TTC: $notifTTC`nESO-Hub: $notifEH`nHarvestMap: $notifHM"
        if ($global:notifAddons) { $msg += "`nAdd-ons: $($global:notifAddons)" }
        try {
            [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
            [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
            $appId = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
            $template = "<toast><visual><binding template=`"ToastText02`"><text id=`"1`">Windows Tamriel Trade Center v$APP_VERSION</text><text id=`"2`">$msg</text></binding></visual></toast>"
            $xmlDocument = New-Object Windows.Data.Xml.Dom.XmlDocument
            $xmlDocument.LoadXml($template)
            $toast = [Windows.UI.Notifications.ToastNotification]::new($xmlDocument)
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
        } catch {}
    }

    if ($AUTO_MODE -eq "1") { 
        try {
            $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
            if ($parent.ParentProcessId) {
                $parentProc = Get-Process -Id $parent.ParentProcessId -ErrorAction SilentlyContinue
                if ($parentProc.Name -eq "cmd") { Stop-Process -Id $parentProc.Id -Force }
            }
        } catch {}
        [Environment]::Exit(0)
    }

