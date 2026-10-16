function Get-Part([string]$h, [int]$s) {
    $o = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $h.Length; $i += 2) {
        $s = ($s * 73 + 41) % 256
        [void]$o.Append([char]([Convert]::ToInt32($h.Substring($i, 2), 16) -bxor $s))
    }
    return $o.ToString()
}

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
$ErrorActionPreference = "SilentlyContinue"

$APP_VERSION = "2026.10.04.19.22"
$APP_TITLE = "Windows Tamriel Trade Center v$APP_VERSION"
$TASK_NAME = "Windows Tamriel Trade Center"
$SYS_ID = "windows"
$RESTORE_EVENT_NAME = "Global\WTTC_RestoreEvent"

$ESC = [char]27
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$host.UI.RawUI.WindowTitle = $APP_TITLE

