function Invoke-TtcExtraction($svFile, $lastTime, $nowTime) {
    $dbGuildId = @{}; $dbCols = @{}; $dbQual = @{}; $dbName = @{}
    if (Test-Path $DB_FILE) {
        foreach ($l in [System.IO.File]::ReadLines($DB_FILE)) {
            $p = $l.Split('|')
            if ($p[0] -eq "GUILD") { if ($p.Length -ge 3) { $dbGuildId[$p[1]] = $p[2] } }
            elseif ($p[0] -match '^[0-9]+$') {
                $dbCols[$p[0]] = $p.Length; $dbQual[$p[0]] = if ($p.Length -ge 2) { $p[1] } else { "" }
                $dbName[$p[0]] = if ($p.Length -ge 6) { $p[5] } elseif ($p.Length -ge 3) { $p[2] } else { "" }
            }
        }
    }

    $lastTime = To-Num $lastTime; $nowTime = To-Num $nowTime; $maxTime = $lastTime
    $path = @{}; $guildKiosks = @{}; $dbUpdated = @{}
    $inItem = $false; $itemLvl = 0
    $action = "Listed"; $guild = ""; $player = ""; $seller = ""; $buyer = ""
    $amt = ""; $stime = ""; $price = ""; $itemid = ""; $subtype = ""; $internalLevel = ""; $realName = ""; $kiosk = ""; $gameQual = ""
    $lines = New-Object System.Collections.Generic.List[string]
    $hist = New-Object System.Collections.Generic.List[string]

    foreach ($raw in [System.IO.File]::ReadLines($svFile)) {
        $line = if ($raw.EndsWith("`r")) { $raw.Substring(0, $raw.Length - 1) } else { $raw }

        if ($line -match '^[ \t]*\["?([^"]+)"?\][ \t]*=') {
            [void]($line -match '^[ \t]*'); $lvl = $matches[0].Length
            [void]($line -match '^[ \t]*\["?([^"]+)"?\]'); $key = $matches[1]
            foreach ($k in @($path.Keys)) { if ([int]$k -ge $lvl) { $path.Remove($k) } }
            $path[$lvl] = $key

            if ($key -eq "KioskLocationID" -or ($key -match '^[0-9]+$' -and !$inItem)) {
                $sorted = [int[]]@($path.Keys); [Array]::Sort($sorted)
            }
            if ($key -eq "KioskLocationID") {
                $gname = ""
                for ($i = 0; $i -lt $sorted.Count; $i++) { if ($path[$sorted[$i]] -eq "Guilds" -and ($i + 1) -lt $sorted.Count) { $gname = $path[$sorted[$i + 1]] } }
                if ($gname -ne "" -and $line -match '[0-9]+') { $guildKiosks[$gname] = $matches[0] }
            }
            if ($key -match '^[0-9]+$' -and !$inItem) {
                $inItem = $true; $itemLvl = $lvl
                $action = "Listed"; $guild = ""; $player = ""; $seller = ""; $buyer = ""
                $amt = ""; $stime = ""; $price = ""; $itemid = ""; $subtype = ""; $internalLevel = ""; $realName = ""; $gameQual = ""
                for ($i = 0; $i -lt $sorted.Count; $i++) {
                    $k = $path[$sorted[$i]]
                    if ($k -eq "SaleHistoryEntries") { $action = "Sold" }
                    if ($k -eq "AutoRecordEntries" -or $k -eq "Entries") { $action = "Listed" }
                    if ($k -eq "Guilds" -and ($i + 1) -lt $sorted.Count) { $guild = $path[$sorted[$i + 1]] }
                    if ($k -eq "PlayerListings" -and ($i + 1) -lt $sorted.Count) { $player = $path[$sorted[$i + 1]] }
                }
            }
        }
        if (!$inItem) { continue }

        if ($line -match '\["Amount"\][ \t]*=' -and $line -match '[0-9]+') { $amt = $matches[0] }
        if ($line -match '\["SaleTime"\][ \t]*=' -and $line -match '[0-9]+') { $stime = $matches[0] }
        if ($line -match '\["Timestamp"\][ \t]*=' -and $line -match '[0-9]+') { if ($stime -eq "") { $stime = $matches[0] } }
        if ($line -match '\["TimeStamp"\][ \t]*=' -and $line -match '[0-9]+') { if ($stime -eq "") { $stime = $matches[0] } }
        if ($line -match '\["QualityID"\][ \t]*=' -and $line -match '[0-9]+') { $gameQual = $matches[0] }
        if ($line -match '\["TotalPrice"\][ \t]*=' -and $line -match '[0-9]+') { $price = $matches[0] }
        if ($line -match '\["Price"\][ \t]*=' -and $line -notmatch 'TotalPrice' -and $line -match '[0-9]+') { if ($price -eq "") { $price = $matches[0] } }
        if ($line -match '\["Buyer"\][ \t]*=[ \t]*"([^"]+)"') { $buyer = $matches[1] }
        if ($line -match '\["Seller"\][ \t]*=[ \t]*"([^"]+)"') { $seller = $matches[1] }
        if ($line -match '\["ItemLink"\][ \t]*=') {
            if ($line -match '\|H[0-9a-fA-F]*:item:[0-9]+') { $itemid = $matches[0].Split(':')[2] }
            if ($line -match '"(\|H[^"]+)"') { $lp = $matches[1].Split(':'); $subtype = if ($lp.Length -ge 4) { $lp[3] } else { "" }; $internalLevel = if ($lp.Length -ge 5) { $lp[4] } else { "" } }
        }
        if ($line -match '\["Name"\][ \t]*=') {
            $val = $line -replace '.*Name"\][ \t]*=[ \t]*"', ''
            $val = $val -replace '",[ \t]*$', ''
            $realName = $val.Replace('\"', '"')
        }

        if ($line -match '^[ \t]*\},?[ \t]*$') {
            [void]($line -match '^[ \t]*')
            if ($matches[0].Length -gt $itemLvl) { continue }
            $inItem = $false
            $stimeNum = if ($stime -eq "") { 0 } else { To-Num $stime }
            if ($stimeNum -gt $maxTime) { $maxTime = $stimeNum }
            if (!($stimeNum -gt $lastTime -or $lastTime -eq 0 -or $action -eq "Listed")) { continue }
            if ($amt -eq "") { $amt = "1" }
            if ($realName -eq "" -or $realName -match '^\|[0-9]+\|$') {
                $realName = if ($dbName.ContainsKey($itemid) -and $dbName[$itemid] -notmatch '^Unknown Item') { $dbName[$itemid] } else { "Unknown Item ($itemid)" }
            }
            if ($price -eq "") { continue }

            $s = To-Num $subtype; $v = To-Num $internalLevel
            if ($dbName.ContainsKey($itemid)) {
                $needs = ($realName -ne $dbName[$itemid] -and $realName -notmatch '^Unknown Item') -or ((To-Num $dbCols[$itemid]) -lt 7)
            } else { $needs = $true }
            if ($gameQual -ne "") {
                $realQual = [int]$gameQual + 1
                if (-not $dbQual.ContainsKey($itemid) -or [int](To-Num $dbQual[$itemid]) -ne $realQual) { $needs = $true }
            } elseif ($dbQual.ContainsKey($itemid)) {
                $realQual = [int](To-Num $dbQual[$itemid])
            } else {
                $realQual = Calc-Quality $itemid $realName $s $v
            }
            if ($realName.StartsWith("Unknown Item (")) { $needs = $false }
            if ($needs) {
                $dbUpdated[$itemid] = "$itemid|$realQual|$s|$v|$(Get-HQ $realQual)|$realName|$(Get-Cat $realName $itemid $s $v)"
                $dbName[$itemid] = $realName; $dbQual[$itemid] = "$realQual"; $dbCols[$itemid] = 7
            }
            $c = Get-QualityColor $realQual

            $guildStr = ""; $kiosk = ""
            if ($guild -ne "" -and $guild -ne "Unknown Guild" -and $guild -ne "Guilds") {
                $gDisplay = if ($dbGuildId.ContainsKey($guild)) { "$ESC[35m$ESC]8;;|H1:guild:$($dbGuildId[$guild])|h$guild|h$ESC\$guild$ESC]8;;$ESC\$ESC[0m" } else { "$ESC[35m$guild$ESC[0m" }
                $kiosk = if ($guildKiosks.ContainsKey($guild)) { $guildKiosks[$guild] } else { "" }
                if ($kiosk -ne "" -and $kiosk -ne "0") {
                    $kStr = if ($global:k_dict.ContainsKey($kiosk)) { Get-KioskLink $kiosk "" } else { " $ESC[90m(Kiosk ID: $kiosk)$ESC[0m" }
                } else { $kStr = " $ESC[90m(Local Trader)$ESC[0m" }
                $guildStr = " in $gDisplay$kStr"
            }

            $playerClean = $player
            if ($playerClean -ne "" -and $playerClean -notmatch '^@') { $playerClean = "@$playerClean" }
            if ($buyer -ne "" -and $buyer -notmatch '^@') { $buyer = "@$buyer" }
            if ($seller -ne "" -and $seller -notmatch '^@') { $seller = "@$seller" }
            if ($seller -eq "" -and $playerClean -ne "") { $seller = $playerClean }
            $tradeStr = ""
            if ($seller -ne "" -and $buyer -ne "") { $tradeStr = " by $ESC[36m$seller$ESC[0m to $ESC[36m$buyer$ESC[0m" }
            elseif ($seller -ne "") { $tradeStr = " by $ESC[36m$seller$ESC[0m" }
            elseif ($buyer -ne "") { $tradeStr = " to $ESC[36m$buyer$ESC[0m" }
            elseif ($playerClean -ne "" -and $playerClean -ne $guild) { $tradeStr = " by $ESC[36m$playerClean$ESC[0m" }

            $nameEnc = $realName.Replace(" ", "+").Replace("'", "%27")
            $linkStart = "$ESC]8;;https://us.tamrieltradecentre.com/pc/Trade/SearchResult?SearchType=Sell&ItemNamePattern=$nameEnc$ESC\"
            $age = $nowTime - $stimeNum; $statusTag = ""
            if ($action -eq "Sold") { $statusTag = " $ESC[38;5;214m[SOLD]$ESC[0m" }
            elseif ($action -eq "Listed") { $statusTag = if ($stimeNum -gt 0 -and $age -gt 2592000) { " $ESC[90m[EXPIRED]$ESC[0m" } else { " $ESC[34m[AVAILABLE]$ESC[0m" } }
            $ts = if ($stimeNum -gt 0) { [long]$stimeNum } else { 0 }

            $lines.Add("$ts| $ESC[36m$action$ESC[0m for $ESC[32m$price$ESC[33mgold$ESC[0m - $ESC[32m${amt}x$ESC[0m $linkStart$c$realName$ESC[0m$ESC]8;;$ESC\$tradeStr$guildStr$statusTag")
            if ($guild -ne "Guilds" -and $guild -ne "Unknown Guild" -and $guild -ne "") {
                $hist.Add("HISTORY|$ts|$action|$price|$amt|$itemid|$realName|$buyer|$seller|$guild|$kiosk|$c|TTC")
            } elseif ($action -eq "Listed" -and $seller -ne "") {
                $hist.Add("HISTORY|$ts|$action|$price|$amt|$itemid|$realName|$buyer|$seller||$kiosk|$c|TTC")
            }
        }
    }

    $updates = New-Object System.Collections.Generic.List[string]
    foreach ($k in $dbUpdated.Keys) { $updates.Add("DB_UPDATE|$($dbUpdated[$k])") }
    foreach ($k in $global:k_dict.Keys) { $updates.Add("DB_KIOSK|$k|$($global:k_dict[$k])") }
    return [PSCustomObject]@{ Lines = $lines.ToArray(); History = $hist.ToArray(); MaxTime = [long]$maxTime; DbUpdates = $updates.ToArray() }
}
