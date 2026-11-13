<#
.SYNOPSIS
  Gera o APK de release para a maquininha Stone (Windows).

.EXAMPLE
  .\tool\build.ps1
  .\tool\build.ps1 -Loja minhaloja -SuportePhone '(11) 4000-0000' -SuporteEmail suporte@exemplo.com
#>
[CmdletBinding()]
param(
    [string]$Loja,
    [string]$Dominio,
    [string]$SuporteNome,
    [string]$SuportePhone,
    [string]$SuporteEmail,
    [string]$SuporteSite,
    [switch]$SemTestes
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value -split '\+')[0].Trim()
$defines = @("--dart-define=MOBIZ_APP_VERSION=$version")
$map = [ordered]@{
    MOBIZ_STORE = $Loja; MOBIZ_DOMAIN = $Dominio; MOBIZ_SUPPORT_NAME = $SuporteNome
    MOBIZ_SUPPORT_PHONE = $SuportePhone; MOBIZ_SUPPORT_EMAIL = $SuporteEmail; MOBIZ_SUPPORT_SITE = $SuporteSite
}
foreach ($key in $map.Keys) { if ($map[$key]) { $defines += "--dart-define=$key=$($map[$key])" } }

flutter pub get
if (-not $SemTestes) {
    flutter analyze;  if ($LASTEXITCODE -ne 0) { throw 'flutter analyze apontou problemas.' }
    flutter test;     if ($LASTEXITCODE -ne 0) { throw 'Os testes falharam.' }
}

# Só ARM (terminais Stone não usam x86); símbolos de depuração fora do APK.
flutter build apk --release --target-platform android-arm,android-arm64 --split-debug-info=build/symbols @defines
if ($LASTEXITCODE -ne 0) { throw 'O build falhou.' }

$apk = 'build\app\outputs\flutter-apk\app-release.apk'
$mb = [math]::Round((Get-Item $apk).Length / 1MB, 1)
Write-Host "`nAPK: $apk ($mb MB — limite da Stone: 70 MB)" -ForegroundColor Green
if ($mb -gt 70) { throw 'O APK passou de 70 MB.' }
if (-not (Test-Path 'android\key.properties')) {
    Write-Warning 'Sem android\key.properties: APK assinado com a chave de DEBUG (teste). Para homologar, veja docs\stone.md.'
}
