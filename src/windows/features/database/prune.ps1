function Prune-HistoryLines([string[]]$lines, [double]$cutoff, [hashtable]$dbName, [hashtable]$dbQual) {
    $kept = New-Object System.Collections.Generic.List[string]
    $pruned = New-Object System.Collections.Generic.List[string]
    foreach ($raw in $lines) {
        $line = $raw.TrimEnd("`r")
        $f = $line.Split('|')
        if ($f[0] -ne "HISTORY") { if ($line -ne "") { $kept.Add($line) }; continue }
        if ((To-Num $f[1]) -lt $cutoff) { $pruned.Add($line); continue }

        $nf = $f.Length
        if ($f[$nf - 1] -match '^[0-9]+$') { $scans = [long]$f[$nf - 1]; $src = $f[$nf - 2] } else { $scans = 1; $src = $f[$nf - 1] }
        if ($src -match '^(Unknown|\[Unknown\])$' -or $src -eq "") { $src = "TTC" }
        if ($nf -lt 14) { $f = $f + (,"" * (14 - $nf)) }

        if ($dbName.ContainsKey($f[5]) -and $dbName[$f[5]] -ne "" -and $dbName[$f[5]] -notmatch '^Unknown Item') { $f[6] = $dbName[$f[5]] }
        if ($dbQual.ContainsKey($f[5])) { $f[11] = Get-QualityColor $dbQual[$f[5]] }
        elseif (!$f[11].StartsWith("$ESC[")) { $f[11] = "$ESC[0m" }
        $f[12] = $src; $f[13] = "$scans"
        $kept.Add(($f[0..13] -join '|'))
    }
    return [PSCustomObject]@{ Kept = $kept.ToArray(); Pruned = $pruned.ToArray() }
}

function Prune-History {
    Log-Event "INFO" "prune_history: Initiating 30 days data prune and metadata sync."
    if (!(Test-Path $HIST_FILE)) { return }
    Start-Spinner "Pruning history data (30 days)..."
    $now = if ($CURRENT_TIME) { $CURRENT_TIME } else { [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

    $dbName = New-Object System.Collections.Hashtable; $dbQual = New-Object System.Collections.Hashtable
    if (Test-Path $DB_FILE) {
        foreach ($line in [System.IO.File]::ReadLines($DB_FILE)) {
            $p = $line.Split('|')
            if ($p[0] -match '^[0-9]+$') {
                $dbName[$p[0]] = if ($p.Length -ge 6) { $p[5] } elseif ($p.Length -ge 3) { $p[2] } else { "" }
                $dbQual[$p[0]] = To-Num $p[1]
            }
        }
    }

    $orig = [System.IO.File]::ReadAllLines($HIST_FILE)
    $res = Prune-HistoryLines $orig ($now - 2592000) $dbName $dbQual
    [System.IO.File]::WriteAllText($HIST_FILE, $(if ($res.Kept.Count) { ($res.Kept -join "`n") + "`n" } else { "" }), (New-Object System.Text.UTF8Encoding $false))

    if ($global:LOG_MODE -eq "detailed") {
        foreach ($l in $res.Pruned) { Log-Event "ITEM" "Pruned History Item: $l" }
    }
    $count = [math]::Max(0, $orig.Count - $res.Kept.Count)
    Stop-Spinner 0 "History pruned ($count items removed)"
}
