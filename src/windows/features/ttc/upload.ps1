$TTC_WEB_CLIENT_VERSION = "3.1.0.0"
$TTC_BATCH_SIZE = 100

function Get-TTCClientId {
    if ([string]::IsNullOrEmpty($global:TTC_CLIENT_ID)) {
        $global:TTC_CLIENT_ID = [guid]::NewGuid().ToString()
        $global:CONFIG_CHANGED = $true
    }
    return $global:TTC_CLIENT_ID
}

function ConvertFrom-TTCKey([string]$s) {
    $s = $s.Trim().TrimStart('[').TrimEnd(']')
    if ($s.Length -ge 2 -and $s.StartsWith('"') -and $s.EndsWith('"')) { $s = $s.Substring(1, $s.Length - 2) }
    return $s
}

function Add-TTCJson([string]$json, [string]$name, $value) {
    if ([string]::IsNullOrEmpty($value) -or $value -eq "nil") { return $json }
    $sep = if ($json -eq "") { "" } else { "," }
    return "$json$sep`"$name`":$value"
}

function Get-TTCList($table) {
    $nums = @($table.Keys | Where-Object { $_ -like '#*' } | ForEach-Object { [double]$table[$_] } | Sort-Object)
    return "[" + (($nums | ForEach-Object { $_.ToString([Globalization.CultureInfo]::InvariantCulture) }) -join ",") + "]"
}

function Get-TTCItemJson($t) {
    $j = ""
    foreach ($pair in @(@("ID", "ID"), @("UID", "UID"), @("QualityID", "QualityID"), @("Category2IDOverWrite", "Category2IDOverWrite"),
                        @("TraitID", "TraitID"), @("LevelTotal", "Level"), @("PotionEffectIDs", "PotionEffects"))) {
        $j = Add-TTCJson $j $pair[0] $t[$pair[1]]
    }
    $mw = if ($t.ContainsKey("MasterWritInfo")) { $t["MasterWritInfo"] } else { "null" }
    return "{" + (Add-TTCJson $j "MasterWritInfo" $mw) + "}"
}

function Read-TTCUpload([string]$path, [string]$region, [long]$now, [string]$cache) {
    $sent = @{}
    if ($cache -and (Test-Path -LiteralPath $cache)) {
        foreach ($l in [IO.File]::ReadLines($cache)) { $p = $l.Split("`t"); if ($p.Count -ge 2) { $sent["$($p[0])|$($p[1])"] = $true } }
    }
    $stack = New-Object System.Collections.Generic.List[string]
    $tables = New-Object System.Collections.Generic.List[hashtable]
    $pending = ""
    $self = New-Object System.Collections.Generic.List[object]
    $auto = New-Object System.Collections.Generic.List[object]
    $guildInfo = @{}; $autoGuild = @{}; $settings = @{}; $accounts = @{}
    $dataKey = "${region}Data"

    foreach ($raw in [IO.File]::ReadLines($path)) {
        $t = $raw.Trim()
        if ($t -eq "{") { $stack.Add($pending); $tables.Add(@{}); $pending = ""; continue }
        if ($t -eq "}" -or $t -eq "},") {
            $d = $stack.Count
            $key = $stack[$d - 1]; $tbl = $tables[$d - 1]
            $s = { param($i) if ($stack.Count -gt $i) { $stack[$i] } else { "" } }
            if ($d -ge 2 -and ($key -eq "PotionEffects" -or $key -eq "RequiredPotionEffectIDs")) {
                $tables[$d - 2][$key] = Get-TTCList $tbl
            } elseif ($key -eq "MasterWritInfo") {
                $j = ""
                foreach ($k in @("RequiredItemID", "RequiredQualityID", "RequiredTraitID", "RequiredSetID", "RequiredStyleID", "RequiredPotionEffectIDs", "NumVoucher")) {
                    $j = Add-TTCJson $j $k $tbl[$k]
                }
                $tables[$d - 2]["MasterWritInfo"] = "{$j}"
            } elseif ($d -eq 9 -and (& $s 4) -eq $dataKey -and (& $s 5) -eq "Guilds" -and (& $s 7) -eq "Entries") {
                $self.Add(@{ Acct = $stack[2]; Guild = $stack[6]; Table = $tbl })
            } elseif ($d -eq 7 -and (& $s 4) -eq $dataKey -and (& $s 5) -eq "Guilds") {
                $guildInfo["$($stack[2])`t$($stack[6])"] = $tbl
            } elseif ($d -eq 11 -and (& $s 4) -eq $dataKey -and (& $s 5) -eq "AutoRecordEntries" -and (& $s 8) -eq "PlayerListings") {
                $auto.Add(@{ Acct = $stack[2]; Guild = $stack[7]; Player = $stack[9]; Table = $tbl })
            } elseif ($d -eq 8 -and (& $s 4) -eq $dataKey -and (& $s 5) -eq "AutoRecordEntries" -and (& $s 6) -eq "Guilds") {
                $autoGuild["$($stack[2])`t$($stack[7])"] = $tbl
            } elseif ($d -eq 5 -and $key -eq "Settings") {
                $settings[$stack[2]] = $tbl
            } elseif ($d -eq 4 -and $key -eq '$AccountWide') {
                $accounts[$stack[2]] = $tbl
            }
            $stack.RemoveAt($d - 1); $tables.RemoveAt($d - 1)
            continue
        }
        $eq = $t.IndexOf("=")
        if ($eq -lt 0) { continue }
        $k = ConvertFrom-TTCKey $t.Substring(0, $eq)
        $v = $t.Substring($eq + 1).Trim().TrimEnd(',').Trim()
        if ($v -eq "") { $pending = $k; continue }
        if ($k -match '^\d+$') { $k = "#$k" }
        if ($tables.Count -gt 0) { $tables[$tables.Count - 1][$k] = $v }
    }

    $best = @{}; $noId = New-Object System.Collections.Generic.List[string]; $kiosks = @{}; $culture = ""; $seen = @{ Newest = [long]0 }
    $keep = {
        param($guild, $player, $tbl, $discover, $expire, $kiosk)
        if ([string]::IsNullOrEmpty($discover) -or [string]::IsNullOrEmpty($expire)) { return }
        $dv = [long][double]$discover; $ev = [long][double]$expire
        if ($dv -le $now -and $dv -gt $seen.Newest) { $seen.Newest = $dv }
        $uid = "$($tbl['UID'])".Trim('"')
        if ($uid -eq "" -or $uid -eq "0") { return }
        if ($sent.ContainsKey("$uid|$dv") -or $now -gt $ev -or $dv -gt $now -or $now - $dv -gt 21600) { return }
        if (-not $tbl.ContainsKey("ID")) { if ($tbl["ItemLink"]) { $noId.Add("$($tbl['ItemLink'])".Trim('"')) }; return }
        $asset = Add-TTCJson (Add-TTCJson "" "Amount" $tbl["Amount"]) "TotalPrice" $tbl["TotalPrice"]
        $json = "{`"TradeAsset`":{$asset,`"Item`":$(Get-TTCItemJson $tbl)},`"PlayerID`":`"$player`",`"GuildID`":@@"
        if (-not [string]::IsNullOrEmpty($kiosk)) { $json += ",`"GuildKioskLocationID`":$kiosk" }
        $json += ",`"DiscoverUnixTime`":$dv,`"ExpireUnixTime`":$ev}"
        if ($best.ContainsKey($uid) -and $best[$uid].Discover -ge $dv) { return }
        $best[$uid] = @{ Discover = $dv; Guild = $guild; Json = $json; Uid = $uid }
    }

    foreach ($acct in $accounts.Keys) {
        $info = $accounts[$acct]
        if ([double]("0" + "$($info['ActualVersion'])") -lt 7) { continue }
        if ($culture -eq "") { $culture = "$($info['ClientCulture'])".Trim('"') }
        $set = $settings[$acct]
        if ($set -and $set["EnableAutoRecordStoreEntries"] -eq "true") {
            foreach ($e in $auto) {
                if ($e.Acct -ne $acct) { continue }
                $g = $autoGuild["$acct`t$($e.Guild)"]
                if (-not $g -or [string]::IsNullOrEmpty($g["KioskLocationID"])) { continue }
                & $keep $e.Guild $e.Player $e.Table $e.Table["DiscoverTime"] $e.Table["ExpireTime"] $g["KioskLocationID"]
                $kiosks[$e.Guild] = @($g["KioskLocationID"], $g["LastUpdate"])
            }
        }
        if ($set -and $set["EnableSelfEntriesUpload"] -eq "true") {
            foreach ($e in $self) {
                if ($e.Acct -ne $acct) { continue }
                $g = $guildInfo["$acct`t$($e.Guild)"]
                $scan = if ($g) { $g["LastFullScan"] } else { "" }
                $expire = if ($scan) { [string]([long][double]$scan + 604800) } else { "" }
                $kiosk = if ($g) { $g["KioskLocationID"] } else { "" }
                & $keep $e.Guild $acct $e.Table $scan $expire $kiosk
            }
        }
    }
    return @{ Entries = @($best.Values); NoId = $noId; Kiosks = $kiosks; Culture = $culture; Newest = $seen.Newest }
}

function Send-TTCJson([string]$domain, [string]$file, [string]$route) {
    & curl.exe -s -f -m 60 -X POST -A "$TTC_USER_AGENT" -H "Content-Type: application/json; charset=UTF-8" `
        -H "WebClientVersion: $TTC_WEB_CLIENT_VERSION" -H "ClientID: $(Get-TTCClientId)" `
        --data-binary "@$file" "https://$domain$route" 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Get-TTCUploadCache([string]$region) { return (Join-Path $DB_DIR "LTTC_TTC_Uploaded_$region.txt") }

function Invoke-TTCUpload([string]$domain, [string]$region, [string]$sv) {
    $global:TTC_UPLOAD_COUNT = 0; $global:TTC_UPLOAD_NEWEST = 0
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $cache = Get-TTCUploadCache $region
    try { $parsed = Read-TTCUpload $sv $region $now $cache } catch { return $false }
    $global:TTC_UPLOAD_NEWEST = $parsed.Newest
    $work = Join-Path ([IO.Path]::GetTempPath()) ("lttc_upload_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $ok = $true; $count = 0
    try {
        $ids = @{}
        foreach ($guild in @($parsed.Entries | ForEach-Object { $_.Guild } | Sort-Object -Unique)) {
            $resp = & curl.exe -s -f -m 30 -G -A "$TTC_USER_AGENT" -H "WebClientVersion: $TTC_WEB_CLIENT_VERSION" `
                -H "ClientID: $(Get-TTCClientId)" --data-urlencode "guildName=$guild" "https://$domain/api/PC/Trade/GetGuildID" 2>$null
            if ("$resp" -match '"GuildID":(\d+)') { $ids[$guild] = $Matches[1] }
        }
        $ready = New-Object System.Collections.Generic.List[object]
        foreach ($e in $parsed.Entries) {
            if ($ids.ContainsKey($e.Guild)) { $ready.Add($e) } else { $ok = $false }
        }
        for ($i = 0; $i -lt $ready.Count; $i += $TTC_BATCH_SIZE) {
            $batch = $ready.GetRange($i, [Math]::Min($TTC_BATCH_SIZE, $ready.Count - $i))
            $file = Join-Path $work "batch.json"
            [IO.File]::WriteAllText($file, "[" + (($batch | ForEach-Object { $_.Json.Replace("@@", $ids[$_.Guild]) }) -join ",") + "]", $utf8)
            if (Send-TTCJson $domain $file "/api/PC/Trade/PostAutoRecordedEntry") {
                $count += $batch.Count
                [IO.File]::AppendAllText($cache, (($batch | ForEach-Object { "$($_.Uid)`t$($_.Discover)`t$now`n" }) -join ""), $utf8)
            } else { $ok = $false }
        }
        if ($ready.Count -gt 0) {
            $links = @($parsed.NoId | Sort-Object -Unique)
            if ($parsed.Culture -eq "en" -and $links.Count -gt 0 -and $links.Count -lt ($ready.Count / 5)) {
                $file = Join-Path $work "links.json"
                [IO.File]::WriteAllText($file, "[" + (($links | ForEach-Object { "`"$_`"" }) -join ",") + "]", $utf8)
                Send-TTCJson $domain $file "/api/PC/Trade/RecordItemLinks" | Out-Null
            }
            foreach ($guild in $parsed.Kiosks.Keys) {
                if (-not $ids.ContainsKey($guild)) { continue }
                $k = $parsed.Kiosks[$guild]
                $stamp = if ($k[1]) { $k[1] } else { 0 }
                $file = Join-Path $work "kiosk.json"
                [IO.File]::WriteAllText($file, "{`"GuildID`":$($ids[$guild]),`"GuildKioskLocationID`":$($k[0]),`"Timestamp`":$stamp}", $utf8)
                Send-TTCJson $domain $file "/api/PC/Trade/VerifyKioskLocation" | Out-Null
            }
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $cache) {
        $cut = $now - 172800
        $keepLines = @([IO.File]::ReadAllLines($cache) | Where-Object { $p = $_.Split("`t"); $p.Count -ge 2 -and [long]("0" + $p[1]) -ge $cut })
        [IO.File]::WriteAllText($cache, $(if ($keepLines.Count) { ($keepLines -join "`n") + "`n" } else { "" }), $utf8)
    }
    $global:TTC_UPLOAD_COUNT = $count
    return $ok
}

function Get-TTCNothingNewReason {
    $newest = [long]$global:TTC_UPLOAD_NEWEST
    if ($newest -le 0) { return "no listings in TamrielTradeCentre.lua yet" }
    $clock = [DateTimeOffset]::FromUnixTimeSeconds($newest).ToLocalTime().ToString("HH:mm")
    if ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $newest -gt 21600) {
        return "newest scan saved is $clock, TTC takes the last 6 hours; ESO saves new scans on /reloadui or logout"
    }
    return "every listing up to $clock was already uploaded; ESO saves new scans on /reloadui or logout"
}
