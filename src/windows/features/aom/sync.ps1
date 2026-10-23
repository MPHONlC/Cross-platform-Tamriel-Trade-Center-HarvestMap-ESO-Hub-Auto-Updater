$AOM_REPO = Get-Part "7571da8442f9e55021d9729e7b930306e69085fe2e" 151
$AOM_API = if ($env:LTTC_AOM_API) { $env:LTTC_AOM_API } else { Get-Part "d0d5663bff2f09d08179d31dd314ba8f7d134c78b388" 23 }
$AOM_RAW = if ($env:LTTC_AOM_RAW) { $env:LTTC_AOM_RAW } else { Get-Part "abb079ae04222e5dd98d02a838291d72e676a85d221ab2ad154820b85bbe5a050e" 202 }
$AOM_WORKFLOW_DIR = Get-Part "6fd58258ddb3fdafde35a13f7b02e8df622d" 88
$AOM_ACCEPT = "Accept: " + (Get-Part "e72f300573f075a9472806feb415586bb146e4511f014fc70d78d6" 117)
$AOM_WORKFLOWS = @("$($AOM_WORKFLOW_DIR)data-tables-refresh.yml", "$($AOM_WORKFLOW_DIR)console-data-refresh.yml", "$($AOM_WORKFLOW_DIR)data-release.yml")
$AOM_SLOTS = @(66, 354, 642, 930, 1218)
$AOM_TABLES = @("KnownLibraries.lua", "KnownAddonVersions.lua", "KnownAddonDependencies.lua", "SuggestedCategories.lua", "KnownConsoleAddons.lua", "KnownConsoleLibraries.lua", "KnownConsoleAddonDependencies.lua", "ConsoleSuggestedCategories.lua")
$AOM_SHOW_DETAILS = 8
$AOM_ASK_SECONDS = 60
$global:AOM_ASKED = $false
$AOM_UTF8 = New-Object System.Text.UTF8Encoding($false)

function Get-AomSlots([long]$now) {
    $day = $now - ($now % 86400); $latest = [long]0; $next = [long]0
    foreach ($m in $AOM_SLOTS) {
        $s = $day + $m * 60
        if ($s -le $now) { $latest = $s } elseif ($next -eq 0) { $next = $s }
    }
    if ($latest -eq 0) { $latest = $day - 86400 + $AOM_SLOTS[-1] * 60 }
    if ($next -eq 0) { $next = $day + 86400 + $AOM_SLOTS[0] * 60 }
    return @($latest, $next)
}

function Get-AomWaitText([long]$secs) {
    $m = [long][math]::Floor(($secs + 59) / 60)
    if ($m -ge 60) { return "$([long][math]::Floor($m / 60)) h $($m % 60) min" }
    return "$m min"
}

function Test-AomRow($line) {
    return ($line -notmatch '^\t') -and ($line -match '\t')
}

function Get-AomKey($line) {
    if (Test-AomRow $line) { return ($line -split "`t")[0] }
    if ($line -match '^\t\["([^"]*)"\]') { return $matches[1] }
    if ($line -match '^\t([^ ]+) = \{') { return $matches[1] }
    return ""
}

function Get-AomVersion($line) {
    $parsed = [long]0
    if (Test-AomRow $line) {
        $v = ($line -split "`t")[1]
        if (($v -match '^[0-9]+$') -and [long]::TryParse($v, [ref]$parsed)) { return $parsed }
        return [long]-1
    }
    if (($line -match 'requiredVersion = ([0-9]*)') -and [long]::TryParse("0$($matches[1])", [ref]$parsed)) { return $parsed }
    return [long]-1
}

function Get-AomDisplay($line) {
    if (Test-AomRow $line) {
        $parts = $line -split "`t"
        if ($parts.Count -gt 2) { return $parts[2] }
        return ""
    }
    if ($line -match 'displayVersion = "([^"]*)"') { return $matches[1] }
    return ""
}

function Get-AomShortValue($line) {
    if (Test-AomRow $line) { $v = ($line -replace '^[^\t]*\t', '') -replace "`t", ' | ' }
    else { $v = ($line -replace '^[^=]*= *', '') -replace ',$', '' }
    if ($v.Length -gt 70) { $v = $v.Substring(0, 67) + "..." }
    return $v
}

function ConvertTo-AomLower([string]$text) {
    $chars = $text.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        if ($chars[$i] -ge [char]'A' -and $chars[$i] -le [char]'Z') { $chars[$i] = [char]([int]$chars[$i] + 32) }
    }
    return -join $chars
}

function Read-AomLines($path) {
    $text = [System.IO.File]::ReadAllText($path, $AOM_UTF8)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    $text = $text -replace "`r`n", "`n"
    if ($text.EndsWith("`n")) { $text = $text.Substring(0, $text.Length - 1) }
    return ,($text -split "`n")
}

function Merge-AomTable($localLines, $remoteLines) {
    $order = New-Object System.Collections.Generic.List[string]
    $lineByKey = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    $verByKey = New-Object 'System.Collections.Generic.Dictionary[string,long]' ([StringComparer]::Ordinal)
    $header = New-Object System.Collections.Generic.List[string]
    $addedDetails = New-Object System.Collections.Generic.List[string]
    $updatedDetails = New-Object System.Collections.Generic.List[string]
    $inTable = $false; $footer = "}"; $added = 0; $updated = 0

    foreach ($line in $localLines) {
        $key = Get-AomKey $line
        if ($key -ne "") {
            if (!$lineByKey.ContainsKey($key)) { $order.Add($key) }
            $lineByKey[$key] = $line
            $verByKey[$key] = Get-AomVersion $line
        } elseif (!$inTable) {
            $header.Add($line)
        }
        if ($line -match ' = \{$') { $inTable = $true; $footer = "}" }
        if ($line -match '\(\[==\[$') { $inTable = $true; $footer = "]==])" }
    }

    foreach ($line in $remoteLines) {
        $key = Get-AomKey $line
        if ($key -eq "") { continue }
        $rver = Get-AomVersion $line
        $rdisp = Get-AomDisplay $line
        if (!$lineByKey.ContainsKey($key)) {
            $order.Add($key)
            $lineByKey[$key] = $line
            $verByKey[$key] = $rver
            $added++
            if ($rver -ge 0) { $addedDetails.Add("+ ${key}: new entry, version $rver ($rdisp)") }
            else { $addedDetails.Add("+ ${key}: new entry, $(Get-AomShortValue $line)") }
            continue
        }
        if ($lineByKey[$key] -ceq $line) { continue }
        $lver = $verByKey[$key]
        if ($lver -ge 0 -and $rver -lt 0) { continue }
        if ($lver -ge 0 -and $rver -lt $lver) { continue }
        $oldLine = $lineByKey[$key]
        $lineByKey[$key] = $line
        $verByKey[$key] = $rver
        $updated++
        if ($rver -gt $lver -and $lver -ge 0) { $updatedDetails.Add("~ ${key}: $lver ($(Get-AomDisplay $oldLine)) -> $rver ($rdisp)") }
        else { $updatedDetails.Add("~ ${key}: $(Get-AomShortValue $oldLine) -> $(Get-AomShortValue $line)") }
    }

    $keys = $order.ToArray()
    $sortKeys = [string[]]@(foreach ($k in $keys) { (ConvertTo-AomLower $k) + [char]1 + $k })
    [Array]::Sort($sortKeys, $keys, [StringComparer]::Ordinal)
    $sb = New-Object System.Text.StringBuilder
    foreach ($h in $header) { [void]$sb.Append($h).Append("`n") }
    foreach ($k in $keys) { [void]$sb.Append($lineByKey[$k]).Append("`n") }
    [void]$sb.Append($footer).Append("`n")
    $details = New-Object System.Collections.Generic.List[string]
    $details.AddRange($addedDetails); $details.AddRange($updatedDetails)
    return @{ Text = $sb.ToString(); Added = $added; Updated = $updated; Details = $details }
}

function Get-AomRepoState {
    $runs = & curl.exe -s -f -m 20 -H $AOM_ACCEPT "$AOM_API/repos/$AOM_REPO/actions/runs?per_page=30" 2>$null
    if ($LASTEXITCODE -ne 0) { return "unknown" }
    $pending = ""
    foreach ($m in [regex]::Matches(($runs -join "`n"), '"(path|status)": *"([^"]*)"')) {
        if ($m.Groups[1].Value -eq "path") { $pending = $m.Groups[2].Value; continue }
        if ($pending -and $m.Groups[2].Value -ne "completed" -and $AOM_WORKFLOWS -ccontains $pending) { return "updating" }
        $pending = ""
    }
    return "idle"
}

function Test-AomInstalled {
    if (!$global:ADDON_DIR) { return $false }
    return (Test-Path -LiteralPath (Join-Path (Join-Path $global:ADDON_DIR "APH-OnManager") "DATA") -PathType Container)
}

function Show-AomQuestion {
    Write-Host "$ESC[0;32mAPH-OnManager is in your AddOns folder. Keep its add-on data up to date?$ESC[0m"
    Write-Host "$ESC[0;90m(Its lists of add-on versions, libraries, dependencies and categories, checked an hour after each data refresh)$ESC[0m"
    Write-Host "1) Yes $ESC[0;32m(Default)$ESC[0m"
    Write-Host "2) No"
}

function Set-AomAnswer($ans) {
    $global:AOM_DATA_UPDATES = if ("$ans".Trim() -eq "2") { "false" } else { "true" }
    Log-Event "INFO" "APH-OnManager data updates set to $($global:AOM_DATA_UPDATES)."
}

function Test-AomCanAsk {
    return (!$global:SILENT -and !$global:IS_TASK -and ![Console]::IsInputRedirected)
}

function Read-AomAnswer {
    $typed = ""
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $AOM_ASK_SECONDS) {
        [System.Windows.Forms.Application]::DoEvents()
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Enter) { Write-Host ""; return $typed }
            if ($key.Key -eq [ConsoleKey]::Backspace) {
                if ($typed.Length -gt 0) { $typed = $typed.Substring(0, $typed.Length - 1); Write-Host -NoNewline "`b `b" }
                continue
            }
            if ($key.KeyChar -ne [char]0) { $typed += $key.KeyChar; Write-Host -NoNewline $key.KeyChar }
        }
        Start-Sleep -Milliseconds 50
    }
    return $null
}

function Invoke-AomAskNow {
    if ($global:AOM_ASKED) {
        UIEcho " $ESC[90mAPH-OnManager's data is left as it is until you answer. The updater asks again the next time it starts.$ESC[0m`n"
        return $false
    }
    $global:AOM_ASKED = $true
    if (!(Test-AomCanAsk)) {
        UIEcho " $ESC[90mAPH-OnManager was found. Start the updater in a terminal to choose whether to keep its data up to date.$ESC[0m`n"
        Log-Event "INFO" "APH-OnManager found; its data updates wait for an answer in a visible terminal."
        return $false
    }
    Show-AomQuestion
    Write-Host -NoNewline "$ESC[0;34mChoice [1-2]: $ESC[0m"
    $ans = Read-AomAnswer
    if ($null -eq $ans) {
        Write-Host ""
        UIEcho " $ESC[90mNo answer, so APH-OnManager's data is left as it is. The updater asks again the next time it starts.$ESC[0m`n"
        return $false
    }
    Set-AomAnswer $ans
    $global:CONFIG_CHANGED = $true
    if ($global:AOM_DATA_UPDATES -eq "true") { return $true }
    UIEcho " $ESC[90mAPH-OnManager's data won't be updated. Run the updater with --setup to change this.$ESC[0m`n"
    return $false
}

function Invoke-AomDataSync {
    $dir = Join-Path $ADDON_DIR "APH-OnManager"
    if (!(Test-Path -LiteralPath (Join-Path $dir "DATA") -PathType Container)) { return }
    if ($global:AOM_DATA_UPDATES -eq "false") { return }
    UIEcho "$ESC[1m$ESC[97m [+] Updating APH-OnManager's Add-On Data $ESC[0m"
    if (Test-LinkedFolder $dir) {
        UIEcho " $ESC[90mAPH-OnManager is a linked folder, so its data is left as it is.$ESC[0m`n"
        return
    }
    if ($global:AOM_DATA_UPDATES -ne "true") {
        if (!(Invoke-AomAskNow)) { return }
    }

    $now = [long]$CURRENT_TIME
    $slots = Get-AomSlots $now; $latest = $slots[0]; $next = $slots[1]
    $last = [long](To-Num $global:AOM_LAST_SYNC)
    if ($last -ge $latest -and $last -le $now) {
        UIEcho " $ESC[90mChecked $(Get-AomWaitText ($now - $last)) ago. Next check in $(Get-AomWaitText ($next - $now)), an hour after the next data refresh.$ESC[0m`n"
        return
    }

    if ((Get-AomRepoState) -eq "updating") {
        UIEcho " $ESC[33mAPH-OnManager's data is being refreshed right now. $ESC[35mTrying again next cycle.$ESC[0m`n"
        $global:notifAom = "Waiting For Refresh"
        Log-Event "INFO" "APH-OnManager data sync postponed: a data refresh is still running."
        return
    }

    $base = "$AOM_RAW/$AOM_REPO/main/DATA"; $work = Join-Path $TEMP_DIR_ROOT "AoM_Data"; $sha = ""
    $commit = & curl.exe -s -f -m 20 -H $AOM_ACCEPT "$AOM_API/repos/$AOM_REPO/commits/main" 2>$null
    if ($LASTEXITCODE -eq 0 -and (($commit -join "`n") -match '"sha": *"([0-9a-f]{40})"')) { $sha = $matches[1]; $base = "$AOM_RAW/$AOM_REPO/$sha/DATA" }

    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Start-Spinner "Downloading APH-OnManager's data tables..."
    foreach ($f in $AOM_TABLES) {
        & curl.exe -s -f -L -m 60 -o (Join-Path $work $f) "$base/$f" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Stop-Spinner 1 "Could not download $f"
            UIEcho " $ESC[90mNothing was changed. $ESC[35mTrying again next cycle.$ESC[0m`n"
            $global:notifAom = "Download Failed"
            Log-Event "WARN" "APH-OnManager data sync failed: $f could not be downloaded."
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
            return
        }
    }
    Stop-Spinner 0 "Downloaded the data tables$(if ($sha) { " (commit $($sha.Substring(0, 7)))" })"

    $changed = 0
    foreach ($f in $AOM_TABLES) {
        $localPath = Join-Path (Join-Path $dir "DATA") $f
        if (!(Test-Path -LiteralPath $localPath -PathType Leaf)) { continue }
        try {
            $result = Merge-AomTable (Read-AomLines $localPath) (Read-AomLines (Join-Path $work $f))
        } catch {
            UIEcho " $ESC[31m[-] Could not merge $f; it was left as it is.$ESC[0m"
            continue
        }
        if ($result.Added -eq 0 -and $result.Updated -eq 0) { continue }
        [System.IO.File]::WriteAllBytes($localPath, $AOM_UTF8.GetBytes($result.Text))
        $changed++
        UIEcho " $ESC[92m$f$ESC[0m $ESC[90m$($result.Updated) changed, $($result.Added) new$ESC[0m"
        Log-Event "INFO" "APH-OnManager data: $f updated ($($result.Updated) changed, $($result.Added) new)."
        $shown = 0
        foreach ($detail in $result.Details) {
            Log-Event "INFO" "APH-OnManager data: $detail"
            $shown++
            if ($shown -le $AOM_SHOW_DETAILS) { UIEcho " `t$ESC[90m$detail$ESC[0m" }
        }
        $more = $shown - $AOM_SHOW_DETAILS
        if ($more -gt 0) { UIEcho " `t$ESC[90m... and $more more (see the log)$ESC[0m" }
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

    $global:AOM_LAST_SYNC = $now; $global:CONFIG_CHANGED = $true
    if ($changed -gt 0) {
        $global:notifAom = "Updated ($changed)"
        UIEcho " $ESC[90mAPH-OnManager uses the new data after a /reloadui or your next login.$ESC[0m`n"
    } else {
        $global:notifAom = "Up-to-date"
        UIEcho " $ESC[90mNo changes detected. $ESC[92mAPH-OnManager's data is up-to-date.$ESC[0m`n"
    }
}
