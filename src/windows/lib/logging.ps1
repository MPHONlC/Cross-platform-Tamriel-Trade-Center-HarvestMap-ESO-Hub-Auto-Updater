function Log-Event($level, $message) {
    if ($level -eq "ITEM" -and $global:LOG_MODE -ne "detailed") { return }
    $clean_msg = $message -replace "\e\[[0-9;]*m", ""
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] [$level] $clean_msg" | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
}

function Convert-TimeStr($ts) {
    $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $diff = $now - $ts
    if ($diff -lt 0) { $diff = 0 }
    if ($ts -eq 0) { return "Active" }
    if ($diff -lt 60) { return "$diff" + "s ago" }
    if ($diff -lt 3600) { return "$([math]::Floor($diff/60))m ago" }
    if ($diff -lt 86400) { return "$([math]::Floor($diff/3600))h ago" }
    return "$([math]::Floor($diff/86400))d ago"
}

function UIEcho($msg) {
    if (!$global:SILENT) {
        $formatted = [System.Text.RegularExpressions.Regex]::Replace($msg, '\[TS:(\d+)\]', { 
            param($m) 
            $rel = Convert-TimeStr ([int]$m.Groups[1].Value)
            return "[$ESC[90m$rel$ESC[0m]" 
        })
        [Console]::WriteLine($formatted)
        [System.IO.File]::AppendAllText($UI_STATE_FILE, "$formatted`n", [System.Text.Encoding]::UTF8)
    }
}

