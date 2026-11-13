<#
.SYNOPSIS
  Instala o APK na maquininha de desenvolvimento ligada por USB e abre o app.

.EXAMPLE
  .\tool\deploy.ps1
  .\tool\deploy.ps1 -Logs
#>
[CmdletBinding()]
param([switch]$Logs)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$apk = 'build\app\outputs\flutter-apk\app-release.apk'
$pkg = 'br.com.mobizweb.pos'
if (-not (Test-Path $apk)) { throw 'Rode .\tool\build.ps1 antes.' }

adb devices -l
adb install -r $apk
if ($LASTEXITCODE -ne 0) { throw 'A instalação falhou. Veja "Instalação na maquininha" em docs\stone.md.' }
adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
Write-Host "Instalado e aberto: $pkg" -ForegroundColor Green

if ($Logs) {
    $appPid = (adb shell pidof -s $pkg).Trim()
    adb logcat --pid=$appPid
}
