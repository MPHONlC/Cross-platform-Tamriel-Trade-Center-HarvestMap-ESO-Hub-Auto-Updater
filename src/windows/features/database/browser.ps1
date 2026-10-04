function Get-NameEnc([string]$s) { return $s.Replace(" ", "+").Replace("'", "%27") }
function Get-TtcUrl([string]$name) { return "https://us.tamrieltradecentre.com/pc/Trade/SearchResult?SearchType=Sell&ItemNamePattern=$(Get-NameEnc $name)" }

$UESP_STYLE_SUFFIXES = @(
    ' (Axes|Belts|Boots|Bows|Chests|Daggers|Gloves|Helmets)$',
    ' (Legs|Maces|Shields|Shoulders|Staves|Swords|Cuirass)$',
    ' (Greaves|Helm|Pauldrons|Sabatons|Gauntlets|Bracers)$',
    ' (Epaulets|Jack|Guards|Belt|Shoes|Jerkin|Breeches|Hat)$',
    ' (Robes|Sash|Girdle|Corselet|Arm Cops)$',
    ' Style$'
)

function Get-ItemLinks([string]$name, [string]$id) {
    $out = "$ESC[90m[$ESC]8;;$(Get-TtcUrl $name)$ESC\TTC$ESC]8;;$ESC\]$ESC[0m " +
           "$ESC[90m[$ESC]8;;https://eso-hub.com/en/trading/$id$ESC\ESO-Hub$ESC]8;;$ESC\]$ESC[0m"
    if ($name -cmatch '^(Blueprint|Praxis|Design|Pattern|Formula|Diagram|Sketch): ') {
        $u = ([regex]'^[^:]+: ').Replace($name, '', 1).Replace(" ", "_").Replace("'", "%27")
        $out += " $ESC[90m[$ESC]8;;https://en.uesp.net/wiki/File:ON-furnishing-$u.jpg$ESC\UESP$ESC]8;;$ESC\]$ESC[0m"
    } elseif ($name -cmatch 'Crafting Motif' -or $name -cmatch 'Style Page:') {
        $u = ([regex]'^.*Crafting Motif [^:]+: ').Replace($name, '', 1)
        $u = ([regex]'^.*Style Page: ').Replace($u, '', 1)
        foreach ($suf in $UESP_STYLE_SUFFIXES) { $u = ([regex]$suf).Replace($u, '', 1) }
        $u = $u.Replace(" ", "_").Replace("'", "%27")
        $out += " $ESC[90m[$ESC]8;;https://en.uesp.net/wiki/Online:${u}_Style$ESC\UESP$ESC]8;;$ESC\]$ESC[0m"
    }
    return $out
}

function Get-BandPrice([System.Collections.Generic.List[double]]$list) {
    $a = $list.ToArray(); [Array]::Sort($a); $n = $a.Length
    $trim = [math]::Floor($n * 0.10); if ($trim -eq 0) { $trim = 1 }
    $validN = $n - (2 * $trim); if ($validN -lt 1) { $validN = 1 }
    $ms = $trim + [math]::Floor($validN * 0.45); $me = $trim + [math]::Floor($validN * 0.55)
    if ($me -lt $ms) { $me = $ms }
    $sum = 0.0; $c = 0
    for ($i = $ms; $i -le $me; $i++) { $sum += $a[$i]; $c++ }
    return $sum / $c
}

function Test-RowPasses($p) {
    if ($script:bCutoff -gt 0 -and (To-Num $p[1]) -lt $script:bCutoff) { return $false }
    if ($script:bSrc -and (To-LowerAscii $p[12]).IndexOf($script:bSrc, [StringComparison]::Ordinal) -lt 0) { return $false }
    if ($script:bUser -and (To-LowerAscii $p[7]).IndexOf($script:bUser, [StringComparison]::Ordinal) -lt 0 -and (To-LowerAscii $p[8]).IndexOf($script:bUser, [StringComparison]::Ordinal) -lt 0) { return $false }
    if ("$($p[6])".StartsWith("Unknown Item (", [StringComparison]::Ordinal)) { return $false }
    return $true
}

function Get-RelTime([double]$ts, [long]$now) {
    if ($ts -eq 0) { return "Active" }
    $d = $now - $ts; if ($d -lt 0) { $d = 0 }
    if ($d -lt 60) { return "${d}s ago" }
    if ($d -lt 3600) { return "$([math]::Floor($d / 60))m ago" }
    if ($d -lt 86400) { return "$([math]::Floor($d / 3600))h ago" }
    return "$([math]::Floor($d / 86400))d ago"
}

function Get-BrowseSortKey([string]$sortOpt, [double]$ts, [double]$price, [string]$name, [int]$idx) {
    $k = switch ($sortOpt) {
        "2" { ([long]$ts).ToString().PadLeft(10, '0') }
        "3" { (Format-Fixed (100000000000000 - $price) 3).PadLeft(18, '0') }
        "4" { (Format-Fixed $price 3).PadLeft(18, '0') }
        "5" { To-LowerAscii $name }
        default { ([long](9999999999 - $ts)).ToString().PadLeft(10, '0') }
    }
    return "$k|$($idx.ToString().PadLeft(9, '0'))"
}

function Sort-ByKey($keys, $rows) {
    $k = [string[]]$keys.ToArray(); $r = [string[]]$rows.ToArray()
    [Array]::Sort($k, $r, [StringComparer]::Ordinal)
    return ,$r
}

function Read-BrowseFilters {
    $script:bSrcRaw = Read-Host "$ESC[33mSearch by Source [TTC or ESO-Hub] (leave empty for ALL)$ESC[0m"
    $script:bPersonal = Read-Host "$ESC[33mFilter to your @Username only? (y/N)$ESC[0m"
    Write-Host "`n$ESC[33mTime Filter:$ESC[0m"
    Write-Host " 1) Past 1 Week`n 2) Past 2 Weeks`n 3) Past 3 Weeks`n 4) All Data"
    $script:bTimeOpt = Read-Host "$ESC[33mChoice [1-4] (default 4)$ESC[0m"

    $script:bCutoff = 0; $now = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    switch ($script:bTimeOpt) { "1" { $script:bCutoff = $now - 604800 } "2" { $script:bCutoff = $now - 1209600 } "3" { $script:bCutoff = $now - 1814400 } }

    $script:bUserRaw = ""
    if ($script:bPersonal -match '^[Yy]$') {
        if ([string]::IsNullOrEmpty($global:TARGET_USERNAME)) { Write-Host "$ESC[31m[!] @Username not set!$ESC[0m" }
        else { $script:bUserRaw = $global:TARGET_USERNAME }
    }
    $script:bSrc = To-LowerAscii $script:bSrcRaw
    $script:bUser = To-LowerAscii $script:bUserRaw
}

function Get-BrowseCacheFile([string]$key) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hash = -join ($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$key`n")) | ForEach-Object { $_.ToString("x2") })
    return "$script:bCacheDir\cache_$hash.txt"
}

function Test-CacheFresh($cacheFile) {
    return ((Test-Path -LiteralPath $cacheFile) -and (Get-Item -LiteralPath $cacheFile).LastWriteTimeUtc -gt (Get-Item -LiteralPath $HIST_FILE).LastWriteTimeUtc)
}

function Write-Lines($path, $lines) {
    [System.IO.File]::WriteAllText($path, $(if (@($lines).Count) { (@($lines) -join "`n") + "`n" } else { "" }), (New-Object System.Text.UTF8Encoding $false))
}

function Show-Pages($rows) {
    $total = $rows.Count; $pages = [math]::Ceiling($total / 50); $page = 1
    while ($true) {
        Clear-Host
        Write-Host "$ESC[36m--- Results Page $page of $pages ---$ESC[0m`n"
        $start = ($page - 1) * 50; $end = [math]::Min($start + 50, $total)
        for ($i = $start; $i -lt $end; $i++) { [Console]::WriteLine($rows[$i]) }
        Write-Host "`n$ESC[33mPress [SPACE] for next page, or 'q' to quit...$ESC[0m"
        $key = [Console]::ReadKey($true)
        if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') { break }
        if ($page * 50 -ge $total) { break }
        $page++
    }
}

function Get-HistoryRows([string]$file, [string]$term, [string]$sortOpt) {
    $now = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $guildId = (New-Object System.Collections.Hashtable)
    if (Test-Path $DB_FILE) {
        foreach ($l in [System.IO.File]::ReadLines($DB_FILE)) { $q = $l.Split('|'); if ($q[0] -eq "GUILD") { $guildId[$q[1]] = $q[2] } }
    }
    $keys = New-Object System.Collections.Generic.List[string]; $rows = New-Object System.Collections.Generic.List[string]
    $nr = 0
    foreach ($raw in [System.IO.File]::ReadLines($file)) {
        $nr++
        $line = $raw.TrimEnd("`r"); $p = $line.Split('|')
        if ($p[0] -ne "HISTORY" -or !(Test-RowPasses $p)) { continue }
        if ($p[9] -eq "Unknown Guild" -or $p[9] -eq "Guilds") { continue }
        $kname = "$($p[10])"
        if ($kname -ne "" -and $kname -ne "0" -and $global:k_dict.ContainsKey($kname)) { $kname = $global:k_dict[$kname].Split('|')[0] }
        if ($term -and (To-LowerAscii "$line|$kname").IndexOf($term, [StringComparison]::Ordinal) -lt 0) { continue }

        $actCol = "$ESC[36m"
        if ($p[2] -eq "Sold") { $actCol = "$ESC[38;5;214m" }
        if ($p[2] -eq "Purchased") { $actCol = "$ESC[92m" }
        if ($p[2] -eq "Cancelled") { $actCol = "$ESC[31m" }

        $kStr = ""
        if ("$($p[10])" -ne "" -and $p[10] -ne "0") {
            $kStr = if ($global:k_dict.ContainsKey($p[10])) { Get-KioskLink $p[10] "" } else { " $ESC[90m(Kiosk ID: $($p[10]))$ESC[0m" }
        }
        $gStr = ""
        if ("$($p[9])" -ne "") {
            $gStr = if ($guildId.ContainsKey($p[9])) { " in $ESC[35m$ESC]8;;|H1:guild:$($guildId[$p[9]])|h$($p[9])|h$ESC\$($p[9])$ESC]8;;$ESC\$ESC[0m" } else { " in $ESC[35m$($p[9])$ESC[0m" }
        }
        $link = if ($p[12] -eq "TTC") { Get-TtcUrl $p[6] } else { "https://eso-hub.com/en/trading/$($p[5])" }
        $scans = To-Num $p[13]
        $scanStr = if ($scans -gt 1) { " $ESC[96m[${scans}x Scans]$ESC[0m" } else { "" }
        $trade = ""
        if ("$($p[8])" -ne "" -and "$($p[7])" -ne "") { $trade = " by $ESC[36m$($p[8])$ESC[0m to $ESC[36m$($p[7])$ESC[0m" }
        elseif ("$($p[8])" -ne "") { $trade = " by $ESC[36m$($p[8])$ESC[0m" }
        elseif ("$($p[7])" -ne "") { $trade = " to $ESC[36m$($p[7])$ESC[0m" }

        $ts = To-Num $p[1]
        $keys.Add((Get-BrowseSortKey $sortOpt $ts (To-Num $p[3]) $p[6] $nr))
        $rows.Add(" [$ESC[90m$(Get-RelTime $ts $now)$ESC[0m] $actCol$($p[2])$ESC[0m for $ESC[32m$($p[3])$ESC[33mgold$ESC[0m - $ESC[32m$($p[4])x$ESC[0m $ESC]8;;$link$ESC\$($p[11])$($p[6])$ESC[0m$ESC]8;;$ESC\$trade$gStr$kStr [$ESC[90m$($p[12])$ESC[0m]$scanStr")
    }
    return Sort-ByKey $keys $rows
}

function Get-ScanRows([string]$file, [string]$term, [string]$sortOpt) {
    $now = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $keys = New-Object System.Collections.Generic.List[string]; $rows = New-Object System.Collections.Generic.List[string]
    $nr = 0
    foreach ($raw in [System.IO.File]::ReadLines($file)) {
        $nr++
        $line = $raw.TrimEnd("`r")
        if ($line -cnotmatch "\[TS:[0-9]+\]|\[$ESC\[90mListing$ESC\[0m\]") { continue }
        $plain = [regex]::Replace($line, "$ESC\]8;;[^$ESC]*$ESC\\", "")
        $plain = [regex]::Replace($plain, "$ESC\[[0-9;]*m", "")
        if ($term -and (To-LowerAscii $plain).IndexOf($term, [StringComparison]::Ordinal) -lt 0) { continue }
        $ts = if ($line -cmatch '\[TS:([0-9]+)\]') { To-Num $matches[1] } else { 0 }
        $price = if ($plain -cmatch ' for ([0-9]+)gold') { To-Num $matches[1] } else { 0 }
        $name = ([regex]'^[^-]* - [0-9]+x ').Replace($plain, '', 1)
        $row = if ($ts -gt 0) { ([regex]'\[TS:[0-9]+\]').Replace($line, "[$ESC[90m$(Get-RelTime $ts $now)$ESC[0m]", 1) } else { $line }
        $keys.Add((Get-BrowseSortKey $sortOpt $ts $price $name $nr))
        $rows.Add($row)
    }
    return Sort-ByKey $keys $rows
}

function Show-BrowseListing([string]$mode) {
    $term = To-LowerAscii (Read-Host "$ESC[33mEnter search term (leave empty for ALL data)$ESC[0m")
    Read-BrowseFilters
    Write-Host "`n$ESC[33mSort By:$ESC[0m"
    Write-Host " 1) Date (Newest First)`n 2) Date (Oldest First)`n 3) Price (Highest First)`n 4) Price (Lowest First)`n 5) Alphabetical (A-Z)"
    $sortOpt = Read-Host "$ESC[33mChoice [1-5]$ESC[0m"

    if ($mode -eq "scan") { Write-Host "`n$ESC[36m--- View Previous Extraction History ---$ESC[0m" } else { Write-Host "`n$ESC[36mProcessing data...$ESC[0m" }
    Start-Spinner "Filtering and sorting..."
    $rows = if ($mode -eq "scan") { Get-ScanRows $LAST_SCAN_FILE $term $sortOpt } else { Get-HistoryRows $HIST_FILE $term $sortOpt }
    Stop-Spinner 0 "$($rows.Count) results"

    if ($rows.Count -eq 0) {
        Write-Host " $ESC[31m[-] No results found.$ESC[0m"
        Read-Host "`n$ESC[33mPress Enter to return...$ESC[0m" | Out-Null
    } else {
        Show-Pages $rows
    }
}

function Get-TopLines([string]$kind, [string]$file = $HIST_FILE) {
    $prices = (New-Object System.Collections.Hashtable); $total = (New-Object System.Collections.Hashtable); $colors = (New-Object System.Collections.Hashtable); $ids = (New-Object System.Collections.Hashtable)
    foreach ($raw in [System.IO.File]::ReadLines($file)) {
        $p = $raw.TrimEnd("`r").Split('|')
        if ($p[0] -ne "HISTORY" -or ($p[2] -ne "Sold" -and $p[2] -ne "Purchased" -and $p[2] -ne "Listed") -or (To-Num $p[4]) -le 0) { continue }
        if (!(Test-RowPasses $p)) { continue }
        $qty = To-Num $p[4]; $unit = (To-Num $p[3]) / $qty; $name = $p[6]
        $scans = if ("$($p[13])" -ne "" -and (To-Num $p[13]) -gt 0) { To-Num $p[13] } else { 1 }
        $colors[$name] = if ("$($p[11])" -ne "") { $p[11] } else { "$ESC[0m" }
        $ids[$name] = $p[5]
        if (!$prices.ContainsKey($name)) { $prices[$name] = New-Object System.Collections.Generic.List[double] }
        $sold = ($p[2] -eq "Sold" -or $p[2] -eq "Purchased")
        for ($s = 0; $s -lt $scans; $s++) {
            $prices[$name].Add($unit)
            if ($sold) { $total[$name] = $total[$name] + $(if ($kind -eq "vol") { $qty } else { To-Num $p[3] }) }
        }
    }
    $keys = New-Object System.Collections.Generic.List[string]; $rows = New-Object System.Collections.Generic.List[string]
    foreach ($name in $total.Keys) {
        $n = $prices[$name].Count
        $sugg = if ($n -ge 5) { Get-BandPrice $prices[$name] } else { 0 }
        $pStr = if ($sugg -eq 0) { "Not enough data" } else { "$(Format-Fixed $sugg 2)g" }
        $lead = if ($kind -eq "vol") { " $ESC[36m$(Format-Fixed $total[$name] 0)x$ESC[0m sold - " } else { " $ESC[33m$(Format-Fixed $total[$name] 0)g$ESC[0m grossed - " }
        $inv = -join ((Format-Fixed $total[$name] 3).PadLeft(20, '0').ToCharArray() | ForEach-Object { if ($_ -ge '0' -and $_ -le '9') { [char](105 - [int]$_) } else { $_ } })
        $keys.Add("$inv`t$name")
        $rows.Add("$lead$($colors[$name])$name$ESC[0m (Avg: $ESC[33m$pStr$ESC[0m) $(Get-ItemLinks $name $ids[$name])")
    }
    $sorted = Sort-ByKey $keys $rows
    return ,@($sorted | Select-Object -First 10)
}

function Show-BrowseTop([string]$kind) {
    if ($kind -eq "vol") { Log-Event "INFO" "DB Browser: Generating Top 10 Selling Items list."; $tag = "O1v4"; $title = "Top 10 Selling Items (By Volume)" }
    else { Log-Event "INFO" "DB Browser: Generating Top 10 Highest Grossing Items list."; $tag = "O2v4"; $title = "Top 10 Highest Grossing Items" }
    Read-BrowseFilters
    if ($script:bUserRaw) { Write-Host "`n$ESC[36m--- $title [$($script:bUserRaw)] ---$ESC[0m" } else { Write-Host "`n$ESC[36m--- $title [Global] ---$ESC[0m" }

    $cacheFile = Get-BrowseCacheFile "$tag|$($script:bSrcRaw)|$($script:bPersonal)|$($script:bTimeOpt)"
    if (Test-CacheFresh $cacheFile) {
        Write-Host " $ESC[32m[+] Loading instantly from persistent cache...$ESC[0m`n"
        [Console]::Write([System.IO.File]::ReadAllText($cacheFile))
    } else {
        Write-Host ""
        if ($kind -eq "vol") { Start-Spinner "Calculating Top 10 by Volume (Building Cache)..." } else { Start-Spinner "Calculating Top 10 by Grossing (Building Cache)..." }
        $lines = Get-TopLines $kind
        Write-Lines $cacheFile $lines
        Stop-Spinner 0 "Calculation complete"
        Write-Host ""
        foreach ($l in $lines) { [Console]::WriteLine($l) }
    }
    Write-Host ""
}

function Get-PriceLines([string]$term, [string]$file = $HIST_FILE) {
    $prices = (New-Object System.Collections.Hashtable); $colors = (New-Object System.Collections.Hashtable); $ids = (New-Object System.Collections.Hashtable)
    foreach ($raw in [System.IO.File]::ReadLines($file)) {
        $p = $raw.TrimEnd("`r").Split('|')
        if ($p[0] -ne "HISTORY" -or (To-LowerAscii $p[6]).IndexOf($term, [StringComparison]::Ordinal) -lt 0) { continue }
        if (($p[2] -ne "Listed" -and $p[2] -ne "Sold" -and $p[2] -ne "Purchased") -or "$($p[3])" -notmatch '^[0-9]+(\.[0-9]+)?$' -or (To-Num $p[4]) -le 0) { continue }
        if (!(Test-RowPasses $p)) { continue }
        $qty = To-Num $p[4]; $unit = (To-Num $p[3]) / $qty; $name = $p[6]
        $scans = if ("$($p[13])" -ne "" -and (To-Num $p[13]) -gt 0) { To-Num $p[13] } else { 1 }
        $colors[$name] = if ("$($p[11])" -ne "") { $p[11] } else { "$ESC[0m" }
        $ids[$name] = $p[5]
        if (!$prices.ContainsKey($name)) { $prices[$name] = New-Object System.Collections.Generic.List[double] }
        for ($s = 0; $s -lt $scans; $s++) { $prices[$name].Add($unit) }
    }
    $keys = New-Object System.Collections.Generic.List[string]; $rows = New-Object System.Collections.Generic.List[string]
    foreach ($name in $prices.Keys) {
        $n = $prices[$name].Count
        if ($n -lt 5) { continue }
        $keys.Add($name)
        $rows.Add("$($colors[$name])$name$ESC[0m - Suggested Price: $ESC[33m$(Format-Fixed (Get-BandPrice $prices[$name]) 2)g$ESC[0m (Based on $n data points) $(Get-ItemLinks $name $ids[$name])")
    }
    return Sort-ByKey $keys $rows
}

function Show-BrowsePrice {
    $pTerm = Read-Host "$ESC[33mEnter exact or partial item name for price check$ESC[0m"
    Read-BrowseFilters
    Log-Event "INFO" "DB Browser: Executed Suggested Price Check for '$pTerm'"
    Write-Host "`n$ESC[36m--- Suggested Price Check ---$ESC[0m"

    $cacheFile = Get-BrowseCacheFile "O3v4|$pTerm|$($script:bSrcRaw)|$($script:bPersonal)|$($script:bTimeOpt)"
    if (Test-CacheFresh $cacheFile) {
        Write-Host " $ESC[32m[+] Loading instantly from persistent cache...$ESC[0m`n"
        [Console]::Write([System.IO.File]::ReadAllText($cacheFile))
    } else {
        Write-Host ""
        Start-Spinner "Calculating Outlier Eliminations (Building Cache)..."
        $lines = Get-PriceLines (To-LowerAscii $pTerm)
        if ($lines.Count -gt 0) {
            Write-Lines $cacheFile $lines
            Stop-Spinner 0 "Calculation complete"
            Write-Host ""
            foreach ($l in $lines) { [Console]::WriteLine($l) }
        } else {
            Stop-Spinner 1 "Not enough data to display anything"
        }
    }
    Write-Host ""
}

function Set-BrowseUser {
    Write-Host "`n$ESC[36m--- Settings: Edit My Target Username ---$ESC[0m"
    $u = Read-Host "$ESC[33mEnter your exact @Username (leave blank to clear)$ESC[0m"
    if ($u) { $u = "@" + $u.TrimStart('@') }
    $global:TARGET_USERNAME = $u
    $lines = if (Test-Path $CONFIG_FILE) { @([System.IO.File]::ReadAllLines($CONFIG_FILE)) } else { @() }
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^TARGET_USERNAME=') { $lines[$i] = "TARGET_USERNAME=`"$u`""; $found = $true } }
    if (!$found) { $lines += "TARGET_USERNAME=`"$u`"" }
    [System.IO.File]::WriteAllLines($CONFIG_FILE, [string[]]$lines, (New-Object System.Text.UTF8Encoding $false))

    if (!$u) {
        Write-Host " $ESC[90m[-] Username cleared.$ESC[0m`n"
        Log-Event "INFO" "DB Browser: Target Username cleared."
    } else {
        Write-Host " $ESC[92m[+] Username saved as $u$ESC[0m`n"
        Log-Event "INFO" "DB Browser: Target Username updated to '$u'"
    }
    Read-Host "$ESC[33mPress Enter to return...$ESC[0m" | Out-Null
}

function Browse-Database {
    try { [ConsoleConfig]::DisableQuickEdit() } catch {}
    Log-Event "INFO" "browse_database: entering DB browser"
    Clear-Host
    Write-Host "`n$ESC[92m===========================================================================$ESC[0m"
    Write-Host "$ESC[1m$ESC[94m                         TTC & ESO-Hub Database Browser$ESC[0m"
    Write-Host "$ESC[97m                 (Data automatically retained for the last 30 days)$ESC[0m"
    Write-Host "$ESC[92m===========================================================================$ESC[0m`n"

    if (!(Test-Path $HIST_FILE) -or (Get-Item $HIST_FILE).Length -eq 0) {
        Write-Host "$ESC[31m[!] No history database found. Wait for extraction first.$ESC[0m`n"
        Write-Host "$ESC[31m[!] (or go visit a guild store in-game and press scan then /reloadui)$ESC[0m`n"
        Read-Host "$ESC[33mPress Enter to return...$ESC[0m" | Out-Null
        return
    }

    if (Test-Path $CONFIG_FILE) {
        $saved = Get-Content $CONFIG_FILE | Where-Object { $_ -match '^TARGET_USERNAME=' } | Select-Object -Last 1
        if ($saved -match '^TARGET_USERNAME="?([^"]*)"?$') { $global:TARGET_USERNAME = $matches[1] }
    }

    $script:bCacheDir = "$TARGET_DIR\Cache"
    if (!(Test-Path $script:bCacheDir)) { New-Item -ItemType Directory -Force -Path $script:bCacheDir | Out-Null }

    while ($true) {
        $cur = if ($global:TARGET_USERNAME) { $global:TARGET_USERNAME } else { "None" }
        Write-Host "`n$ESC[33mSelect a Database Function:$ESC[0m"
        Write-Host " 1) View / Search Database (Paginated & Sorted)"
        Write-Host " 2) Top 10 Most Selling Items (By Volume)"
        Write-Host " 3) Top 10 Highest Grossing Items (By Total Gold)"
        Write-Host " 4) Suggested Price Calculator (Outlier Elimination)"
        Write-Host " 5) View Previous Extraction History (Paginated & Sorted)"
        Write-Host " 6) Settings: Edit My Target Username $ESC[90m(Current: $cur)$ESC[0m"
        Write-Host " 7) Exit Browser & Resume Updater"
        $opt = Read-Host "$ESC[33mChoice [1-7]$ESC[0m"

        switch ($opt) {
            "1" { Show-BrowseListing "db" }
            "2" { Show-BrowseTop "vol" }
            "3" { Show-BrowseTop "gold" }
            "4" { Show-BrowsePrice }
            "5" { Show-BrowseListing "scan" }
            "6" { Set-BrowseUser }
            "7" { Log-Event "INFO" "browse_database: exiting DB browser" }
            default { Write-Host "$ESC[31mInvalid option.$ESC[0m" }
        }
        if ($opt -eq "7") { break }
    }
    Clear-Host
    if (!$global:SILENT -and (Test-Path $UI_STATE_FILE)) { Get-Content -LiteralPath $UI_STATE_FILE -Raw | Write-Host -NoNewline }
}
