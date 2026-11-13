<#
.SYNOPSIS
  Faz tudo para o app rodar na maquininha de desenvolvimento: acha a chave do
  fabricante, configura a assinatura, compila, instala por USB e abre o app.

.DESCRIPTION
  Terminais de debug da Gertec e da Positivo só aceitam APK assinado com a
  chave (.jks) do fabricante, que a Stone fornece. Este script:

    1. garante o ambiente (roda o setup-windows.ps1 se faltar Flutter/adb);
    2. procura a .jks e o arquivo de senhas na pasta de chaves;
    3. confere a chave e grava android\key.properties (fora do git);
    4. compila o APK assinado com ela;
    5. instala na maquininha ligada por USB e abre o app.

  As senhas nunca são mostradas na tela.

.EXAMPLE
  .\tool\maquininha.ps1
  .\tool\maquininha.ps1 -Chaves D:\stone\gertec -Logs
  .\tool\maquininha.ps1 -VarianteDebug        # se o terminal recusar o build de release
  .\tool\maquininha.ps1 -Diagnostico          # o que há no terminal (apps da Stone, deeplinks)

.NOTES
  Para HOMOLOGAR troque android\key.properties pela sua keystore própria
  (docs\stone.md). A chave do fabricante é só para o terminal de debug.
#>
[CmdletBinding()]
param(
    # Pasta com a .jks do fabricante (e, se houver, o .properties com as senhas).
    [string]$Chaves = 'C:\projetos\chaves',
    # Compila a variante de debug assinada com a mesma chave (plano B).
    [switch]$VarianteDebug,
    # Só configura a chave; não compila nem instala.
    [switch]$SomenteChave,
    # Compila mas não instala.
    [switch]$SemInstalar,
    # Depois de instalar, fica mostrando os logs do app.
    [switch]$Logs,
    # Não compila nem instala: mostra o que a maquininha tem (Android, apps da
    # Stone e se os deeplinks de pagamento/impressão respondem).
    [switch]$Diagnostico
)

$ErrorActionPreference = 'Stop'
$Projeto = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Pacote  = 'br.com.mobizweb.pos'

function Passo($texto) { Write-Host "`n==> $texto" -ForegroundColor Cyan }
function Info($texto)  { Write-Host "    $texto" }
function Falha($texto) { Write-Host "`nERRO: $texto" -ForegroundColor Red; exit 1 }
function Tem($comando) { [bool](Get-Command $comando -ErrorAction SilentlyContinue) }

# Roda um programa externo capturando a saída sem que o stderr vire exceção
# (no Windows PowerShell 5.1, "2>&1" com ErrorActionPreference=Stop explode).
function Rodar {
    param([string]$Programa, [string[]]$Argumentos)
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $saida = & $Programa @Argumentos 2>&1 | ForEach-Object { "$_" }
        $script:Codigo = $LASTEXITCODE
        return $saida
    } finally { $ErrorActionPreference = $anterior }
}

function Somar-Path($pasta) {
    if ($pasta -and (Test-Path $pasta) -and (($env:Path -split [IO.Path]::PathSeparator) -notcontains $pasta)) {
        $env:Path = "$pasta$([IO.Path]::PathSeparator)$env:Path"
    }
}

# ── Diagnóstico do terminal ─────────────────────────────────────────────────
function Diagnosticar {
    Passo 'Diagnóstico da maquininha'
    [void](Rodar 'adb' @('start-server'))
    $aparelhos = @(Rodar 'adb' @('devices') | Where-Object { $_ -match "`tdevice\s*$" })
    if ($aparelhos.Count -ne 1) { Falha "Esperava 1 maquininha ligada por USB; o adb vê $($aparelhos.Count)." }
    $prop = { param($nome) ((Rodar 'adb' @('shell', 'getprop', $nome)) -join '').Trim() }
    Info "Modelo:  $(& $prop 'ro.product.manufacturer') $(& $prop 'ro.product.model')"
    Info "Android: $(& $prop 'ro.build.version.release') (API $(& $prop 'ro.build.version.sdk'))"
    Info "CPU:     $(& $prop 'ro.product.cpu.abilist')"

    Write-Host "`n    Apps da Stone instalados:"
    $pacotes = @(Rodar 'adb' @('shell', 'pm', 'list', 'packages') | Where-Object { $_ -match 'stone' } | Sort-Object)
    if ($pacotes.Count -eq 0) { Info '  (nenhum pacote com "stone" no nome)' }
    foreach ($p in $pacotes) {
        $nome = ($p -replace '^package:', '').Trim()
        $versao = (Rodar 'adb' @('shell', 'dumpsys', 'package', $nome) | Where-Object { $_ -match 'versionName=' } | Select-Object -First 1)
        Info "  $nome  $(("$versao").Trim())"
    }

    Write-Host "`n    Quem atende cada deeplink:"
    foreach ($uri in 'payment-app://pay', 'cancel-app://cancel', 'printer-app://print', 'reprinter-app://reprint') {
        $r = @(Rodar 'adb' @('shell', 'cmd', 'package', 'query-activities', '--brief', '-a', 'android.intent.action.VIEW', '-d', $uri) |
            Where-Object { $_ -match '/' })
        $quem = if ($r.Count -gt 0) { ($r | ForEach-Object { $_.Trim() }) -join ', ' } else { 'NINGUÉM (deeplink não disponível neste terminal)' }
        Info "  $uri  ->  $quem"
    }
    Write-Host "`nCopie o texto acima se precisar de ajuda." -ForegroundColor Green
}

# ── 1. Ambiente ─────────────────────────────────────────────────────────────
function Preparar-Ambiente {
    # Onde o setup-windows.ps1 instala; cobre o terminal aberto antes do setup.
    if (-not $env:ANDROID_HOME -and (Test-Path 'C:\dev\android-sdk')) { $env:ANDROID_HOME = 'C:\dev\android-sdk' }
    Somar-Path 'C:\dev\flutter\bin'
    if ($env:ANDROID_HOME) { Somar-Path (Join-Path $env:ANDROID_HOME 'platform-tools') }
    if ($env:JAVA_HOME)    { Somar-Path (Join-Path $env:JAVA_HOME 'bin') }
    if (-not (Tem keytool)) {
        $jdk = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -Filter 'jdk-*' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($jdk) { $env:JAVA_HOME = $jdk.FullName; Somar-Path (Join-Path $jdk.FullName 'bin') }
    }
}

Passo 'Ambiente'
Preparar-Ambiente
$precisa = @('flutter', 'keytool')
if ($Diagnostico -or (-not $SomenteChave -and -not $SemInstalar)) { $precisa += 'adb' }
$faltando = @($precisa | Where-Object { -not (Tem $_) })
if ($faltando.Count -gt 0) {
    Info "Faltando: $($faltando -join ', '). Rodando o setup do ambiente (demora na primeira vez)..."
    & (Join-Path $PSScriptRoot 'setup-windows.ps1') -ProjectDir $Projeto
    Preparar-Ambiente
    $faltando = @($precisa | Where-Object { -not (Tem $_) })
    if ($faltando.Count -gt 0) { Falha "Ainda falta: $($faltando -join ', '). Feche e abra o PowerShell e rode de novo." }
}
Info 'Flutter, JDK e adb encontrados.'
if ($Diagnostico) { Diagnosticar; exit 0 }

# Android SDK instalado pelo nosso setup (C:\dev\android-sdk): confere e
# conserta. Cobre a instalação que ficou sem o NDK por causa do sdkmanager
# novo, que não entende "ndk;versão" no Windows. Rápido quando está completo.
if (-not $SomenteChave -and $env:ANDROID_HOME -and ((Split-Path $env:ANDROID_HOME -Leaf) -eq 'android-sdk')) {
    & (Join-Path $PSScriptRoot 'setup-windows.ps1') -SomenteSdk -ToolsDir (Split-Path $env:ANDROID_HOME -Parent)
    Preparar-Ambiente
}

# ── 2. Chave do fabricante ──────────────────────────────────────────────────
Passo "Chave do fabricante em $Chaves"
if (-not (Test-Path $Chaves)) { Falha "A pasta $Chaves não existe. Informe a pasta certa com -Chaves." }

$keystores = @(Get-ChildItem -Path $Chaves -Recurse -File | Where-Object { $_.Extension -in '.jks', '.keystore', '.p12' })
if ($keystores.Count -eq 0) {
    $achados = (Get-ChildItem -Path $Chaves -Recurse -File | Select-Object -First 12 | ForEach-Object { $_.Name }) -join ', '
    Falha "Nenhuma chave (.jks) em $Chaves. Arquivos encontrados: $achados"
}
$keystore = $keystores | Where-Object { $_.Name -match 'gertec' } | Select-Object -First 1
if (-not $keystore) {
    if ($keystores.Count -gt 1) {
        Falha ("Há mais de uma chave em $Chaves e nenhuma com 'gertec' no nome: " +
            (($keystores | ForEach-Object { $_.Name }) -join ', ') + '. Deixe só a do seu terminal na pasta.')
    }
    $keystore = $keystores[0]
}
Info "Chave: $($keystore.Name)"

# Senhas: do .properties que acompanha a chave (storePassword/keyAlias/keyPassword).
$dados = @{}
$propriedades = @(Get-ChildItem -Path $Chaves -Recurse -File -Filter '*.properties')
$preferido = $propriedades | Where-Object { $_.DirectoryName -eq $keystore.DirectoryName } | Select-Object -First 1
if (-not $preferido) { $preferido = $propriedades | Select-Object -First 1 }
if ($preferido) {
    Info "Senhas: $($preferido.Name)"
    foreach ($linha in Get-Content -LiteralPath $preferido.FullName) {
        if ($linha -match '^\s*([A-Za-z_.]+)\s*[=:]\s*(.*?)\s*$' -and $linha -notmatch '^\s*[#!]') {
            $dados[$Matches[1].ToLower()] = $Matches[2]
        }
    }
}

function Pedir($rotulo, [switch]$Secreto) {
    if ($Secreto) {
        $seguro = Read-Host -Prompt "    $rotulo" -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    }
    return (Read-Host -Prompt "    $rotulo").Trim()
}

$senhaStore = $dados['storepassword']
$alias      = $dados['keyalias']
$senhaChave = $dados['keypassword']
# Marcador de exemplo ("<store-password>") não é senha.
foreach ($nome in 'senhaStore', 'alias', 'senhaChave') {
    $valor = Get-Variable $nome -ValueOnly
    if ($valor -match '^<.*>$') { Set-Variable $nome $null }
}
if (-not $senhaStore) { Info 'Senha da keystore não encontrada em arquivo.'; $senhaStore = Pedir 'Senha da keystore (storePassword)' -Secreto }

# Confere a senha e descobre o alias dentro da própria chave.
$env:MOBIZ_KS_PASS = $senhaStore
$lista = Rodar 'keytool' @('-list', '-keystore', $keystore.FullName, '-storepass:env', 'MOBIZ_KS_PASS')
if ($script:Codigo -ne 0) {
    $env:MOBIZ_KS_PASS = $null
    $motivo = ($lista | Where-Object { $_ -match 'keytool|error|erro|exception' -and $_ -notmatch 'JAVA_TOOL_OPTIONS' } | Select-Object -First 2) -join ' '
    Falha "Não foi possível abrir a chave (senha da keystore incorreta?). $motivo"
}
$aliases = @($lista | Where-Object { $_ -match '^([^,]+),.*(PrivateKeyEntry|Entrada|entry)' } | ForEach-Object { ($_ -split ',')[0].Trim() })
if (-not $alias) {
    if ($aliases.Count -eq 1) { $alias = $aliases[0]; Info "Alias encontrado na chave: $alias" }
    else { Info "Aliases na chave: $($aliases -join ', ')"; $alias = Pedir 'Alias (keyAlias)' }
} elseif ($aliases.Count -gt 0 -and ($aliases -notcontains $alias.ToLower()) -and ($aliases -notcontains $alias)) {
    $env:MOBIZ_KS_PASS = $null
    Falha "O alias '$alias' não existe na chave. Aliases disponíveis: $($aliases -join ', ')"
}
if (-not $senhaChave) { $senhaChave = $senhaStore }   # o comum é serem iguais
$env:MOBIZ_KS_PASS = $null
Info 'Chave conferida (senha e alias corretos).'

# android\key.properties: é o arquivo que o Gradle lê. Sem BOM (o Java não
# aceita) e com "\" escapada. O arquivo está no .gitignore.
$destino = Join-Path (Join-Path $Projeto 'android') 'key.properties'
$escapar = { param($v) $v -replace '\\', '\\' }
$conteudo = @(
    '# Gerado por tool\maquininha.ps1 - chave do FABRICANTE (terminal de debug).'
    '# Para homologar, troque pela sua keystore propria. Nunca versionar.'
    "storeFile=$($keystore.FullName -replace '\\', '/')"
    "storePassword=$(& $escapar $senhaStore)"
    "keyAlias=$(& $escapar $alias)"
    "keyPassword=$(& $escapar $senhaChave)"
    'signDebug=true'
)
if (Test-Path $destino) {
    $atual = Get-Content -LiteralPath $destino -Raw
    if ($atual -notmatch [regex]::Escape(($keystore.FullName -replace '\\', '/'))) {
        Copy-Item -LiteralPath $destino -Destination "$destino.anterior" -Force
        Info 'Havia outro key.properties: guardado como key.properties.anterior'
    }
}
[IO.File]::WriteAllLines($destino, $conteudo, (New-Object Text.UTF8Encoding($false)))
Info 'android\key.properties gravado.'
if ($SomenteChave) { Write-Host "`nChave configurada." -ForegroundColor Green; exit 0 }

# ── 3. Compilar ─────────────────────────────────────────────────────────────
Set-Location $Projeto
$versao = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value -split '\+')[0].Trim()
$tipo = if ($VarianteDebug) { 'debug' } else { 'release' }
Passo "Compilando o APK ($tipo) - alguns minutos na primeira vez"
flutter pub get
if ($LASTEXITCODE -ne 0) { Falha 'flutter pub get falhou.' }
if ($VarianteDebug) {
    flutter build apk --debug "--dart-define=MOBIZ_APP_VERSION=$versao"
} else {
    flutter build apk --release --target-platform android-arm,android-arm64 --split-debug-info=build/symbols "--dart-define=MOBIZ_APP_VERSION=$versao"
}
if ($LASTEXITCODE -ne 0) { Falha 'O build falhou. Veja as mensagens acima.' }

$apk = Join-Path $Projeto "build\app\outputs\flutter-apk\app-$tipo.apk"
if (-not (Test-Path $apk)) { Falha "APK não encontrado em $apk" }
$mb = [math]::Round((Get-Item $apk).Length / 1MB, 1)
Info "APK: $apk ($mb MB)"

# Confere com QUAL chave o APK saiu assinado.
$apksigner = $null
if ($env:ANDROID_HOME) {
    $apksigner = Get-ChildItem (Join-Path $env:ANDROID_HOME 'build-tools') -Recurse -Filter 'apksigner.bat' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($apksigner) {
    $assinatura = Rodar $apksigner.FullName @('verify', '--print-certs', '--min-sdk-version', '21', $apk)
    $dono = ($assinatura | Where-Object { $_ -match 'certificate DN' } | Select-Object -First 1)
    if ($dono) { Info "Assinado por: $(($dono -split 'DN:')[-1].Trim())" }
    if ($dono -match 'Android Debug') { Falha 'O APK saiu com a chave de debug comum, não com a do fabricante.' }
}
if ($SemInstalar) { Write-Host "`nAPK pronto." -ForegroundColor Green; exit 0 }

# ── 4. Instalar na maquininha ───────────────────────────────────────────────
Passo 'Maquininha (USB)'
[void](Rodar 'adb' @('start-server'))
$linhas = @(Rodar 'adb' @('devices') | Where-Object { $_ -match "`t" })
$prontos = @($linhas | Where-Object { $_ -match "`tdevice\s*$" })
if ($prontos.Count -eq 0) {
    if ($linhas | Where-Object { $_ -match 'unauthorized' }) {
        Falha 'A maquininha apareceu mas não autorizou este PC. Aceite o aviso "Permitir depuração USB" na tela dela e rode de novo.'
    }
    Falha @'
Nenhuma maquininha encontrada pelo adb. Confira:
  - cabo USB de DADOS ligado e maquininha ligada;
  - é o terminal de DEBUG (o de produção tem a USB bloqueada);
  - depuração USB ativa (Configurações > Sobre > toque 7x em "Número da versão",
    depois Opções do desenvolvedor > Depuração USB);
  - driver USB da Gertec/ADB instalado no Windows (Gerenciador de Dispositivos).
O APK já está pronto; depois é só rodar .\tool\maquininha.ps1 de novo.
'@
}
if ($prontos.Count -gt 1) { Falha 'Há mais de um aparelho Android ligado. Deixe só a maquininha.' }
$serial = ($prontos[0] -split "`t")[0]
$modelo = (Rodar 'adb' @('-s', $serial, 'shell', 'getprop', 'ro.product.model')) -join ''
$android = (Rodar 'adb' @('-s', $serial, 'shell', 'getprop', 'ro.build.version.release')) -join ''
$api = (Rodar 'adb' @('-s', $serial, 'shell', 'getprop', 'ro.build.version.sdk')) -join ''
$abi = (Rodar 'adb' @('-s', $serial, 'shell', 'getprop', 'ro.product.cpu.abilist')) -join ''
Info "Terminal: $($modelo.Trim()) - Android $($android.Trim()) (API $($api.Trim())) - $($abi.Trim())"
if ([int]($api.Trim()) -lt 24) { Falha "Este terminal tem Android $($android.Trim()); o app exige 7.0 (API 24) ou mais novo." }

Passo 'Instalando'
$saida = Rodar 'adb' @('-s', $serial, 'install', '-r', $apk)
$texto = $saida -join "`n"
if ($texto -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match') {
    Info 'Já havia uma versão assinada com outra chave: removendo e instalando de novo.'
    [void](Rodar 'adb' @('-s', $serial, 'uninstall', $Pacote))
    $saida = Rodar 'adb' @('-s', $serial, 'install', '-r', $apk)
    $texto = $saida -join "`n"
}
if ($texto -notmatch 'Success') {
    Write-Host $texto
    if ($texto -match 'NO_CERTIFICATES|INSTALL_PARSE_FAILED|VERIFICATION|signature|certificate') {
        $dica = if ($VarianteDebug) { 'Confirme com a Stone se esta é a chave certa para o seu modelo.' }
                else { 'Tente a variante de debug:  .\tool\maquininha.ps1 -VarianteDebug' }
        Falha "O terminal recusou a assinatura do APK. $dica"
    }
    Falha 'A instalação falhou (mensagem do adb acima).'
}
Info 'Instalado.'

[void](Rodar 'adb' @('-s', $serial, 'shell', 'monkey', '-p', $Pacote, '-c', 'android.intent.category.LAUNCHER', '1'))
Write-Host "`nApp aberto na maquininha." -ForegroundColor Green
Write-Host @'

Roteiro rápido de teste:
  1. Login: endereço da loja + e-mail e senha de um usuário do Mobizweb.
  2. Engrenagem > "Impressão, maquininha e suporte" > Imprimir página de teste.
  3. Abra uma mesa, lance um item, peça a conta e receba no débito com valor
     terminado em ,00 (aprova no sandbox). Valor terminado em ,51 é recusado.
'@

if ($Logs) {
    Start-Sleep -Seconds 2
    $appPid = ((Rodar 'adb' @('-s', $serial, 'shell', 'pidof', '-s', $Pacote)) -join '').Trim()
    if ($appPid) { adb -s $serial logcat "--pid=$appPid" } else { adb -s $serial logcat -s flutter }
}
