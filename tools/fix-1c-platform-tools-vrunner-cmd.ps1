#Requires -Version 5.1
# Fix Platform Tools: cmd quoting for vrunner tasks on Windows.
# Re-run after upgrading yellow-hammer.1c-platform-tools.
$ErrorActionPreference = 'Stop'

$extRoot = Join-Path $env:USERPROFILE '.cursor\extensions'
$pkg = Get-ChildItem $extRoot -Directory -Filter 'yellow-hammer.1c-platform-tools-*-universal' |
    Sort-Object Name -Descending |
    Select-Object -First 1

if (-not $pkg) {
    Write-Error 'Extension yellow-hammer.1c-platform-tools not found'
}

$extensionJs = Join-Path $pkg.FullName 'out\extension.js'
$content = Get-Content $extensionJs -Raw -Encoding UTF8

$old = 'const argsString = escapeCommandArgs(args);'
$new = 'const argsString = escapeCommandArgs(args, process.platform === "win32" ? "cmd" : void 0);'

if ($content.Contains($new)) {
    Write-Host ('Already patched: ' + $extensionJs)
    exit 0
}

if (-not $content.Contains($old)) {
    Write-Error ('Pattern not found in ' + $extensionJs)
}

$content = $content.Replace($old, $new)
Set-Content -Path $extensionJs -Value $content -Encoding UTF8 -NoNewline
Write-Host ('Patched: ' + $extensionJs)
Write-Host 'Reload Window in Cursor.'
