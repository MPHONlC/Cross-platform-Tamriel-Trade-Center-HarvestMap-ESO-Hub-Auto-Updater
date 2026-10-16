function Clean-Legacy-Tags {
    Log-Event "INFO" "clean_legacy_tags: sanitizing legacy DB files"
    $found = $false
    foreach ($db in @($DB_FILE, $HIST_FILE)) {
        if ((Test-Path $db) -and (Select-String -LiteralPath $db -SimpleMatch "<title>" -Quiet)) {
            $t = [System.IO.File]::ReadAllText($db).Replace("<title>UESP:ESO Item -- ", "").Replace("<title>ESO Item -- ", "").Replace("</title>", "")
            [System.IO.File]::WriteAllText($db, $t, (New-Object System.Text.UTF8Encoding $false))
            $found = $true
        }
    }
    if ($found) {
        Log-Event "INFO" "Sanitized legacy tags."
        if (!$global:SILENT) { Write-Host " $ESC[92m[+] Cleaned legacy tags.$ESC[0m" }
    }
}
Clean-Legacy-Tags

function Auto-Repair-Database {
    if (!(Test-Path $DB_FILE)) { return }
    Log-Event "INFO" "auto_repair_database: checking and repairing DB entries with missing item names."
    
    $missingCount = 0
    $dbLines = [System.IO.File]::ReadAllLines($DB_FILE)
    foreach ($line in $dbLines) {
        $parts = $line.Split('|')
        if ($parts[0] -match '^[0-9]+$') {
            $tempName = if ($parts.Length -ge 6) { $parts[5] } else { $parts[2] }
            if ($tempName -match '^Unknown Item \(') { $missingCount++ }
        }
    }
    
    if ($missingCount -gt 0) {
        if (!$SILENT) { Write-Host " $ESC[33m[!] Auto-Repair: Scanning local TTC data to resolve $missingCount items...$ESC[0m" }
        Log-Event "INFO" "Auto-Repair: Found $missingCount unknown items. Scanning local lua files for item links."
        $offlineDict = @{}
        if (Test-Path "$SAVED_VAR_DIR\TamrielTradeCentre.lua") {
            foreach ($line in [System.IO.File]::ReadLines("$SAVED_VAR_DIR\TamrielTradeCentre.lua")) {
                if ($line -match '\|H[^:]*:item:([0-9]+)[^|]*\|h([^|]+)\|h') {
                    $id = $matches[1]; $n = $matches[2] -replace '\^.*$', ''
                    if ($id -and $n) { $offlineDict[$id] = $n }
                }
            }
        }
        
        $newDb = New-Object System.Collections.ArrayList
        foreach ($line in $dbLines) {
            $parts = $line.Split('|')
            if ($parts[0] -match '^[0-9]+$' -and $parts.Length -ge 6) {
                if ($parts[5] -match '^Unknown Item \(' -and $offlineDict.ContainsKey($parts[0])) {
                    $parts[5] = $offlineDict[$parts[0]]
                    $real_qual = Calc-Quality $parts[0] $parts[5] ([int]$parts[2]) ([int]$parts[3])
                    $parts[1] = $real_qual; $parts[4] = Get-HQ $real_qual; $parts[6] = Get-Cat $parts[5] $parts[0] ([int]$parts[2]) ([int]$parts[3])
                    [void]$newDb.Add(($parts -join '|'))
                    continue
                }
            }
            [void]$newDb.Add($line)
        }
        [System.IO.File]::WriteAllLines($DB_FILE, $newDb.ToArray())
        if (!$SILENT) { Write-Host " $ESC[92m[+]$ESC[0m Offline Database repair complete!" }
        Log-Event "INFO" "Auto-Repair: Offline database repair completed successfully."
    }
}

