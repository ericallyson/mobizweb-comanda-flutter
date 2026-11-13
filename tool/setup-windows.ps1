<#
.SYNOPSIS
  Prepara um PC Windows para compilar o Mobiz POS e instalar na maquininha Stone.

.DESCRIPTION
  Instala (se faltar) Git, JDK 17, Flutter e o Android SDK; clona o projeto em
  C:\projetos\mobizweb-pos-flutter; baixa as dependências e roda os testes.
  Pode ser executado mais de uma vez: o que já existe é mantido.

  Com o repositório clonado, abra o PowerShell (não precisa ser
  administrador) na pasta do projeto e rode:

    Set-ExecutionPolicy -Scope Process Bypass -Force
    .\tool\setup-windows.ps1

  Rodando de outro lugar, o script clona o projeto em -ProjectDir.

.NOTES
  Versões fixadas para bater com o que foi usado no desenvolvimento.
#>
[CmdletBinding()]
param(
    [string]$ProjectDir = 'C:\projetos\mobizweb-pos-flutter',
    [string]$ToolsDir   = 'C:\dev',
    [string]$RepoUrl    = 'https://github.com/ericallyson/mobizweb-comanda-flutter.git',
    [string]$Branch     = '',
    # Só instala/conserta o Android SDK (usado pelo maquininha.ps1).
    [switch]$SomenteSdk
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # Invoke-WebRequest fica MUITO mais rápido

$FlutterVersion = '3.50.0'
# cmdline-tools 10.0. NÃO subir sem testar no Windows: a partir da 23.0 o
# sdkmanager.bat virou um atalho para o "Android CLI" que lê os argumentos com
# %1/shift, e o cmd parte "ndk;28.2.13676358" no ponto e vírgula ("Package ndk
# not found"). O próprio Flutter chama o sdkmanager nesse formato no build.
$CmdlineTools   = '9862592'
$AndroidApi     = '36'
$BuildTools     = '36.0.0'
$NdkVersion     = '28.2.13676358'

$NoWindows = ($env:OS -eq 'Windows_NT')
$Bat = if ($NoWindows) { '.bat' } else { '' }
$Exe = if ($NoWindows) { '.exe' } else { '' }

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Have($cmd)  { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Add-UserPath($dir) {
    $sep = [IO.Path]::PathSeparator
    if ($NoWindows) {
        $current = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (($current -split $sep) -notcontains $dir) {
            [Environment]::SetEnvironmentVariable('Path', "$current$sep$dir".Trim($sep), 'User')
        }
    }
    if (($env:Path -split $sep) -notcontains $dir) { $env:Path = "$env:Path$sep$dir" }
}

function Set-UserEnv($name, $value) {
    [Environment]::SetEnvironmentVariable($name, $value, 'User')
    Set-Item -Path "Env:$name" -Value $value
}

function Get-Zip($url, $destination) {
    $zip = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetFileName($url))
    Write-Host "    baixando $url"
    Invoke-WebRequest -Uri $url -OutFile $zip
    Write-Host "    extraindo em $destination"
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    # O tar do Windows 10+ extrai o zip do Flutter em 1-2 min; o
    # Expand-Archive do PowerShell 5.1 pode levar mais de 10.
    # (o tar do System32 é o bsdtar, que abre zip; o do Git não abre.)
    $tar = if ($NoWindows) { Join-Path $env:SystemRoot 'System32\tar.exe' } else { $null }
    if ($tar -and (Test-Path $tar)) {
        & $tar -xf $zip -C $destination
        if ($LASTEXITCODE -ne 0) { throw "Falha ao extrair $zip" }
    } else {
        Expand-Archive -Path $zip -DestinationPath $destination -Force
    }
    Remove-Item $zip
}

New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

# ── Git e JDK (winget) ──────────────────────────────────────────────────────
if (-not $SomenteSdk) {
    Step 'Git'
    if (Have git) { Write-Host '    já instalado' }
    elseif (Have winget) { winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements }
    else { throw 'Instale o Git (https://git-scm.com/download/win) e rode de novo.' }
}

Step 'JDK 17'
$javaHome = $env:JAVA_HOME
if (-not $javaHome -or -not (Test-Path (Join-Path (Join-Path $javaHome 'bin') "java$Exe"))) {
    $found = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) {
        if (-not (Have winget)) { throw 'Instale o JDK 17 (https://adoptium.net) e rode de novo.' }
        winget install --id EclipseAdoptium.Temurin.17.JDK -e --accept-source-agreements --accept-package-agreements
        $found = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -Filter 'jdk-17*' | Select-Object -First 1
    }
    $javaHome = $found.FullName
}
Set-UserEnv 'JAVA_HOME' $javaHome
Add-UserPath (Join-Path $javaHome 'bin')
Write-Host "    JAVA_HOME=$javaHome"

# ── Flutter ─────────────────────────────────────────────────────────────────
$flutterDir = Join-Path $ToolsDir 'flutter'
if (-not $SomenteSdk) {
    Step "Flutter $FlutterVersion"
    if (-not (Test-Path "$flutterDir\bin\flutter.bat")) {
        Get-Zip "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip" $ToolsDir
    } else { Write-Host '    já instalado' }
    Add-UserPath "$flutterDir\bin"
}

# ── Android SDK ─────────────────────────────────────────────────────────────
function Install-AndroidSdk {
    Step 'Android SDK'
    $sdk = Join-Path $ToolsDir 'android-sdk'
    $latest = Join-Path (Join-Path $sdk 'cmdline-tools') 'latest'
    $sdkmanager = Join-Path (Join-Path $latest 'bin') "sdkmanager$Bat"

    # Instalação anterior com o sdkmanager novo (o que parte "ndk;versão"):
    # troca pela versão que funciona.
    if ((Test-Path $sdkmanager) -and (Select-String -Path $sdkmanager -Pattern 'deprecated' -Quiet)) {
        Write-Host '    trocando o sdkmanager incompatível pela versão que funciona'
        Remove-Item $latest -Recurse -Force
    }
    if (-not (Test-Path $sdkmanager)) {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) 'mobiz-cmdline-tools'
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        $plataforma = if ($NoWindows) { 'win' } else { 'linux' }
        Get-Zip "https://dl.google.com/android/repository/commandlinetools-$plataforma-${CmdlineTools}_latest.zip" $tmp
        New-Item -ItemType Directory -Force -Path (Join-Path $sdk 'cmdline-tools') | Out-Null
        Move-Item (Join-Path $tmp 'cmdline-tools') $latest
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    Set-UserEnv 'ANDROID_HOME' $sdk
    Set-UserEnv 'ANDROID_SDK_ROOT' $sdk
    Add-UserPath (Join-Path $sdk 'platform-tools')

    # Pacote -> arquivo que prova que ele está instalado.
    $pacotes = [ordered]@{
        'platform-tools'                 = "platform-tools/adb$Exe"
        "platforms;android-$AndroidApi"  = "platforms/android-$AndroidApi/android.jar"
        "build-tools;$BuildTools"        = "build-tools/$BuildTools/aapt2$Exe"
        "ndk;$NdkVersion"                = "ndk/$NdkVersion/source.properties"
    }
    $faltam = @($pacotes.Keys | Where-Object { -not (Test-Path (Join-Path $sdk $pacotes[$_])) })
    if ($faltam.Count -eq 0) {
        Write-Host '    plataforma, build-tools, NDK e adb já instalados'
    } else {
        Write-Host "    instalando: $($faltam -join ', ')  (o NDK tem ~700 MB)"
        $yes = ('y' + [Environment]::NewLine) * 40
        $yes | & $sdkmanager "--sdk_root=$sdk" --licenses | Out-Null
        & $sdkmanager "--sdk_root=$sdk" --install @faltam
        # Confere no disco: o código de saída do sdkmanager não é confiável.
        $faltam = @($pacotes.Keys | Where-Object { -not (Test-Path (Join-Path $sdk $pacotes[$_])) })
        if ($faltam.Count -gt 0) {
            throw "O Android SDK ficou incompleto. Não foi instalado: $($faltam -join ', '). Confira a internet e rode de novo."
        }
    }

    $flutter = Join-Path (Join-Path (Join-Path $ToolsDir 'flutter') 'bin') "flutter$Bat"
    if (Test-Path $flutter) { & $flutter config --android-sdk $sdk --no-analytics | Out-Null }
}

if ($SomenteSdk) {
    Install-AndroidSdk
    Write-Host "`nAndroid SDK pronto." -ForegroundColor Green
    return
}

Install-AndroidSdk

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
  .\tool\maquininha.ps1             # Gertec/Positivo: acha a chave do fabricante, compila e instala
  .\tool\build.ps1                  # só gera o APK (build\app\outputs\flutter-apk\app-release.apk)
  .\tool\deploy.ps1 -Logs           # instala o último APK e mostra os logs

Detalhes em docs\stone.md.
"@
