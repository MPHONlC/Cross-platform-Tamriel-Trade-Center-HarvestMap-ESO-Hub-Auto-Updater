$ESOUI_API = if ($env:LTTC_ESOUI_API) { $env:LTTC_ESOUI_API } else { "https://api.mmoui.com" }
$ESOUI_UA = "Mozilla/5.0"
$ESOUI_SELF_ID = "3249"
$ESOUI_DB_ID = "4428"

function Get-Md5Hex($path) {
    try { return (Get-FileHash -LiteralPath $path -Algorithm MD5).Hash.ToLowerInvariant() } catch { return "" }
}

function Test-VersionNewer([string]$a, [string]$b) {
    $a = $a -replace '^[vV]', ''; $b = $b -replace '^[vV]', ''
    $x = [regex]::Split($a, '[^0-9]+'); $y = [regex]::Split($b, '[^0-9]+')
    $n = [math]::Max($x.Length, $y.Length)
    for ($i = 0; $i -lt $n; $i++) {
        $p = if ($i -lt $x.Length) { To-Num $x[$i] } else { 0 }
        $q = if ($i -lt $y.Length) { To-Num $y[$i] } else { 0 }
        if ($p -gt $q) { return $true }
        if ($p -lt $q) { return $false }
    }
    return $false
}

function Get-JsonValue([string]$json, [string]$key) {
    if ($json -cmatch ('"' + [regex]::Escape($key) + '"\s*:\s*"([^"]*)"')) { return $matches[1].Replace('\/', '/') }
    return ""
}

function Get-EsouiDetails($id) {
    $script:ESOUI_VERSION = ""; $script:ESOUI_DOWNLOAD = ""; $script:ESOUI_MD5 = ""
    $resp = (& curl.exe -s -f -m 30 -A $ESOUI_UA "$ESOUI_API/v3/game/ESO/filedetails/$id.json" 2>$null) -join ""
    if ($LASTEXITCODE -ne 0 -or !$resp) { return $false }
    $script:ESOUI_VERSION = Get-JsonValue $resp "UIVersion"
    $script:ESOUI_DOWNLOAD = Get-JsonValue $resp "UIDownload"
    $script:ESOUI_MD5 = (Get-JsonValue $resp "UIMD5").ToLowerInvariant()
    return ($script:ESOUI_VERSION -ne "" -and $script:ESOUI_DOWNLOAD -ne "")
}

function Invoke-EsouiDownload($id, $dest) {
    if (!(Get-EsouiDetails $id)) { return 1 }
    Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    & curl.exe -s -f -L -m 180 -A $ESOUI_UA -o $dest $script:ESOUI_DOWNLOAD 2>$null
    if ($LASTEXITCODE -ne 0) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue; return 1 }
    if ($script:ESOUI_MD5 -and (Get-Md5Hex $dest) -ne $script:ESOUI_MD5) {
        Log-Event "WARN" "ESOUI file $id failed its checksum, discarded."
        Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue; return 2
    }
    if (!(Test-ZipFile $dest)) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue; return 2 }
    return 0
}
