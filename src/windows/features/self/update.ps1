$SELF_UPDATE_INTERVAL = 21600
$SELF_RESTART_CODE = 3
$GH_SELF_API = if ($env:LTTC_SELF_GH_API) { $env:LTTC_SELF_GH_API } else { "https://api.github.com" }
$GH_SELF_REPO = "MPHONlC/Cross-platform-Tamriel-Trade-Center-HarvestMap-ESO-Hub-Auto-Updater"
$GH_SELF_ASSET = "Tamriel_Trade_Center_Auto-Updater.zip"

function Get-GithubSelfDetails {
    $script:GH_SELF_VERSION = ""; $script:GH_SELF_URL = ""
    try {
        $resp = & curl.exe -fsS -m 20 -H "Accept: application/vnd.github+json" "$GH_SELF_API/repos/$GH_SELF_REPO/releases/latest" 2>$null
        if (!$resp) { return $false }
        $data = ($resp -join "`n") | ConvertFrom-Json
        $script:GH_SELF_VERSION = "$($data.tag_name)" -replace '^Version-', ''
        $asset = @($data.assets | Where-Object { $_.name -eq $GH_SELF_ASSET }) | Select-Object -First 1
        if ($asset) { $script:GH_SELF_URL = "$($asset.browser_download_url)" }
        return ([bool]$script:GH_SELF_VERSION -and [bool]$script:GH_SELF_URL)
    } catch { return $false }
}

function Install-SelfUpdate($src, $ghUrl) {
    if (!$src) { $src = "esoui" }
    $zip = Join-Path $TEMP_DIR_ROOT "self_update.zip"; $work = Join-Path $TEMP_DIR_ROOT "self_update"
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    $script:SELF_NEW_VERSION = ""
    if ($src -eq "github") {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        & curl.exe -fsSL -m 120 -o $zip $ghUrl 2>$null
        if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $zip)) { return 1 }
    } else {
        $rc = Invoke-EsouiDownload $ESOUI_SELF_ID $zip
        if ($rc -ne 0) { return $rc }
    }
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

    $script:ESOUI_VERSION = ""
    if (!(Get-EsouiDetails $ESOUI_SELF_ID)) { Log-Event "WARN" "Self-update: could not reach ESOUI." }
    if (!(Get-GithubSelfDetails)) { Log-Event "WARN" "Self-update: could not reach GitHub." }

    $bestVer = $APP_VERSION; $bestSrc = ""; $bestUrl = ""
    if ($script:ESOUI_VERSION -and (Test-VersionNewer $script:ESOUI_VERSION $bestVer)) { $bestVer = $script:ESOUI_VERSION; $bestSrc = "esoui"; $bestUrl = "" }
    if ($script:GH_SELF_VERSION -and (Test-VersionNewer $script:GH_SELF_VERSION $bestVer)) { $bestVer = $script:GH_SELF_VERSION; $bestSrc = "github"; $bestUrl = $script:GH_SELF_URL }
    if (!$bestSrc) { return }

    Start-Spinner "Updating the updater to $bestVer (from $bestSrc)..."
    if ((Install-SelfUpdate $bestSrc $bestUrl) -eq 0) {
        Stop-Spinner 0 "Updated to v$($script:SELF_NEW_VERSION), restarting"
        [Environment]::Exit($SELF_RESTART_CODE)
    } else {
        Stop-Spinner 1 "Update to $bestVer failed, keeping v$APP_VERSION"
    }
}
