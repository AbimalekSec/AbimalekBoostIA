#Requires -RunAsAdministrator
<#
.SYNOPSIS
    AbimalekBoost Loader — instala e executa via GitHub
.DESCRIPTION
    Uso:
        iex (irm 'https://raw.githubusercontent.com/SEU_USUARIO/SEU_REPO/main/loader.ps1')

    O loader:
    1. Verifica requisitos (admin, PS version)
    2. Baixa AbimalekBoost_v7.ps1 do GitHub
    3. Baixa a pasta MalikIA (Python server) se Python estiver instalado
    4. Inicia o servidor MalikIA em background (opcional)
    5. Executa o script principal
#>

# ================================================================
#  CONFIGURAÇÃO — ALTERE PARA SEU REPOSITÓRIO
# ================================================================
$REPO_USER   = "AbimalekSec"           # seu username do GitHub
$REPO_NAME   = "AbimalekBoostIA"             # nome do repositório
$REPO_BRANCH = "main"                 # branch principal
$BASE_URL    = "https://raw.githubusercontent.com/$REPO_USER/$REPO_NAME/$REPO_BRANCH"

$SCRIPT_NAME = "AbimalekBoost_v7.ps1"
$MALIK_FILES = @(
    "MalikIA/server.py",
    "MalikIA/malik_db.py",
    "MalikIA/malik_ml.py",
    "MalikIA/game_analyzer.py",
    "MalikIA/requirements.txt"
)

# Pasta local de instalação
$InstallDir  = Join-Path $env:LOCALAPPDATA "AbimalekBoost"
$MalikDir    = Join-Path $InstallDir "MalikIA"
$ScriptPath  = Join-Path $InstallDir $SCRIPT_NAME

# ================================================================
#  HELPERS VISUAIS
# ================================================================
function Write-Header {
    Clear-Host
    $c = [char]0x2588
    Write-Host ""
    Write-Host "  $c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c" -ForegroundColor Cyan
    Write-Host "  $c  ABIMALEKBOOST v7 — LOADER                     $c" -ForegroundColor Cyan
    Write-Host "  $c  Otimizador de Performance com MalikIA           $c" -ForegroundColor Cyan
    Write-Host "  $c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c$c" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step  { param($n,$total,$msg) Write-Host "  [$n/$total] $msg" -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "  [X]  $msg" -ForegroundColor Red }
function Write-Info  { param($msg) Write-Host "       $msg" -ForegroundColor DarkGray }


# ================================================================
#  LER URL DA MALIKIA DO GITHUB (atualizada pelo start_server.py)
# ================================================================
function Get-MalikIAUrl {
    try {
        $apiUrl = "https://api.github.com/repos/$REPO_USER/$REPO_NAME/contents/MalikIA/url.json"
        $headers = @{ "User-Agent" = "AbimalekBoost-Loader"; "Accept" = "application/vnd.github.v3+json" }
        $resp    = Invoke-WebRequest $apiUrl -Headers $headers -UseBasicParsing -TimeoutSec 6 -EA Stop
        $json    = $resp.Content | ConvertFrom-Json
        # Conteúdo é base64
        $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($json.content -replace "`n",""))
        $data    = $decoded | ConvertFrom-Json

        if ($data.status -eq "online" -and $data.malikia_url) {
            return @{ URL = $data.malikia_url; APIKey = $data.api_key; Online = $true }
        }
    } catch {}
    return @{ URL = ""; APIKey = "malikia-dev-2025"; Online = $false }
}

# ================================================================
#  VERIFICAR PRÉ-REQUISITOS
# ================================================================
function Test-Prerequisites {
    Write-Step 1 5 "Verificando pré-requisitos..."

    # Admin
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Err "Execute como Administrador."
        Write-Info "Clique com botão direito no PowerShell → 'Executar como administrador'"
        Write-Host ""
        Read-Host "  Pressione Enter para sair"
        exit 1
    }
    Write-OK "Administrador"

    # PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Err "PowerShell 5+ necessário. Versão atual: $($PSVersionTable.PSVersion)"
        exit 1
    }
    Write-OK "PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"

    # Windows 10/11
    $winBuild = [System.Environment]::OSVersion.Version.Build
    if ($winBuild -lt 17763) {
        Write-Warn "Windows 10 1809+ recomendado (build $winBuild detectado)"
    } else {
        Write-OK "Windows build $winBuild"
    }

    # TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-OK "TLS 1.2 ativo"
}

# ================================================================
#  BAIXAR ARQUIVO COM RETRY
# ================================================================
function Get-RemoteFile {
    param(
        [string]$Url,
        [string]$Dest,
        [string]$Label = "",
        [int]$MaxRetries = 3
    )

    $dir = Split-Path $Dest -Parent
    if (-not (Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }

    for ($try = 1; $try -le $MaxRetries; $try++) {
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -TimeoutSec 30 -EA Stop
            return $true
        } catch {
            if ($try -lt $MaxRetries) {
                Write-Info "Tentativa $try falhou, aguardando..."
                Start-Sleep -Seconds 2
            }
        }
    }
    return $false
}

# ================================================================
#  VERIFICAR ATUALIZAÇÃO DISPONÍVEL
# ================================================================
function Test-UpdateAvailable {
    try {
        $remoteRaw = Invoke-WebRequest -Uri "$BASE_URL/$SCRIPT_NAME" -UseBasicParsing -TimeoutSec 8 -EA Stop
        $remoteVersion = if ($remoteRaw.Content -match '\$Script:Versao\s*=\s*"([^"]+)"') { $Matches[1] } else { "?" }

        $localVersion = "não instalado"
        if (Test-Path $ScriptPath) {
            $localContent = Get-Content $ScriptPath -Raw -EA SilentlyContinue
            if ($localContent -match '\$Script:Versao\s*=\s*"([^"]+)"') { $localVersion = $Matches[1] }
        }

        return @{
            Remote = $remoteVersion
            Local  = $localVersion
            NeedsUpdate = ($localVersion -ne $remoteVersion)
        }
    } catch {
        return @{ Remote = "?"; Local = "?"; NeedsUpdate = $true }
    }
}

# ================================================================
#  BAIXAR SCRIPT PRINCIPAL
# ================================================================
function Install-MainScript {
    Write-Step 2 5 "Baixando AbimalekBoost v7..."

    $versionInfo = Test-UpdateAvailable

    if (-not $versionInfo.NeedsUpdate -and (Test-Path $ScriptPath)) {
        Write-OK "Já na versão mais recente ($($versionInfo.Local)) — pulando download"
        return $true
    }

    if ($versionInfo.Remote -ne "?") {
        Write-Info "Versão remota : $($versionInfo.Remote)"
        Write-Info "Versão local  : $($versionInfo.Local)"
    }

    $ok = Get-RemoteFile -Url "$BASE_URL/$SCRIPT_NAME" -Dest $ScriptPath -Label "Script principal"
    if ($ok) {
        Write-OK "AbimalekBoost_v7.ps1 baixado"
        return $true
    } else {
        Write-Err "Falha ao baixar o script. Verifique a conexão."
        return $false
    }
}

# ================================================================
#  BAIXAR MALIKIA (PYTHON)
# ================================================================
function Install-MalikIA {
    Write-Step 3 5 "Verificando MalikIA (Python server)..."

    # Python instalado?
    $python = Get-Command "python" -EA SilentlyContinue
    if (-not $python) { $python = Get-Command "python3" -EA SilentlyContinue }

    if (-not $python) {
        Write-Warn "Python não encontrado — MalikIA cloud offline"
        Write-Info "Instale Python 3.9+ em python.org para ativar a IA completa"
        Write-Info "O script funciona normalmente sem a MalikIA"
        return $false
    }

    $pyVersion = & $python.Source --version 2>&1
    Write-OK "Python: $pyVersion"

    # Baixar arquivos da MalikIA
    Write-Info "Baixando MalikIA..."
    $allOk = $true

    foreach ($file in $MALIK_FILES) {
        $dest = Join-Path $InstallDir $file
        $url  = "$BASE_URL/$file"
        $ok   = Get-RemoteFile -Url $url -Dest $dest
        if ($ok) {
            Write-Info "  ✓ $file"
        } else {
            Write-Warn "  ✗ $file (falhou)"
            $allOk = $false
        }
    }

    # Instalar dependências Python
    if ($allOk) {
        $reqFile = Join-Path $MalikDir "requirements.txt"
        if (Test-Path $reqFile) {
            Write-Info "Instalando dependências Python..."
            $pip = & $python.Source -m pip install -r $reqFile --quiet 2>&1
            Write-OK "Dependências instaladas"
        }
    }

    return $allOk
}

# ================================================================
#  INICIAR SERVIDOR MALIKIA EM BACKGROUND
# ================================================================
function Start-MalikServer {
    Write-Step 4 5 "Conectando ao servidor MalikIA..."

    # 1. Tentar URL publicada no GitHub (seu PC com tunnel ativo)
    $remote = Get-MalikIAUrl
    if ($remote.Online) {
        try {
            $test = Invoke-WebRequest "$($remote.URL)/health" -UseBasicParsing -TimeoutSec 5 -EA Stop
            $health = $test.Content | ConvertFrom-Json
            if ($health.status -eq "ok") {
                Write-OK "MalikIA online: $($remote.URL)"
                # Guardar URL em variável global para o script principal usar
                $env:MALIKIA_URL    = $remote.URL
                $env:MALIKIA_APIKEY = $remote.APIKey
                return $true
            }
        } catch {}
        Write-Warn "MalikIA publicada no GitHub mas não respondeu ($($remote.URL))"
    } else {
        Write-Info "MalikIA offline no momento (servidor do desenvolvedor desligado)"
    }

    # 2. Fallback: localhost (se o próprio cliente tiver server.py)
    $serverScript = Join-Path $MalikDir "server.py"
    if (Test-Path $serverScript) {
        try {
            $test = Invoke-WebRequest "http://localhost:8000/health" -UseBasicParsing -TimeoutSec 2 -EA Stop
            Write-OK "MalikIA local: http://localhost:8000"
            $env:MALIKIA_URL = "http://localhost:8000"
            return $true
        } catch {}
    }

    # 3. Sem servidor — modo offline (script funciona normalmente)
    Write-Info "Modo offline — otimizações locais sem ML"
    return $false
}

# ================================================================
#  EXECUTAR SCRIPT PRINCIPAL
# ================================================================
function Start-AbimalekBoost {
    Write-Step 5 5 "Iniciando AbimalekBoost..."
    Write-Host ""

    if (-not (Test-Path $ScriptPath)) {
        Write-Err "Script não encontrado: $ScriptPath"
        Read-Host "  Pressione Enter para sair"
        exit 1
    }

    # Liberar execução para este processo
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -EA SilentlyContinue
    Unblock-File -Path $ScriptPath -EA SilentlyContinue

    # Executar
    & $ScriptPath
}

# ================================================================
#  MENU DO LOADER (quando já instalado)
# ================================================================
function Show-LoaderMenu {
    Write-Header
    Write-Host "  Instalação encontrada em: $InstallDir" -ForegroundColor DarkGray
    Write-Host ""

    $vInfo = Test-UpdateAvailable
    if ($vInfo.NeedsUpdate -and $vInfo.Remote -ne "?") {
        Write-Host "  [!] Atualização disponível: $($vInfo.Local) → $($vInfo.Remote)" -ForegroundColor Yellow
        Write-Host ""
    } else {
        Write-Host "  Versão instalada: $($vInfo.Local)" -ForegroundColor Green
        Write-Host ""
    }

    Write-Host "  [1]  Executar AbimalekBoost" -ForegroundColor Cyan
    Write-Host "  [2]  Atualizar para versão mais recente" -ForegroundColor Yellow
    Write-Host "  [3]  Reinstalar tudo do zero" -ForegroundColor White
    Write-Host "  [4]  Remover instalação" -ForegroundColor DarkGray
    Write-Host ""

    $op = Read-Host "  Opcao"
    switch ($op.Trim()) {
        '1' { return "run" }
        '2' { return "update" }
        '3' { return "fresh" }
        '4' {
            Write-Host ""
            Write-Host "  Remover $InstallDir ? [S/N]: " -NoNewline -ForegroundColor Red
            if ((Read-Host) -match '^[sS]') {
                Remove-Item $InstallDir -Recurse -Force -EA SilentlyContinue
                Write-Host "  Removido." -ForegroundColor Green
            }
            exit 0
        }
        default { return "run" }
    }
}

# ================================================================
#  MAIN
# ================================================================
# Liberar execução de scripts para este processo
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -EA SilentlyContinue

Write-Header

$alreadyInstalled = Test-Path $ScriptPath
$action = "install"

if ($alreadyInstalled) {
    $action = Show-LoaderMenu
    Write-Header
}

switch ($action) {
    "run" {
        # Só iniciar servidor e executar
        $malikOk = $false
        if (Test-Path (Join-Path $MalikDir "server.py")) {
            $malikOk = Start-MalikServer
        }
        Write-Step 5 5 "Iniciando AbimalekBoost..."
        Write-Host ""
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -EA SilentlyContinue
        Unblock-File -Path $ScriptPath -EA SilentlyContinue
        & $ScriptPath
    }

    "update" {
        Write-Host ""
        Test-Prerequisites
        $ok = Install-MainScript
        if ($ok) {
            Install-MalikIA | Out-Null
            Start-MalikServer | Out-Null
            Write-Host ""
            Write-OK "Atualização concluída!"
            Start-Sleep 1
            & $ScriptPath
        }
    }

    { $_ -in "install","fresh" } {
        if ($action -eq "fresh" -and (Test-Path $InstallDir)) {
            Write-Info "Removendo instalação anterior..."
            Remove-Item $InstallDir -Recurse -Force -EA SilentlyContinue
        }

        Write-Host ""
        Test-Prerequisites
        $ok = Install-MainScript
        if (-not $ok) {
            Write-Err "Instalação falhou."
            Read-Host "  Pressione Enter para sair"
            exit 1
        }
        Install-MalikIA | Out-Null
        Start-MalikServer | Out-Null

        Write-Host ""
        Write-Host "  ─────────────────────────────────────────────" -ForegroundColor Green
        Write-OK "Instalação concluída em: $InstallDir"
        Write-Host "  ─────────────────────────────────────────────" -ForegroundColor Green
        Write-Host ""
        Start-Sleep 1
        & $ScriptPath
    }
}
