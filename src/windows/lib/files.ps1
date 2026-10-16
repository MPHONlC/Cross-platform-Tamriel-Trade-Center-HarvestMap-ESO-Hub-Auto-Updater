Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Numerics

$USER_AGENTS = @(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.0.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0"
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"
)

function Test-FileNewer($src, $snap) {
    if (!(Test-Path -LiteralPath $snap)) { return $true }
    return ((Get-Item -LiteralPath $src).LastWriteTimeUtc -gt (Get-Item -LiteralPath $snap).LastWriteTimeUtc)
}

function Test-ZipFile($path) {
    if (!(Test-Path -LiteralPath $path)) { return $false }
    try { $z = [System.IO.Compression.ZipFile]::OpenRead($path); $ok = $z.Entries.Count -gt 0; $z.Dispose(); return $ok } catch { return $false }
}

function To-Num($v) {
    if ("$v" -match '^\s*([0-9]+(\.[0-9]+)?)') { return [double]$matches[1] }
    return 0
}

$script:spinMsg = ""; $script:spinStart = 0
function Start-Spinner($msg) {
    $script:spinMsg = $msg; $script:spinStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (!$global:SILENT) { Write-Host -NoNewline "`r$ESC[K $ESC[33m[~]$ESC[0m $msg" }
}
function Update-Spinner($msg) {
    $script:spinMsg = $msg
    if (!$global:SILENT) { Write-Host -NoNewline "`r$ESC[K $ESC[33m[~]$ESC[0m $msg" }
}
function Stop-Spinner($ok, $msg) {
    $el = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $script:spinStart
    if (!$global:SILENT) {
        $mark = if ("$ok" -eq "0") { " $ESC[92m[" + [char]0x2713 + "]$ESC[0m" } else { " $ESC[31m[" + [char]0x2717 + "]$ESC[0m" }
        $out = "$mark $msg (${el}s)"
        Write-Host "`r$ESC[K$out"
        [System.IO.File]::AppendAllText($UI_STATE_FILE, "$out`n", [System.Text.Encoding]::UTF8)
    }
    Log-Event "INFO" "Task '$msg' finished in ${el}s (Status: $ok)."
}

function Get-QualityColor($q) {
    switch ([int](To-Num $q)) {
        0 { return "$ESC[90m" }; 1 { return "$ESC[97m" }; 2 { return "$ESC[32m" }; 3 { return "$ESC[36m" }
        4 { return "$ESC[35m" }; 5 { return "$ESC[33m" }; 6 { return "$ESC[38;5;214m" }
    }
    return "$ESC[0m"
}

function Merge-HistoryLines([string[]]$existing, [string[]]$incoming, [hashtable]$dbColors, [switch]$MaxScans) {
    $out = New-Object System.Collections.Generic.List[string]
    $order = New-Object System.Collections.Generic.List[string]
    $rows = @{}
    foreach ($raw in @($existing) + @($incoming)) {
        if ($null -eq $raw) { continue }
        $line = $raw.TrimEnd("`r")
        $f = $line.Split('|')
        if ($f[0] -ne "HISTORY") { if ($line -ne "") { $out.Add($line) }; continue }
        $nf = $f.Length
        if ($f[$nf - 1] -match '^[0-9]+$') { $scans = [int]$f[$nf - 1]; $src = $f[$nf - 2] } else { $scans = 1; $src = $f[$nf - 1] }
        if ($src -match '^(Unknown|\[Unknown\])$' -or $src -eq "") { $src = "TTC" }
        if ($nf -lt 13) { $f = $f + (,"" * (13 - $nf)) }
        $kiosk = $f[10]
        $uid = "$($f[5])|$($f[2])|$($f[3])|$($f[4])|$src"
        $ts = To-Num $f[1]
        $buyer = $f[7]; $seller = $f[8]; $guild = $f[9]
        $color = $dbColors[$f[5]]
        if (!$color) { $color = $f[11]; if (!$color.StartsWith("$ESC[")) { $color = "$ESC[0m" } }
        if (!$rows.ContainsKey($uid)) {
            $order.Add($uid)
            $rows[$uid] = @{ TS = $ts; Name = $f[6]; Buyer = $buyer; Seller = $seller; Guild = $guild; Kiosk = $kiosk; Color = $color; Scans = $scans }
        } else {
            $r = $rows[$uid]
            if ($ts -gt $r.TS) { $r.TS = $ts }
            if ($buyer -ne "" -and $r.Buyer.IndexOf($buyer) -lt 0) { $r.Buyer = if ($r.Buyer -eq "") { $buyer } else { "$($r.Buyer), $buyer" } }
            if ($seller -ne "" -and $r.Seller.IndexOf($seller) -lt 0) { $r.Seller = if ($r.Seller -eq "") { $seller } else { "$($r.Seller), $seller" } }
            if ($guild -ne "" -and $r.Guild.IndexOf($guild) -lt 0) { $r.Guild = if ($r.Guild -eq "") { $guild } else { "$($r.Guild), $guild" } }
            if ($kiosk -ne "" -and $r.Kiosk.IndexOf($kiosk) -lt 0) { $r.Kiosk = if ($r.Kiosk -eq "") { $kiosk } else { "$($r.Kiosk), $kiosk" } }
            if ($MaxScans) { if ($scans -gt $r.Scans) { $r.Scans = $scans } } else { $r.Scans += $scans }
        }
    }
    foreach ($uid in $order) {
        $p = $uid.Split('|'); $r = $rows[$uid]
        $out.Add("HISTORY|$([long]$r.TS)|$($p[1])|$($p[2])|$($p[3])|$($p[0])|$($r.Name)|$($r.Buyer)|$($r.Seller)|$($r.Guild)|$($r.Kiosk)|$($r.Color)|$($p[4])|$($r.Scans)")
    }
    return ,$out.ToArray()
}

function Merge-History($newLines) {
    if (!$newLines -or @($newLines).Count -eq 0) { return }
    if (!(Test-Path $HIST_FILE)) { New-Item -ItemType File -Force -Path $HIST_FILE | Out-Null }
    $dbColors = @{}
    if (Test-Path $DB_FILE) {
        foreach ($l in [System.IO.File]::ReadLines($DB_FILE)) {
            $p = $l.Split('|')
            if ($p[0] -match '^[0-9]+$' -and $p.Length -ge 2) { $dbColors[$p[0]] = Get-QualityColor $p[1] }
        }
    }
    $merged = Merge-HistoryLines ([System.IO.File]::ReadAllLines($HIST_FILE)) @($newLines) $dbColors
    if ($merged.Count -gt 0) { [System.IO.File]::WriteAllLines($HIST_FILE, $merged, (New-Object System.Text.UTF8Encoding $false)) }
}

function Merge-TemplateHistory([string]$histFile, [string]$templateFile, [string]$ver) {
    $dbColors = @{}
    if (Test-Path $DB_FILE) {
        foreach ($l in [System.IO.File]::ReadLines($DB_FILE)) {
            $p = $l.Split('|')
            if ($p[0] -match '^[0-9]+$' -and $p.Length -ge 2) { $dbColors[$p[0]] = Get-QualityColor $p[1] }
        }
    }
    $existing = if (Test-Path -LiteralPath $histFile) { @([System.IO.File]::ReadAllLines($histFile) | Where-Object { !$_.StartsWith("#HISTORY VERSION:") }) } else { @() }
    $incoming = @([System.IO.File]::ReadAllLines($templateFile) | Where-Object { $_.StartsWith("HISTORY|") })
    $lines = Merge-HistoryLines $existing $incoming $dbColors -MaxScans
    $merged = @("#HISTORY VERSION: $ver") + $lines
    [System.IO.File]::WriteAllText($histFile, ($merged -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
}

function Format-Fixed([double]$x, [int]$d) {
    $bits = [BitConverter]::DoubleToInt64Bits($x)
    $neg = $bits -lt 0
    $e = [int](($bits -shr 52) -band 0x7FF)
    $m = [System.Numerics.BigInteger]($bits -band 0xFFFFFFFFFFFFF)
    if ($e -eq 0) { $e = 1 } else { $m += [System.Numerics.BigInteger]::Pow(2, 52) }
    $e -= 1075
    $num = $m * [System.Numerics.BigInteger]::Pow(10, $d)
    if ($e -ge 0) {
        $q = $num * [System.Numerics.BigInteger]::Pow(2, $e)
    } else {
        $den = [System.Numerics.BigInteger]::Pow(2, -$e)
        $r = [System.Numerics.BigInteger]::Zero
        $q = [System.Numerics.BigInteger]::DivRem($num, $den, [ref]$r)
        $c = [System.Numerics.BigInteger]::Compare($r * 2, $den)
        if ($c -gt 0 -or ($c -eq 0 -and !$q.IsEven)) { $q += 1 }
    }
    $s = $q.ToString().PadLeft($d + 1, '0')
    if ($d -gt 0) { $s = $s.Substring(0, $s.Length - $d) + "." + $s.Substring($s.Length - $d) }
    if ($neg -and !$q.IsZero) { $s = "-" + $s }
    return $s
}

function To-LowerAscii([string]$s) {
    if (!$s) { return "" }
    $b = $s.ToCharArray()
    for ($i = 0; $i -lt $b.Length; $i++) { if ($b[$i] -ge 'A' -and $b[$i] -le 'Z') { $b[$i] = [char]([int]$b[$i] + 32) } }
    return -join $b
}
