#Requires -Version 5.1
<#
.SYNOPSIS
    Чтение параметров из .dev.env (или .dev.env.example как fallback).
    Кроссплатформенно: Windows PowerShell 5.1 и PowerShell 7+ (Windows/Linux/macOS).
#>

# Определение ОС: работает и в 5.1 (где $IsWindows отсутствует → $null), и в pwsh 7+.
$script:OnWindows = if ($null -ne $IsWindows) { [bool]$IsWindows } else { $true }

function Get-ProjectRootFromScript {
    param([string]$ScriptRoot)
    return Split-Path (Split-Path $ScriptRoot -Parent) -Parent
}

function Read-DevEnvFile {
    param(
        [string]$ProjectRoot,
        [string]$EnvFile
    )

    $result = @{}
    $candidates = @()

    if ($EnvFile) {
        $candidates += $EnvFile
    } else {
        $candidates += (Join-Path $ProjectRoot '.dev.env')
        $candidates += (Join-Path $ProjectRoot '.dev.env.example')
    }

    $path = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $path) {
        return $result
    }

    Get-Content -Path $path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#')) { return }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { return }
        $key = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim()
        $result[$key] = $value
    }

    return $result
}

function Get-DevEnvValue {
    param(
        [hashtable]$Env,
        [string]$Key,
        [string]$Default = ''
    )

    if ($Env.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace($Env[$Key])) {
        return $Env[$Key]
    }
    return $Default
}

function Get-PlatformExe {
    param(
        [hashtable]$Env,
        # Базовое имя БЕЗ расширения: 'ibcmd' | 'ibsrv'. '.exe' добавляется на Windows.
        [string]$ExeName
    )

    $platformPath = Get-DevEnvValue -Env $Env -Key 'PLATFORM_PATH'
    if ([string]::IsNullOrWhiteSpace($platformPath)) {
        throw "PLATFORM_PATH не задан в .dev.env. Заполните путь к каталогу платформы 1С."
    }

    # Windows: <PLATFORM_PATH>\bin\*.exe; Linux/macOS: обычно прямо <PLATFORM_PATH>/*
    # (напр. /opt/1cv8/x86_64/<ver>/). Проверяем оба размещения.
    $name = if ($script:OnWindows) { "$ExeName.exe" } else { $ExeName }
    $candidates = @(
        (Join-Path $platformPath $name),
        (Join-Path (Join-Path $platformPath 'bin') $name)
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    throw "Не найден '$name' в '$platformPath' (и в '$platformPath/bin')."
}

function Get-StandaloneDefaults {
    param(
        [string]$ProjectRoot,
        [hashtable]$Env
    )

    $projectSlug = Split-Path $ProjectRoot -Leaf
    $httpBase = Get-DevEnvValue -Env $Env -Key 'STANDALONE_HTTP_BASE' -Default "/$projectSlug-dev"
    if (-not $httpBase.StartsWith('/')) {
        $httpBase = "/$httpBase"
    }

    $port = Get-DevEnvValue -Env $Env -Key 'STANDALONE_PORT' -Default '8314'
    $serverName = "$projectSlug-dev"
    $publishUrl = Get-DevEnvValue -Env $Env -Key 'INFOBASE_PUBLISH_URL'
    if ([string]::IsNullOrWhiteSpace($publishUrl)) {
        $publishUrl = "http://localhost:$port$httpBase/"
    }
    if (-not $publishUrl.EndsWith('/')) {
        $publishUrl += '/'
    }

    $standaloneRoot = Join-Path (Join-Path $ProjectRoot 'build') 'standalone'
    $dataPath = Get-DevEnvValue -Env $Env -Key 'STANDALONE_DATA_PATH'
    if ([string]::IsNullOrWhiteSpace($dataPath)) {
        $dataPath = Join-Path $standaloneRoot 'data'
    }

    $configPath = Get-DevEnvValue -Env $Env -Key 'IBCMD_CONFIG'
    if ([string]::IsNullOrWhiteSpace($configPath)) {
        $configPath = Join-Path $standaloneRoot 'config.yml'
    }

    $ibPath = Get-DevEnvValue -Env $Env -Key 'INFOBASE_PATH'
    if ([string]::IsNullOrWhiteSpace($ibPath)) {
        $ibPath = Join-Path (Join-Path $ProjectRoot 'build') 'ib'
    }

    return [ordered]@{
        ProjectSlug    = $projectSlug
        HttpBase       = $httpBase
        Port           = $port
        ServerName     = $serverName
        PublishUrl     = $publishUrl
        StandaloneRoot = $standaloneRoot
        DataPath       = $dataPath
        ConfigPath     = $configPath
        IbPath         = $ibPath
    }
}
