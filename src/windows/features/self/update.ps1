$SELF_UPDATE_INTERVAL = 21600
$SELF_RESTART_CODE = 3

function Install-SelfUpdate {
    $zip = Join-Path $TEMP_DIR_ROOT "self_update.zip"; $work = Join-Path $TEMP_DIR_ROOT "self_update"
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    $script:SELF_NEW_VERSION = ""
    $rc = Invoke-EsouiDownload $ESOUI_SELF_ID $zip
    if ($rc -ne 0) { return $rc }
    try { Expand-Archive -LiteralPath $zip -DestinationPath $work -Force } catch { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue; return 2 }
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    $new = Get-ChildItem -LiteralPath $work -Recurse -File -Filter $SCRIPT_NAME | Select-Object -First 1
    if (!$new) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue; return 2 }
    $text = [System.IO.File]::ReadAllText($new.FullName)
    $newVer = if ($text -cmatch '\$APP_VERSION = "([^"]+)"') { $matches[1] } else { "" }
    if ($text -notmatch '(?m)^==POWERSHELL_START==' -or !$newVer -or !(Test-VersionNewer $newVer $APP_VERSION)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue; return 3
    }

    $installed = Join-Path $TARGET_DIR $SCRIPT_NAME
    $running = if ($FULL_SCRIPT_PATH) { [System.IO.Path]::GetFullPath($FULL_SCRIPT_PATH) } else { "" }
    if ($running -and $running -ieq [System.IO.Path]::GetFullPath($installed)) {
        Copy-Item -LiteralPath $new.FullName -Destination "$running.new" -Force
    } else {
        Copy-Item -LiteralPath $new.FullName -Destination $installed -Force
        if ($running) { Copy-Item -LiteralPath $new.FullName -Destination "$running.new" -Force }
    }
    Log-Event "INFO" "Self-update: staged v$newVer"
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    $script:SELF_NEW_VERSION = $newVer
    return 0
}

function Invoke-SelfUpdateCheck {
    if ("$global:AUTO_SELF_UPDATE" -eq "false" -or $global:AUTO_SELF_UPDATE -eq $false) { return }
    if ($global:ENABLE_LOCAL_MODE) { return }
    if ($env:LTTC_DEV) { return }
    $now = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $since = $now - (To-Num $global:SELF_LAST_CHECK)
    if ($since -lt $SELF_UPDATE_INTERVAL -and $since -ge 0) { return }
    $global:SELF_LAST_CHECK = $now; save_config

    if (!(Get-EsouiDetails $ESOUI_SELF_ID)) { Log-Event "WARN" "Self-update: could not reach ESOUI."; return }
    if (!(Test-VersionNewer $script:ESOUI_VERSION $APP_VERSION)) { return }

    Start-Spinner "Updating the updater to $($script:ESOUI_VERSION)..."
    if ((Install-SelfUpdate) -eq 0) {
        Stop-Spinner 0 "Updated to v$($script:SELF_NEW_VERSION), restarting"
        [Environment]::Exit($SELF_RESTART_CODE)
    } else {
        Stop-Spinner 1 "Update to $($script:ESOUI_VERSION) failed, keeping v$APP_VERSION"
    }
}
