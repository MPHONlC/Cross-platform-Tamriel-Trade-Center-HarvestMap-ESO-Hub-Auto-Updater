function auto_scan_addons {
    Write-Host "$ESC[0;34mScanning default locations and drives for Addons folder...$ESC[0m"
    $docs = [Environment]::GetFolderPath("MyDocuments")
    $publicDocs = [Environment]::GetFolderPath("CommonDocuments")
    $oneDrive = $env:OneDrive

    $quickPaths = @(
        "$docs\Elder Scrolls Online\live\AddOns",
        "$oneDrive\Documents\Elder Scrolls Online\live\AddOns",
        "$publicDocs\Elder Scrolls Online\live\AddOns"
    )

    foreach ($p in $quickPaths) {
        if (Test-Path $p) {
            $liveDir = (Get-Item $p).Parent.FullName
            if ((Test-Path "$liveDir\UserSettings.txt") -and (Test-Path "$liveDir\AddOnSettings.txt")) { return $p }
        }
    }
    
    Log-Event "INFO" "auto_scan_addons: Performing deep drive scan"
    $drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root
    $suffixes = @("Documents\Elder Scrolls Online\live\AddOns", "*\Documents\Elder Scrolls Online\live\AddOns", "Elder Scrolls Online\live\AddOns", "*\Elder Scrolls Online\live\AddOns", "*\*\Elder Scrolls Online\live\AddOns", "live\AddOns", "*\live\AddOns", "*\*\live\AddOns")

    foreach ($drive in $drives) {
        foreach ($s in $suffixes) {
            $checkPath = Join-Path $drive $s
            $found = Resolve-Path $checkPath -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $liveDir = (Get-Item $found.Path).Parent.FullName
                if ((Test-Path "$liveDir\UserSettings.txt") -and (Test-Path "$liveDir\AddOnSettings.txt")) { return $found.Path }
            }
        }
    }
    return ""
}

