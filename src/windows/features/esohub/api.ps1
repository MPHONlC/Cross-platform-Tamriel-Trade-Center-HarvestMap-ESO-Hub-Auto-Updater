$ESOHUB_API = if ($env:LTTC_ESOHUB_API) { $env:LTTC_ESOHUB_API } else { "https://data.eso-hub.com" }
$ESOHUB_V2_UA = "ESO-Hub Client v2"
$ESOHUB_V2_VERSION = "0.2.23"
$ESOHUB_V1_UA = "ESOHubClient/1.0.9"
$ESOHUB_LANGS = @("en")
function Get-EsoHubLang {
    $l = "$([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName)".ToLower()
    if ($ESOHUB_LANGS -contains $l) { return $l }
    return "en"
}
$ESOHUB_LANG = Get-EsoHubLang
$ESOHUB_CF_PAGE = "https://eso-hub.com/$ESOHUB_LANG/user/profile"
$ESOHUB_LOGIN_PAGE = "https://eso-hub.com/$ESOHUB_LANG/client-token-login?code="
$ESOHUB_CF_ASK_SECONDS = 300
$ESOHUB_CODE_SECONDS = 300
$ESOHUB_CODE_POLL = 2
$ESOHUB_UA_WAIT = 30
$global:ESOHUB_CF_ASKED = $false
$global:ESOHUB_CF_HINT = ""
$global:ESOHUB_UA_SEEN = ""

function Test-EsoHubCfReady {
    return ([bool]$global:ESOHUB_CF_CLEARANCE -and [bool]$global:ESOHUB_CF_UA)
}

function Import-EsoHubCf {
    if (!$CONFIG_FILE -or !(Test-Path -LiteralPath $CONFIG_FILE)) { return }
    foreach ($line in [System.IO.File]::ReadAllLines($CONFIG_FILE)) {
        if ($line -match '^ESOHUB_CF_CLEARANCE=(.*)$') { $v = Unprotect-Secret ($matches[1].Trim().Trim('"')); if ($v) { $global:ESOHUB_CF_CLEARANCE = $v } }
        elseif ($line -match '^ESOHUB_CF_UA=(.*)$') { $v = Unprotect-Secret ($matches[1].Trim().Trim('"')); if ($v) { $global:ESOHUB_CF_UA = $v } }
    }
}

function Get-EsoHubUA($fallback) {
    if (Test-EsoHubCfReady) { return $global:ESOHUB_CF_UA }
    return $fallback
}

function Test-EsoHubCfHost($url) {
    $u = "$url"
    if ($u.StartsWith("$ESOHUB_API/", [StringComparison]::Ordinal)) { return $true }
    if ($u -cnotmatch '^https://([^/?#]*)') { return $false }
    $h = $matches[1]
    if ($h -match '[@:]') { return $false }
    return ($h -ceq "eso-hub.com" -or $h.EndsWith(".eso-hub.com", [StringComparison]::Ordinal))
}

function Get-EsoHubCfConfig($url) {
    if ((Test-EsoHubCfReady) -and (Test-EsoHubCfHost $url)) { return "header = `"Cookie: cf_clearance=$($global:ESOHUB_CF_CLEARANCE)`"" }
    return ""
}

function Invoke-EsoHubCurl($url, [string[]]$curlArgs, [string[]]$lines = @()) {
    $OutputEncoding = New-Object System.Text.ASCIIEncoding
    $cfg = (@($lines) + @(Get-EsoHubCfConfig $url) | Where-Object { $_ }) -join "`n"
    return ("$cfg`n" | & curl.exe -K - @curlArgs "$url" 2>$null)
}

function Get-EsoHubCleanCookie($v) {
    $v = "$v" -replace '\s', ''
    if ($v.StartsWith("Cookie:", [StringComparison]::Ordinal)) { $v = $v.Substring(7) }
    if ($v.StartsWith("cf_clearance=", [StringComparison]::Ordinal)) { $v = $v.Substring(13) }
    $v = $v.Split(';')[0]
    if ($v.Length -lt 20 -or $v -cnotmatch '^[A-Za-z0-9._~+/=-]+$') { return $null }
    return $v
}

function Get-EsoHubCleanUA($v) {
    $v = ("$v" -replace '[\r\n]', '').Trim()
    if ($v.Length -ge 2 -and ($v[0] -eq '"' -or $v[0] -eq "'")) { $v = $v.Substring(1) }
    if ($v.EndsWith('"') -or $v.EndsWith("'")) { $v = $v.Substring(0, $v.Length - 1) }
    if (!$v.StartsWith("Mozilla/", [StringComparison]::Ordinal)) { return $null }
    if ($v -match '["$`\\]') { return $null }
    return $v
}

function Test-EsoHubCfCanAsk {
    return (!$global:SILENT -and !$global:IS_TASK -and ![Console]::IsInputRedirected)
}

function Read-EsoHubCfAnswer([bool]$secret) {
    $typed = New-Object System.Text.StringBuilder
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $ESOHUB_CF_ASK_SECONDS) {
        if (![Console]::KeyAvailable) {
            Invoke-EsoHubIdle
            continue
        }
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Enter) { Write-Host ""; return $typed.ToString() }
        if ($key.Key -eq [ConsoleKey]::Backspace) {
            if ($typed.Length -gt 0) {
                [void]$typed.Remove($typed.Length - 1, 1)
                if (!$secret) { Write-Host -NoNewline "`b `b" }
            }
            continue
        }
        if ($key.KeyChar -ne [char]0) {
            [void]$typed.Append($key.KeyChar)
            if (!$secret) { Write-Host -NoNewline $key.KeyChar }
        }
    }
    return $null
}

function Invoke-EsoHubIdle {
    if ('System.Windows.Forms.Application' -as [type]) { [System.Windows.Forms.Application]::DoEvents() }
    Start-Sleep -Milliseconds 50
}

function Open-EsoHubUrl($url) {
    try { Start-Process $url } catch { }
}

function Get-EsoHubLoginCode {
    return [guid]::NewGuid().ToString()
}

function New-EsoHubTcpListener {
    $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $l.Start()
    return $l
}

function Read-EsoHubUaRequest($client, $path, $target) {
    $latin = [System.Text.Encoding]::GetEncoding(28591)
    $client.ReceiveTimeout = 5000
    $stream = $client.GetStream()
    $buf = New-Object byte[] 4096
    $ms = New-Object System.IO.MemoryStream
    $text = ""
    while ($ms.Length -lt 32768) {
        try { $n = $stream.Read($buf, 0, $buf.Length) } catch { break }
        if ($n -le 0) { break }
        $ms.Write($buf, 0, $n)
        $text = $latin.GetString($ms.ToArray())
        if ($text.Contains("`r`n`r`n")) { break }
    }
    $lines = @((($text -split "`r`n`r`n", 2)[0]) -split "`r`n")
    $hit = "$($lines[0])".StartsWith("GET $path ", [StringComparison]::Ordinal)
    $ua = ""
    foreach ($line in @($lines | Select-Object -Skip 1)) { if ($line -match '^(?i)user-agent:\s*(.*?)\s*$') { $ua = $matches[1] } }
    $reply = if ($hit) { "HTTP/1.1 302 Found`r`nLocation: $target`r`nCache-Control: no-store`r`nContent-Length: 0`r`nConnection: close`r`n`r`n" } else { "HTTP/1.1 404 Not Found`r`nContent-Length: 0`r`nConnection: close`r`n`r`n" }
    $bytes = $latin.GetBytes($reply)
    try { $stream.Write($bytes, 0, $bytes.Length) } catch { }
    $client.Close()
    if ($hit) { return $ua }
    return $null
}

function Wait-EsoHubUa($listener, $path, $target) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $ESOHUB_UA_WAIT) {
        if (!$listener.Pending()) { Invoke-EsoHubIdle; continue }
        $ua = Read-EsoHubUaRequest $listener.AcceptTcpClient() $path $target
        if ($null -ne $ua) { return $ua }
    }
    return $null
}

function Invoke-EsoHubBrowserOpen($page) {
    $global:ESOHUB_UA_SEEN = ""
    try {
        $listener = New-EsoHubTcpListener
    } catch {
        $why = ("$($_.Exception.Message)" -replace '[\r\n]+', ' ').Trim()
        Write-Host " $ESC[33m[-] The updater can't read your browser's User-Agent by itself: Windows didn't allow a local TcpListener on 127.0.0.1 ($why). Step 4 asks you to paste it.$ESC[0m"
        Open-EsoHubUrl $page
        return $false
    }
    try {
        $path = "/" + (Get-EsoHubLoginCode)
        Open-EsoHubUrl "http://127.0.0.1:$($listener.LocalEndpoint.Port)$path"
        $ua = Wait-EsoHubUa $listener $path $page
    } finally {
        $listener.Stop()
    }
    if ($null -ne $ua) {
        $clean = Get-EsoHubCleanUA $ua
        if ($clean) {
            $global:ESOHUB_UA_SEEN = $clean
            Write-Host " $ESC[0;32m[+] Login and Verify.$ESC[0m"
            return $true
        }
        Write-Host " $ESC[33m[-] Your browser sent a User-Agent the updater can't use. Step 4 asks you to paste it.$ESC[0m"
        return $false
    }
    Write-Host " $ESC[33m[-] Your browser didn't reach the updater's page within $ESOHUB_UA_WAIT seconds, so ESO-Hub opens directly. Step 4 asks you to paste the User-Agent.$ESC[0m"
    Open-EsoHubUrl $page
    return $false
}

function Invoke-EsoHubCfPrompt($page, $step) {
    if (!$page) { $page = $ESOHUB_CF_PAGE }
    if (!$step) { $step = "Opening $ESC[0;35m$page$ESC[0m in your browser $ESC[90m(opening it now)$ESC[0m wait until ESO-Hub's page shows." }
    Write-Host " $ESC[0;33m[-] ESO-Hub Human Verification Required:$ESC[0m"
    Write-Host "  $ESC[0;32m1)$ESC[0m $step"
    [void](Invoke-EsoHubBrowserOpen $page)
    Write-Host "  $ESC[0;32m2)$ESC[0m Press F12, then open $ESC[0;36mApplication$ESC[0m $ESC[90m(Chrome, Edge, Brave)$ESC[0m or $ESC[0;36mStorage$ESC[0m $ESC[90m(Firefox)$ESC[0m > $ESC[0;36mCookies$ESC[0m > https://eso-hub.com."
    Write-Host "  $ESC[0;32m3)$ESC[0m Copy the value of $ESC[0;36mcf_clearance$ESC[0m and paste it here."
    Write-Host "     $ESC[90mcf_clearance is ESO-Hub's proof that a human, not a bot, passed this check. The updater$ESC[0m"
    Write-Host "     $ESC[90msends it with each request so ESO-Hub answers with data instead of the check again. It$ESC[0m"
    Write-Host "     $ESC[90mstays on this PC and is sent only to eso-hub.com.$ESC[0m"
    Write-Host -NoNewline " $ESC[0;34mcf_clearance $ESC[90m(hidden while you paste, Enter skips)$ESC[0;34m: $ESC[0m"
    $ck = Read-EsoHubCfAnswer $true
    if ($null -eq $ck) {
        Write-Host ""
        Write-Host " $ESC[90mNo answer, so ESO-Hub is skipped this time.$ESC[0m"
        Log-Event "WARN" "ESO-Hub browser check skipped: no cf_clearance entered within $([int]($ESOHUB_CF_ASK_SECONDS / 60)) minutes; the updater continues."
        return $false
    }
    if (!$ck) {
        Write-Host " $ESC[90mSkipped.$ESC[0m"
        return $false
    }
    $ck = Get-EsoHubCleanCookie $ck
    if (!$ck) {
        Write-Host " $ESC[31m[-] That isn't a cf_clearance value. Copy the Value column of the cf_clearance row.$ESC[0m"
        return $false
    }
    if ($global:ESOHUB_UA_SEEN) {
        $ua = $global:ESOHUB_UA_SEEN
    } else {
        Write-Host "  $ESC[0;32m4)$ESC[0m In the same DevTools window open $ESC[0;36mConsole$ESC[0m, type $ESC[0;36mnavigator.userAgent$ESC[0m, press Enter and copy the text it shows."
        Write-Host -NoNewline " $ESC[0;34mUser-Agent: $ESC[0m"
        $ua = Read-EsoHubCfAnswer $false
        if ($null -eq $ua) {
            Write-Host ""
            Write-Host " $ESC[90mNo answer, so ESO-Hub is skipped this time.$ESC[0m"
            Log-Event "WARN" "ESO-Hub browser check skipped: no cf_clearance entered within $([int]($ESOHUB_CF_ASK_SECONDS / 60)) minutes; the updater continues."
            return $false
        }
        $ua = Get-EsoHubCleanUA $ua
        if (!$ua) {
            Write-Host " $ESC[31m[-] That isn't a browser User-Agent. It starts with Mozilla/5.0.$ESC[0m"
            return $false
        }
    }
    $global:ESOHUB_CF_CLEARANCE = $ck; $global:ESOHUB_CF_UA = $ua; $global:CONFIG_CHANGED = $true
    Write-Host " $ESC[0;32m[+] Saved ($($ck.Length) characters). The updater only sends it to eso-hub.com.$ESC[0m"
    Log-Event "INFO" "ESO-Hub browser check saved (cf_clearance and User-Agent)."
    return $true
}

function Invoke-EsoHubCfAskNow {
    if ($global:ESOHUB_CF_ASKED) {
        $global:ESOHUB_CF_HINT = "The updater asks for ESO-Hub's browser check again the next time it starts."
        return $false
    }
    $global:ESOHUB_CF_ASKED = $true
    if (!(Test-EsoHubCfCanAsk)) {
        $global:ESOHUB_CF_HINT = "Start the updater in a terminal or run --setup to refresh ESO-Hub's cf_clearance; a running copy picks it up next cycle."
        return $false
    }
    $global:ESOHUB_CF_HINT = ""
    return (Invoke-EsoHubCfPrompt)
}

function Format-EsoHubField($v) {
    if ($null -eq $v) { return "" }
    return ("$v" -replace '[|\t\r\n]', ' ')
}

function ConvertFrom-EsoHubV2($text) {
    $out = New-Object System.Collections.Generic.List[string]
    try { $data = $text | ConvertFrom-Json } catch { return ,$out.ToArray() }
    if ($null -eq $data -or $null -eq $data.addons) { return ,$out.ToArray() }
    foreach ($a in @($data.addons)) {
        $folder = Format-EsoHubField $a.folder_name
        if (!$folder) { continue }
        $file = Format-EsoHubField $a.file
        $id = if ($file -match '([0-9]+)$') { $matches[1] } else { Format-EsoHubField $a.id }
        if (!$id) { $id = "0" }
        $ver = ""
        if ($null -ne $a.version) {
            $ver = Format-EsoHubField $a.version.integer
            if (!$ver) { $ver = Format-EsoHubField $a.version.string }
        }
        $ep = ""; $sv = ""
        if ($null -ne $a.transfer) {
            $ep = Format-EsoHubField $a.transfer.endpoint
            $sv = (@($a.transfer.sv_file_names) | ForEach-Object { Format-EsoHubField $_ } | Where-Object { $_ }) -join ';'
        }
        $out.Add("$id|$folder|$ver|$file|$(Format-EsoHubField $a.checksum)|$ep|$sv")
    }
    return ,$out.ToArray()
}

function ConvertFrom-EsoHubV1($text) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in @("$text".Replace('{"folder_name"', "`n{`"folder_name`"") -split "`n" | Where-Object { $_ -match '"folder_name"' })) {
        $fname = if ($line -match '"folder_name":"([^"]+)"') { $matches[1] } else { "" }
        if (!$fname) { continue }
        $sv = if ($line -match '"sv_file_name":"([^"]+)"') { $matches[1] } else { "" }
        $ep = if ($line -match '"endpoint":"([^"]+)"') { $matches[1].Replace('\', '') } else { "" }
        $file = if ($line -match '"file":"([^"]+)"') { $matches[1].Replace('\', '') } else { "" }
        $ver = if ($line -match '"version":\{[^}]*"string":"([^"]+)"') { $matches[1] } else { "" }
        $id = if ($file -match '([0-9]+)$') { $matches[1] } else { "0" }
        $out.Add("$id|$fname|$ver|$file||$ep|$sv")
    }
    return ,$out.ToArray()
}

function Invoke-EsoHubRequest($body, $head, $url, [string[]]$curlArgs, [string[]]$lines = @()) {
    Remove-Item -LiteralPath $body, $head -Force -ErrorAction SilentlyContinue
    $code = (Invoke-EsoHubCurl $url (@("-s", "-m", "30", "-D", $head, "-o", $body, "-w", '%{http_code}') + $curlArgs) $lines) -join ""
    if (!$code) { $code = "000" }
    return $code
}

function Test-EsoHubChallenge($head) {
    return ((Test-Path -LiteralPath $head) -and [bool](Select-String -LiteralPath $head -Pattern '^cf-mitigated: *challenge' -Quiet))
}

function Get-EsoHubReason($code, $head) {
    if (!$code -or $code -eq "000") { return "no connection" }
    if (Test-EsoHubChallenge $head) { return "HTTP $code (Cloudflare challenge)" }
    return "HTTP $code"
}

function Get-EsoHubAuthArgs {
    if ($global:EH_USER_TOKEN) { return @("-H", "Authorization: Bearer $global:EH_USER_TOKEN") }
    return @()
}

function Get-EsoHubAddons {
    $global:ESOHUB_RECORDS = @(); $global:ESOHUB_API_USED = ""; $global:ESOHUB_FAIL = ""; $global:ESOHUB_BLOCKED = $false
    if (!(Test-Path -LiteralPath $TEMP_DIR_ROOT)) { New-Item -ItemType Directory -Force -Path $TEMP_DIR_ROOT | Out-Null }
    $body = Join-Path $TEMP_DIR_ROOT "lttc_eh_list.json"; $head = Join-Path $TEMP_DIR_ROOT "lttc_eh_list.head"
    $v2 = @("-H", "User-Agent: $(Get-EsoHubUA $ESOHUB_V2_UA)", "-H", "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION", "-H", "Accept: application/json")
    $listUrl = "$ESOHUB_API/v2/api/get-addon-versions"

    $code = Invoke-EsoHubRequest $body $head $listUrl ($v2 + @(Get-EsoHubAuthArgs))
    if ($global:EH_USER_TOKEN -and $code -eq "401" -and !(Select-String -LiteralPath $head -Pattern '^cf-mitigated' -Quiet -ErrorAction SilentlyContinue)) {
        Log-Event "WARN" "ESO-Hub did not accept the saved token (HTTP 401); asking again without it."
        $code = Invoke-EsoHubRequest $body $head $listUrl $v2
    }
    if ($code -eq "200" -and (Test-Path -LiteralPath $body)) { $global:ESOHUB_RECORDS = ConvertFrom-EsoHubV2 ([System.IO.File]::ReadAllText($body)) }
    if (@($global:ESOHUB_RECORDS).Count -gt 0) {
        $global:ESOHUB_API_USED = "v2"
        Remove-Item -LiteralPath $body, $head -Force -ErrorAction SilentlyContinue
        return $true
    }
    $whyV2 = if ($code -eq "200") { "HTTP 200 without an add-on list" } else { Get-EsoHubReason $code $head }

    $code = Invoke-EsoHubRequest $body $head "$ESOHUB_API/v1/api/get-addon-versions" @("-X", "POST", "-H", "User-Agent: $(Get-EsoHubUA $ESOHUB_V1_UA)", "-d", "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en")
    if ($code -eq "200" -and (Test-Path -LiteralPath $body)) { $global:ESOHUB_RECORDS = ConvertFrom-EsoHubV1 ([System.IO.File]::ReadAllText($body)) }
    if (@($global:ESOHUB_RECORDS).Count -gt 0) {
        $global:ESOHUB_API_USED = "v1"
        Remove-Item -LiteralPath $body, $head -Force -ErrorAction SilentlyContinue
        Log-Event "WARN" "ESO-Hub v2 add-on list failed ($whyV2); the v1 list answered."
        return $true
    }
    $whyV1 = if ($code -eq "200") { "HTTP 200 without an add-on list" } else { Get-EsoHubReason $code $head }
    Remove-Item -LiteralPath $body, $head -Force -ErrorAction SilentlyContinue

    $global:ESOHUB_FAIL = "v2: $whyV2, v1: $whyV1"
    $global:ESOHUB_BLOCKED = $global:ESOHUB_FAIL.Contains("Cloudflare")
    return $false
}

function Get-EsoHubLocalVersion($dir, $name) {
    foreach ($ext in @("txt", "addon")) {
        $f = Join-Path $dir "$name.$ext"
        if (!(Test-Path -LiteralPath $f)) { continue }
        foreach ($l in [System.IO.File]::ReadAllLines($f)) {
            if ($l -match 'IntVersion:[ \t]*([^ \t\r]*)') { return $matches[1] }
        }
        return ""
    }
    return ""
}

function Test-EsoHubNewer($srv, $loc) {
    if (!$srv) { return $false }
    if ("$srv$loc" -match '[^0-9]') { return ("$srv" -cne "$loc") }
    if (!$loc) { return $true }
    return ([decimal]::Parse($srv) -gt [decimal]::Parse($loc))
}

function Get-EsoHubFile($url, $out, $want) {
    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    $auth = @(Get-EsoHubAuthArgs)
    Invoke-EsoHubCurl $url (@("-s", "-f", "-L", "-m", "60", "-H", "User-Agent: $(Get-EsoHubUA $ESOHUB_V2_UA)", "-H", "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION") + $auth + @("-o", $out)) | Out-Null
    if ($LASTEXITCODE -ne 0) { Invoke-EsoHubCurl $url @("-s", "-f", "-L", "-m", "30", "-A", (Get-EsoHubUA $ESOHUB_V1_UA), "-o", $out) | Out-Null }
    if ($LASTEXITCODE -ne 0 -and $RAND_UA) { & curl.exe -s -f -L -m 30 -A "$RAND_UA" -o $out "$url" 2>$null }
    if ($LASTEXITCODE -ne 0) { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue; return 1 }
    if ($want) {
        $got = try { (Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash } catch { "" }
        if ($got -and $got.ToLowerInvariant() -ne "$want".ToLowerInvariant()) {
            Log-Event "ERROR" "ESO-Hub download $url failed its checksum (expected $want, got $($got.ToLowerInvariant()))."
            Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
            return 2
        }
    }
    if (!(Test-ZipFile $out)) { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue; return 1 }
    return 0
}

function Send-EsoHubUploadV2($url, [string[]]$files) {
    $found = @($files | ForEach-Object { Join-Path $SAVED_VAR_DIR $_ } | Where-Object { Test-Path -LiteralPath $_ })
    if ($found.Count -eq 0) { return $false }
    $zip = Join-Path $TEMP_DIR_ROOT "lttc_eh_upload.zip"
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    try {
        Compress-Archive -LiteralPath $found -DestinationPath $zip -Force -ErrorAction Stop
    } catch {
        Log-Event "WARN" "ESO-Hub v2 upload could not pack $($files -join ', ')."
        return $false
    }
    $auth = @(Get-EsoHubAuthArgs)
    $name = [guid]::NewGuid().ToString()
    Invoke-EsoHubCurl $url (@("-s", "-f", "-m", "60", "-H", "User-Agent: $(Get-EsoHubUA $ESOHUB_V2_UA)", "-H", "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION", "-H", "Accept: application/json") + $auth + @("-F", "archive=@$zip;filename=$name.zip;type=application/zip", "-F", "server=live")) | Out-Null
    $ok = $LASTEXITCODE -eq 0
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    return $ok
}

function Send-EsoHubUploadV1($url, [string[]]$files) {
    foreach ($f in $files) {
        Invoke-EsoHubCurl "$url`?user_token=$global:EH_USER_TOKEN" @("-s", "-f", "-m", "60", "-A", (Get-EsoHubUA $ESOHUB_V1_UA), "-F", "file=@$(Join-Path $SAVED_VAR_DIR $f)") | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
    }
    return $true
}

function Send-EsoHubUpload($api, $endpoint, $send, $all) {
    $url = if ($endpoint -match '^https?://') { $endpoint } else { "$ESOHUB_API$endpoint" }
    $sendFiles = [string[]]@("$send".Split(';') | Where-Object { $_ })
    $allFiles = [string[]]@("$all".Split(';') | Where-Object { $_ })
    if ($sendFiles.Count -eq 0) { return $false }
    if ($allFiles.Count -eq 0) { $allFiles = $sendFiles }
    if ($api -eq "v1") {
        if (Send-EsoHubUploadV1 $url $sendFiles) { return $true }
        return (Send-EsoHubUploadV2 $url $allFiles)
    }
    if (Send-EsoHubUploadV2 $url $allFiles) { return $true }
    return (Send-EsoHubUploadV1 $url $sendFiles)
}

function Get-EsoHubLoginReason($code, $head, $body) {
    if (!$code -or $code -eq "000") { return "no connection to ESO-Hub" }
    if (Test-EsoHubChallenge $head) { return "ESO-Hub's server answered with a Cloudflare check" }
    $msg = ""
    if ((Test-Path -LiteralPath $body) -and [System.IO.File]::ReadAllText($body) -match '"message" *: *"([^"]*)"') {
        $msg = $matches[1] -replace '[^\x20-\x7E]', '' -replace '\\', ''
        if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 120) }
    }
    $note = if ($msg) { " ($msg)" } else { "" }
    if ($code -in @("200", "401", "403", "422")) { return "ESO-Hub did not accept that username and password$note" }
    return "ESO-Hub answered HTTP $code$note"
}

function Get-EsoHubTokenFrom($body) {
    if (!(Test-Path -LiteralPath $body)) { return "" }
    if ([System.IO.File]::ReadAllText($body) -match '"token" *: *"([^"]*)"') { return $matches[1] }
    return ""
}

function Get-EsoHubToken($user, $pass) {
    $global:ESOHUB_TOKEN = ""; $global:ESOHUB_LOGIN_FAIL = ""; $global:ESOHUB_LOGIN_BLOCKED = $false
    $body = [System.IO.Path]::GetTempFileName(); $head = [System.IO.Path]::GetTempFileName()
    try {
        $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${user}:$pass"))
        $code = Invoke-EsoHubRequest $body $head "$ESOHUB_API/v2/api/request-token" @("-X", "POST", "-H", "User-Agent: $(Get-EsoHubUA $ESOHUB_V2_UA)", "-H", "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION", "-H", "Accept: application/json") @("header = `"Authorization: Basic $basic`"")
        $token = Get-EsoHubTokenFrom $body
        $whyV2 = Get-EsoHubLoginReason $code $head $body
        if (!$token) {
            $form = "username=$([Uri]::EscapeDataString("$user"))&password=$([Uri]::EscapeDataString("$pass"))"
            $code = Invoke-EsoHubRequest $body $head "$ESOHUB_API/v1/api/login" @("-X", "POST", "-H", "User-Agent: $(Get-EsoHubUA $ESOHUB_V1_UA)", "--data-urlencode", "client_system=$SYS_ID", "--data-urlencode", "client_version=1.0.9", "--data-urlencode", "client_version_int=1009", "--data-urlencode", "lang=en") @("data = `"$form`"")
            $token = Get-EsoHubTokenFrom $body
            if (!$token) {
                if ($whyV2.Contains("Cloudflare")) {
                    $global:ESOHUB_LOGIN_FAIL = Get-EsoHubLoginReason $code $head $body
                    $global:ESOHUB_LOGIN_BLOCKED = $global:ESOHUB_LOGIN_FAIL.Contains("Cloudflare")
                } else {
                    $global:ESOHUB_LOGIN_FAIL = $whyV2
                }
            }
        }
        $basic = $null; $form = $null
    } finally {
        Remove-Item -LiteralPath $body, $head -Force -ErrorAction SilentlyContinue
    }
    $global:ESOHUB_TOKEN = "$token"
    return $global:ESOHUB_TOKEN
}

function Invoke-EsoHubCodePoll($code, $body, $head) {
    return (Invoke-EsoHubRequest $body $head "$ESOHUB_API/v2/api/request-token-with-code" @("-X", "POST", "-H", "User-Agent: $(Get-EsoHubUA $ESOHUB_V2_UA)", "-H", "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION", "-H", "Accept: application/json", "-H", "Content-Type: application/json") @('data = "{\"code\":\"' + $code + '\"}"'))
}

function Wait-EsoHubCodePoll($seconds) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $seconds) {
        $key = $null
        try { if ([Console]::KeyAvailable) { $key = [Console]::ReadKey($true) } } catch { }
        if ($null -ne $key -and $key.Key -eq [ConsoleKey]::Enter) { return $true }
        Invoke-EsoHubIdle
    }
    return $false
}

function Get-EsoHubWaitText($seconds) {
    if ($seconds -ge 120) { return "$([int][Math]::Floor($seconds / 60)) minutes" }
    return "$seconds seconds"
}

function Get-EsoHubJsonText($body, $field, $max) {
    if (!(Test-Path -LiteralPath $body)) { return "" }
    if ([System.IO.File]::ReadAllText($body) -notmatch ('"' + $field + '" *: *"([^"]*)"')) { return "" }
    $v = $matches[1] -replace '[^\x20-\x7E]', '' -replace '\\', ''
    if ($v.Length -gt $max) { $v = $v.Substring(0, $max) }
    return $v
}

function Get-EsoHubCodeAnswer($code, $body) {
    if (!$code -or $code -eq "000") { return "no connection" }
    $msg = Get-EsoHubJsonText $body "message" 120
    if ($msg) { return "HTTP $code, $msg" }
    return "HTTP $code"
}

function Invoke-EsoHubCodeLogin {
    $global:ESOHUB_TOKEN = ""; $global:ESOHUB_LOGIN_USER = ""; $global:ESOHUB_LOGIN_FAIL = ""
    $code = Get-EsoHubLoginCode
    $body = [System.IO.Path]::GetTempFileName(); $head = [System.IO.Path]::GetTempFileName()
    try {
        $url = "$ESOHUB_LOGIN_PAGE$code"
        $http = Invoke-EsoHubCodePoll $code $body $head
        if ($http -eq "000") {
            $global:ESOHUB_LOGIN_FAIL = "no connection to ESO-Hub"
            return $false
        }
        if (Test-EsoHubChallenge $head) {
            if (!(Invoke-EsoHubCfPrompt $url "Opening ESO-Hub's login page in your browser $ESC[90m(opening it now)$ESC[0m, log in and link this device, then stay on that tab for the next steps.")) {
                $global:ESOHUB_LOGIN_FAIL = "the updater can't pick up the Login Token without cf_clearance, because ESO-Hub's data server answers with a Cloudflare check"
                return $false
            }
        } else {
            Write-Host " $ESC[0;33mLog in to ESO-Hub in your browser $ESC[90m(opening it now)$ESC[0;33m and link this device when ESO-Hub asks.$ESC[0m"
            Open-EsoHubUrl $url
        }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Host " $ESC[36mWaiting for ESO-Hub to confirm the login $ESC[90m(up to $(Get-EsoHubWaitText $ESOHUB_CODE_SECONDS), Enter stops waiting)$ESC[36m...$ESC[0m"
        while ($true) {
            $http = Invoke-EsoHubCodePoll $code $body $head
            $token = Get-EsoHubTokenFrom $body
            if ($token) {
                $global:ESOHUB_TOKEN = $token
                $global:ESOHUB_LOGIN_USER = Get-EsoHubJsonText $body "username" 60
                break
            }
            if (Test-EsoHubChallenge $head) {
                $global:ESOHUB_LOGIN_FAIL = "ESO-Hub's server still answers with a Cloudflare check; copy cf_clearance from the browser that opened, on this PC and network"
                break
            }
            if ($sw.Elapsed.TotalSeconds -ge $ESOHUB_CODE_SECONDS) {
                $global:ESOHUB_LOGIN_FAIL = "ESO-Hub didn't confirm the login within $(Get-EsoHubWaitText $ESOHUB_CODE_SECONDS) (last answer: $(Get-EsoHubCodeAnswer $http $body))"
                break
            }
            if (Wait-EsoHubCodePoll $ESOHUB_CODE_POLL) {
                $global:ESOHUB_LOGIN_FAIL = "you stopped waiting"
                break
            }
        }
        $token = $null
    } finally {
        Remove-Item -LiteralPath $body, $head -Force -ErrorAction SilentlyContinue
    }
    return [bool]$global:ESOHUB_TOKEN
}
