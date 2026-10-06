function Get-KioskLink($kiosk, $mapId) {
    if ($global:k_dict.ContainsKey($kiosk)) {
        $kp = $global:k_dict[$kiosk].Split('|')
        $kLoc = $kp[0]; $kMap = if ($kp.Length -ge 2) { $kp[1] } else { "" }; $kCoords = if ($kp.Length -ge 3) { $kp[2] } else { "" }
        if ($kMap -ne "" -and $kCoords -ne "") { return " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?map=$kMap&ping=$kCoords$ESC\$kLoc$ESC]8;;$ESC\)$ESC[0m" }
        if ($kMap -ne "") { return " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?map=$kMap$ESC\$kLoc$ESC]8;;$ESC\)$ESC[0m" }
        return " $ESC[90m($kLoc)$ESC[0m"
    }
    if ($mapId) { return " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?map=$mapId$ESC\$kiosk$ESC]8;;$ESC\)$ESC[0m" }
    return " $ESC[90m($kiosk)$ESC[0m"
}

function Replace-First([string]$text, [string]$find, [string]$with) {
    $i = $text.IndexOf($find)
    if ($i -lt 0) { return $text }
    return $text.Substring(0, $i) + $with + $text.Substring($i + $find.Length)
}

function Invoke-EsoHubExtraction($svFile, $lastTime, $nowTime) {
    $dbGuildName = @{}; $dbCols = @{}; $dbQual = @{}; $dbName = @{}
    if (Test-Path $DB_FILE) {
        foreach ($l in [System.IO.File]::ReadLines($DB_FILE)) {
            $p = $l.Split('|')
            if ($p[0] -eq "GUILD") { if ($p.Length -ge 3) { $dbGuildName[$p[2]] = $p[1] } }
            elseif ($p[0] -match '^[0-9]+$') {
                $dbCols[$p[0]] = $p.Length; $dbQual[$p[0]] = if ($p.Length -ge 2) { $p[1] } else { "" }
                $dbName[$p[0]] = if ($p.Length -ge 6) { $p[5] } elseif ($p.Length -ge 3) { $p[2] } else { "" }
            }
        }
    }

    $lastTime = To-Num $lastTime; $maxTime = $lastTime
    $inTrader = $false; $inGuild = $false; $currentTrader = ""; $currentGid = ""; $buffered = ""; $scanType = ""
    $traderMaps = @{}; $guildKiosks = @{}; $guildMaps = @{}; $guildNames = @{}; $dbUpdated = @{}; $dbGuildUpdated = @{}
    $lines = New-Object System.Collections.Generic.List[string]
    $hist = New-Object System.Collections.Generic.List[string]
    $lineGid = New-Object System.Collections.Generic.List[string]

    foreach ($raw in [System.IO.File]::ReadLines($svFile)) {
        $line = if ($raw.EndsWith("`r")) { $raw.Substring(0, $raw.Length - 1) } else { $raw }
        if ($line.Contains('["traderData"]')) { $inTrader = $true; $inGuild = $false }
        if ($line.Contains('["guildData"]')) { $inGuild = $true; $inTrader = $false }

        if ($inTrader -and $line -match '^[ \t]*\["([^"]+)"\][ \t]*=[ \t]*$') {
            $val = $matches[1]
            if ($val -ne "NA Megaserver" -and $val -ne "EU Megaserver" -and $val -ne "PTS" -and $val -ne "guildHistory") { $currentTrader = $val }
        }
        if ($inTrader -and $line -match '\["mapId"\][ \t]*=[ \t]*[0-9]+') {
            if ($line -match '[0-9]+' -and $currentTrader -ne "") { $traderMaps[$currentTrader] = $matches[0] }
        }
        if ($inTrader -and $line -match '^[ \t]*\[[0-9]+\][ \t]*=[ \t]*[0-9]+') {
            if ($line -match '=[ \t]*([0-9]+)' -and $currentTrader -ne "") {
                $gid = $matches[1]; $guildKiosks[$gid] = $currentTrader
                if ($traderMaps[$currentTrader]) { $guildMaps[$gid] = $traderMaps[$currentTrader] }
            }
        }
        if ($inGuild -and $line -match '^[ \t]*\[[0-9]+\][ \t]*=[ \t]*$') {
            [void]($line -match '[0-9]+'); $currentGid = $matches[0]; $buffered = ""; $scanType = ""
        }
        if ($inGuild -and $line -match '\["guildId"\][ \t]*=[ \t]*[0-9]+') {
            [void]($line -match '[0-9]+'); $currentGid = $matches[0]
            if ($buffered -ne "") { $guildNames[$currentGid] = $buffered; $dbGuildUpdated[$buffered] = $currentGid; $buffered = "" }
        }
        if ($inGuild -and $line -match '\["(traderGuildName|guildName)"\][ \t]*=[ \t]*"([^"]+)"') {
            $val = $matches[2]
            if ($currentGid -ne "") { $guildNames[$currentGid] = $val; $dbGuildUpdated[$val] = $currentGid } else { $buffered = $val }
        }
        if ($line -match '\["(scannedSales|scannedItems|cancelledItems|purchasedItems|traderHistory)"\]') {
            switch ($matches[1]) {
                "scannedSales" { $scanType = "Sold" }; "scannedItems" { $scanType = "Listed" }; "cancelledItems" { $scanType = "Cancelled" }
                "purchasedItems" { $scanType = "Purchased" }; "traderHistory" { $scanType = "History" }
            }
        }

        if ($line.IndexOf(":item:") -lt 0 -or $scanType -eq "") { continue }
        $sIdx = $line.IndexOf('"|H')
        if ($sIdx -lt 0) { continue }
        $tStr = $line.Substring($sIdx + 1)
        $eIdx = $tStr.IndexOf('",'); if ($eIdx -lt 0) { $eIdx = $tStr.IndexOf('"') }
        if ($eIdx -lt 0) { continue }
        $fullVal = $tStr.Substring(0, $eIdx)
        $splitIdx = $fullVal.IndexOf('|h|h,'); $offset = 5
        if ($splitIdx -lt 0) { $splitIdx = $fullVal.IndexOf('|h,'); $offset = 3 }
        if ($splitIdx -lt 0) { continue }

        $itemLink = $fullVal.Substring(0, $splitIdx + 2)
        $dataCsv = $fullVal.Substring($splitIdx + $offset)
        $lp = $itemLink.Split(':')
        $itemid = if ($lp.Length -ge 3) { $lp[2] } else { "" }
        $s = if ($lp.Length -ge 4) { To-Num $lp[3] } else { 0 }
        $v = if ($lp.Length -ge 5) { To-Num $lp[4] } else { 0 }

        $arr = if ($dataCsv -eq "") { @() } else { $dataCsv.Split(',') }
        $len = $arr.Count
        $price = if ($len -ge 1) { $arr[0] } else { "" }
        $qty = if ($len -ge 2) { $arr[1] } else { "" }
        if ($qty -eq "") { $qty = "1" }
        $buyer = ""; $seller = ""
        if ($len -ge 5) { $buyer = $arr[2]; $seller = $arr[3]; $stime = To-Num $arr[4] }
        else { $seller = if ($len -ge 3) { $arr[2] } else { "" }; $stime = if ($len -ge 4) { To-Num $arr[3] } else { 0 } }
        if (!($stime -gt 1400000000)) {
            $stime = 0
            for ($idx = $len - 1; $idx -ge 2; $idx--) {
                if ($arr[$idx] -match '^[0-9]+$' -and [double]$arr[$idx] -gt 1400000000) { $stime = [double]$arr[$idx]; break }
            }
        }
        if ($buyer -ne "" -and $buyer -notmatch '^@') { $buyer = "@$buyer" }
        if ($seller -ne "" -and $seller -notmatch '^@') { $seller = "@$seller" }

        $realName = if ($dbName.ContainsKey($itemid) -and $dbName[$itemid] -notmatch '^Unknown Item') { $dbName[$itemid] } else { "Unknown Item ($itemid)" }
        $realQual = if ($dbQual.ContainsKey($itemid)) { [int](To-Num $dbQual[$itemid]) } else { Calc-Quality $itemid $realName $s $v }

        if ($realName.IndexOf("Unknown Item (") -lt 0) {
            $needs = ($dbName[$itemid] -ne $realName) -or !$dbQual.ContainsKey($itemid) -or ([int](To-Num $dbQual[$itemid]) -ne [int]$realQual) -or ((To-Num $dbCols[$itemid]) -lt 7)
            if ($needs) {
                $dbUpdated[$itemid] = "$itemid|$realQual|$s|$v|$(Get-HQ $realQual)|$realName|$(Get-Cat $realName $itemid $s $v)"
                $dbName[$itemid] = $realName; $dbQual[$itemid] = "$realQual"; $dbCols[$itemid] = 7
            }
        }

        if ($realName -ne "" -and $price -ne "") {
            if ($stime -gt $maxTime) { $maxTime = $stime }
            if ($stime -gt $lastTime -or $stime -eq 0 -or $scanType -eq "Listed") {
                $c = Get-QualityColor $realQual
                $itemDisplay = "$ESC]8;;https://eso-hub.com/en/trading/$itemid$ESC\$c$realName$ESC[0m$ESC]8;;$ESC\"
                $tradeStr = ""
                if ($seller -ne "" -and $buyer -ne "") { $tradeStr = " by $ESC[36m$seller$ESC[0m to $ESC[36m$buyer$ESC[0m" }
                elseif ($seller -ne "") { $tradeStr = " by $ESC[36m$seller$ESC[0m" }
                elseif ($buyer -ne "") { $tradeStr = " to $ESC[36m$buyer$ESC[0m" }
                $age = (To-Num $nowTime) - $stime; $statusTag = ""
                if ($scanType -eq "Sold") { $statusTag = " $ESC[38;5;214m[SOLD]$ESC[0m" }
                elseif ($scanType -eq "Purchased") { $statusTag = " $ESC[92m[PURCHASED]$ESC[0m" }
                elseif ($scanType -eq "Cancelled") { $statusTag = " $ESC[31m[CANCELLED]$ESC[0m" }
                elseif ($scanType -eq "Listed") { $statusTag = if ($stime -gt 0 -and $age -gt 2592000) { " $ESC[90m[EXPIRED]$ESC[0m" } else { " $ESC[34m[AVAILABLE]$ESC[0m" } }
                $ts = [long]$stime
                $lines.Add("$ts| $ESC[36m$scanType$ESC[0m for $ESC[32m$price$ESC[33mgold$ESC[0m - $ESC[32m${qty}x$ESC[0m $itemDisplay$tradeStr in GUILD_PLACEHOLDER_$currentGid$statusTag")
                $hist.Add($(if ($currentGid -ne "") { "HISTORY|$ts|$scanType|$price|$qty|$itemid|$realName|$buyer|$seller|$currentGid||$c|ESO-Hub" } else { "" }))
                $lineGid.Add($currentGid)
            }
        }
    }

    foreach ($gid in @($dbGuildName.Keys)) { if (!$guildNames.ContainsKey($gid)) { $guildNames[$gid] = $dbGuildName[$gid] } }
    $outLines = New-Object System.Collections.Generic.List[string]
    $outHist = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $gid = $lineGid[$i]
        $gname = if ($guildNames.ContainsKey($gid)) { $guildNames[$gid] } else { "" }
        if ($gname -eq "" -and $dbGuildName.ContainsKey($gid)) { $gname = $dbGuildName[$gid] }
        if ($gname -ne "" -and $gname -ne "Unknown Guild") { $gLink = "$ESC[35m$ESC]8;;|H1:guild:$gid|h$gname|h$ESC\$gname$ESC]8;;$ESC\$ESC[0m" }
        else { $gLink = "$ESC[35mUnknown Guild$ESC[0m"; $gname = "Unknown Guild" }
        $kiosk = if ($guildKiosks.ContainsKey($gid)) { $guildKiosks[$gid] } else { "" }
        $kStr = if ($kiosk -ne "") { Get-KioskLink $kiosk $guildMaps[$gid] } else { "" }
        $outLines.Add((Replace-First $lines[$i] "GUILD_PLACEHOLDER_$gid" "$gLink$kStr"))
        if ($hist[$i] -ne "") { $outHist.Add((Replace-First $hist[$i] "$gid||" "$gname|$kiosk|")) }
    }
    $updates = New-Object System.Collections.Generic.List[string]
    foreach ($k in $dbUpdated.Keys) { $updates.Add("DB_UPDATE|$($dbUpdated[$k])") }
    foreach ($g in $dbGuildUpdated.Keys) { $updates.Add("DB_GUILD|$g|$($dbGuildUpdated[$g])") }
    return [PSCustomObject]@{ Lines = $outLines.ToArray(); History = $outHist.ToArray(); MaxTime = [long]$maxTime; DbUpdates = $updates.ToArray() }
}
