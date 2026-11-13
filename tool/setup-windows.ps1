<#
.SYNOPSIS
  Prepara um PC Windows para compilar o Mobiz POS e instalar na maquininha Stone.

.DESCRIPTION
  Instala (se faltar) Git, JDK 17, Flutter e o Android SDK; clona o projeto em
  C:\projetos\mobizweb-pos-flutter; baixa as dependências e roda os testes.
  Pode ser executado mais de uma vez: o que já existe é mantido.

  Abra o PowerShell (não precisa ser administrador) e rode:

    Set-ExecutionPolicy -Scope Process Bypass -Force
    irm https://raw.githubusercontent.com/ericallyson/mobizweb-comanda-flutter/main/tool/setup-windows.ps1 | iex

  ou, com o repositório já clonado:  .\tool\setup-windows.ps1

.NOTES
  Versões fixadas para bater com o que foi usado no desenvolvimento.
#>
[CmdletBinding()]
param(
    [string]$ProjectDir = 'C:\projetos\mobizweb-pos-flutter',
    [string]$ToolsDir   = 'C:\dev',
    [string]$RepoUrl    = 'https://github.com/ericallyson/mobizweb-comanda-flutter.git',
    [string]$Branch     = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # Invoke-WebRequest fica MUITO mais rápido

$FlutterVersion = '3.50.0'
$CmdlineTools   = '16111833'
$AndroidApi     = '36'
$BuildTools     = '36.0.0'
$NdkVersion     = '28.2.13676358'

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Have($cmd)  { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Add-UserPath($dir) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($current -split ';') -notcontains $dir) {
        [Environment]::SetEnvironmentVariable('Path', "$current;$dir".Trim(';'), 'User')
    }
    if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$env:Path;$dir" }
}

function Set-UserEnv($name, $value) {
    [Environment]::SetEnvironmentVariable($name, $value, 'User')
    Set-Item -Path "Env:$name" -Value $value
}

function Get-Zip($url, $destination) {
    $zip = Join-Path $env:TEMP ([IO.Path]::GetFileName($url))
    Write-Host "    baixando $url"
    Invoke-WebRequest -Uri $url -OutFile $zip
    Write-Host "    extraindo em $destination"
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Expand-Archive -Path $zip -DestinationPath $destination -Force
    Remove-Item $zip
}

New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

# ── Git e JDK (winget) ──────────────────────────────────────────────────────
Step 'Git'
if (Have git) { Write-Host '    já instalado' }
elseif (Have winget) { winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements }
else { throw 'Instale o Git (https://git-scm.com/download/win) e rode de novo.' }

Step 'JDK 17'
$javaHome = $env:JAVA_HOME
if (-not $javaHome -or -not (Test-Path "$javaHome\bin\java.exe")) {
    $found = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) {
        if (-not (Have winget)) { throw 'Instale o JDK 17 (https://adoptium.net) e rode de novo.' }
        winget install --id EclipseAdoptium.Temurin.17.JDK -e --accept-source-agreements --accept-package-agreements
        $found = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -Filter 'jdk-17*' | Select-Object -First 1
    }
    $javaHome = $found.FullName
}
Set-UserEnv 'JAVA_HOME' $javaHome
Add-UserPath "$javaHome\bin"
Write-Host "    JAVA_HOME=$javaHome"

# ── Flutter ─────────────────────────────────────────────────────────────────
Step "Flutter $FlutterVersion"
$flutterDir = Join-Path $ToolsDir 'flutter'
if (-not (Test-Path "$flutterDir\bin\flutter.bat")) {
    Get-Zip "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip" $ToolsDir
} else { Write-Host '    já instalado' }
Add-UserPath "$flutterDir\bin"

# ── Android SDK ─────────────────────────────────────────────────────────────
Step 'Android SDK'
$sdk = Join-Path $ToolsDir 'android-sdk'
$sdkmanager = "$sdk\cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkmanager)) {
    $tmp = Join-Path $env:TEMP 'mobiz-cmdline-tools'
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Get-Zip "https://dl.google.com/android/repository/commandlinetools-win-${CmdlineTools}_latest.zip" $tmp
    New-Item -ItemType Directory -Force -Path "$sdk\cmdline-tools" | Out-Null
    Move-Item "$tmp\cmdline-tools" "$sdk\cmdline-tools\latest"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Set-UserEnv 'ANDROID_HOME' $sdk
Set-UserEnv 'ANDROID_SDK_ROOT' $sdk
Add-UserPath "$sdk\platform-tools"

Write-Host '    aceitando licenças e instalando plataforma, build-tools, NDK e adb'
$yes = ('y' + [Environment]::NewLine) * 40
$yes | & $sdkmanager --licenses | Out-Null
& $sdkmanager --install 'platform-tools' "platforms;android-$AndroidApi" "build-tools;$BuildTools" "ndk;$NdkVersion"
if ($LASTEXITCODE -ne 0) { throw 'O sdkmanager falhou. Confira a conexão e rode de novo.' }

& "$flutterDir\bin\flutter.bat" config --android-sdk $sdk --no-analytics | Out-Null

# ── Projeto ─────────────────────────────────────────────────────────────────
Step "Projeto em $ProjectDir"
if (Test-Path "$ProjectDir\pubspec.yaml") {
    Write-Host '    já existe — atualizando'
    git -C $ProjectDir pull --ff-only
} elseif ($PSScriptRoot -and (Test-Path "$PSScriptRoot\..\pubspec.yaml") -and ((Resolve-Path "$PSScriptRoot\..").Path -eq $ProjectDir)) {
    Write-Host '    usando o repositório atual'
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $ProjectDir) | Out-Null
    if ($Branch) { git clone --branch $Branch $RepoUrl $ProjectDir } else { git clone $RepoUrl $ProjectDir }
}

Push-Location $ProjectDir
try {
    Step 'Dependências, análise e testes'
    flutter pub get
    flutter analyze
    flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Os testes falharam.' }

    Step 'flutter doctor'
    flutter doctor
} finally { Pop-Location }

Write-Host "`nAmbiente pronto." -ForegroundColor Green
Write-Host @"

Próximos passos (abra um NOVO PowerShell para pegar o PATH):
  cd $ProjectDir
  .\tool\build.ps1                  # gera o APK (build\app\outputs\flutter-apk\app-release.apk)
  .\tool\deploy.ps1                 # instala na maquininha ligada por USB
  .\tool\deploy.ps1 -Logs           # instala e mostra os logs

Leia docs\stone.md antes de instalar na maquininha (assinatura de debug por fabricante).
"@
