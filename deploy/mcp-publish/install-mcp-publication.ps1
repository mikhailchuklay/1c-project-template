#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deploy additional IIS MCP publication for {PROJECT_SLUG}.
.PARAMETER ServiceName
    HTTP service metadata name: mcp or APA_MCP.
.PARAMETER McpUser
    Infobase user for built-in auth in default.vrd.
.PARAMETER McpPassword
    Infobase password for built-in auth in default.vrd.
.PARAMETER DiagnosticNoAuth
    Deploy without embedded IB credentials (expect HTTP 401 if publication structure is valid).
.PARAMETER DiagnosticAllExtHttp
    Deploy Documents-style publication with all extension HTTP services (broadest diagnostic).
.PARAMETER DiagnosticCopyMain
    Deploy exact copy of working /{PROJECT_SLUG} default.vrd with base path changed only.
#>
param(
    [ValidateSet('mcp', 'APA_MCP')]
    [string] $ServiceName = 'APA_MCP',

    [string] $McpUser,

    [string] $McpPassword,

    [switch] $DiagnosticNoAuth,

    [switch] $DiagnosticAllExtHttp,

    [switch] $DiagnosticCopyMain
)

$ErrorActionPreference = 'Stop'

$needsCredentials = -not $DiagnosticNoAuth -and -not $DiagnosticAllExtHttp -and -not $DiagnosticCopyMain
if ($needsCredentials -and ([string]::IsNullOrWhiteSpace($McpUser) -or [string]::IsNullOrWhiteSpace($McpPassword))) {
    throw 'Production deploy requires -McpUser and -McpPassword (dedicated IB user for MCP publication; do not commit real values to the repo).'
}

$srcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dstDir = '{IIS_WWWROOT}\{PROJECT_SLUG}-mcp'
$baseUrl = 'http://{PROD_HOST}/{PROJECT_SLUG}-mcp'
$mcpUrl = "$baseUrl/hs/mcp"

$vrdSource = if ($DiagnosticCopyMain) {
    Join-Path $srcDir 'default-copy-main-noauth.vrd'
} elseif ($DiagnosticAllExtHttp) {
    Join-Path $srcDir 'default-all-ext-http.vrd'
} elseif ($DiagnosticNoAuth) {
    Join-Path $srcDir 'default-noauth.vrd'
} elseif ($ServiceName -eq 'APA_MCP') {
    Join-Path $srcDir 'default-APA_MCP.vrd'
} else {
    Join-Path $srcDir 'default.vrd'
}

if (-not (Test-Path $vrdSource)) {
    throw "Publication file not found: $vrdSource"
}

$vrdContent = Get-Content -Raw -Path $vrdSource -Encoding UTF8

# Inject IB credentials into ib="..." when not already present (single quotes per 1C convention).
if (-not $DiagnosticNoAuth -and -not $DiagnosticAllExtHttp -and -not $DiagnosticCopyMain -and $vrdContent -notmatch 'Usr=') {
    $ibReplacement = 'ib="Srvr=&quot;{SERVER}:{PORT}&quot;;Ref=&quot;{PROJECT_SLUG}&quot;;Usr=''' + $McpUser + ''';Pwd=''' + $McpPassword + ''';"'
    $vrdContent = $vrdContent -replace 'ib="Srvr=&quot;{SERVER}:{PORT}&quot;;Ref=&quot;{PROJECT_SLUG}&quot;;"', $ibReplacement
}

# Legacy fallback: separate usr element in old templates.
$usrReplacement = '<usr name="' + $McpUser + '" pwd="' + $McpPassword + '"/>'
$vrdContent = $vrdContent -replace '<usr name="[^"]*" pwd="[^"]*"/>', $usrReplacement

function Register-IisPublication {
    param(
        [string] $SiteName,
        [string] $AppPath,
        [string] $PhysicalPath
    )

    $appcmd = Join-Path $env:windir 'system32\inetsrv\appcmd.exe'
    if (-not (Test-Path $appcmd)) {
        throw 'appcmd.exe not found. Register the publication manually in IIS Manager as an Application.'
    }

    $appId = "$SiteName$AppPath"
    & $appcmd delete app $appId 2>$null | Out-Null
    & $appcmd add app /site.name:$SiteName /path:$AppPath /physicalPath:$PhysicalPath | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) {
        throw "appcmd add app failed with exit code $LASTEXITCODE"
    }

    & $appcmd set app $appId /enabled:true | Out-Null
    & $appcmd recycle apppool /apppool.name:DefaultAppPool 2>$null | Out-Null
}

New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
$vrdPath = Join-Path $dstDir 'default.vrd'
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($vrdPath, $vrdContent, $utf8NoBom)
Copy-Item -Path (Join-Path $srcDir 'web.config') -Destination $dstDir -Force

Write-Host "Publication copied to $dstDir"
Write-Host 'Registering IIS application...'
Register-IisPublication -SiteName 'Default Web Site' -AppPath '/{PROJECT_SLUG}-mcp' -PhysicalPath $dstDir
Write-Host "HTTP service: $ServiceName, IB user: $McpUser"
Write-Host "Probing $mcpUrl ..."

function Get-HttpCode([string]$Url) {
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop
        return [int]$response.StatusCode
    } catch {
        if ($_.Exception.Response) {
            return [int]$_.Exception.Response.StatusCode
        }
        throw $_
    }
}

$rootCode = Get-HttpCode "$baseUrl/"
$code = Get-HttpCode $mcpUrl
Write-Host "HTTP root $rootCode, /hs/mcp $code"

switch ($code) {
    401 {
        Write-Warning 'HTTP 401. Publication is alive. Check IB user/password and HTTP service rights.'
        if ($DiagnosticNoAuth -or $DiagnosticAllExtHttp -or ($DiagnosticCopyMain -and $rootCode -in 200,401)) {
            Write-Host 'Diagnostic: non-500 response means default.vrd structure is valid.'
            exit 0
        }
        exit 1
    }
    403 {
        Write-Warning "HTTP 403. User $McpUser has no rights on HTTP service $ServiceName."
        exit 1
    }
    404 {
        Write-Warning "HTTP 404. HTTP service $ServiceName not found. Check service name and OneMCP.cfe."
        exit 1
    }
    500 {
        if ($DiagnosticCopyMain -and $rootCode -eq 200) {
            Write-Host 'DiagnosticCopyMain: root publication works (HTTP 200). Folder and IIS are OK.'
            exit 0
        }
        Write-Warning 'HTTP 500. Folder exists but IIS may not treat it as an Application. Script now runs appcmd add app; if 500 persists, run iisreset and retry -DiagnosticCopyMain.'
        exit 1
    }
    { $_ -in 200, 201, 204, 400, 405, 406 } {
        Write-Host "Endpoint reachable without HTTP Basic auth. MCP URL: $mcpUrl"
    }
    default {
        Write-Warning "Unexpected HTTP $code for $mcpUrl"
        exit 1
    }
}
