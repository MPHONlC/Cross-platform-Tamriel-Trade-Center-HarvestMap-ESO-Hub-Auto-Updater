$ADDON_UPDATE_EXCLUDE = @("HarvestMapData", "EsoTradingHub", "EsoHubScanner", "LibEsoHubPrices")
$ADDON_UPDATE_INTERVAL = 21600

function Get-AddonExcludes {
    $list = New-Object System.Collections.Generic.List[string]
    $list.AddRange([string[]]$ADDON_UPDATE_EXCLUDE)
    foreach ($s in ("$global:ADDON_UPDATE_SKIP" -split '\s+')) { if ($s) { $list.Add($s) } }
    return ,$list.ToArray()
}

function Test-LinkedFolder($path) {
    try { return [bool]((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) } catch { return $false }
}

function Get-ManifestField([string[]]$lines, [string]$field) {
    foreach ($l in $lines) {
        if ($l -match ('^##\s*' + $field + ':')) { return $l }
    }
    return $null
}

function Get-AddonLocalList($dir) {
    $out = New-Object System.Collections.Generic.List[string]
    $latin = [System.Text.Encoding]::GetEncoding(28591)
    foreach ($top in @(Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue | Where-Object { !$_.Name.StartsWith(".") } | Sort-Object Name)) {
        if (Test-LinkedFolder $top.FullName) { continue }
        $dirs = @($top) + @(Get-ChildItem -LiteralPath $top.FullName -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { !(Test-LinkedFolder $_.FullName) })
        foreach ($d in $dirs) {
            $mf = Join-Path $d.FullName "$($d.Name).addon"
            if (!(Test-Path -LiteralPath $mf)) { $mf = Join-Path $d.FullName "$($d.Name).txt" }
            if (!(Test-Path -LiteralPath $mf)) { continue }
            $lines = [System.IO.File]::ReadAllText($mf, $latin) -split "`n"
            $av = ""; $ver = ""
            $l = Get-ManifestField $lines "AddOnVersion"
            if ($null -ne $l) {
                $v = $l.Replace("`r", ""); $v = $v.Substring($v.IndexOf(':') + 1).TrimStart(" `t")
                $av = ($v.Replace("|", "").Trim(" `t") -split '\s+')[0]
            }
            $l = Get-ManifestField $lines "Version"
            if ($null -ne $l) {
                $v = $l.Replace("`r", "").Replace("|", ""); $ver = $v.Substring($v.IndexOf(':') + 1).Trim(" `t")
            }
            $rel = $d.FullName.Substring($dir.TrimEnd('\', '/').Length + 1).Replace('\', '/')
            $out.Add("$rel|$av|$ver")
        }
    }
    return ,$out.ToArray()
}

function Get-JStr([string]$s, [string]$key) {
    $p = $s.IndexOf('"' + $key + '":"', [StringComparison]::Ordinal)
    if ($p -lt 0) { return "" }
    $i = $p + $key.Length + 4
    $sb = New-Object System.Text.StringBuilder
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -eq '\') {
            $c2 = if ($i + 1 -lt $s.Length) { $s[$i + 1] } else { "" }
            if ("$c2" -ceq "u") {
                $hex = if ($i + 6 -le $s.Length) { $s.Substring($i + 2, 4) } else { $s.Substring([math]::Min($i + 2, $s.Length)) }
                if ((To-LowerAscii $hex) -ne "feff") { [void]$sb.Append("?") }
                $i += 6; continue
            }
            [void]$sb.Append($c2); $i += 2; continue
        }
        if ($c -eq '"') { break }
        [void]$sb.Append($c); $i++
    }
    return $sb.ToString()
}

function Test-Dotted([string]$v) { return $v -cmatch '^[vV]?[0-9]+(\.[0-9]+)*$' }
function Get-VersionParts([string]$v) { return ($v -replace '^[vV]', '').Split('.').Length }

function Get-AddonUpdatePlan([string[]]$localLines, [string]$catalogText, [string]$recordsFile = "") {
    $recId = New-Object System.Collections.Hashtable; $recLu = New-Object System.Collections.Hashtable
    if ($recordsFile -and (Test-Path -LiteralPath $recordsFile)) {
        foreach ($l in [System.IO.File]::ReadAllLines($recordsFile)) { $r = $l.Split('|'); if ($r.Length -ge 3) { $recId[$r[0]] = $r[1]; $recLu[$r[0]] = $r[2] } }
    }
    $localAv = New-Object System.Collections.Hashtable; $localVer = New-Object System.Collections.Hashtable
    foreach ($l in $localLines) { $p = $l.Split('|'); $localAv[$p[0]] = $p[1]; $localVer[$p[0]] = if ($p.Length -gt 2) { $p[2] } else { "" } }
    $skipped = New-Object System.Collections.Hashtable
    foreach ($s in (Get-AddonExcludes)) { $skipped[$s] = $true }

    $bestId = New-Object System.Collections.Hashtable; $bestScore = @{}; $bestMine = @{}; $bestVer = @{}; $bestTav = @{}; $bestLu = @{}
    $pathsOf = New-Object System.Collections.Hashtable
    $order = New-Object System.Collections.Generic.List[string]

    $listings = ($catalogText -replace '\},\{"id":', "}`n{`"id`":") -split "`n"
    foreach ($s in $listings) {
        if ($s -cnotmatch '"id":([0-9]+)') { continue }
        $id = $matches[1]
        if ($s -cmatch '"categoryId":157[,}]') { continue }
        $title = To-LowerAscii (Get-JStr $s "title")
        $lver = Get-JStr $s "version"
        $lu = if ($s -cmatch '"lastUpdate":([0-9]+)') { $matches[1] } else { "" }
        $a = $s.IndexOf('"addons":[', [StringComparison]::Ordinal)
        if ($a -lt 0) { continue }
        $rest = $s.Substring($a); $npaths = 0
        $tops = New-Object System.Collections.Generic.List[object]
        $all = New-Object System.Collections.Generic.List[object]
        while (($p = $rest.IndexOf('"path":"', [StringComparison]::Ordinal)) -ge 0) {
            $rest = $rest.Substring($p)
            $path = Get-JStr $rest "path"
            $nxt = if ($rest.Length -gt 8) { $rest.IndexOf('"path":"', 8, [StringComparison]::Ordinal) } else { -1 }
            $obj = if ($nxt -ge 0) { $rest.Substring(0, $nxt) } else { $rest }
            $av = Get-JStr $obj "addOnVersion"
            $npaths++
            $all.Add(@($path, $av))
            if ($path.IndexOf('/') -lt 0) { $tops.Add(@($path, $av)) }
            $rest = if ($rest.Length -gt 8) { $rest.Substring(8) } else { "" }
        }
        $pathsOf[$id] = $all
        foreach ($t in $tops) {
            $f = $t[0]
            if (!$localAv.ContainsKey($f) -or $skipped.ContainsKey($f)) { continue }
            $score = $(if ($npaths -eq 1) { 2 } else { 0 }) + $(if ($title -ceq (To-LowerAscii $f)) { 1 } else { 0 })
            $mine = if (($t[1] -ne "" -and $t[1] -ceq "$($localAv[$f])") -or ($lver -ne "" -and ($lver -replace '^[vV]', '') -ceq ("$($localVer[$f])" -replace '^[vV]', ''))) { 1 } else { 0 }
            if (!$bestId.ContainsKey($f) -or $score -gt $bestScore[$f] -or ($score -eq $bestScore[$f] -and ($mine -gt $bestMine[$f] -or ($mine -eq $bestMine[$f] -and (To-Num $lu) -gt (To-Num $bestLu[$f]))))) {
                if (!$bestId.ContainsKey($f)) { $order.Add($f) }
                $bestId[$f] = $id; $bestScore[$f] = $score; $bestMine[$f] = $mine; $bestVer[$f] = $lver; $bestTav[$f] = $t[1]; $bestLu[$f] = $lu
            }
        }
    }

    $keys = New-Object System.Collections.Generic.List[string]; $rows = New-Object System.Collections.Generic.List[string]
    foreach ($f in $order) {
        $id = $bestId[$f]; $state = ""; $lshow = $localAv[$f]; $rshow = $bestTav[$f]
        foreach ($pa in $pathsOf[$id]) {
            $path = $pa[0]; $ra = $pa[1]
            if ($path -cne $f -and !$path.StartsWith("$f/", [StringComparison]::Ordinal)) { continue }
            if (!$localAv.ContainsKey($path)) { continue }
            $la = $localAv[$path]
            if ($la -cmatch '^[0-9]+$' -and $ra -cmatch '^[0-9]+$') {
                if ([double]$ra -gt [double]$la) { $state = "UPDATE"; $lshow = $la; $rshow = $ra; break }
                if ($state -eq "") { $state = "CURRENT"; if ($path -ceq $f) { $lshow = $la; $rshow = $ra } }
            } elseif ((Test-Dotted $la) -and (Test-Dotted $ra) -and (Get-VersionParts $la) -eq (Get-VersionParts $ra)) {
                if (Test-VersionNewer $ra $la) { $state = "UPDATE"; $lshow = $la; $rshow = $ra; break }
                if ($state -eq "") { $state = "CURRENT"; if ($path -ceq $f) { $lshow = $la; $rshow = $ra } }
            }
        }
        $lv = "$($localVer[$f])"; $rv = "$($bestVer[$f])"
        if ($state -eq "" -and $recId.ContainsKey($f) -and $recId[$f] -ceq $id -and "$($bestLu[$f])" -ne "") {
            $state = if ([double]$bestLu[$f] -gt (To-Num $recLu[$f])) { "UPDATE" } else { "CURRENT" }; $lshow = $lv; $rshow = $rv
        }
        if ($state -eq "" -and $rv -ne "" -and (($lv -replace '^[vV]', '') -ceq ($rv -replace '^[vV]', '') -or ("$($localAv[$f])" -replace '^[vV]', '') -ceq ($rv -replace '^[vV]', ''))) { $state = "CURRENT"; $lshow = $rv; $rshow = $rv }
        if ($state -eq "") {
            if ((Test-Dotted $lv) -and (Test-Dotted $rv) -and (Get-VersionParts $lv) -eq (Get-VersionParts $rv)) {
                $state = if (Test-VersionNewer $rv $lv) { "UPDATE" } else { "CURRENT" }; $lshow = $lv; $rshow = $rv
            } else {
                $state = "UNKNOWN"
                $lshow = if ("$($localAv[$f])" -ne "") { $localAv[$f] } else { $lv }
                $rshow = if ("$($bestTav[$f])" -ne "") { $bestTav[$f] } else { $rv }
            }
        }
        $keys.Add($f); $rows.Add("$state|$id|$f|$lshow|$rshow|$($bestLu[$f])")
    }
    return Sort-ByKey $keys $rows
}

function Install-AddonZip($zip) {
    $work = Join-Path $TEMP_DIR_ROOT "addon_update"
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    try { Expand-Archive -LiteralPath $zip -DestinationPath $work -Force } catch { return $false }
    $backup = Join-Path (Join-Path $TARGET_DIR "Backups") "AddOns"
    if (!(Test-Path $backup)) { New-Item -ItemType Directory -Force -Path $backup | Out-Null }
    $excludes = Get-AddonExcludes
    $installed = New-Object System.Collections.Generic.List[string]
    foreach ($d in @(Get-ChildItem -LiteralPath $work -Directory)) {
        $name = $d.Name
        if ($excludes -ccontains $name) { continue }
        $target = Join-Path $ADDON_DIR $name
        if (Test-LinkedFolder $target) { continue }
        Remove-Item -LiteralPath (Join-Path $backup $name) -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $target) {
            Move-Item -LiteralPath $target -Destination (Join-Path $backup $name) -Force
            (Get-Item -LiteralPath (Join-Path $backup $name)).LastWriteTime = Get-Date
        }
        try {
            Move-Item -LiteralPath $d.FullName -Destination $target -Force -ErrorAction Stop
            $installed.Add($name)
            Log-Event "INFO" "Add-on updated: $name"
        } catch {
            if (Test-Path -LiteralPath (Join-Path $backup $name)) { Move-Item -LiteralPath (Join-Path $backup $name) -Destination $target -Force }
        }
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    $script:ADDON_INSTALLED = $installed.ToArray()
    return ($installed.Count -gt 0)
}

$ADDON_RECORDS = Join-Path $DB_DIR "LTTC_AddonUpdates.db"

function Save-AddonInstallRecord($id, $lu) {
    if (!$lu) { return }
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $ADDON_RECORDS) { foreach ($l in [System.IO.File]::ReadAllLines($ADDON_RECORDS)) { if ($script:ADDON_INSTALLED -cnotcontains $l.Split('|')[0]) { $lines.Add($l) } } }
    foreach ($name in $script:ADDON_INSTALLED) { $lines.Add("$name|$id|$lu") }
    [System.IO.File]::WriteAllText($ADDON_RECORDS, ($lines -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
}

$ADDON_BACKUP_DAYS = 30

function Remove-OldAddonBackups {
    $dir = Join-Path (Join-Path $TARGET_DIR "Backups") "AddOns"
    if (!(Test-Path -LiteralPath $dir)) { return }
    $limit = (Get-Date).AddDays(-$ADDON_BACKUP_DAYS)
    foreach ($old in @(Get-ChildItem -LiteralPath $dir -Directory | Where-Object { $_.LastWriteTime -lt $limit })) {
        Remove-Item -LiteralPath $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Log-Event "INFO" "Add-on backup older than $ADDON_BACKUP_DAYS days removed: $($old.Name)"
    }
}

function Invoke-AddonUpdates {
    Remove-OldAddonBackups
    if ("$global:ENABLE_ADDON_UPDATES" -ne "true" -and $global:ENABLE_ADDON_UPDATES -ne $true) { return }
    if (!(Test-Path -LiteralPath $ADDON_DIR)) { return }
    UIEcho "$ESC[1m$ESC[97m [+] Updating Your Add-Ons & Libraries $ESC[0m"
    $now = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $since = $now - (To-Num $global:ADDON_LAST_CHECK)
    if ($since -lt $ADDON_UPDATE_INTERVAL -and $since -ge 0) {
        UIEcho " $ESC[90mChecked $([math]::Floor($since / 60)) minutes ago. Next check in $([math]::Floor(($ADDON_UPDATE_INTERVAL - $since) / 60)) minutes.$ESC[0m`n"
        return
    }

    $catalog = Join-Path $TEMP_DIR_ROOT "esoui_filelist.json"
    Start-Spinner "Reading the ESOUI add-on list..."
    & curl.exe -s -f -m 120 -A $ESOUI_UA -o $catalog "$ESOUI_API/v4/game/ESO/filelist.json" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Stop-Spinner 1 "Could not reach ESOUI"
        $global:notifAddons = "Check Failed"
        Remove-Item -LiteralPath $catalog -Force -ErrorAction SilentlyContinue; UIEcho ""; return
    }
    $plan = Get-AddonUpdatePlan (Get-AddonLocalList $ADDON_DIR) ([System.IO.File]::ReadAllText($catalog)) $ADDON_RECORDS
    Remove-Item -LiteralPath $catalog -Force -ErrorAction SilentlyContinue
    Stop-Spinner 0 "Compared $($plan.Count) add-ons with ESOUI"
    $global:ADDON_LAST_CHECK = $now; $global:CONFIG_CHANGED = $true

    $updates = @($plan | Where-Object { $_.StartsWith("UPDATE|") })
    if ($updates.Count -eq 0) {
        UIEcho " $ESC[90mNo changes detected. $ESC[92mAll add-ons are up-to-date.$ESC[0m`n"
        $global:notifAddons = "Up-to-date"
        return
    }
    foreach ($u in $updates) { $p = $u.Split('|'); UIEcho " $ESC[33m$($p[2])$ESC[0m $ESC[90m$($p[3])$ESC[0m -> $ESC[92m$($p[4])$ESC[0m" }
    foreach ($u in @($plan | Where-Object { $_.StartsWith("UNKNOWN|") })) { $p = $u.Split('|'); Log-Event "INFO" "Add-on update skipped for $($p[2]): its version ($($p[3])) can't be compared with ESOUI's ($($p[4]))." }

    $count = 0; $failed = 0; $seen = @{}
    foreach ($u in $updates) {
        $p = $u.Split('|'); $id = $p[1]
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        Start-Spinner "Downloading $($p[2]) from ESOUI..."
        $TEMP_DIR_USED = $true
        $zip = Join-Path $TEMP_DIR_ROOT "addon_$id.zip"
        if ((Invoke-EsouiDownload $id $zip) -eq 0 -and (Install-AddonZip $zip)) {
            Stop-Spinner 0 "Installed: $($script:ADDON_INSTALLED -join ' ')"
            $count++
            Save-AddonInstallRecord $id $p[5]
            if ($script:ADDON_INSTALLED -ccontains "TamrielTradeCentre") { $global:TTC_NA_VERSION = 0; $global:TTC_EU_VERSION = 0 }
        } else {
            Stop-Spinner 1 "Update failed for $($p[2])"
            Log-Event "WARN" "Add-on update failed for $($p[2]): ESOUI file $($p[1]) could not be downloaded or installed."
            $failed++
        }
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    }
    $global:notifAddons = "Updated ($count)"
    if ($failed -gt 0) { $global:notifAddons += ", Failed ($failed)" }
    UIEcho ""
}
