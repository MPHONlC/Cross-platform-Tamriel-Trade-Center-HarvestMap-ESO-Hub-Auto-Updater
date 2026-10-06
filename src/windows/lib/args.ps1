$parsedArgs = @()
if ([string]::IsNullOrWhiteSpace($env:PS_ARGS) -eq $false) {
    $parsedArgs = [System.Text.RegularExpressions.Regex]::Matches($env:PS_ARGS, '[\"]([^\"]+)[\"]|([^ ]+)') |
        ForEach-Object { if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } }
}
$global:HAS_ARGS = if ($parsedArgs.Count -gt 0) {$true} else {$false}
$global:IS_TASK = $false
$global:IS_STEAM_LAUNCH = $false

for ($i = 0; $i -lt $parsedArgs.Count; $i++) {
    if ($parsedArgs[$i] -eq "--task" -or $parsedArgs[$i] -eq "--silent") { 
        $global:IS_TASK = $true 
        [ConsoleConfig]::HideWindow()
    }
    if ($parsedArgs[$i] -eq "--steam") { $global:IS_STEAM_LAUNCH = $true }
}

