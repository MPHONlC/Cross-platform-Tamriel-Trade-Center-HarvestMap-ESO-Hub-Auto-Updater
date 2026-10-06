function Apply-DB-Updates($updates) {
    if (!$updates -or @($updates).Count -eq 0) { return }
    Log-Event "INFO" "apply_db_updates: applying database updates"

    $header = New-Object System.Collections.Generic.List[string]
    $dbLines = New-Object System.Collections.Hashtable
    if (Test-Path $DB_FILE) {
        foreach ($line in [System.IO.File]::ReadAllLines($DB_FILE)) {
            $p = $line.Split('|')
            if ($line.StartsWith("#DATABASE VERSION")) { $header.Add($line) }
            if ($p[0] -eq "GUILD") { $dbLines["GUILD_" + $p[1]] = $line }
            elseif ($p[0] -eq "KIOSK") { $dbLines["KIOSK_" + $p[1]] = $line }
            elseif ($p[0] -match '^[0-9]+$') { $dbLines["ITEM_" + $p[0]] = $line }
        }
    }

    foreach ($u in @($updates)) {
        $p = $u.Split('|')
        if ($p[0] -eq "DB_UPDATE") { $dbLines["ITEM_" + $p[1]] = ($p[1..($p.Length - 1)] -join '|') }
        elseif ($p[0] -eq "DB_GUILD") { $dbLines["GUILD_" + $p[1]] = "GUILD|$($p[1])|$($p[2])" }
        elseif ($p[0] -eq "DB_KIOSK") { $dbLines["KIOSK_" + $p[1]] = "KIOSK|$($p[1])|$($p[2])|$($p[3])|$($p[4])" }
    }

    $vals = [string[]]@($dbLines.Values)
    $keys = New-Object 'string[]' $vals.Length
    for ($i = 0; $i -lt $vals.Length; $i++) {
        $p = $vals[$i].Split('|')
        $keys[$i] = "$($p[0])`0$(if ($p.Length -ge 7) { $p[6] })`0$(if ($p.Length -ge 6) { $p[5] })`0$($vals[$i])"
    }
    [Array]::Sort($keys, $vals, [StringComparer]::Ordinal)

    $final = New-Object System.Collections.Generic.List[string]
    $final.AddRange($header); $final.AddRange($vals)
    [System.IO.File]::WriteAllText($DB_FILE, $(if ($final.Count) { ($final -join "`n") + "`n" } else { "" }), (New-Object System.Text.UTF8Encoding $false))
}
