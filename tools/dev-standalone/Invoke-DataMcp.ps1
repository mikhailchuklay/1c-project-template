#Requires -Version 5.1
<#
.SYNOPSIS
    Универсальный клиент к 1c-data-mcp (HTTP-сервис hs/mcp, расширение OneMCP / APA_MCP)
    на DEV-базе автономного сервера.

.DESCRIPTION
    Вызывает инструменты live-базы по протоколу MCP (JSON-RPC поверх Streamable HTTP):
      vcexecutecode  — выполнить BSL-код   (значение возвращается через переменную Результат);
      vcexecutequery — выполнить запрос    (результат — текстовая таблица);
      validatequery  — проверить запрос    (без выполнения);
      vcloggetlasterror — последняя ошибка журнала регистрации за 24 ч.

    Переносимость: адрес и учётные данные читаются из .dev.env проекта
    (INFOBASE_PUBLISH_URL, IB_USER, IB_PASSWORD). Скрипт не содержит проектных
    значений — копируется в любой проект на том же ruleset/тулинге как есть.

    Особенности (см. .cursor/rules/functional-testing.mdc):
      * Basic-auth собирается из UTF-8-байт (кириллический логин иначе → 401).
      * bslcode/querytext по умолчанию схлопываются в одну строку: сервер инжектит
        payload в строковый литерал, экранируя кавычки, но НЕ переводы строк
        (\n → "Неопознанный оператор" или пустой результат). Отключить: -NoFlatten.

.PARAMETER Action
    code | query | validate-query | last-error | tools | raw

.PARAMETER Text
    Текст BSL-кода / запроса (для code, query, validate-query). Взаимоисключим с -File.

.PARAMETER File
    Путь к файлу с BSL-кодом / запросом (UTF-8). Взаимоисключим с -Text.

.PARAMETER Tool
    Имя инструмента для Action=raw.

.PARAMETER Arguments
    JSON-объект аргументов для Action=raw (по умолчанию '{}').

.PARAMETER Url
    Переопределить endpoint. По умолчанию: INFOBASE_PUBLISH_URL + 'hs/mcp'.

.PARAMETER User
    Переопределить логин. По умолчанию: IB_USER из .dev.env.

.PARAMETER Password
    Переопределить пароль. По умолчанию: IB_PASSWORD из .dev.env.

.PARAMETER EnvFile
    Путь к .dev.env. По умолчанию — в корне проекта (на два уровня выше скрипта).

.PARAMETER NoFlatten
    Не схлопывать переводы строк в payload (для серверов, поддерживающих многострочный ввод).

.EXAMPLE
    .\Invoke-DataMcp.ps1 tools

.EXAMPLE
    .\Invoke-DataMcp.ps1 code -Text 'Результат = Строка(ТекущаяДатаСеанса());'

.EXAMPLE
    .\Invoke-DataMcp.ps1 query -Text 'ВЫБРАТЬ КОЛИЧЕСТВО(*) КАК К ИЗ Справочник.Контрагенты'

.EXAMPLE
    .\Invoke-DataMcp.ps1 code -File .\build\probe.bsl
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('code', 'query', 'validate-query', 'last-error', 'tools', 'raw')]
    [string]$Action = 'tools',

    [string]$Text,
    [string]$File,

    [string]$Tool,
    [string]$Arguments = '{}',

    [string]$Url,
    [string]$User,
    [string]$Password,
    [string]$EnvFile,

    [switch]$NoFlatten
)

$ErrorActionPreference = 'Stop'

# --- .dev.env --------------------------------------------------------------
function Read-DotEnv {
    param([string]$Path)
    $map = @{}
    foreach ($line in (Get-Content -Path $Path -Encoding UTF8)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        $map[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
    }
    return $map
}

if (-not $EnvFile) {
    $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $EnvFile = Join-Path $projectRoot '.dev.env'
}
if (-not (Test-Path $EnvFile)) {
    throw ".dev.env не найден: $EnvFile. Укажите -EnvFile или задайте -Url/-User/-Password."
}
$dotenv = Read-DotEnv -Path $EnvFile

# --- endpoint & auth -------------------------------------------------------
if (-not $Url) {
    $base = $dotenv['INFOBASE_PUBLISH_URL']
    if (-not $base) { throw "INFOBASE_PUBLISH_URL не задан в $EnvFile; укажите -Url." }
    $Url = $base.TrimEnd('/') + '/hs/mcp'
}
if (-not $PSBoundParameters.ContainsKey('User'))     { $User = $dotenv['IB_USER'] }
if (-not $PSBoundParameters.ContainsKey('Password')) { $Password = $dotenv['IB_PASSWORD'] }

$baseHeaders = @{
    'Accept'               = 'application/json, text/event-stream'
    'MCP-Protocol-Version' = '2025-06-18'
}
if ($User) {
    $pairBytes = [Text.Encoding]::UTF8.GetBytes("$($User):$($Password)")
    $baseHeaders['Authorization'] = 'Basic ' + [Convert]::ToBase64String($pairBytes)
}

# --- payload ---------------------------------------------------------------
function Get-Payload {
    if ($Text -and $File) { throw "Укажите либо -Text, либо -File, но не оба." }
    $value = if ($File) { Get-Content -Path $File -Raw -Encoding UTF8 } else { $Text }
    if (-not $NoFlatten -and $value) {
        $value = ($value -replace "`r", ' ') -replace "`n", ' '
        $value = $value.Trim()
    }
    return $value
}

# --- JSON-RPC over Streamable HTTP ----------------------------------------
function Read-RpcContent {
    param($Response)
    $ct = [string]$Response.Headers['Content-Type']
    $raw = $Response.Content
    if ($ct -match 'text/event-stream') {
        $events = @()
        $buf = New-Object System.Collections.Generic.List[string]
        foreach ($line in ($raw -split "`n")) {
            $l = $line.TrimEnd("`r")
            if ($l -eq '') { if ($buf.Count) { $events += ($buf -join "`n"); $buf.Clear() }; continue }
            if ($l -match '^data:\s?(.*)$') { $buf.Add($Matches[1]) }
        }
        if ($buf.Count) { $events += ($buf -join "`n") }
        $payload = $null
        foreach ($e in $events) {
            try { $obj = $e | ConvertFrom-Json } catch { continue }
            if ($obj.PSObject.Properties.Name -contains 'result' -or
                $obj.PSObject.Properties.Name -contains 'error') { $payload = $obj }
        }
        return $payload
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return $raw | ConvertFrom-Json
}

function Send-Rpc {
    param([hashtable]$Headers, [hashtable]$Body)
    $json = $Body | ConvertTo-Json -Depth 20 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $resp = Invoke-WebRequest -Uri $Url -Method Post -Headers $Headers `
        -ContentType 'application/json' -Body $bytes -UseBasicParsing
    return $resp
}

# --- MCP handshake ---------------------------------------------------------
Write-Host "MCP endpoint: $Url" -ForegroundColor DarkGray

$initBody = @{
    jsonrpc = '2.0'; id = 1; method = 'initialize'
    params  = @{
        protocolVersion = '2025-06-18'
        capabilities    = @{}
        clientInfo      = @{ name = 'Invoke-DataMcp'; version = '1.0' }
    }
}
$initResp = Send-Rpc -Headers $baseHeaders -Body $initBody

$session = [string]$initResp.Headers['Mcp-Session-Id']
$headers = $baseHeaders.Clone()
if ($session) { $headers['Mcp-Session-Id'] = $session }

try { Send-Rpc -Headers $headers -Body @{ jsonrpc = '2.0'; method = 'notifications/initialized' } | Out-Null }
catch { }

# --- build & send the actual call -----------------------------------------
if ($Action -eq 'tools') {
    $callBody = @{ jsonrpc = '2.0'; id = 2; method = 'tools/list'; params = @{} }
}
else {
    switch ($Action) {
        'code'           { $name = 'vcexecutecode';  $toolArgs = @{ bslcode   = (Get-Payload) } }
        'query'          { $name = 'vcexecutequery'; $toolArgs = @{ querytext = (Get-Payload) } }
        'validate-query' { $name = 'validatequery';  $toolArgs = @{ querytext = (Get-Payload) } }
        'last-error'     { $name = 'vcloggetlasterror'; $toolArgs = @{} }
        'raw' {
            if (-not $Tool) { throw "Для Action=raw укажите -Tool." }
            $name = $Tool
            $toolArgs = @{}
            ($Arguments | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $toolArgs[$_.Name] = $_.Value }
        }
    }
    $callBody = @{ jsonrpc = '2.0'; id = 2; method = 'tools/call'; params = @{ name = $name; arguments = $toolArgs } }
}

$callResp = Send-Rpc -Headers $headers -Body $callBody
$obj = Read-RpcContent -Response $callResp

if ($null -eq $obj) { throw "Пустой ответ сервера (проверьте публикацию hs/mcp и Basic-auth)." }
if ($obj.PSObject.Properties.Name -contains 'error') {
    Write-Error ("JSON-RPC error {0}: {1}" -f $obj.error.code, $obj.error.message)
    exit 1
}

# --- print result ----------------------------------------------------------
if ($Action -eq 'tools') {
    $obj.result.tools | ForEach-Object { Write-Output $_.name }
}
else {
    $texts = foreach ($c in $obj.result.content) { if ($c.type -eq 'text') { $c.text } }
    Write-Output ($texts -join "`n")
    if ($obj.result.isError) { exit 1 }
}
