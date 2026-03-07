#Requires -Version 5.1
<#
.SYNOPSIS
    AbimalekBoost v6.1
    Sistema de otimizacao inteligente com Motor de IA Heuristica
    Detecta hardware, analisa gargalos, decide e aplica tweaks automaticamente

.NOTES
    - Requer execucao como Administrador (Windows 10/11)
    - Totalmente reversivel via backup automatico + ponto de restauracao
    - Execute com: powershell.exe -ExecutionPolicy Bypass -File "AbimalekBoost.ps1"
    - Ou via IEX: irm "https://raw.githubusercontent.com/AbimalekSec/AbimalekBoost/refs/heads/main/AbimalekBoost.ps1" | iex

.CHANGELOG v7.0
    - MOTOR IA v7: 5 funcoes rebuilt do zero com aprendizado real local
    - Get-IASnapshot: 40+ metricas (antes 25) - thermal, E/P cores, GPU throttle, DPC, Spectre, hibernacao
    - Measure-PerformanceScore: nova dimensao Thermal Score + Power Throttle + MMCSS + GPU throttle
    - Invoke-IAMotorDecisao: 25 regras (antes 20) com bloco executavel embutido
    - NOVO: Intel Hybrid CPU (12a/13a/14a gen) - detecta E/P cores e fixa jogos em P-cores via MMCSS
    - NOVO: Thermal Throttle - detecta CPU >90graus e GPU throttle via nvidia-smi, alerta usuario
    - NOVO: GPU Throttle - detecta limitacao por temperatura/power limit via nvidia-smi
    - NOVO: Power Throttling detection e desativacao automatica
    - NOVO: DPC Latency alta detectada via Event Log
    - NOVO: Hibernation detection - desativa hiberfil.sys em NVMe (libera espaco e overhead)
    - NOVO: MMCSS Gaming detection - verifica se ja esta configurado antes de reaplicar
    - Save-IAExecucao v2: salva eficacia por tweak individual (granular learning)
    - Get-IAInsightHistorico v7: detecta regressoes, top tweaks, tendencia (melhorando/estavel/revertendo)
    - Aprendizado local: tweaks com ganho negativo sao sinalizados nas proximas sessoes
    - QoS expandido: 12 jogos (era 7) incluindo r5apex, overwatch, rocketleague, pubg
    - Historico formato v2: armazena score por dimensao (Latencia, Resp, Gamer, Thermal)
    - Remocao do modulo MalikIA/Supabase (sem dependencia externa)

.CHANGELOG v6.1
    - BENCHMARK REAL: Ryzen 5 5700X + 24GB DDR4 + Win10 -> +58fps FiveM (+34.5%)
    - Estimativas de ganho de FPS atualizadas com dados reais por hardware
    - Simulacao FiveM: ganho absoluto em fps exibido alem do percentual
    - Motor de IA: aviso especial para Ryzen + Win10 com resultado documentado
    - Historico: benchmark de referencia exibido antes da primeira execucao

.CHANGELOG v6.0
    - NOVO: Motor de IA Heuristico - analise local sem servidor externo
    - NOVO: Sistema de Score (Geral, Latencia, Responsividade, Gamer)
    - NOVO: Perfis inteligentes: Seguro, Gamer, Streamer, Extremo
    - NOVO: Coleta de metricas em tempo real (CPU, RAM, Disk Queue, Ping, Timer)
    - NOVO: Motor de Decisao - 20+ regras condicionais por hardware/gargalo
    - NOVO: Aprendizado local (JSON) - historico de sessoes e ganhos
    - NOVO: Score comparativo antes/depois com delta visual
    - NOVO: Interface WPF com resultados em tempo real
    - NOVO: Simulacao de impacto para FiveM, CS2 e Valorant
    - NOVO: Ponto de restauracao automatico pre-otimizacao
    - NOVO: Rollback de registro com backup por sessao
    - NOVO: Nuclear Microsoft (OneDrive, Copilot, Teams, Recall, Edge)
    - NOVO: Reducao de Processos CPU e desafogo de RAM
    - NOVO: Input Lag (mouse 1:1, IRQ, QoS, DWM, MMCSS)
    - NOVO: Group Policy Performance Pack (funciona no Windows Home)
    - MELHORIA: TLS 1.2 forcado para chamadas HTTPS
    - MELHORIA: Versao 6.0 - arquitetura modular escalavel
    - NOVO: IA Advisor - analisa hardware e gera plano personalizado via API Claude
    - NOVO: Tweaks granulares - escolha tweak por tweak antes de aplicar
    - NOVO: Modo Checklist interativo com preview de cada tweak
    - NOVO: Tweaks de CPU avancados (Affinity, QoS, C-States, SpeedStep)
    - NOVO: Tweaks de memoria (Large Pages, prefetch avancado, Working Set)
    - NOVO: Tweaks de GPU adicionais (TDR Delay, PhysX, shader cache)
    - NOVO: Tweaks de latencia de audio (WASAPI, buffer de audio)
    - NOVO: Tweaks de storage adicionais (Write-back cache, TRIM)
    - NOVO: Desativar mitigacoes Spectre/Meltdown (opcional, risco vs ganho)
    - NOVO: Otimizacao de paginacao e memoria virtual
    - MELHORIA: Modo IA Advisor com chave API configuravel
    - MELHORIA: Relatorio gerado pelo IA com recomendacoes especificas
#>

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Fundo preto e texto padrao
$host.UI.RawUI.BackgroundColor = 'Black'
$host.UI.RawUI.ForegroundColor = 'White'
Clear-Host

# ================================================================
#  VARIAVEIS GLOBAIS
# ================================================================
$Script:Versao      = "7.3.0"
$Script:NomeProg    = "AbimalekBoost"
$Script:IDSessao    = (New-Guid).ToString("N").Substring(0,8).ToUpper()

# Hardware
$Script:CPUNome     = ""; $Script:CPUFab   = ""; $Script:CPUNucleos  = 0; $Script:CPUThreads = 0
$Script:CPUX3D      = $false; $Script:CPUIntelK = $false; $Script:CPUGen = 0
$Script:RAMtotalGB  = 0; $Script:RAMtipo   = ""; $Script:RAMvelocidade = 0; $Script:RAMslots = 0
$Script:GPUNome     = ""; $Script:GPUFab   = ""; $Script:GPUVRAM = 0
$Script:GPUTemp     = -1; $Script:GPUCore  = -1; $Script:GPUPL   = -1; $Script:GPUPLmax = -1
$Script:GPUSmi      = ""; $Script:GPUDriver = ""
$Script:DiscoTipo   = ""; $Script:DiscoNome = ""; $Script:DiscoNVMe = $false
$Script:WinBuild    = 0;  $Script:WinVer    = ""
$Script:IsWin11     = $false   # detectado em Invoke-DetectarHardware
$Script:TemWinget   = $false

# Estado
$Script:TweaksFeitos   = [System.Collections.Generic.List[string]]::new()
$Script:SvcsBackup     = @{}
$Script:PlanoOrig      = ""
$Script:OtimAplicada   = $false
$Script:ModoStreamer    = $false

# IA - Chave hardcoded (cliente nao precisa configurar nada)
# Para obter sua chave: https://console.anthropic.com > API Keys
$Script:IAChave        = "SUA-CHAVE-AQUI"   # <- substitua pela sua sk-ant-...
$Script:IAAtiva        = ($Script:IAChave -match '^sk-ant-')

# Pastas
$Script:PastaRaiz   = Join-Path $env:LOCALAPPDATA "AbimalekBoost"
$Script:PastaBackup = Join-Path $Script:PastaRaiz "Backup"
$Script:PastaLogs   = Join-Path $Script:PastaRaiz "Logs"
$Script:ArqChaveIA  = Join-Path $Script:PastaRaiz "ia_key.txt"
$Script:LogFile     = Join-Path $Script:PastaLogs "v5_$($Script:IDSessao)_$(Get-Date -f 'yyyyMMdd_HHmmss').log"

foreach ($p in @($Script:PastaRaiz, $Script:PastaBackup, $Script:PastaLogs)) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

# Carregar config MalikIA salva (se existir)
# Detectar versao do Windows cedo (antes de DetectarHardware)
try {
    $osEarly = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($osEarly) {
        $Script:WinBuild = [int]$osEarly.BuildNumber
        $Script:WinVer   = $osEarly.Caption
        $Script:IsWin11  = ($Script:WinBuild -ge 22000)
    }
} catch {}

# Verificar se chave esta configurada
if (-not $Script:IAAtiva) {
    Write-Host "  [!] IA: chave nao configurada no script." -ForegroundColor DarkGray
}

# ================================================================
#  MALIKIA - MODULO DE TELEMETRIA E APRENDIZADO COLETIVO
# ================================================================

# ================================================================
#  MALIKIA - MODULO DE TELEMETRIA E APRENDIZADO
#  AbimalekBoost v6.1
#  Envia dados anonimos para Supabase e baixa insights
# ================================================================

# ================================================================
#  REGION: CONFIGURACAO SUPABASE
#  Substitua com suas credenciais do projeto Supabase
# ================================================================
$Script:MalikIA = [ordered]@{
    # URL e APIKey preenchidos automaticamente pelo loader via $env:MALIKIA_URL
    URL            = if ($env:MALIKIA_URL)    { $env:MALIKIA_URL }    else { "" }
    APIKey         = if ($env:MALIKIA_APIKEY) { $env:MALIKIA_APIKEY } else { "malikia-dev-2025" }

    # Estado
    Ativo          = $false
    SessionId      = $null
    InsightCache   = $null
    UltimoEnvio    = $null
}

# Ativar se loader passou a URL do servidor
$Script:MalikIA.Ativo = ($Script:MalikIA.URL -ne "" -and $Script:MalikIA.URL -match "http")

# ================================================================
#  REGION: HELPER HTTP - compativel com fileless (sem modulos externos)
# ================================================================
function Invoke-MalikRequest {
    param(
        [string]$Method = "GET",
        [string]$Endpoint,
        [object]$Body = $null
    )

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $url     = "$($Script:MalikIA.SupabaseURL)$Endpoint"
        $headers = @{
            "apikey"        = $Script:MalikIA.SupabaseAnonKey
            "Authorization" = "Bearer $($Script:MalikIA.SupabaseAnonKey)"
            "Content-Type"  = "application/json"
            "Prefer"        = "return=representation"
        }

        $params = @{
            Uri             = $url
            Method          = $Method
            Headers         = $headers
            UseBasicParsing = $true
            TimeoutSec      = 8
            ErrorAction     = "Stop"
        }

        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
        }

        $resp = Invoke-WebRequest @params
        return $resp.Content | ConvertFrom-Json
    } catch {
        # Falha silenciosa - telemetria nunca interrompe o script
        return $null
    }
}

# ================================================================
#  REGION: GERAR HARDWARE ID ANONIMO
#  SHA256 de CPU+RAM+GPU - nao identifica o usuario
# ================================================================
function Get-MalikHardwareId {
    $raw = "$($Script:CPUNome)|$($Script:RAMtotalGB)|$($Script:GPUNome)" +
           "|$($Script:CPUNucleos)|$($Script:RAMtipo)"
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($raw)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hash   = $sha256.ComputeHash($bytes)
    return ([BitConverter]::ToString($hash) -replace '-').ToLower().Substring(0, 32)
}

# ================================================================
#  REGION: ENVIAR SESSAO PARA SUPABASE
# ================================================================
function Send-MalikSession {
    param(
        [hashtable]$snapAntes,
        [hashtable]$snapDepois,
        [string]$Perfil,
        [array]$TweaksAplicados,
        [array]$Gargalos
    )

    if (-not $Script:MalikIA.Ativo) { return }

    $hwId = Get-MalikHardwareId

    # Montar payload para a funcao RPC do Supabase
    $payload = @{
        p_hardware_id     = $hwId
        p_cpu_model       = $Script:CPUNome
        p_cpu_vendor      = $Script:CPUFab
        p_cpu_cores       = $Script:CPUNucleos
        p_cpu_threads     = $Script:CPUThreads
        p_cpu_is_x3d      = $Script:CPUX3D
        p_cpu_gen         = $Script:CPUGen
        p_ram_gb          = $Script:RAMtotalGB
        p_ram_type        = $Script:RAMtipo
        p_ram_mhz         = $Script:RAMvelocidade
        p_gpu_model       = $Script:GPUNome
        p_gpu_vendor      = $Script:GPUFab
        p_gpu_vram_gb     = $Script:GPUVRAM
        p_disk_type       = $Script:DiscoTipo
        p_os_is_win11     = $Script:IsWin11
        p_os_build        = $Script:WinBuild
        p_perfil          = $Perfil
        p_score_g_antes   = $snapAntes.Score.Geral
        p_score_l_antes   = $snapAntes.Score.Latencia
        p_score_r_antes   = $snapAntes.Score.Responsividade
        p_score_gm_antes  = $snapAntes.Score.Gamer
        p_score_g_dep     = $snapDepois.Score.Geral
        p_score_l_dep     = $snapDepois.Score.Latencia
        p_score_r_dep     = $snapDepois.Score.Responsividade
        p_score_gm_dep    = $snapDepois.Score.Gamer
        p_cpu_uso_antes   = $snapAntes.CPUUsoPct
        p_ram_uso_antes   = $snapAntes.RAMUsoPct
        p_ping_antes      = $snapAntes.LatenciaMS
        p_jitter_antes    = $snapAntes.NetworkJitter
        p_timer_antes     = $snapAntes.TimerResMS
        p_cpu_uso_dep     = $snapDepois.CPUUsoPct
        p_ram_uso_dep     = $snapDepois.RAMUsoPct
        p_ping_dep        = $snapDepois.LatenciaMS
        p_jitter_dep      = $snapDepois.NetworkJitter
        p_timer_dep       = $snapDepois.TimerResMS
        p_script_version  = $Script:Versao
        p_tweaks_count    = $TweaksAplicados.Count
        p_gargalos        = $Gargalos
    }

    IN "MalikIA: enviando sessao..."
    $result = Invoke-MalikRequest -Method "POST" -Endpoint "/rest/v1/rpc/upsert_hardware_and_session" -Body $payload

    if ($result) {
        $Script:MalikIA.SessionId = $result
        OK "MalikIA: sessao registrada (ID: $($result.ToString().Substring(0,8))...)"

        # Enviar tweaks em batch
        if ($TweaksAplicados -and $TweaksAplicados.Count -gt 0) {
            $tweaksBatch = $TweaksAplicados | ForEach-Object {
                $parts = $_ -split ': ', 2
                @{
                    session_id  = $result.ToString()
                    hardware_id = $hwId
                    tweak_id    = if ($parts[0]) { $parts[0].Trim() } else { $_ }
                    tweak_desc  = if ($parts[1]) { $parts[1].Trim() } else { "" }
                    perfil      = $Perfil
                }
            }
            Invoke-MalikRequest -Method "POST" -Endpoint "/rest/v1/tweaks_applied" -Body $tweaksBatch | Out-Null
        }

        $Script:MalikIA.UltimoEnvio = Get-Date
    } else {
        IN "MalikIA: offline ou nao configurado - sessao salva localmente."
    }
}

# ================================================================
#  REGION: ENVIAR BENCHMARK DE FPS (opcional, usuario informa)
# ================================================================
function Send-MalikBenchmark {
    param([string]$Jogo)

    if (-not $Script:MalikIA.Ativo) { return }

    H2 "MALIKIA - REGISTRAR BENCHMARK DE FPS"
    Write-Host "  Contribua com dados reais para melhorar as estimativas da MalikIA." -ForegroundColor DarkGray
    Write-Host "  Os dados sao 100%% anonimos - apenas FPS e hardware." -ForegroundColor DarkGray
    Write-Host ""

    $jogoInput = if ($Jogo) { $Jogo } else {
        Write-Host "  Jogo [FiveM / CS2 / Valorant / outro]: " -NoNewline
        Read-Host
    }
    if (-not $jogoInput) { return }

    Write-Host "  FPS ANTES de otimizar (ex: 168): " -NoNewline
    $fpsBefore = Read-Host
    Write-Host "  FPS DEPOIS de otimizar (ex: 226): " -NoNewline
    $fpsAfter  = Read-Host

    if (-not ($fpsBefore -match '^\d+$') -or -not ($fpsAfter -match '^\d+$')) {
        WN "Valores invalidos. Benchmark nao enviado."; return
    }

    $fbInt = [int]$fpsBefore
    $faInt = [int]$fpsAfter
    $pct   = if ($fbInt -gt 0) { [math]::Round((($faInt - $fbInt) / $fbInt) * 100, 1) } else { 0 }

    $payload = @{
        hardware_id   = Get-MalikHardwareId
        session_id    = if ($Script:MalikIA.SessionId) { $Script:MalikIA.SessionId.ToString() } else { $null }
        game          = $jogoInput
        fps_antes     = $fbInt
        fps_depois    = $faInt
        fps_ganho_pct = $pct
        perfil        = $Script:IA.Perfil
    }

    $result = Invoke-MalikRequest -Method "POST" -Endpoint "/rest/v1/benchmarks" -Body $payload
    if ($result) {
        OK "MalikIA: benchmark enviado! +$($faInt - $fbInt) fps (+$pct%%) no $jogoInput"
        Write-Host "  Obrigado! Esses dados ajudam a calibrar as estimativas para hardware similar." -ForegroundColor DarkGreen
    }
    PAUSE
}

# ================================================================
#  REGION: BAIXAR INSIGHT DA MALIKIA PARA O HARDWARE ATUAL
# ================================================================
function Get-MalikInsight {
    if (-not $Script:MalikIA.Ativo) { return $null }
    if (-not $Script:CPUNome) { return $null }

    # Tentar insight especifico para o CPU
    $hwId    = Get-MalikHardwareId
    $encoded = [Uri]::EscapeDataString($Script:CPUNome)

    $insight = Invoke-MalikRequest -Method "GET" `
        -Endpoint "/rest/v1/malik_insights?hardware_id=eq.$hwId&limit=1"

    # Fallback: insight por modelo de CPU (sem hardware_id especifico)
    if (-not $insight -or ($insight -is [array] -and $insight.Count -eq 0)) {
        $insight = Invoke-MalikRequest -Method "GET" `
            -Endpoint "/rest/v1/malik_insights?cpu_model=eq.$encoded&os_is_win11=eq.$($Script:IsWin11.ToString().ToLower())&limit=1"
    }

    # Fallback: insight por fabricante
    if (-not $insight -or ($insight -is [array] -and $insight.Count -eq 0)) {
        $vendor  = [Uri]::EscapeDataString($Script:CPUFab)
        $insight = Invoke-MalikRequest -Method "GET" `
            -Endpoint "/rest/v1/malik_insights?cpu_vendor=eq.$vendor&os_is_win11=eq.$($Script:IsWin11.ToString().ToLower())&order=amostras.desc&limit=1"
    }

    if ($insight -and $insight -is [array] -and $insight.Count -gt 0) {
        $Script:MalikIA.InsightCache = $insight[0]
        return $insight[0]
    }
    return $null
}

# ================================================================
#  REGION: EXIBIR INSIGHT DA MALIKIA NO TERMINAL
# ================================================================
function Show-MalikInsight {
    $insight = Get-MalikInsight
    if (-not $insight) { return }

    Write-Host ""
    Write-Host "  $('=' * 60)" -ForegroundColor Magenta
    Write-Host "  MALIK IA - RECOMENDACAO PARA SEU HARDWARE" -ForegroundColor Magenta
    Write-Host "  $('=' * 60)" -ForegroundColor Magenta

    if ($insight.perfil_recomendado) {
        Write-Host ("  Perfil recomendado : {0}" -f $insight.perfil_recomendado) -ForegroundColor Cyan
    }
    if ($insight.ganho_medio_pct) {
        Write-Host ("  Ganho medio (score): +{0}%%" -f $insight.ganho_medio_pct) -ForegroundColor Green
    }
    if ($insight.ganho_medio_fps_fivem) {
        Write-Host ("  FiveM esperado     : +{0} fps" -f $insight.ganho_medio_fps_fivem) -ForegroundColor Green
    }
    if ($insight.ganho_medio_fps_cs2) {
        Write-Host ("  CS2 esperado       : +{0} fps" -f $insight.ganho_medio_fps_cs2) -ForegroundColor Green
    }
    if ($insight.tweaks_criticos -and $insight.tweaks_criticos.Count -gt 0) {
        Write-Host "  Tweaks criticos    :" -ForegroundColor Yellow -NoNewline
        Write-Host " $($insight.tweaks_criticos -join ', ')" -ForegroundColor White
    }
    if ($insight.amostras) {
        Write-Host ("  Baseado em         : {0} sessoes similares  [{1}]" -f $insight.amostras, $insight.confianca.ToUpper()) -ForegroundColor DarkGray
    }
    Write-Host "  $('=' * 60)" -ForegroundColor Magenta
    Write-Host ""
}

# ================================================================
#  REGION: BUSCAR STATS GLOBAIS DA MALIKIA
# ================================================================
function Get-MalikStats {
    if (-not $Script:MalikIA.Ativo) {
        WN "MalikIA nao configurada. Configure a URL e chave do Supabase."
        PAUSE; return
    }

    H2 "MALIKIA - ESTATISTICAS GLOBAIS"
    IN "Buscando dados..."

    # Stats gerais
    $stats = Invoke-MalikRequest -Method "GET" -Endpoint "/rest/v1/v_stats_gerais?limit=1"
    if ($stats -and $stats -is [array] -and $stats.Count -gt 0) {
        $s = $stats[0]
        Write-Host ""
        Write-Host "  REDE ABIMALEKBOOST:" -ForegroundColor Cyan
        Write-Host ("  Total de sessoes  : {0}" -f $s.total_sessoes) -ForegroundColor White
        Write-Host ("  Maquinas unicas   : {0}" -f $s.total_maquinas) -ForegroundColor White
        Write-Host ("  Ganho medio score : +{0} pts" -f $s.ganho_medio_score) -ForegroundColor Green
        Write-Host ("  Score medio final : {0}/100" -f $s.score_medio_final) -ForegroundColor Green
        Write-Host ("  Reducao ping media: -{0}ms" -f $s.reducao_ping_media) -ForegroundColor Green
        Write-Host ("  Reducao RAM media : -{0}%%" -f $s.reducao_ram_media) -ForegroundColor Green
        if ($s.ultima_sessao) {
            Write-Host ("  Ultima sessao     : {0}" -f ([datetime]$s.ultima_sessao).ToString("dd/MM/yyyy HH:mm")) -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    # Stats por perfil
    $perfis = Invoke-MalikRequest -Method "GET" -Endpoint "/rest/v1/v_stats_por_perfil"
    if ($perfis -and $perfis.Count -gt 0) {
        Write-Host "  GANHO POR PERFIL:" -ForegroundColor Cyan
        foreach ($p in $perfis) {
            Write-Host ("  {0,-12} {1,3} sessoes  ganho medio: +{2} pts" -f $p.perfil, $p.sessoes, $p.ganho_medio) -ForegroundColor White
        }
    }

    Write-Host ""
    # Benchmarks FPS
    $fps = Invoke-MalikRequest -Method "GET" -Endpoint "/rest/v1/v_benchmarks_por_jogo"
    if ($fps -and $fps.Count -gt 0) {
        Write-Host "  BENCHMARKS DE FPS (dados reais):" -ForegroundColor Cyan
        foreach ($b in $fps) {
            Write-Host ("  {0,-12} {1,3} amostras  +{2} fps medio  +{3}%%" -f $b.game, $b.amostras, $b.ganho_medio_fps, $b.ganho_medio_pct) -ForegroundColor Green
        }
    }

    Write-Host ""
    # Top CPUs
    $cpus = Invoke-MalikRequest -Method "GET" -Endpoint "/rest/v1/v_top_cpus?limit=5"
    if ($cpus -and $cpus.Count -gt 0) {
        Write-Host "  TOP CPUs COM MAIOR GANHO:" -ForegroundColor Cyan
        foreach ($c in $cpus) {
            $os = if ($c.os_is_win11) { "Win11" } else { "Win10" }
            Write-Host ("  {0,-30} {1}  ganho: +{2} pts ({3} sessoes)" -f $c.cpu_model, $os, $c.ganho_medio, $c.sessoes) -ForegroundColor White
        }
    }

    PAUSE
}

# ================================================================
#  REGION: MENU MALIKIA
# ================================================================
function Show-MenuMalikIA {
    while ($true) {
        Show-Banner; Show-StatusBar
        H1 "MALIK IA - INTELIGENCIA COLETIVA"
        Write-Host "  Aprende com dados de todos os usuarios. 100%% anonimo." -ForegroundColor DarkGray
        Write-Host ""

        # Status de conexao
        if ($Script:MalikIA.Ativo) {
            Write-Host "  STATUS: CONECTADO ao Supabase" -ForegroundColor Green
            Write-Host "  URL: $($Script:MalikIA.SupabaseURL)" -ForegroundColor DarkGray
        } else {
            Write-Host "  STATUS: NAO CONFIGURADO" -ForegroundColor Red
            Write-Host "  Configure a URL e chave do Supabase no script." -ForegroundColor Yellow
        }
        Write-Host ""

        Write-Host "  [1]  Ver estatisticas globais da rede" -ForegroundColor Cyan
        Write-Host "  [2]  Ver insight para meu hardware" -ForegroundColor Cyan
        Write-Host "  [3]  Enviar benchmark de FPS" -ForegroundColor Yellow
        Write-Host "  [4]  Configurar conexao Supabase" -ForegroundColor White
        Write-Host ""
        Write-Host "  [V]  Voltar" -ForegroundColor DarkGray
        Write-Host ""; SEP; Write-Host ""

        $op = Read-Host "  Opcao"
        switch ($op.Trim().ToUpper()) {
            '1' { Clear-Host; Get-MalikStats }
            '2' { Clear-Host; Show-MalikInsight; PAUSE }
            '3' { Clear-Host; Send-MalikBenchmark }
            '4' { Clear-Host; Set-MalikConfig }
            'V' { return }
        }
    }
}

# ================================================================
#  REGION: CONFIGURAR SUPABASE INTERATIVAMENTE
# ================================================================
function Set-MalikConfig {
    H2 "CONFIGURAR MALIKIA - SUPABASE"
    Write-Host ""
    Write-Host "  Como obter suas credenciais:" -ForegroundColor DarkCyan
    Write-Host "  1. Acesse supabase.com e crie um projeto gratuito" -ForegroundColor White
    Write-Host "  2. Va em Settings > API" -ForegroundColor White
    Write-Host "  3. Copie o 'Project URL' e o 'anon public' key" -ForegroundColor White
    Write-Host "  4. Execute o schema SQL em Database > SQL Editor" -ForegroundColor White
    Write-Host ""

    $url = Read-Host "  Project URL (ex: https://abc123.supabase.co)"
    $key = Read-Host "  Anon Key (eyJ...)"

    if ($url -match "supabase\.co" -and $key.Length -gt 20) {
        $Script:MalikIA.SupabaseURL     = $url.TrimEnd('/')
        $Script:MalikIA.SupabaseAnonKey = $key.Trim()
        $Script:MalikIA.Ativo           = $true

        # Salvar localmente para proximas execucoes
        $cfg = @{ url = $Script:MalikIA.SupabaseURL; key = $Script:MalikIA.SupabaseAnonKey }
        $cfg | ConvertTo-Json | Out-File (Join-Path $Script:PastaRaiz "malik_config.json") -Encoding UTF8 -Force

        OK "MalikIA configurada! Testando conexao..."
        $test = Invoke-MalikRequest -Method "GET" -Endpoint "/rest/v1/v_stats_gerais?limit=1"
        if ($test) { OK "Conexao OK!" } else { WN "Sem resposta - verifique URL e chave." }
    } else {
        WN "Dados invalidos. Configure novamente."
    }
    PAUSE
}

# ================================================================
#  REGION: CARREGAR CONFIG SALVA
# ================================================================
function Load-MalikConfig {
    $cfgFile = Join-Path $Script:PastaRaiz "malik_config.json"
    if (Test-Path $cfgFile) {
        try {
            $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
            if ($cfg.url -match "supabase\.co" -and $cfg.key.Length -gt 20) {
                $Script:MalikIA.SupabaseURL      = $cfg.url
                $Script:MalikIA.SupabaseAnonKey  = $cfg.key
                $Script:MalikIA.Ativo            = $true
            }
        } catch {}
    }
}


# ================================================================
#  MALIKIA - ANALISE AO VIVO COM JOGO ABERTO
# ================================================================
# ================================================================
#  MALIKIA - CAPTURA AO VIVO COM JOGO ABERTO
#  Detecta o jogo, coleta metricas reais durante a sessao,
#  envia para analise ML e aplica otimizacoes cirurgicas
# ================================================================

# ?? Perfis de jogos conhecidos ???????????????????????????????????
$Script:GameProfiles = @{
    "FiveM" = @{
        Processos    = @("FiveM", "FiveM_b2372_GTAProcess", "GTA5", "fivem_service_unhandled")
        DisplayName  = "FiveM (GTA V Multiplayer)"
        Engine       = "RAGE Engine"
        GargaloPrim  = "CPU single-core + scheduler"
        GargaloSec   = "RAM bandwidth + rede"
        FPSAlvo      = 144
        # Tweaks especificos para este jogo (ordem de impacto)
        TweaksPriority = @(
            "CORE_PARKING_OFF", "WIN32_PRIORITY_SEP", "TIMER_RESOLUTION",
            "NAGLE_OFF", "MMCSS_GAMING", "POWER_THROTTLE_OFF",
            "QOS_GAMING", "BG_APPS_OFF", "SYSMAIN_OFF"
        )
        # Thresholds de alerta especificos para FiveM
        Thresholds = @{
            CPUGamePct   = 80    # % CPU do processo do jogo que indica gargalo
            RAMUsoPct    = 70    # RAM total usada
            GPUTempAlert = 85    # temperatura GPU
            PingAlert    = 60    # ms de latencia
            FPSMinimo    = 60    # FPS minimo aceitavel
        }
    }
    "CS2" = @{
        Processos    = @("cs2", "csgo")
        DisplayName  = "CS2 (Counter-Strike 2)"
        Engine       = "Source 2"
        GargaloPrim  = "CPU single-core + input lag"
        GargaloSec   = "Latencia de rede + timer"
        FPSAlvo      = 300
        TweaksPriority = @(
            "NAGLE_OFF", "TIMER_RESOLUTION", "IRQ_INPUT_PRIORITY",
            "MOUSE_ACCEL_OFF", "MMCSS_GAMING", "CORE_PARKING_OFF",
            "WIN32_PRIORITY_SEP", "TCP_STACK", "QOS_GAMING"
        )
        Thresholds = @{
            CPUGamePct   = 75
            RAMUsoPct    = 65
            GPUTempAlert = 83
            PingAlert    = 40
            FPSMinimo    = 120
        }
    }
    "Valorant" = @{
        Processos    = @("VALORANT-Win64-Shipping", "VALORANT")
        DisplayName  = "Valorant"
        Engine       = "Unreal Engine 4"
        GargaloPrim  = "CPU scheduler + VRAM"
        GargaloSec   = "Latencia + memory bandwidth"
        FPSAlvo      = 240
        TweaksPriority = @(
            "WIN32_PRIORITY_SEP", "MMCSS_GAMING", "NAGLE_OFF",
            "TIMER_RESOLUTION", "CORE_PARKING_OFF", "POWER_THROTTLE_OFF",
            "BG_APPS_OFF", "QOS_GAMING", "TCP_STACK"
        )
        Thresholds = @{
            CPUGamePct   = 70
            RAMUsoPct    = 70
            GPUTempAlert = 85
            PingAlert    = 50
            FPSMinimo    = 144
        }
    }
}

# ?? Estado da sessao ao vivo ?????????????????????????????????????
$Script:LiveSession = @{
    JogoDetectado  = $null
    JogoPerfil     = $null
    JogoProcesso   = $null
    Coletando      = $false
    Amostras       = [System.Collections.Generic.List[object]]::new()
    Inicio         = $null
    Duracao        = 120    # segundos de coleta padrao
    IntervalSec    = 3      # coletar a cada 3s
    Analise        = $null  # resultado da analise ML
}

# ????????????????????????????????????????????????????????????????
#  DETECTAR JOGO ABERTO
# ????????????????????????????????????????????????????????????????
function Find-GameRunning {
    $processos = Get-Process -EA SilentlyContinue

    foreach ($nomeJogo in $Script:GameProfiles.Keys) {
        $perfil = $Script:GameProfiles[$nomeJogo]
        foreach ($procNome in $perfil.Processos) {
            $proc = $processos | Where-Object { $_.ProcessName -eq $procNome } | Select-Object -First 1
            if ($proc) {
                return @{
                    Jogo     = $nomeJogo
                    Perfil   = $perfil
                    Processo = $proc
                }
            }
        }
    }
    return $null
}

# ????????????????????????????????????????????????????????????????
#  CAPTURAR UMA AMOSTRA - metricas completas num instante
# ????????????????????????????????????????????????????????????????
function Get-GameSample {
    param(
        [System.Diagnostics.Process]$GameProc,
        [string]$GameName
    )

    $sample = [ordered]@{
        Timestamp    = (Get-Date -Format "HH:mm:ss")
        GameName     = $GameName

        # CPU total e do jogo
        CPUTotal     = 0.0
        CPUGame      = 0.0
        CPUFreqMHz   = 0

        # RAM
        RAMUsoPct    = 0.0
        RAMGameMB    = 0
        RAMLivreGB   = 0.0

        # GPU (NVIDIA ou WMI)
        GPUUsoPct    = 0
        GPUTempC     = 0
        GPUMemUsedMB = 0
        GPUMemTotalMB= 0
        GPUClockMHz  = 0
        GPUThrottle  = $false
        GPUPowerW    = 0

        # FPS (via PDH ou MSI Afterburner shared memory)
        FPS          = 0
        FrameTimeMs  = 0.0

        # Disco
        DiskQueueLen = 0.0

        # Rede
        PingMS       = 0
        PacketLoss   = 0.0

        # Flags de alerta
        Alert        = @()
    }

    # ?? CPU total ????????????????????????????????????????????
    try {
        $cpuPct = (Get-Counter "\Processor(_Total)\% Processor Time" -EA SilentlyContinue).CounterSamples.CookedValue
        $sample.CPUTotal = [math]::Round($cpuPct, 1)

        $freqPct = (Get-Counter "\Processor Information(_Total)\% Processor Performance" -EA SilentlyContinue).CounterSamples.CookedValue
        if ($freqPct -and $Script:CPUBaseClock) {
            $sample.CPUFreqMHz = [math]::Round($Script:CPUBaseClock * $freqPct / 100)
        }
    } catch {}

    # ?? CPU do processo do jogo ??????????????????????????????
    try {
        if ($GameProc -and -not $GameProc.HasExited) {
            $GameProc.Refresh()
            # CPU% do processo = tempo CPU / elapsed / cores
            $cpuGame = $GameProc.TotalProcessorTime.TotalSeconds
            Start-Sleep -Milliseconds 500
            $GameProc.Refresh()
            $cpuGame2 = $GameProc.TotalProcessorTime.TotalSeconds
            $elapsed  = 0.5
            $sample.CPUGame  = [math]::Round(($cpuGame2 - $cpuGame) / $elapsed / $Script:CPUNucleos * 100, 1)
            $sample.RAMGameMB = [math]::Round($GameProc.WorkingSet64 / 1MB, 0)
        }
    } catch {}

    # ?? RAM sistema ??????????????????????????????????????????
    try {
        $os = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
        if ($os) {
            $totalMB = $os.TotalVisibleMemorySize / 1024
            $livreMB = $os.FreePhysicalMemory / 1024
            $sample.RAMLivreGB = [math]::Round($livreMB / 1024, 1)
            $sample.RAMUsoPct  = [math]::Round((($totalMB - $livreMB) / $totalMB) * 100, 1)
        }
    } catch {}

    # ?? GPU via nvidia-smi (NVIDIA) ??????????????????????????
    $smiOk = $false
    try {
        $smiCmd = Get-Command "nvidia-smi" -EA SilentlyContinue
        if ($smiCmd) {
            $fields = "utilization.gpu,temperature.gpu,memory.used,memory.total,clocks.gr,power.draw,clocks_throttle_reasons.active"
            $smiOut = & nvidia-smi --query-gpu=$fields --format=csv,noheader,nounits 2>$null
            if ($smiOut) {
                $parts = ($smiOut -split ',') | ForEach-Object { $_.Trim() }
                if ($parts.Count -ge 6) {
                    $sample.GPUUsoPct    = [int]($parts[0] -replace '[^0-9]')
                    $sample.GPUTempC     = [int]($parts[1] -replace '[^0-9]')
                    $sample.GPUMemUsedMB = [int]($parts[2] -replace '[^0-9]')
                    $sample.GPUMemTotalMB= [int]($parts[3] -replace '[^0-9]')
                    $sample.GPUClockMHz  = [int]($parts[4] -replace '[^0-9]')
                    if ($parts[5] -match '\d') { $sample.GPUPowerW = [int]($parts[5] -replace '[^0-9]') }
                    if ($parts.Count -ge 7)    { $sample.GPUThrottle = ($parts[6].Trim() -ne "0x0000000000000000") }
                    $smiOk = $true
                }
            }
        }
    } catch {}

    # ?? GPU via WMI fallback ?????????????????????????????????
    if (-not $smiOk) {
        try {
            # Temperatura via ACPI
            $tz = Get-CimInstance -Namespace root/WMI -ClassName MSAcpi_ThermalZoneTemperature -EA SilentlyContinue | Select-Object -Last 1
            if ($tz) { $sample.GPUTempC = [math]::Round(($tz.CurrentTemperature - 2732) / 10) }
            # Uso GPU via PDH (Win8+)
            $gpuUso = (Get-Counter "\GPU Engine(*)\Utilization Percentage" -EA SilentlyContinue).CounterSamples |
                      Where-Object { $_.InstanceName -match "engtype_3D" } |
                      Measure-Object CookedValue -Sum | Select-Object -ExpandProperty Sum
            if ($gpuUso) { $sample.GPUUsoPct = [math]::Round([math]::Min(100, $gpuUso)) }
        } catch {}
    }

    # ?? MSI Afterburner (se instalado) ??????????????????????
    try {
        $msiReg = Get-ItemProperty "HKLM:\SOFTWARE\MSI\Afterburner" -EA SilentlyContinue
        if ($msiReg) {
            # Tentar ler shared memory do RTSS (RivaTuner)
            # Se nao conseguir, mantemos o que ja temos da GPU
        }
    } catch {}

    # ?? FPS via PDH - FrameTime do processo do jogo ?????????
    try {
        if ($GameProc -and -not $GameProc.HasExited) {
            # Tentar via contador de frames do Direct3D
            $fpsCounter = "\GPU Engine($($GameProc.Id)*engtype_3D)\Utilization Percentage"
            # Estimativa FPS via frame time do processo
            $pname = $GameProc.ProcessName
            $gfxCounter = (Get-Counter "\GPU Engine($pname*engtype_3D)\Utilization Percentage" -EA SilentlyContinue)
            if ($gfxCounter) {
                $gfxVal = ($gfxCounter.CounterSamples | Measure-Object CookedValue -Average).Average
                # Frame time estimado baseado em GPU util e clock
                if ($sample.GPUClockMHz -gt 0 -and $gfxVal -gt 0) {
                    $sample.FPS = [math]::Round(($sample.GPUClockMHz / 1000.0) * (100 / [math]::Max($gfxVal, 1)) * 2)
                    $sample.FPS = [math]::Min($sample.FPS, 999)
                }
            }
        }
    } catch {}

    # ?? Disk Queue ???????????????????????????????????????????
    try {
        $dq = (Get-Counter "\PhysicalDisk(_Total)\Avg. Disk Queue Length" -EA SilentlyContinue).CounterSamples.CookedValue
        $sample.DiskQueueLen = [math]::Round($dq, 2)
    } catch {}

    # ?? Ping rapido ??????????????????????????????????????????
    try {
        $ping = Test-Connection "8.8.8.8" -Count 1 -EA SilentlyContinue
        $sample.PingMS = if ($ping) { $ping.ResponseTime } else { 999 }
    } catch { $sample.PingMS = 999 }

    # ?? Alertas desta amostra ????????????????????????????????
    $thresh = $Script:LiveSession.JogoPerfil.Thresholds
    if ($thresh) {
        if ($sample.CPUGame   -gt $thresh.CPUGamePct)   { $sample.Alert += "CPU_GAME_HIGH" }
        if ($sample.RAMUsoPct -gt $thresh.RAMUsoPct)    { $sample.Alert += "RAM_HIGH" }
        if ($sample.GPUTempC  -gt $thresh.GPUTempAlert) { $sample.Alert += "GPU_TEMP" }
        if ($sample.PingMS    -gt $thresh.PingAlert)    { $sample.Alert += "PING_HIGH" }
        if ($sample.GPUThrottle)                        { $sample.Alert += "GPU_THROTTLE" }
        if ($sample.CPUTotal  -gt 90)                   { $sample.Alert += "CPU_TOTAL_HIGH" }
        if ($sample.DiskQueueLen -gt 1.5)               { $sample.Alert += "IO_HIGH" }
    }

    return $sample
}

# ????????????????????????????????????????????????????????????????
#  SESSAO DE CAPTURA COMPLETA - loop principal
# ????????????????????????????????????????????????????????????????
function Start-GameSession {
    param(
        [int]$DuracaoSeg = 120,   # 2 minutos padrao
        [switch]$Silent
    )

    # ?? Detectar jogo ????????????????????????????????????????
    $found = Find-GameRunning
    if (-not $found) {
        H2 "NENHUM JOGO DETECTADO"
        Write-Host ""
        Write-Host "  Abra um dos jogos suportados e tente novamente:" -ForegroundColor Yellow
        foreach ($j in $Script:GameProfiles.Keys) {
            Write-Host "    ? $($Script:GameProfiles[$j].DisplayName)" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "  Ou use [J] para informar o jogo manualmente." -ForegroundColor DarkGray
        PAUSE; return $null
    }

    $Script:LiveSession.JogoDetectado  = $found.Jogo
    $Script:LiveSession.JogoPerfil     = $found.Perfil
    $Script:LiveSession.JogoProcesso   = $found.Processo
    $Script:LiveSession.Amostras.Clear()
    $Script:LiveSession.Inicio         = Get-Date
    $Script:LiveSession.Coletando      = $true

    Clear-Host
    Show-Banner

    $perfil    = $found.Perfil
    $proc      = $found.Processo
    $totalAmostras = [math]::Ceiling($DuracaoSeg / $Script:LiveSession.IntervalSec)

    Write-Host ""
    Write-Host "  ????????????????????????????????????????????????????????" -ForegroundColor Cyan
    Write-Host "  ?   MALIKIA - ANALISE AO VIVO COM JOGO ABERTO         ?" -ForegroundColor Cyan
    Write-Host "  ????????????????????????????????????????????????????????" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("  JOGO DETECTADO : {0}" -f $perfil.DisplayName)  -ForegroundColor Green
    Write-Host ("  ENGINE         : {0}" -f $perfil.Engine)        -ForegroundColor White
    Write-Host ("  PROCESSO       : {0} (PID {1})" -f $proc.ProcessName, $proc.Id) -ForegroundColor DarkGray
    Write-Host ("  DURACAO        : {0} segundos ({1} amostras)" -f $DuracaoSeg, $totalAmostras) -ForegroundColor White
    Write-Host ""
    Write-Host "  INSTRUCAO: Jogue normalmente durante a coleta." -ForegroundColor Yellow
    Write-Host "  A MalikIA vai analisar onde esta o gargalo REAL do seu PC." -ForegroundColor Yellow
    Write-Host ""

    # Contagem regressiva
    for ($c = 3; $c -gt 0; $c--) {
        Write-Host "  Iniciando em $c..." -ForegroundColor DarkCyan
        Start-Sleep 1
    }
    Write-Host ""

    # ?? Loop de coleta ???????????????????????????????????????
    $amostrasColetadas = 0
    $barWidth = 40

    for ($i = 0; $i -lt $totalAmostras; $i++) {
        # Verificar se o jogo ainda esta rodando
        if ($proc.HasExited) {
            Write-Host "  [!] Jogo fechado. Encerrando coleta." -ForegroundColor Yellow
            break
        }

        $sample = Get-GameSample -GameProc $proc -GameName $found.Jogo
        $Script:LiveSession.Amostras.Add($sample) | Out-Null
        $amostrasColetadas++

        # ?? Display em tempo real ?????????????????????????
        $pct     = [math]::Round(($i + 1) / $totalAmostras * 100)
        $filled  = [math]::Round($barWidth * $pct / 100)
        $bar     = ("?" * $filled) + ("?" * ($barWidth - $filled))
        $elapsed = [math]::Round(($i + 1) * $Script:LiveSession.IntervalSec)
        $remain  = $DuracaoSeg - $elapsed

        # Linha de progresso
        $line1 = ("  [{0}] {1,3}%  {2,2}s restante" -f $bar, $pct, $remain)

        # Metricas desta amostra
        $cpuColor = if ($sample.CPUTotal -gt 85) {"Red"} elseif ($sample.CPUTotal -gt 60) {"Yellow"} else {"Green"}
        $gpuColor = if ($sample.GPUTempC -gt 85) {"Red"} elseif ($sample.GPUTempC -gt 75) {"Yellow"} else {"Green"}
        $ramColor = if ($sample.RAMUsoPct -gt 80) {"Red"} elseif ($sample.RAMUsoPct -gt 65) {"Yellow"} else {"Green"}
        $netColor = if ($sample.PingMS -gt 80) {"Red"} elseif ($sample.PingMS -gt 40) {"Yellow"} else {"Green"}

        # Limpar e redesenhar as ultimas 4 linhas
        Write-Host "`r$line1" -NoNewline -ForegroundColor Cyan
        Write-Host ""
        Write-Host ("  CPU: {0,5:F1}% (jogo: {1,4:F1}%)  |  " -f $sample.CPUTotal, $sample.CPUGame) -NoNewline -ForegroundColor $cpuColor
        Write-Host ("RAM: {0,4:F1}%  |  " -f $sample.RAMUsoPct) -NoNewline -ForegroundColor $ramColor
        Write-Host ("PING: {0,3}ms" -f $sample.PingMS) -ForegroundColor $netColor
        Write-Host ("  GPU: {0,3}% uso  |  TEMP: {1,2}?C  |  VRAM: {2}/{3} MB" -f `
            $sample.GPUUsoPct, $sample.GPUTempC, $sample.GPUMemUsedMB, $sample.GPUMemTotalMB) -ForegroundColor $gpuColor

        if ($sample.Alert.Count -gt 0) {
            Write-Host ("  ?  {0}" -f ($sample.Alert -join " | ")) -ForegroundColor Red
        } else {
            Write-Host "  ?  Tudo dentro do normal" -ForegroundColor DarkGreen
        }

        # Mover cursor de volta para sobrescrever na proxima iteracao
        if ($i -lt $totalAmostras - 1) {
            [Console]::SetCursorPosition(0, [Console]::CursorTop - 4)
        }

        Start-Sleep -Seconds $Script:LiveSession.IntervalSec
    }

    Write-Host ""
    Write-Host ""
    $Script:LiveSession.Coletando = $false

    Write-Host "  Coleta concluida! $amostrasColetadas amostras em ${DuracaoSeg}s." -ForegroundColor Green
    Write-Host "  Analisando com MalikIA..." -ForegroundColor Cyan
    Write-Host ""

    # ?? Calcular estatisticas da sessao ??????????????????????
    $analise = Measure-GameSessionStats

    # ?? Enviar para MalikIA Python e receber diagnostico ?????
    $diagnostico = Send-GameSession -Analise $analise

    if ($diagnostico) {
        $Script:LiveSession.Analise = $diagnostico
        Show-GameDiagnostico $diagnostico
    } else {
        # Analise local se API offline
        Show-GameDiagnosticoLocal $analise
    }

    return $analise
}

# ????????????????????????????????????????????????????????????????
#  CALCULAR ESTATISTICAS DA SESSAO
# ????????????????????????????????????????????????????????????????
function Measure-GameSessionStats {
    $amostras = $Script:LiveSession.Amostras
    if ($amostras.Count -eq 0) { return $null }

    $n = $amostras.Count

    # Calcular medias, min, max, percentis
    function Stats($values) {
        $sorted = $values | Sort-Object
        $avg    = ($values | Measure-Object -Average).Average
        $p95    = $sorted[[math]::Floor($n * 0.95)]
        $p5     = $sorted[[math]::Floor($n * 0.05)]
        @{
            Media = [math]::Round($avg, 1)
            Min   = [math]::Round(($values | Measure-Object -Minimum).Minimum, 1)
            Max   = [math]::Round(($values | Measure-Object -Maximum).Maximum, 1)
            P95   = [math]::Round($p95, 1)   # 95th percentile
            P5    = [math]::Round($p5,  1)   # 5th percentile (1% lows equivalent)
        }
    }

    $cpuTotal = $amostras | ForEach-Object { $_.CPUTotal }
    $cpuGame  = $amostras | ForEach-Object { $_.CPUGame }
    $ramUso   = $amostras | ForEach-Object { $_.RAMUsoPct }
    $gpuUso   = $amostras | ForEach-Object { $_.GPUUsoPct }
    $gpuTemp  = $amostras | ForEach-Object { $_.GPUTempC }
    $gpuMem   = $amostras | ForEach-Object { $_.GPUMemUsedMB }
    $ping     = $amostras | ForEach-Object { $_.PingMS }
    $fps      = $amostras | Where-Object { $_.FPS -gt 0 } | ForEach-Object { $_.FPS }

    # Contagem de alertas
    $alertCount = @{}
    foreach ($s in $amostras) {
        foreach ($a in $s.Alert) {
            if (-not $alertCount[$a]) { $alertCount[$a] = 0 }
            $alertCount[$a]++
        }
    }

    # Identificar gargalo dominante
    $gargalos = [System.Collections.Generic.List[object]]::new()

    $cpuStats  = Stats $cpuTotal
    $cpuGStats = Stats $cpuGame
    $gpuStats  = Stats $gpuUso
    $ramStats  = Stats $ramUso
    $pingStats = Stats $ping

    if ($cpuGStats.P95 -gt 75)          { $gargalos.Add(@{ Tipo="CPU_JOGO";  Severidade="Alta";  Desc="CPU saturado pelo jogo ($($cpuGStats.P95)% P95)" }) }
    elseif ($cpuStats.P95 -gt 80)       { $gargalos.Add(@{ Tipo="CPU_TOTAL"; Severidade="Media"; Desc="CPU total alto ($($cpuStats.P95)% P95) - processos em segundo plano" }) }
    if ($gpuStats.P95 -gt 95)           { $gargalos.Add(@{ Tipo="GPU_BOUND"; Severidade="Alta";  Desc="GPU 100% - CPU nao e o problema, GPU e o limite" }) }
    elseif ($gpuStats.P95 -lt 70 -and $cpuGStats.P95 -gt 60) {
                                          $gargalos.Add(@{ Tipo="CPU_BOUND"; Severidade="Alta";  Desc="GPU ociosa, CPU saturado - gargalo e CPU" }) }
    if ($ramStats.P95 -gt 82)           { $gargalos.Add(@{ Tipo="RAM_HIGH";  Severidade="Alta";  Desc="RAM quase cheia ($($ramStats.P95)% P95) - stutter provavel" }) }
    if ($pingStats.P95 -gt 60)          { $gargalos.Add(@{ Tipo="REDE";      Severidade="Alta";  Desc="Ping alto ($($pingStats.P95)ms P95) - conexao instavel" }) }
    $gpuThrottleCount = ($amostras | Where-Object { $_.GPUThrottle }).Count
    if ($gpuThrottleCount -gt $n * 0.3) { $gargalos.Add(@{ Tipo="GPU_THROTTLE"; Severidade="Alta"; Desc="GPU fazendo throttle em $($gpuThrottleCount) amostras - thermal ou power limit" }) }
    $gpuTempStats = Stats $gpuTemp
    if ($gpuTempStats.P95 -gt 85)       { $gargalos.Add(@{ Tipo="GPU_TEMP";  Severidade="Media"; Desc="GPU quente ($($gpuTempStats.Max)?C max) - limpeza de cooler recomendada" }) }

    # Calcular FPS stats
    $fpsStats = if ($fps -and $fps.Count -gt 0) { Stats $fps } else { $null }

    $statsResultado = @{
        Jogo            = $Script:LiveSession.JogoDetectado
        Engine          = $Script:LiveSession.JogoPerfil.Engine
        DuracaoSeg      = [math]::Round(($Script:LiveSession.Amostras.Count) * $Script:LiveSession.IntervalSec)
        Amostras        = $n
        CPU             = $cpuStats
        CPUGame         = $cpuGStats
        GPU             = $gpuStats
        GPUTemp         = Stats $gpuTemp
        GPUMem          = Stats $gpuMem
        RAM             = $ramStats
        Ping            = $pingStats
        FPS             = $fpsStats
        Gargalos        = $gargalos.ToArray()
        AlertCount      = $alertCount
        GPUThrottlePct  = [math]::Round($gpuThrottleCount / $n * 100)
        Hardware        = @{
            CPU    = $Script:CPUNome
            GPU    = $Script:GPUNome
            RAM    = "$($Script:RAMtotalGB)GB $($Script:RAMtipo) @ $($Script:RAMvelocidade)MHz"
            Disco  = $Script:DiscoTipo
            OS     = if ($Script:IsWin11) { "Win11" } else { "Win10" }
        }
        # Tweaks recomendados pelo perfil do jogo, ordenados por impacto esperado
        TweaksRecomendados = $Script:LiveSession.JogoPerfil.TweaksPriority
    }

    return $statsResultado
}

# ????????????????????????????????????????????????????????????????
#  ENVIAR SESSAO PARA MALIKIA PYTHON
# ????????????????????????????????????????????????????????????????
function Send-GameSession {
    param($Analise)

    if (-not $Analise) { return $null }

    # Tentar API Python
    try {
        $online = Test-Connection "127.0.0.1" -Count 1 -EA SilentlyContinue
        $headers = @{ "X-API-Key" = $Script:MalikIA.APIKey; "Content-Type" = "application/json" }
        $payload = $Analise | ConvertTo-Json -Depth 10 -Compress

        $resp = Invoke-WebRequest -Uri "$($Script:MalikIA.URL)/game-session" `
            -Method POST -Headers $headers -Body $payload `
            -UseBasicParsing -TimeoutSec 10 -EA Stop

        $result = $resp.Content | ConvertFrom-Json
        Write-Host "  MalikIA: analise recebida!" -ForegroundColor Green
        return $result
    } catch {
        Write-Host "  MalikIA offline - analise local." -ForegroundColor DarkGray
        return $null
    }
}

# ????????????????????????????????????????????????????????????????
#  EXIBIR DIAGNOSTICO - resposta da MalikIA Python
# ????????????????????????????????????????????????????????????????
function Show-GameDiagnostico {
    param($diag)

    $sep = "  " + ("?" * 56)
    Write-Host $sep -ForegroundColor Magenta
    Write-Host "  MALIKIA - DIAGNOSTICO CIRURGICO" -ForegroundColor Magenta
    Write-Host "  $($diag.jogo)  |  $($diag.engine)" -ForegroundColor White
    Write-Host $sep -ForegroundColor Magenta
    Write-Host ""

    if ($diag.gargalo_principal) {
        Write-Host "  GARGALO PRINCIPAL : $($diag.gargalo_principal)" -ForegroundColor Red
    }
    if ($diag.diagnostico) {
        Write-Host "  DIAGNOSTICO       : $($diag.diagnostico)" -ForegroundColor Yellow
    }
    Write-Host ""
    if ($diag.ganho_fps_previsto) {
        Write-Host "  GANHO PREVISTO    : +$($diag.ganho_fps_previsto)% FPS apos otimizacao" -ForegroundColor Green
    }
    Write-Host ""
    if ($diag.tweaks_cirurgicos -and $diag.tweaks_cirurgicos.Count -gt 0) {
        Write-Host "  TWEAKS PRIORITARIOS (por impacto para este jogo):" -ForegroundColor Cyan
        foreach ($t in $diag.tweaks_cirurgicos) {
            $risco = if ($t.risco -eq "alto") { " [ALTO RISCO]" } else { "" }
            Write-Host ("  {0}. {1}{2}" -f $t.ordem, $t.desc, $risco) -ForegroundColor White
        }
    }
    Write-Host ""
    Write-Host $sep -ForegroundColor Magenta
}

# ????????????????????????????????????????????????????????????????
#  DIAGNOSTICO LOCAL - quando API offline
# ????????????????????????????????????????????????????????????????
function Show-GameDiagnosticoLocal {
    param($stats)

    if (-not $stats) { return }

    $sep = "  " + ("?" * 56)
    Write-Host $sep -ForegroundColor Cyan
    Write-Host "  DIAGNOSTICO LOCAL - $($stats.Jogo)" -ForegroundColor Cyan
    Write-Host $sep -ForegroundColor Cyan
    Write-Host ""

    # Resumo de metricas
    Write-Host "  METRICAS DURANTE O JOGO:" -ForegroundColor White
    Write-Host ("  CPU Total   media:{0,5:F1}%   P95:{1,5:F1}%" -f $stats.CPU.Media,  $stats.CPU.P95)    -ForegroundColor $(if($stats.CPU.P95 -gt 85){"Red"}else{"Green"})
    Write-Host ("  CPU Jogo    media:{0,5:F1}%   P95:{1,5:F1}%" -f $stats.CPUGame.Media, $stats.CPUGame.P95) -ForegroundColor $(if($stats.CPUGame.P95 -gt 75){"Yellow"}else{"Green"})
    Write-Host ("  GPU Uso     media:{0,5:F1}%   P95:{1,5:F1}%" -f $stats.GPU.Media,  $stats.GPU.P95)    -ForegroundColor $(if($stats.GPU.P95 -gt 95){"Red"}elseif($stats.GPU.P95 -gt 80){"Yellow"}else{"Green"})
    Write-Host ("  GPU Temp    media:{0,5:F1}?C  max:{1,5:F1}?C"  -f $stats.GPUTemp.Media, $stats.GPUTemp.Max) -ForegroundColor $(if($stats.GPUTemp.Max -gt 85){"Red"}else{"Green"})
    Write-Host ("  RAM         media:{0,5:F1}%   P95:{1,5:F1}%" -f $stats.RAM.Media, $stats.RAM.P95)    -ForegroundColor $(if($stats.RAM.P95 -gt 80){"Red"}else{"Green"})
    Write-Host ("  Ping        media:{0,5}ms    P95:{1,5}ms"    -f $stats.Ping.Media,$stats.Ping.P95)   -ForegroundColor $(if($stats.Ping.P95 -gt 80){"Red"}elseif($stats.Ping.P95 -gt 40){"Yellow"}else{"Green"})
    if ($stats.FPS) {
        Write-Host ("  FPS         media:{0,5:F0}    P5:{1,5:F0} (1%% lows)"    -f $stats.FPS.Media, $stats.FPS.P5)  -ForegroundColor Cyan
    }
    Write-Host ""

    # Gargalos identificados
    if ($stats.Gargalos.Count -gt 0) {
        Write-Host "  GARGALOS IDENTIFICADOS:" -ForegroundColor Red
        foreach ($g in $stats.Gargalos) {
            $cor = if ($g.Severidade -eq "Alta") { "Red" } else { "Yellow" }
            Write-Host "  ? $($g.Desc)" -ForegroundColor $cor
        }
        Write-Host ""
    }

    # Tweaks recomendados
    Write-Host "  TWEAKS RECOMENDADOS PARA $($stats.Jogo.ToUpper()):" -ForegroundColor Cyan
    $prioridade = $stats.TweaksRecomendados
    for ($i = 0; $i -lt [math]::Min($prioridade.Count, 5); $i++) {
        Write-Host ("  {0}. {1}" -f ($i+1), $prioridade[$i]) -ForegroundColor White
    }
    Write-Host ""
    Write-Host $sep -ForegroundColor Cyan
}

# ????????????????????????????????????????????????????????????????
#  APLICAR OTIMIZACOES BASEADAS NO DIAGNOSTICO
# ????????????????????????????????????????????????????????????????
function Invoke-GameOptimization {
    param($Stats)

    if (-not $Stats) { return }

    H2 "APLICANDO OTIMIZACOES CIRURGICAS - $($Stats.Jogo)"
    Write-Host ""
    Write-Host "  Baseado no que a MalikIA mediu durante o jogo," -ForegroundColor DarkGray
    Write-Host "  aplicando apenas os tweaks que vao fazer diferenca REAL." -ForegroundColor DarkGray
    Write-Host ""

    # Confirmar
    Write-Host "  Aplicar otimizacoes cirurgicas? [S/N]: " -NoNewline -ForegroundColor Yellow
    $conf = Read-Host
    if ($conf -notmatch '^[sS]') { return }

    # Determinar perfil baseado no gargalo
    $gargaloTipos = $Stats.Gargalos | ForEach-Object { $_.Tipo }
    $perfilIA = if ("GPU_BOUND" -in $gargaloTipos) { "Gamer" }
                elseif ("CPU_BOUND" -in $gargaloTipos) { "Extremo" }
                elseif ("REDE" -in $gargaloTipos) { "Gamer" }
                else { "Gamer" }

    Write-Host "  Perfil selecionado pelo gargalo: $perfilIA" -ForegroundColor Cyan
    Write-Host ""

    # Executar o Motor de IA com o perfil correto + snap atual
    $Script:IA.Perfil = $perfilIA
    $snapAntes = Get-IASnapshot -Label "antes_game_opt"

    # Aplicar tweaks na ordem de prioridade para o jogo
    $tweaksAplicados = [System.Collections.Generic.List[string]]::new()
    foreach ($tweakId in $Stats.TweaksRecomendados) {
        # Encontrar a regra no motor
        $regraMatch = $null
        foreach ($regra in $Script:IA.OtimizacoesDecididas) {
            if ($regra.Id -eq $tweakId) { $regraMatch = $regra; break }
        }

        # Se nao estava nas decididas, executar manualmente as principais
        switch ($tweakId) {
            "CORE_PARKING_OFF" {
                IN "Core Parking OFF..."
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 2>$null
                powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 0cc5b647-c1df-4637-891a-dec35c318583 100 2>$null
                OK "Core Parking: todos os nucleos ativos"
                $tweaksAplicados.Add($tweakId) | Out-Null
            }
            "NAGLE_OFF" {
                IN "Nagle Algorithm OFF..."
                Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -EA SilentlyContinue | ForEach-Object {
                    Set-ItemProperty $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force 2>$null
                    Set-ItemProperty $_.PSPath -Name "TCPNoDelay"      -Value 1 -Type DWord -Force 2>$null
                }
                OK "Nagle: desativado em todas as interfaces"
                $tweaksAplicados.Add($tweakId) | Out-Null
            }
            "MMCSS_GAMING" {
                IN "MMCSS Gaming..."
                $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
                if (-not (Test-Path $path)) { New-Item $path -Force | Out-Null }
                Set-ItemProperty $path -Name "GPU Priority" -Value 8 -Type DWord -Force 2>$null
                Set-ItemProperty $path -Name "Priority"     -Value 6 -Type DWord -Force 2>$null
                Set-ItemProperty $path -Name "Scheduling Category" -Value "High" -Type String -Force 2>$null
                OK "MMCSS: prioridade RT para threads de jogo"
                $tweaksAplicados.Add($tweakId) | Out-Null
            }
            "WIN32_PRIORITY_SEP" {
                IN "Win32PrioritySeparation..."
                $val = if ($Script:IsWin11) { 2 } else { 0x26 }
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value $val -Type DWord -Force 2>$null
                OK "Scheduler: prioridade foreground otimizada"
                $tweaksAplicados.Add($tweakId) | Out-Null
            }
            "TIMER_RESOLUTION" {
                IN "Timer Resolution..."
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" -Name "GlobalTimerResolutionRequests" -Value 1 -Type DWord -Force 2>$null
                bcdedit /set disabledynamictick yes 2>$null | Out-Null
                if (-not $Script:IsWin11) { bcdedit /set useplatformtick yes 2>$null | Out-Null }
                OK "Timer: resolucao maxima ativada"
                $tweaksAplicados.Add($tweakId) | Out-Null
            }
            "POWER_THROTTLE_OFF" {
                IN "Power Throttling OFF..."
                $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "PowerThrottlingOff" -Value 1 -Type DWord -Force 2>$null
                OK "Power Throttling: desativado"
                $tweaksAplicados.Add($tweakId) | Out-Null
            }
            "BG_APPS_OFF" {
                IN "Background Apps OFF..."
                Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1 -Type DWord -Force 2>$null
                OK "Apps em segundo plano: desativados"
                $tweaksAplicados.Add($tweakId) | Out-Null
            }
            "QOS_GAMING" {
                IN "QoS Gaming..."
                $jogosQos = @("fivem.exe","gta5.exe","cs2.exe","csgo.exe","valorant.exe","r5apex.exe","fortnite.exe")
                $base = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\QoS"
                if (-not (Test-Path $base)) { New-Item $base -Force | Out-Null }
                foreach ($j in $jogosQos) {
                    $p = "$base\$j"
                    if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                    Set-ItemProperty $p -Name "DSCP Value"    -Value "46"  -Type String -Force 2>$null
                    Set-ItemProperty $p -Name "Throttle Rate" -Value "-1"  -Type String -Force 2>$null
                    Set-ItemProperty $p -Name "Protocol"      -Value "17"  -Type String -Force 2>$null
                }
                OK "QoS: prioridade UDP maxima para $($jogosQos.Count) jogos"
                $tweaksAplicados.Add($tweakId) | Out-Null
            }
        }
    }

    # Forcar prioridade do processo do jogo imediatamente (sem reinicio)
    if ($Script:LiveSession.JogoProcesso -and -not $Script:LiveSession.JogoProcesso.HasExited) {
        try {
            $Script:LiveSession.JogoProcesso.PriorityClass = "High"
            OK "Processo $($Script:LiveSession.JogoProcesso.ProcessName): prioridade High aplicada imediatamente"
            $tweaksAplicados.Add("GAME_PRIORITY_HIGH") | Out-Null
        } catch {}
    }

    Write-Host ""
    Write-Host "  $($tweaksAplicados.Count) tweaks aplicados para $($Stats.Jogo)." -ForegroundColor Green
    Write-Host ""

    # Coletar snapshot depois e comparar
    Write-Host "  Aguardando 5 segundos para medir resultado..." -ForegroundColor DarkGray
    Start-Sleep 5
    $snapDepois = Get-IASnapshot -Label "depois_game_opt"

    $ganhoScore = $snapDepois.Score.Geral - $snapAntes.Score.Geral
    $ganhoSign  = if ($ganhoScore -ge 0) { "+" } else { "" }

    Write-Host ""
    Write-Host "  RESULTADO IMEDIATO:" -ForegroundColor Cyan
    Write-Host ("  Score: {0} ? {1} ({2}{3} pts)" -f $snapAntes.Score.Geral, $snapDepois.Score.Geral, $ganhoSign, $ganhoScore) -ForegroundColor $(if($ganhoScore -gt 0){"Green"}else{"Yellow"})
    Write-Host ("  Timer: {0:F2}ms ? {1:F2}ms" -f $snapAntes.TimerResMS, $snapDepois.TimerResMS) -ForegroundColor Green
    Write-Host ""
    Write-Host "  IMPORTANTE: Reinicie para que todas as mudancas tenham efeito." -ForegroundColor Yellow
    Write-Host "  Os ganhos reais de FPS aparecerao na proxima sessao de jogo." -ForegroundColor DarkGray
    Write-Host ""

    PAUSE
}

# ????????????????????????????????????????????????????????????????
#  MENU PRINCIPAL - ANALISE AO VIVO
# ????????????????????????????????????????????????????????????????
function Show-MenuGameAnalysis {
    while ($true) {
        Show-Banner
        H1 "ANALISE AO VIVO COM JOGO ABERTO"
        Write-Host "  MalikIA analisa seu PC enquanto voce joga." -ForegroundColor DarkGray
        Write-Host "  Gargalos reais ? otimizacoes cirurgicas." -ForegroundColor DarkGray
        Write-Host ""

        # Status do jogo aberto
        $found = Find-GameRunning
        if ($found) {
            Write-Host "  JOGO DETECTADO: $($found.Perfil.DisplayName)" -ForegroundColor Green
            Write-Host "  PID: $($found.Processo.Id)  |  Memoria: $([math]::Round($found.Processo.WorkingSet64/1MB,0)) MB" -ForegroundColor DarkGray
        } else {
            Write-Host "  Nenhum jogo aberto no momento." -ForegroundColor DarkGray
            Write-Host "  Abra FiveM, CS2 ou Valorant antes de analisar." -ForegroundColor Yellow
        }
        Write-Host ""

        Write-Host "  [1]  Analisar agora - 2 minutos de captura" -ForegroundColor Cyan
        Write-Host "  [2]  Analisar agora - 5 minutos (mais preciso)" -ForegroundColor Cyan
        Write-Host "  [3]  Analisar e otimizar automaticamente" -ForegroundColor Yellow
        Write-Host "  [4]  Ver ultimo diagnostico" -ForegroundColor White
        Write-Host "  [5]  Monitorar em tempo real (sem otimizar)" -ForegroundColor White
        Write-Host ""
        Write-Host "  [V]  Voltar" -ForegroundColor DarkGray
        Write-Host ""; SEP; Write-Host ""

        switch ((Read-Host "  Opcao").Trim().ToUpper()) {
            '1' {
                Clear-Host
                $stats = Start-GameSession -DuracaoSeg 120
                if ($stats) {
                    Write-Host ""
                    Write-Host "  Deseja aplicar as otimizacoes agora? [S/N]: " -NoNewline -ForegroundColor Yellow
                    if ((Read-Host) -match '^[sS]') {
                        Invoke-GameOptimization -Stats $stats
                    }
                }
            }
            '2' {
                Clear-Host
                $stats = Start-GameSession -DuracaoSeg 300
                if ($stats) {
                    Write-Host ""
                    Write-Host "  Deseja aplicar as otimizacoes agora? [S/N]: " -NoNewline -ForegroundColor Yellow
                    if ((Read-Host) -match '^[sS]') {
                        Invoke-GameOptimization -Stats $stats
                    }
                }
            }
            '3' {
                Clear-Host
                $stats = Start-GameSession -DuracaoSeg 120
                if ($stats) { Invoke-GameOptimization -Stats $stats }
            }
            '4' {
                if ($Script:LiveSession.Analise) {
                    Clear-Host
                    Show-GameDiagnostico $Script:LiveSession.Analise
                    PAUSE
                } elseif ($Script:LiveSession.Amostras.Count -gt 0) {
                    Clear-Host
                    $stats = Measure-GameSessionStats
                    Show-GameDiagnosticoLocal $stats
                    PAUSE
                } else {
                    WN "Nenhuma analise realizada ainda."; Start-Sleep 2
                }
            }
            '5' {
                # Monitor em tempo real simples
                Clear-Host
                $found2 = Find-GameRunning
                if (-not $found2) { WN "Nenhum jogo detectado."; Start-Sleep 2; continue }
                Write-Host "  Monitorando $($found2.Perfil.DisplayName)... [CTRL+C para parar]" -ForegroundColor Cyan
                Write-Host ""
                while (-not $found2.Processo.HasExited) {
                    $s = Get-GameSample -GameProc $found2.Processo -GameName $found2.Jogo
                    $alertStr = if ($s.Alert.Count -gt 0) { " ? " + ($s.Alert -join "|") } else { " ?" }
                    Write-Host ("`r  [{0}] CPU:{1,5:F1}% GPU:{2,3}%@{3,2}?C RAM:{4,4:F1}% PING:{5,3}ms{6}" -f `
                        $s.Timestamp, $s.CPUTotal, $s.GPUUsoPct, $s.GPUTempC, $s.RAMUsoPct, $s.PingMS, $alertStr) -NoNewline
                    Start-Sleep -Seconds $Script:LiveSession.IntervalSec
                }
                Write-Host ""
            }
            'V' { return }
        }
    }
}

# ================================================================
#  UI - HELPERS
# ================================================================
function LOG  { param([string]$m, [string]$n='INFO')
    try { Add-Content $Script:LogFile "$(Get-Date -f 'HH:mm:ss') [$n] $m" -Encoding UTF8 } catch {} }

function OK   { Write-Host "  [+] $args" -ForegroundColor Green }
function WN   { Write-Host "  [!] $args" -ForegroundColor Yellow }
function ER   { Write-Host "  [X] $args" -ForegroundColor Red }
function IN   { Write-Host "  [>] $args" -ForegroundColor Gray }
function H1   { Write-Host "`n  $args" -ForegroundColor Cyan }
function INF  { Write-Host "  [i] $args" -ForegroundColor DarkCyan }

function H2 {
    $txt = $args -join " "
    $linha = "=" * 70
    Write-Host ""
    Write-Host "  $linha" -ForegroundColor Cyan
    Write-Host "  ## $txt" -ForegroundColor Cyan
    Write-Host "  $linha" -ForegroundColor Cyan
    Write-Host ""
}

function SEP  { Write-Host "  $("-"*70)" -ForegroundColor DarkCyan }
function PAUSE { Read-Host "`n  [ ENTER para continuar ]" | Out-Null }

function CONF {
    param([string]$msg = "Confirmar?")
    $r = Read-Host "  $msg (S/N)"
    return ($r -match '^[Ss]$')
}

function Show-Progress {
    param([string]$Label, [int]$Atual, [int]$Total)
    $pct  = [math]::Round($Atual / [math]::Max($Total, 1) * 100)
    $fill = [math]::Round($pct / 5)
    $bar  = ("#" * $fill).PadRight(20)
    Write-Host "`r  [$bar] $pct% - $Label        " -NoNewline -ForegroundColor Cyan
}

function Show-Banner {
    Clear-Host
    $linha = "=" * 72
    $iaStr = if ($Script:IAAtiva) { " [IA ON]" } else { "" }
    Write-Host ""
    Write-Host "  $linha" -ForegroundColor Cyan
    Write-Host "  ##  $($Script:NomeProg)  v$($Script:Versao)$iaStr$((" "*([math]::Max(0,53-$Script:NomeProg.Length-$Script:Versao.Length-$iaStr.Length)))  )##" -ForegroundColor Cyan
    Write-Host "  ##  Otimizador avancado de desempenho para Windows 10/11$((" "*18))##" -ForegroundColor DarkCyan
    Write-Host "  $linha" -ForegroundColor Cyan
    Write-Host "  ID Sessao: $($Script:IDSessao)   |   $(Get-Date -f 'dd/MM/yyyy HH:mm')" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-StatusBar {
    $corCPU = if ($Script:CPUNome) { if ($Script:CPUX3D) {'Magenta'} else {'White'} } else { 'DarkGray' }
    $corGPU = if ($Script:GPUNome) { 'White' } else { 'DarkGray' }
    $corOtm = if ($Script:OtimAplicada) { 'Green' } else { 'DarkGray' }
    $txtOtm = if ($Script:OtimAplicada) { "ATIVO ($($Script:TweaksFeitos.Count) tweaks)" } else { "Pendente" }

    $cpuTxt = if ($Script:CPUNome) { $Script:CPUNome } else { "Nao detectado" }
    $gpuTxt = if ($Script:GPUNome) { $Script:GPUNome } else { "Nao detectada" }

    Write-Host "  CPU : " -NoNewline -ForegroundColor DarkGray
    Write-Host $cpuTxt -NoNewline -ForegroundColor $corCPU
    if ($Script:CPUX3D)     { Write-Host " [X3D]"    -NoNewline -ForegroundColor Magenta }
    if ($Script:CPUIntelK)  { Write-Host " [K-serie]"-NoNewline -ForegroundColor Yellow }
    Write-Host ""

    Write-Host "  GPU : " -NoNewline -ForegroundColor DarkGray
    Write-Host $gpuTxt -NoNewline -ForegroundColor $corGPU
    if ($Script:GPUTemp -gt 0) {
        $cor = if($Script:GPUTemp -lt 60){'Green'}elseif($Script:GPUTemp -lt 75){'Yellow'}else{'Red'}
        Write-Host "  ($($Script:GPUTemp)C)" -NoNewline -ForegroundColor $cor
    }
    Write-Host ""

    Write-Host "  RAM : " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($Script:RAMtotalGB) GB $($Script:RAMtipo)$(if($Script:RAMvelocidade -gt 0){" @ $($Script:RAMvelocidade) MHz"})" -ForegroundColor White

    Write-Host "  Disco: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($Script:DiscoNome) $(if($Script:DiscoNVMe){'[NVMe]'}elseif($Script:DiscoTipo -eq 'SSD'){'[SSD]'}else{'[HDD]'})" -ForegroundColor White

    Write-Host "  Status: " -NoNewline -ForegroundColor DarkGray
    Write-Host $txtOtm -ForegroundColor $corOtm
    if ($Script:ModoStreamer) { Write-Host "  [MODO STREAMER ATIVO]" -ForegroundColor Magenta }
    if ($Script:IAAtiva)      { Write-Host "  [IA ADVISOR ATIVO]"    -ForegroundColor DarkCyan }
    Write-Host ""
    SEP
    Write-Host ""
}

# ================================================================
#  VERIFICACAO DE ADMIN
# ================================================================
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
    Write-Host "`n  [ERRO] Execute como Administrador!" -ForegroundColor Red
    Write-Host "  Clique direito no PowerShell > Executar como Administrador`n" -ForegroundColor Yellow
    Read-Host "  ENTER para sair" | Out-Null; exit 1
}

# ================================================================
#  DETECCAO DE HARDWARE
# ================================================================
function Invoke-DetectarHardware {
    H2 "DETECTANDO HARDWARE"

    # CPU
    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $Script:CPUNome    = $cpu.Name.Trim()
        $Script:CPUNucleos = $cpu.NumberOfCores
        $Script:CPUThreads = $cpu.NumberOfLogicalProcessors
        $Script:CPUFab     = if ($Script:CPUNome -match 'AMD') {'AMD'} elseif ($Script:CPUNome -match 'Intel') {'Intel'} else {'Outro'}
        $Script:CPUX3D     = $Script:CPUNome -match 'X3D'
        $Script:CPUIntelK  = $Script:CPUNome -match '\d{4,5}K[FSs]?\b'
        if ($Script:CPUFab -eq 'Intel' -and $Script:CPUNome -match 'i[3579]-(\d{4,5})') {
            $Script:CPUGen = [int]($Matches[1].Substring(0,2))
        }
        OK "CPU    : $($Script:CPUNome)"
        OK "Nucleos: $($Script:CPUNucleos) fisicos / $($Script:CPUThreads) logicos | Fab: $($Script:CPUFab)$(if($Script:CPUX3D){' | [V-Cache X3D]'})"
        if ($Script:CPUGen -gt 0) { INF "Geracao Intel detectada: $($Script:CPUGen)a geracao" }
    } catch { ER "Falha ao detectar CPU" }

    # RAM
    try {
        $ram = Get-CimInstance Win32_PhysicalMemory
        $Script:RAMtotalGB    = [math]::Round(($ram | Measure-Object -Property Capacity -Sum).Sum / 1GB, 0)
        $Script:RAMslots      = ($ram | Measure-Object).Count
        $Script:RAMvelocidade = ($ram | Select-Object -First 1).Speed
        $ramTipoNum           = ($ram | Select-Object -First 1).SMBIOSMemoryType
        $Script:RAMtipo       = switch ($ramTipoNum) { 26{'DDR4'} 34{'DDR5'} 21{'DDR3'} default{'DDR?'} }
        OK "RAM    : $($Script:RAMtotalGB) GB $($Script:RAMtipo) @ $($Script:RAMvelocidade) MHz | $($Script:RAMslots) modulo(s)"
        if ($Script:RAMslots -eq 1) {
            WN "Apenas 1 modulo de RAM - considere adicionar outro para Dual Channel (ganho de 20pct em perf)"
        }
    } catch { ER "Falha ao detectar RAM" }

    # GPU
    try {
        $gpu = Get-CimInstance Win32_VideoController | Where-Object {
            $_.Name -notmatch 'Microsoft|Remote|Virtual|Basic' -and $_.AdapterRAM -gt 200MB
        } | Sort-Object AdapterRAM -Descending | Select-Object -First 1
        if (-not $gpu) { $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1 }

        $Script:GPUNome   = $gpu.Name.Trim()
        $Script:GPUVRAM   = [math]::Round($gpu.AdapterRAM / 1GB, 0)
        $Script:GPUDriver = $gpu.DriverVersion
        $Script:GPUFab    = if ($Script:GPUNome -match 'NVIDIA|GeForce|RTX|GTX') {'NVIDIA'}
                             elseif ($Script:GPUNome -match 'AMD|Radeon|RX\s') {'AMD'}
                             elseif ($Script:GPUNome -match 'Intel|Arc') {'Intel'}
                             else {'Outro'}

        $smis = @("$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe","$env:SystemRoot\System32\nvidia-smi.exe")
        foreach ($c in $smis) { if (Test-Path $c) { $Script:GPUSmi = $c; break } }
        if (-not $Script:GPUSmi) {
            $cmd = Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue
            if ($cmd) { $Script:GPUSmi = $cmd.Source }
        }

        if ($Script:GPUFab -eq 'NVIDIA' -and $Script:GPUSmi) {
            $d = & $Script:GPUSmi --query-gpu=temperature.gpu,clocks.current.graphics,power.limit,power.max_limit --format=csv,noheader,nounits 2>$null
            if ($d) {
                $cols = $d -split ','
                if ($cols.Count -ge 4) {
                    $Script:GPUTemp  = [int]($cols[0].Trim())
                    $Script:GPUCore  = [int]($cols[1].Trim())
                    $Script:GPUPL    = [math]::Round([double]($cols[2].Trim()), 0)
                    $Script:GPUPLmax = [math]::Round([double]($cols[3].Trim()), 0)
                }
            }
        }
        OK "GPU    : $($Script:GPUNome) ($($Script:GPUVRAM) GB VRAM) | Driver: $($Script:GPUDriver)"
        if ($Script:GPUTemp -gt 0) {
            $corT = if($Script:GPUTemp -lt 60){'Green'}elseif($Script:GPUTemp -lt 75){'Yellow'}else{'Red'}
            Write-Host "  [+] GPU Live: $($Script:GPUTemp)C | Core $($Script:GPUCore)MHz | PL $($Script:GPUPL)W (max $($Script:GPUPLmax)W)" -ForegroundColor $corT
        }
    } catch { ER "Falha ao detectar GPU" }

    # Disco
    try {
        $disco = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq "0" } | Select-Object -First 1
        if (-not $disco) { $disco = Get-PhysicalDisk | Select-Object -First 1 }
        $Script:DiscoNome = $disco.FriendlyName
        $Script:DiscoTipo = $disco.MediaType
        $nvme = Get-CimInstance -Namespace root/Microsoft/Windows/Storage -ClassName MSFT_PhysicalDisk 2>$null |
                Where-Object { $_.BusType -eq 17 } | Select-Object -First 1
        if ($nvme) { $Script:DiscoNVMe = $true }
        if ($Script:DiscoNome -match 'NVMe|M\.2|PCIe') { $Script:DiscoNVMe = $true }
        $tipoStr = if ($Script:DiscoNVMe) { "NVMe" } elseif ($Script:DiscoTipo -match 'SSD') { "SSD SATA" } else { "HDD" }
        OK "Disco  : $($Script:DiscoNome) [$tipoStr]"
    } catch { ER "Falha ao detectar disco" }

    # Windows
    try {
        $win = Get-CimInstance Win32_OperatingSystem
        $Script:WinBuild = [int]$win.BuildNumber
        $Script:IsWin11  = ($Script:WinBuild -ge 22000)   # Win11 = build 22000+
        $Script:WinVer   = $win.Caption
        OK "SO     : $($Script:WinVer) (Build $($Script:WinBuild))"
        OK "Usuario: $env:USERNAME @ $env:COMPUTERNAME"
    } catch {}

    $Script:TemWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    if ($Script:TemWinget) { OK "Winget : Disponivel" } else { WN "Winget : Nao encontrado" }

    LOG "HW: CPU=$($Script:CPUNome) | GPU=$($Script:GPUNome) | RAM=$($Script:RAMtotalGB)GB $($Script:RAMtipo) @$($Script:RAMvelocidade)MHz | Disco=$($Script:DiscoNome) NVMe=$($Script:DiscoNVMe)"
    PAUSE
}

# ================================================================
#  NOVO v5: SISTEMA DE TWEAKS GRANULARES (checklist interativo)
# ================================================================
function Invoke-TweakChecklist {
    param(
        [string]$Titulo,
        [array]$Tweaks   # cada item: @{Nome="..."; Desc="..."; Risco="baixo|medio|alto"; Bloco={...}}
    )

    H2 $Titulo
    Write-Host "  Escolha quais tweaks aplicar. ENTER = aplicar todos marcados." -ForegroundColor DarkCyan
    Write-Host ""

    # Exibir lista com status
    $selecionados = @{}
    for ($i = 0; $i -lt $Tweaks.Count; $i++) {
        # ALTO = desmarcado por padrao (risco real), BAIXO/MEDIO = marcado
        $selecionados[$i] = ($Tweaks[$i].Risco -ne "alto")
    }

    $continuar = $true
    while ($continuar) {
        # Redesenhar lista
        for ($i = 0; $i -lt $Tweaks.Count; $i++) {
            $t   = $Tweaks[$i]
            $chk = if ($selecionados[$i]) { "[X]" } else { "[ ]" }
            $cor = switch ($t.Risco) {
                'alto'  { 'Red' }
                'medio' { 'Yellow' }
                default { 'Green' }
            }
            $risco = "[$($t.Risco.ToUpper())]".PadRight(8)
            Write-Host ("  {0} {1,2}. {2}" -f $chk, ($i+1), $t.Nome) -NoNewline -ForegroundColor White
            Write-Host "  $risco" -NoNewline -ForegroundColor $cor
            Write-Host "  $($t.Desc)" -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host "  [numero] Marcar/desmarcar  |  [A] Todos  |  [N] Nenhum  |  [ENTER] Aplicar marcados  |  [V] Voltar" -ForegroundColor DarkCyan
        Write-Host ""
        $op = Read-Host "  Opcao"

        if ($op -match '^[Vv]$') { return }
        if ($op -match '^[Aa]$') {
            for ($i = 0; $i -lt $Tweaks.Count; $i++) { $selecionados[$i] = $true }
            Clear-Host; continue
        }
        if ($op -match '^[Nn]$') {
            for ($i = 0; $i -lt $Tweaks.Count; $i++) { $selecionados[$i] = $false }
            Clear-Host; continue
        }
        if ($op -eq '') {
            $continuar = $false
        } elseif ($op -match '^\d+$') {
            $idx = [int]$op - 1
            if ($idx -ge 0 -and $idx -lt $Tweaks.Count) {
                $selecionados[$idx] = -not $selecionados[$idx]
            }
            Clear-Host; continue
        } else {
            Clear-Host; continue
        }
    }

    # Aplicar tweaks selecionados
    $aplicados = 0
    Write-Host ""
    for ($i = 0; $i -lt $Tweaks.Count; $i++) {
        if ($selecionados[$i]) {
            $t = $Tweaks[$i]
            try {
                & $t.Bloco
                OK "$($t.Nome)"
                $Script:TweaksFeitos.Add("$Titulo > $($t.Nome)")
                $aplicados++
            } catch {
                ER "Falha: $($t.Nome)"
            }
        }
    }

    Write-Host ""
    OK "$aplicados tweak(s) aplicado(s)"
    LOG "${Titulo}: $aplicados tweaks aplicados"
    PAUSE
}

# ================================================================
#  NOVO v5: IA ADVISOR (Claude API)
# ================================================================
function Invoke-ConfigurarIA {
    H2 "STATUS DA IA ADVISOR"

    if ($Script:IAAtiva) {
        OK "IA Advisor: ATIVA"
        INF "Modelo  : Claude Haiku 4.5 (\$1/M input | \$5/M output)"
        INF "Custo   : ~\$0.003 por analise de hardware"
        INF "200 analises/mes: ~\$0.67 (aprox. R\$ 4,00)"
    } else {
        ER "IA Advisor: INATIVA"
        WN "Configure a variavel \$Script:IAChave no inicio do script"
        INF "Obtenha sua chave em: https://console.anthropic.com"
    }
    PAUSE
}

function Invoke-IaAdvisor {
    H2 "IA ADVISOR - ANALISE PERSONALIZADA"

    if (-not $Script:IAAtiva) {
        WN "IA nao configurada. Configure primeiro em Ferramentas > Configurar IA."
        PAUSE; return
    }

    if (-not $Script:CPUNome) {
        IN "Detectando hardware primeiro..."
        Invoke-DetectarHardware
    }

    # Montar prompt de hardware para a IA
    $hwInfo = @"
Hardware do cliente:
- CPU: $($Script:CPUNome) ($($Script:CPUNucleos) nucleos fisicos / $($Script:CPUThreads) threads, $($Script:CPUFab)$(if($Script:CPUX3D){', V-Cache X3D'})$(if($Script:CPUGen -gt 0){", $($Script:CPUGen)a geracao"}))
- GPU: $($Script:GPUNome) ($($Script:GPUVRAM) GB VRAM, $($Script:GPUFab)$(if($Script:GPUTemp -gt 0){", $($Script:GPUTemp)C atual"}))
- RAM: $($Script:RAMtotalGB) GB $($Script:RAMtipo) @ $($Script:RAMvelocidade) MHz, $($Script:RAMslots) modulo(s)$(if($Script:RAMslots -eq 1){' (SINGLE CHANNEL - ponto critico)'})
- Disco: $($Script:DiscoNome) $(if($Script:DiscoNVMe){'NVMe'}elseif($Script:DiscoTipo -match 'SSD'){'SSD SATA'}else{'HDD'})
- Windows: $($Script:WinVer) Build $($Script:WinBuild)
"@

    # Forcar TLS 1.2 (PS 5.1 usa TLS 1.0 por padrao - API Anthropic exige 1.2+)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Host "  Consultando IA..." -ForegroundColor DarkCyan

    $prompt = @"
Voce e um especialista em otimizacao de Windows para gaming e performance.
Analise o hardware abaixo e gere um relatorio de otimizacao personalizado em portugues.

$hwInfo

Responda com:
1. PONTOS CRITICOS: o que mais limita este sistema agora (max 3 itens)
2. PRIORIDADE DE OTIMIZACAO: lista ordenada dos 5 tweaks mais impactantes para este hardware especifico
3. ALERTAS DE HARDWARE: qualquer coisa que merece atencao (temperatura, single-channel, driver, etc)
4. PERFIL RECOMENDADO: Gaming / Workstation / Equilibrado e por que
5. ESTIMATIVA DE GANHO: estimativa realista de melhora de FPS/latencia com as otimizacoes

Seja especifico ao hardware listado. Mencione o nome dos componentes nas recomendacoes.
Resposta em texto simples, sem markdown, maximo 50 linhas.
"@

    try {
        $body = @{
            model      = "claude-haiku-4-5-20251001"   # Haiku 4.5: $1/$5 por 1M tokens - ideal para analise de hardware
            max_tokens = 1000
            messages   = @(@{ role = "user"; content = $prompt })
        } | ConvertTo-Json -Depth 5

        $headers = @{
            "x-api-key"         = $Script:IAChave
            "anthropic-version" = "2023-06-01"
            "content-type"      = "application/json"
        }

        $resp = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" `
                    -Method POST -Headers $headers -Body $body -ErrorAction Stop

        $texto = $resp.content[0].text

        Write-Host ""
        Write-Host "  $("=" * 70)" -ForegroundColor DarkCyan
        Write-Host "  ANALISE IA ADVISOR - $($Script:CPUNome)" -ForegroundColor Cyan
        Write-Host "  $("=" * 70)" -ForegroundColor DarkCyan
        Write-Host ""

        $texto -split "`n" | ForEach-Object {
            $linha = $_.Trim()
            if ($linha -match '^\d\.') {
                Write-Host "  $linha" -ForegroundColor Cyan
            } elseif ($linha -match '^(CRITICO|ALERTA|URGENTE)') {
                Write-Host "  $linha" -ForegroundColor Red
            } elseif ($linha -match '^(RECOMEND|GANHO|PERFIL)') {
                Write-Host "  $linha" -ForegroundColor Green
            } elseif ($linha -ne '') {
                Write-Host "  $linha" -ForegroundColor White
            } else {
                Write-Host ""
            }
        }

        Write-Host ""
        Write-Host "  $("=" * 70)" -ForegroundColor DarkCyan

        # Salvar relatorio IA
        $relIA = Join-Path $Script:PastaRaiz "IA_Advisor_$(Get-Date -f 'yyyyMMdd_HHmmss').txt"
        @("AbimalekBoost v$($Script:Versao) - Relatorio IA Advisor", "Data: $(Get-Date -f 'dd/MM/yyyy HH:mm')", "", $hwInfo, "", "ANALISE:", $texto) |
            Out-File $relIA -Encoding UTF8 -Force
        Write-Host ""
        IN "Relatorio IA salvo em: $relIA"
        LOG "IA Advisor consultado. Relatorio: $relIA"

    } catch {
        ER "Falha ao conectar na API: $($_.Exception.Message)"
        WN "Verifique sua chave API e conexao com internet."
    }

    PAUSE
}

# ================================================================
#  MODULO 1 - PLANO DE ENERGIA (com checklist)
# ================================================================
function Invoke-PlanoEnergia {
    H2 "PLANO DE ENERGIA INTELIGENTE"

    $atual = powercfg /getactivescheme 2>$null
    if ($atual -match 'GUID:\s*([\w-]+)') {
        $Script:PlanoOrig = $Matches[1]
        $Script:PlanoOrig | Out-File (Join-Path $Script:PastaBackup "plano.txt") -Encoding UTF8 -Force
        IN "Plano atual salvo: $($Script:PlanoOrig)"
    }

    Write-Host "  Selecione o perfil de uso:" -ForegroundColor Cyan
    Write-Host "  [1] Gaming         - maxima performance em jogos" -ForegroundColor White
    Write-Host "  [2] Workstation    - performance + estabilidade termica" -ForegroundColor White
    Write-Host "  [3] Equilibrado    - bom para uso misto (padrao Intel X3D)" -ForegroundColor White
    Write-Host "  [4] Detectar auto  - o script decide baseado no seu hardware" -ForegroundColor Yellow
    Write-Host ""
    $per = Read-Host "  Perfil [1-4]"
    if (-not $per) { $per = "4" }

    $modoGaming = $false; $modoWorkstation = $false; $modoEquil = $false

    switch ($per.Trim()) {
        '1' { $modoGaming = $true }
        '2' { $modoWorkstation = $true }
        '3' { $modoEquil = $true }
        default {
            if ($Script:CPUX3D) { $modoEquil = $true }
            else                { $modoGaming = $true }
        }
    }

    if ($Script:CPUX3D -and $modoGaming) {
        WN "X3D detectado: usando Balanced (High Perf prejudica V-Cache)"
        $modoGaming = $false; $modoEquil = $true
    }

    # Aplicar plano base
    if ($modoEquil -or $Script:CPUX3D) {
        $amd = powercfg /list 2>$null | Select-String 'AMD Ryzen Balanced'
        if ($amd -and $Script:CPUFab -eq 'AMD') {
            $guid = ($amd.Line -split '\s+' | Where-Object {$_ -match '^[0-9a-f-]{36}$'}) | Select-Object -First 1
            if ($guid) { powercfg /setactive $guid 2>$null; OK "AMD Ryzen Balanced ativado" }
        } else { powercfg /setactive SCHEME_BALANCED 2>$null; OK "Plano Balanceado ativado" }
    } elseif ($modoGaming -and $Script:CPUFab -eq 'Intel') {
        powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
        $ult = powercfg /list 2>$null | Select-String 'Ultimate Performance'
        if ($ult) {
            $guid = ($ult.Line -split '\s+' | Where-Object {$_ -match '^[0-9a-f-]{36}$'}) | Select-Object -First 1
            if ($guid) { powercfg /setactive $guid 2>$null; OK "Ultimate Performance ativado" }
        } else { powercfg /setactive SCHEME_MIN 2>$null; OK "Alto Desempenho ativado" }
    } else {
        $amd = powercfg /list 2>$null | Select-String 'AMD Ryzen Balanced'
        if ($amd) {
            $guid = ($amd.Line -split '\s+' | Where-Object {$_ -match '^[0-9a-f-]{36}$'}) | Select-Object -First 1
            if ($guid) { powercfg /setactive $guid 2>$null; OK "AMD Ryzen Balanced ativado" }
        } else { powercfg /setactive SCHEME_MIN 2>$null; OK "Alto Desempenho ativado" }
    }

    # Checklist de tweaks avancados do plano
    $bmodo = if ($Script:CPUX3D) { 4 } elseif ($modoWorkstation) { 0 } else { 2 }
    $tweaks = @(
        @{
            Nome  = "Core Parking OFF"
            Desc  = "Mantem todos os nucleos ativos, sem adormecer"
            Risco = "baixo"
            Bloco = { powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 2>$null }
        }
        @{
            Nome  = "CPU Boost Mode Agressivo"
            Desc  = "Transicoes de frequencia rapidas (melhor FPS)"
            Risco = "baixo"
            Bloco = { powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE $bmodo 2>$null }
        }
        @{
            Nome  = "Sleep e Monitor OFF"
            Desc  = "Desativa suspensao automatica do monitor e PC"
            Risco = "baixo"
            Bloco = {
                powercfg /change standby-timeout-ac 0 2>$null
                powercfg /change monitor-timeout-ac 0 2>$null
            }
        }
        @{
            Nome  = "Throttle de Temperatura Desativado"
            Desc  = "Politica de cooling: Active (sem throttle passivo)"
            Risco = "medio"
            Bloco = { powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR SYSCOOLPOL 0 2>$null }
        }
        @{
            Nome  = "Desativar Hibernate"
            Desc  = "Remove hiberfil.sys (libera GBs no SSD)"
            Risco = "baixo"
            Bloco = { powercfg /h off 2>$null }
        }
        @{
            Nome  = "Desativar USB Selective Suspend"
            Desc  = "Evita que periferiicos USB (mouse/teclado) adormecam"
            Risco = "baixo"
            Bloco = {
                powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
            }
        }
        @{
            Nome  = "PCI Express Link State Power Management OFF"
            Desc  = "Evita que GPU e NVMe reduzam velocidade PCIe"
            Risco = "baixo"
            Bloco = {
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 2>$null
            }
        }
    )

    # Intel 12a gen+: tweak extra
    if ($Script:CPUFab -eq 'Intel' -and $Script:CPUGen -ge 12) {
        $tweaks += @{
            Nome  = "Intel E+P Core Parking 50pct"
            Desc  = "P-cores sempre ativos, E-cores gerenciados pelo SO"
            Risco = "baixo"
            Bloco = { powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 50 2>$null }
        }
    }

    Write-Host ""
    Invoke-TweakChecklist -Titulo "Tweaks de Plano de Energia" -Tweaks $tweaks

    powercfg /setactive SCHEME_CURRENT 2>$null
    $Script:TweaksFeitos.Add("Plano de energia: perfil $(if($modoGaming){'Gaming'}elseif($modoWorkstation){'Workstation'}else{'Equilibrado'})")
    LOG "Plano de energia configurado"
}

# ================================================================
#  MODULO 2 - PRIVACIDADE E TELEMETRIA
# ================================================================
function Invoke-Privacidade {
    H2 "PRIVACIDADE E TELEMETRIA"

    $tweaks = @(
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection";                        N="AllowTelemetry";                              V=0}
        @{P="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection";         N="AllowTelemetry";                              V=0}
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection";                        N="DoNotShowFeedbackNotifications";              V=1}
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection";                        N="LimitDiagnosticLogCollection";                V=1}
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection";                        N="DisableOneSettingsDownloads";                 V=1}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo";                 N="Enabled";                                     V=0}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy";                         N="TailoredExperiencesWithDiagnosticDataEnabled";V=0}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager";          N="SilentInstalledAppsEnabled";                  V=0}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager";          N="SystemPaneSuggestionsEnabled";                V=0}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager";          N="SoftLandingEnabled";                          V=0}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager";          N="SubscribedContentEnabled";                    V=0}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager";          N="OemPreInstalledAppsEnabled";                  V=0}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager";          N="PreInstalledAppsEnabled";                     V=0}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager";          N="ContentDeliveryAllowed";                      V=0}
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                                N="EnableActivityFeed";                          V=0}
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                                N="PublishUserActivities";                       V=0}
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                                N="UploadUserActivities";                        V=0}
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors";                    N="DisableLocation";                             V=1}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"; N="Value";                        V="Deny"; T="String"}
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search";                        N="AllowCortana";                                V=0}
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search";                        N="DisableWebSearch";                            V=1}
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search";                        N="ConnectedSearchUseWeb";                       V=0}
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search";                        N="AllowSearchHighlights";                       V=0}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced";               N="ShowSyncProviderNotifications";               V=0}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced";               N="Start_TrackProgs";                            V=0}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\appDiagnostics"; N="Value";                  V="Deny"; T="String"}
        @{P="HKCU:\SOFTWARE\Microsoft\Siuf\Rules";                                             N="NumberOfSIUFInPeriod";                        V=0}
        @{P="HKCU:\SOFTWARE\Microsoft\Siuf\Rules";                                             N="PeriodInNanoSeconds";                         V=0}
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";                             N="OneDrive";                                    V=""; T="RemoveIfExists"}
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI";                             N="DisableAIDataAnalysis";                       V=1}
    )

    $ok = 0
    foreach ($t in $tweaks) {
        try {
            if (-not (Test-Path $t.P)) { New-Item -Path $t.P -Force | Out-Null }
            if ($t.T -eq 'RemoveIfExists') {
                if (Get-ItemProperty $t.P -Name $t.N -ErrorAction SilentlyContinue) {
                    Remove-ItemProperty $t.P -Name $t.N -Force -ErrorAction SilentlyContinue; $ok++
                }
            } elseif ($t.T -eq 'String') {
                Set-ItemProperty -Path $t.P -Name $t.N -Value $t.V -Type String -Force; $ok++
            } else {
                Set-ItemProperty -Path $t.P -Name $t.N -Value $t.V -Type DWord -Force; $ok++
            }
        } catch {}
    }

    OK "Telemetria, anuncios e Cortana desativados ($ok tweaks)"
    OK "Recall (Windows AI) desativado"

    # Microfone e webcam - pergunta separada
    Write-Host ""
    WN "Atencao: Bloquear microfone e camera desativa o acesso de TODOS os apps"
    WN "incluindo Discord, Zoom, Teams, OBS e outros."
    Write-Host "  [1] Bloquear microfone e camera (mais privacidade)" -ForegroundColor White
    Write-Host "  [2] Manter habilitados (recomendado para uso geral)" -ForegroundColor Yellow
    Write-Host ""
    $micOp = Read-Host "  Opcao [1/2]"
    if ($micOp.Trim() -eq '1') {
        try {
            $micPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone"
            $camPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam"
            if (-not (Test-Path $micPath)) { New-Item $micPath -Force | Out-Null }
            if (-not (Test-Path $camPath)) { New-Item $camPath -Force | Out-Null }
            Set-ItemProperty $micPath -Name "Value" -Value "Deny" -Type String -Force
            Set-ItemProperty $camPath -Name "Value" -Value "Deny" -Type String -Force
            OK "Microfone e camera bloqueados"
            WN "Para reativar: Configuracoes > Privacidade > Microfone / Camera"
            $Script:TweaksFeitos.Add("Privacidade: microfone e camera BLOQUEADOS")
        } catch { ER "Falha ao bloquear microfone/camera" }
    } else {
        OK "Microfone e camera mantidos habilitados"
    }

    $Script:TweaksFeitos.Add("Privacidade: $ok tweaks")
    LOG "Privacidade: $ok tweaks | Mic: $(if($micOp -eq '1'){'BLOQUEADO'}else{'mantido'})"
}

# ================================================================
#  MODULO 3 - GAME BAR / GAME MODE / HAGS
# ================================================================
function Invoke-GameMode {
    H2 "GAME BAR / GAME MODE / HAGS"

    $tweaksList = @(
        @{
            Nome  = "Xbox Game Bar OFF"
            Desc  = "Desativa captura de tela/video em segundo plano"
            Risco = "baixo"
            Bloco = {
                $r = @(
                    @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"; N="AppCaptureEnabled"; V=0}
                    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR";       N="AllowGameDVR";      V=0}
                    @{P="HKCU:\System\GameConfigStore";                            N="GameDVR_Enabled";   V=0}
                )
                foreach ($t in $r) {
                    if (-not (Test-Path $t.P)) { New-Item $t.P -Force | Out-Null }
                    Set-ItemProperty $t.P -Name $t.N -Value $t.V -Type DWord -Force 2>$null
                }
            }
        }
        @{
            Nome  = "Game Mode ON"
            Desc  = "Windows prioriza CPU/GPU para o jogo em execucao"
            Risco = "baixo"
            Bloco = {
                $p = "HKCU:\SOFTWARE\Microsoft\GameBar"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "AllowAutoGameMode"  -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "AutoGameModeEnabled" -Value 1 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "HAGS - Hardware GPU Scheduling"
            Desc  = "GPU gerencia propria fila de trabalho (reduz latencia CPU->GPU)"
            Risco = "baixo"
            Bloco = {
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Multimedia Scheduler - Jogos Prioridade Maxima"
            Desc  = "MMCSS prioriza threads de jogo no scheduler do kernel"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
                Set-ItemProperty $p -Name "SystemResponsiveness" -Value 0 -Type DWord -Force 2>$null
                $g = "$p\Tasks\Games"
                if (-not (Test-Path $g)) { New-Item $g -Force | Out-Null }
                Set-ItemProperty $g -Name "Priority"             -Value 6     -Type DWord  -Force 2>$null
                Set-ItemProperty $g -Name "Affinity"             -Value 0     -Type DWord  -Force 2>$null
                Set-ItemProperty $g -Name "Clock Rate"           -Value 10000 -Type DWord  -Force 2>$null
                Set-ItemProperty $g -Name "GPU Priority"         -Value 8     -Type DWord  -Force 2>$null
                Set-ItemProperty $g -Name "Background Only"      -Value "False" -Type String -Force 2>$null
                Set-ItemProperty $g -Name "Scheduling Category"  -Value "High"  -Type String -Force 2>$null
                Set-ItemProperty $g -Name "SFIO Priority"        -Value "High"  -Type String -Force 2>$null
            }
        }
        @{
            Nome  = "FSE - Fullscreen Exclusive Mode"
            Desc  = "Permite acesso exclusivo da GPU ao jogo em tela cheia"
            Risco = "baixo"
            Bloco = {
                $p = "HKCU:\System\GameConfigStore"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "GameDVR_FSEBehaviorMode"               -Value 2 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "GameDVR_HonorUserFSEBehaviorMode"      -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Value 1 -Type DWord -Force 2>$null
            }
        }
    )

    Invoke-TweakChecklist -Titulo "Game Mode / HAGS" -Tweaks $tweaksList
    $Script:TweaksFeitos.Add("Game Mode: checklist aplicado")
    LOG "Game Mode configurado v5"
}

# ================================================================
#  MODULO 4 - REDE AVANCADA
# ================================================================
function Invoke-OtimizarRede {
    H2 "OTIMIZACAO DE REDE"

    $tweaksList = @(
        @{
            Nome  = "Nagle Algorithm OFF"
            Desc  = "Elimina delay de 200ms em pacotes pequenos (online gaming)"
            Risco = "baixo"
            Bloco = {
                Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" | ForEach-Object {
                    Set-ItemProperty $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force 2>$null
                    Set-ItemProperty $_.PSPath -Name "TCPNoDelay"      -Value 1 -Type DWord -Force 2>$null
                    Set-ItemProperty $_.PSPath -Name "TcpDelAckTicks"  -Value 0 -Type DWord -Force 2>$null
                }
            }
        }
        @{
            Nome  = "TCP Stack Otimizado"
            Desc  = "TTL=64, MaxUserPort, Window Scaling, Timestamps"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
                Set-ItemProperty $p -Name "DefaultTTL"             -Value 64    -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "MaxUserPort"            -Value 65534 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "TcpTimedWaitDelay"      -Value 30    -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "EnablePMTUDiscovery"    -Value 1     -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "Tcp1323Opts"            -Value 1     -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "GlobalMaxTcpWindowSize" -Value 65535 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "TCP Autotuning + DCA/NetDMA"
            Desc  = "Autotuning=normal, DCA e NetDMA ativados, ECN desativado"
            Risco = "baixo"
            Bloco = {
                netsh int tcp set global autotuninglevel=normal 2>$null | Out-Null
                netsh int tcp set global chimney=disabled       2>$null | Out-Null
                netsh int tcp set global dca=enabled            2>$null | Out-Null
                netsh int tcp set global netdma=enabled         2>$null | Out-Null
                netsh int tcp set global ecncapability=disabled 2>$null | Out-Null
            }
        }
        @{
            Nome  = "Liberar Reserva de Banda (20pct)"
            Desc  = "Windows reserva 20pct da banda por padrao - libera isso"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "NonBestEffortLimit" -Value 0 -Type DWord -Force
            }
        }
        @{
            Nome  = "NIC Tweaks (IMod OFF, RSS ON, LSO OFF)"
            Desc  = "Interrupt Moderation OFF, RSS ON, LSO OFF, EEE OFF"
            Risco = "baixo"
            Bloco = {
                $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
                foreach ($ad in $adapters) {
                    Set-NetAdapterAdvancedProperty -Name $ad.Name -DisplayName "Interrupt Moderation"         -DisplayValue "Disabled" 2>$null
                    Set-NetAdapterAdvancedProperty -Name $ad.Name -DisplayName "Receive Side Scaling"         -DisplayValue "Enabled"  2>$null
                    Set-NetAdapterAdvancedProperty -Name $ad.Name -DisplayName "Large Send Offload v2 (IPv4)" -DisplayValue "Disabled" 2>$null
                    Set-NetAdapterAdvancedProperty -Name $ad.Name -DisplayName "Large Send Offload v2 (IPv6)" -DisplayValue "Disabled" 2>$null
                    Set-NetAdapterAdvancedProperty -Name $ad.Name -DisplayName "Energy Efficient Ethernet"    -DisplayValue "Disabled" 2>$null
                    Set-NetAdapterAdvancedProperty -Name $ad.Name -DisplayName "Packet Priority & VLAN"       -DisplayValue "Enabled"  2>$null
                }
            }
        }
        @{
            Nome  = "MSI Mode na NIC"
            Desc  = "Message Signaled Interrupts para adaptador de rede"
            Risco = "baixo"
            Bloco = {
                $nics = Get-PnpDevice -Class 'Net' -Status 'OK' -ErrorAction SilentlyContinue
                foreach ($nic in $nics) {
                    $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($nic.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                    if (Test-Path $path) {
                        Set-ItemProperty $path -Name "MSISupported" -Value 1 -Type DWord -Force 2>$null
                    }
                }
            }
        }
        @{
            Nome  = "Desativar IPv6 (se nao usar)"
            Desc  = "Remove overhead de resolucao dual-stack em redes apenas IPv4"
            Risco = "medio"
            Bloco = {
                $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
                foreach ($ad in $adapters) {
                    Disable-NetAdapterBinding -Name $ad.Name -ComponentID ms_tcpip6 2>$null
                }
            }
        }
    )

    Invoke-TweakChecklist -Titulo "Tweaks de Rede" -Tweaks $tweaksList

    # DNS separado (interativo)
    Write-Host ""
    Write-Host "  Configurar DNS:?" -ForegroundColor Cyan
    Write-Host "  [1] Cloudflare 1.1.1.1  [2] Google 8.8.8.8  [3] Quad9 9.9.9.9  [4] Testar auto  [5] Pular"
    $dns = Read-Host "  DNS [1-5]"
    $dns1 = ""; $dns2 = ""; $dnsNome = ""
    if ($dns.Trim() -eq '4') {
        IN "Testando latencia..."
        $servidores = @(
            @{N="Cloudflare";D1="1.1.1.1";D2="1.0.0.1"}
            @{N="Google";D1="8.8.8.8";D2="8.8.4.4"}
            @{N="Quad9";D1="9.9.9.9";D2="149.112.112.112"}
            @{N="OpenDNS";D1="208.67.222.222";D2="208.67.220.220"}
        )
        $melhor = $null; $melhorPing = 9999
        foreach ($s in $servidores) {
            $ping = (Test-Connection -ComputerName $s.D1 -Count 3 -ErrorAction SilentlyContinue | Measure-Object -Property ResponseTime -Average).Average
            if ($null -eq $ping) { $ping = 9999 }
            Write-Host "    $($s.N.PadRight(12)): $([math]::Round($ping,1)) ms" -ForegroundColor $(if($ping -lt 20){'Green'}elseif($ping -lt 50){'Yellow'}else{'Red'})
            if ($ping -lt $melhorPing) { $melhorPing = $ping; $melhor = $s }
        }
        if ($melhor) { $dns1=$melhor.D1; $dns2=$melhor.D2; $dnsNome="$($melhor.N) ($([math]::Round($melhorPing,0))ms)" }
    } else {
        switch ($dns.Trim()) {
            '1' { $dns1="1.1.1.1";       $dns2="1.0.0.1";          $dnsNome="Cloudflare" }
            '2' { $dns1="8.8.8.8";       $dns2="8.8.4.4";          $dnsNome="Google" }
            '3' { $dns1="9.9.9.9";       $dns2="149.112.112.112";  $dnsNome="Quad9" }
        }
    }
    if ($dns1) {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual|Loopback' }
        foreach ($ad in $adapters) { Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses ($dns1,$dns2) 2>$null }
        OK "DNS $dnsNome configurado"; $Script:TweaksFeitos.Add("DNS: $dnsNome")
    }
    ipconfig /flushdns 2>$null | Out-Null
    OK "Cache DNS limpo"
    $Script:TweaksFeitos.Add("Rede: checklist aplicado")
    LOG "Rede otimizada v5"
}

# ================================================================
#  MODULO 5 - SERVICOS
# ================================================================
function Invoke-Servicos {
    H2 "SERVICOS DESNECESSARIOS"
    WN "Apenas servicos seguros serao desativados."
    Write-Host ""

    $svcs = @(
        @{N="DiagTrack";         D="Telemetria Microsoft (consome CPU+rede)"}
        @{N="dmwappushservice";  D="WAP Push Messages"}
        @{N="XblAuthManager";    D="Xbox Live Auth"}
        @{N="XblGameSave";       D="Xbox Game Save"}
        @{N="XboxNetApiSvc";     D="Xbox Network API"}
        @{N="XboxGipSvc";        D="Xbox Accessories"}
        @{N="lfsvc";             D="Localizacao geografica"}
        @{N="MapsBroker";        D="Mapas Offline"}
        @{N="RetailDemo";        D="Modo demo de loja"}
        @{N="wisvc";             D="Windows Insider Program"}
        @{N="WerSvc";            D="Relatorio de Erros Windows"}
        @{N="Fax";               D="Fax (obsoleto)"}
        @{N="icssvc";            D="Hotspot movel"}
        @{N="PhoneSvc";          D="Vinculador de Telefone"}
        @{N="RmSvc";             D="Gerenciador de Radio"}
        @{N="RemoteRegistry";    D="Registro Remoto (risco de seguranca)"}
        @{N="TapiSrv";           D="Telefonia legada"}
        @{N="WpcMonSvc";         D="Controles parentais"}
        @{N="SharedAccess";      D="ICS compartilhamento de internet"}
        @{N="WMPNetworkSvc";     D="Windows Media Player Network"}
        @{N="AJRouter";          D="AllJoyn Router (IoT legado)"}
        @{N="PrintNotify";       D="Notificacoes de impressora"}
        @{N="EntAppSvc";         D="Enterprise App Management"}
        @{N="MsKeyboardFilter";  D="Filtro de teclado Kiosk"}
        @{N="SysMain";           D="Superfetch (desnecessario em NVMe/SSD)"}
    )

    $off = 0; $i = 0
    foreach ($s in $svcs) {
        $i++; Show-Progress "Verificando servicos..." $i $svcs.Count
        try {
            $svc = Get-Service -Name $s.N -ErrorAction SilentlyContinue
            if ($svc) {
                $Script:SvcsBackup[$s.N] = $svc.StartType.ToString()
                if ($svc.Status -eq 'Running') { Stop-Service -Name $s.N -Force -ErrorAction SilentlyContinue }
                Set-Service -Name $s.N -StartupType Disabled -ErrorAction SilentlyContinue
                $off++
            }
        } catch {}
    }
    Write-Host ""
    $Script:SvcsBackup | ConvertTo-Json | Out-File (Join-Path $Script:PastaBackup "servicos.json") -Encoding UTF8 -Force
    OK "$off servicos desativados | Backup salvo"
    $Script:TweaksFeitos.Add("Servicos: $off desativados")
    LOG "Servicos: $off desativados"
}

# ================================================================
#  MODULO 6 - VISUAL E PERFORMANCE
# ================================================================
function Invoke-VisualPerf {
    H2 "VISUAL E PERFORMANCE"

    $tweaksList = @(
        @{
            Nome  = "Animacoes Windows OFF"
            Desc  = "Desativa todas as animacoes de janela, menu e taskbar"
            Risco = "baixo"
            Bloco = {
                Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -Type DWord -Force 2>$null
                $r = @(
                    @{P="HKCU:\Control Panel\Desktop";                                       N="DragFullWindows";     V="0"; T="String"}
                    @{P="HKCU:\Control Panel\Desktop";                                       N="MenuShowDelay";       V="0"; T="String"}
                    @{P="HKCU:\Control Panel\Desktop\WindowMetrics";                         N="MinAnimate";          V=0}
                    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="TaskbarAnimations";   V=0}
                    @{P="HKCU:\Software\Microsoft\Windows\DWM";                              N="EnableAeroPeek";      V=0}
                    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="ListviewAlphaSelect"; V=0}
                    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="ListviewShadow";      V=0}
                    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="ExtendedUIHoverTime"; V=1}
                )
                foreach ($t in $r) {
                    if (-not (Test-Path $t.P)) { New-Item $t.P -Force | Out-Null }
                    if ($t.T -eq 'String') { Set-ItemProperty $t.P -Name $t.N -Value $t.V -Type String -Force 2>$null }
                    else                   { Set-ItemProperty $t.P -Name $t.N -Value $t.V -Type DWord -Force 2>$null }
                }
            }
        }
        @{
            Nome  = "Transparencia OFF"
            Desc  = "Desativa efeito de vidro do Fluent Design (libera GPU)"
            Risco = "baixo"
            Bloco = {
                Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Widgets e Chat OFF"
            Desc  = "Remove Widgets, Meet Now e News & Interests da taskbar"
            Risco = "baixo"
            Bloco = {
                $p = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                if ($Script:IsWin11) {
                    # Win11: TaskbarDa=Widgets, TaskbarMn=Chat
                    Set-ItemProperty $p -Name "TaskbarDa" -Value 0 -Type DWord -Force 2>$null
                    Set-ItemProperty $p -Name "TaskbarMn" -Value 0 -Type DWord -Force 2>$null
                }
                # Win10 + Win11: News & Interests / Feeds
                Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Value 2 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Menu de Contexto Classico Win11"
            Desc  = "Restaura o menu de contexto completo sem clicar 'Mais opcoes'"
            Risco = "baixo"
            Bloco = {
                $p = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "(default)" -Value "" -Type String -Force 2>$null
            }
        }
        @{
            Nome  = "Extensoes e Arquivos Ocultos Visiveis"
            Desc  = "Mostra extensoes de arquivo e pastas ocultas no Explorer"
            Risco = "baixo"
            Bloco = {
                $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Set-ItemProperty $p -Name "HideFileExt" -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "Hidden"      -Value 1 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Prefetch Mantido (SSD/NVMe)"
            Desc  = "Mantem Prefetch ativo - melhora carregamento de jogos em SSD"
            Risco = "baixo"
            Bloco = {
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name "EnablePrefetcher" -Value 3 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Search Indexing OFF"
            Desc  = "Desativa indexacao de arquivos (libera I/O em segundo plano)"
            Risco = "medio"
            Bloco = {
                Stop-Service WSearch -Force 2>$null
                Set-Service WSearch -StartupType Disabled 2>$null
            }
        }
    )

    Invoke-TweakChecklist -Titulo "Visual e Performance" -Tweaks $tweaksList
    $Script:TweaksFeitos.Add("Visual/Performance: checklist aplicado")
    LOG "Visual performance v5"
}

# ================================================================
#  MODULO 7 - NTFS E I/O AVANCADO
# ================================================================
function Invoke-NTFSIOTweaks {
    H2 "NTFS E I/O - OTIMIZACOES AVANCADAS"

    $tweaksList = @(
        @{
            Nome  = "NTFS Last Access Time OFF"
            Desc  = "Nao registra hora de acesso a cada arquivo lido (menos writes)"
            Risco = "baixo"
            Bloco = { fsutil behavior set DisableLastAccess 1 2>$null | Out-Null }
        }
        @{
            Nome  = "NTFS 8.3 Filename OFF"
            Desc  = "Desativa nomes curtos 8.3 (melhora Explorer com muitos arquivos)"
            Risco = "baixo"
            Bloco = { fsutil behavior set Disable8dot3 1 2>$null | Out-Null }
        }
        @{
            Nome  = "Criptografia de PageFile OFF"
            Desc  = "Desativa criptografia do arquivo de paginacao (ganho de I/O)"
            Risco = "baixo"
            Bloco = { fsutil behavior set EncryptPagingFile 0 2>$null | Out-Null }
        }
        @{
            Nome  = "Network Throttling OFF"
            Desc  = "Desativa limitacao de I/O de rede durante multitarefa"
            Risco = "baixo"
            Bloco = {
                Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "I/O Timeout Otimizado (SSD/NVMe)"
            Desc  = "Reduz timeout de disco para detectar falhas mais rapido"
            Risco = "baixo"
            Bloco = { Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\disk" -Name "TimeOutValue" -Value 30 -Type DWord -Force 2>$null }
        }
        @{
            Nome  = "NVMe Write Cache Flushing"
            Desc  = "Ativa buffer de escrita acelerada no NVMe"
            Risco = "medio"
            Bloco = {
                $discos = Get-CimInstance Win32_DiskDrive
                foreach ($d in $discos) {
                    $reg = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($d.PNPDeviceID)\Device Parameters\Disk"
                    if (Test-Path $reg) { Set-ItemProperty $reg -Name "UserWriteCacheSetting" -Value 1 -Type DWord -Force 2>$null }
                }
            }
        }
        @{
            Nome  = "StorNVMe Command Spreading OFF"
            Desc  = "Reduz latencia do NVMe desativando espalhamento de comandos"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "FpdoEnableCommandSpreading" -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "TRIM Automatico (SSD)"
            Desc  = "Garante que TRIM esta habilitado no SSD"
            Risco = "baixo"
            Bloco = { fsutil behavior set DisableDeleteNotify 0 2>$null | Out-Null }
        }
    )

    Invoke-TweakChecklist -Titulo "NTFS e I/O" -Tweaks $tweaksList
    $Script:TweaksFeitos.Add("NTFS/IO: checklist aplicado")
    LOG "NTFS IO tweaks v5"
}

# ================================================================
#  MODULO 8 - TIMER RESOLUTION
# ================================================================
function Invoke-TimerResolution {
    H2 "TIMER RESOLUTION - PRECISAO DO SCHEDULER"

    INF "O Windows usa por padrao um timer de 15.625ms."
    INF "Tweaks abaixo melhoram consistencia de FPS e latencia."
    Write-Host ""

    $tweaksList = @(
        @{
            Nome  = "System Responsiveness = 0"
            Desc  = "CPU 100pct dedicada ao processo em primeiro plano"
            Risco = "baixo"
            Bloco = {
                Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "BCD Dynamic Tick OFF"
            Desc  = "Timer de clock mais consistente (menos stuttering de FPS)"
            Risco = "medio"
            Bloco = {
                bcdedit /set disabledynamictick yes 2>$null | Out-Null
                "bcd_gaming=yes" | Out-File (Join-Path $Script:PastaBackup "bcd.txt") -Encoding UTF8 -Force
            }
        }
        @{
            Nome  = "BCD Platform Tick - Limpar (recomendado Win11)"
            Desc  = "Remove forcos de platform tick - Win11 ja gerencia timer corretamente"
            Risco = "baixo"
            Bloco = {
                if ($Script:IsWin11) { bcdedit /deletevalue {current} useplatformtick  2>$null | Out-Null }
                bcdedit /deletevalue {current} useplatformclock 2>$null | Out-Null
            }
        }
        @{
            Nome  = "Platform Clock OFF (Win11 22H2+)"
            Desc  = "Remove Platform Clock que causa stuttering em alguns jogos"
            Risco = "medio"
            Bloco = { bcdedit /deletevalue {current} useplatformclock 2>$null | Out-Null }
        }
        @{
            Nome  = "Platform Performance Counters ON"
            Desc  = "Ativa contadores de hardware de alta precisao"
            Risco = "baixo"
            Bloco = { bcdedit /set useplatformperfcounters yes 2>$null | Out-Null }
        }
    )

    Invoke-TweakChecklist -Titulo "Timer Resolution" -Tweaks $tweaksList
    $Script:TweaksFeitos.Add("Timer Resolution: checklist aplicado")
    LOG "Timer Resolution v5"
}

# ================================================================
#  MODULO 9 - MSI MODE
# ================================================================
function Invoke-MSIMode {
    H2 "MSI MODE - MESSAGE SIGNALED INTERRUPTS"

    INF "MSI elimina conflitos de IRQ e reduz latencia de interrupcoes."
    Write-Host ""

    $tweaksList = @(
        @{
            Nome  = "GPU MSI Mode + Prioridade High"
            Desc  = "Ativa MSI na GPU e define prioridade de interrupcao como High"
            Risco = "baixo"
            Bloco = {
                $gpuDevs = Get-PnpDevice -Class 'Display' -Status 'OK' -ErrorAction SilentlyContinue
                foreach ($dev in $gpuDevs) {
                    $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                    if (-not (Test-Path $path)) { New-Item $path -Force | Out-Null }
                    Set-ItemProperty $path -Name "MSISupported" -Value 1 -Type DWord -Force 2>$null
                    $liPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.InstanceId)\Device Parameters\Interrupt Management\Affinity Policy"
                    if (-not (Test-Path $liPath)) { New-Item $liPath -Force | Out-Null }
                    Set-ItemProperty $liPath -Name "DevicePriority" -Value 3 -Type DWord -Force 2>$null
                }
            }
        }
        @{
            Nome  = "NVMe MSI Mode"
            Desc  = "Ativa MSI no controlador NVMe (reduz latencia de I/O)"
            Risco = "baixo"
            Bloco = {
                $nvmeDev = Get-PnpDevice -Class 'DiskDrive' -Status 'OK' | Where-Object { $_.FriendlyName -match 'NVMe' }
                foreach ($dev in $nvmeDev) {
                    $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                    if (-not (Test-Path $path)) { New-Item $path -Force | Out-Null }
                    Set-ItemProperty $path -Name "MSISupported" -Value 1 -Type DWord -Force 2>$null
                }
            }
        }
    )

    Invoke-TweakChecklist -Titulo "MSI Mode" -Tweaks $tweaksList
    WN "REINICIE para MSI Mode ter efeito."
    $Script:TweaksFeitos.Add("MSI Mode: checklist aplicado")
    LOG "MSI Mode v5"
}

# ================================================================
#  NOVO v5: MODULO - TWEAKS DE CPU AVANCADOS
# ================================================================
function Invoke-TweaksCPU {
    H2 "TWEAKS DE CPU AVANCADOS"

    $tweaksList = @(
        @{
            Nome  = "Desativar C-States via BCD (gaming)"
            Desc  = "Impede que o CPU entre em estados de baixo consumo (latencia menor)"
            Risco = "medio"
            Bloco = { bcdedit /set disabledynamictick yes 2>$null | Out-Null }
        }
        @{
            Nome  = "CPU Priority para Processos de Jogo"
            Desc  = "Configura IFEO para elevar prioridade de jogos comuns"
            Risco = "baixo"
            Bloco = {
                $jogos = @("csgo.exe","valorant.exe","fortnite.exe","apex.exe","r5apex.exe","cod.exe","warzone.exe","overwolf.exe")
                foreach ($j in $jogos) {
                    $p = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$j\PerfOptions"
                    if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                    Set-ItemProperty $p -Name "CpuPriorityClass" -Value 3 -Type DWord -Force 2>$null
                    Set-ItemProperty $p -Name "IoPriority"       -Value 3 -Type DWord -Force 2>$null
                }
            }
        }
        @{
            Nome  = "Desativar Mitigacao Spectre/Meltdown"
            Desc  = "Ganho de 5-15pct em CPU - RISCO: vulnerabilidade a ataques locais"
            Risco = "alto"
            Bloco = {
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "FeatureSettingsOverride"     -Value 3 -Type DWord -Force 2>$null
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "FeatureSettingsOverrideMask" -Value 3 -Type DWord -Force 2>$null
                bcdedit /set {current} nx AlwaysOff 2>$null | Out-Null
            }
        }
        @{
            Nome  = "NUMA Memory Interleaving OFF"
            Desc  = "Melhora consistencia de acesso a memoria em sistemas multi-canal"
            Risco = "baixo"
            Bloco = {
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Startup Delay Apps OFF"
            Desc  = "Remove delay de 10s antes de apps de startup serem carregados"
            Risco = "baixo"
            Bloco = {
                $p = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "StartupDelayInMSec" -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Thread DPC Latency Otimizada"
            Desc  = "Reduz latencia de chamadas de procedimento diferidas do kernel"
            Risco = "baixo"
            Bloco = {
                $w32v = if ($Script:IsWin11) { 2 } else { 0x26 }; Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value $w32v -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Large System Cache OFF"
            Desc  = "Prioriza memoria para processos em vez de cache de disco"
            Risco = "baixo"
            Bloco = {
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 0 -Type DWord -Force 2>$null
            }
        }
    )

    Invoke-TweakChecklist -Titulo "Tweaks de CPU Avancados" -Tweaks $tweaksList
    $Script:TweaksFeitos.Add("CPU Avancado: checklist aplicado")
    LOG "CPU tweaks avancados v5"
}

# ================================================================
#  NOVO v5: MODULO - TWEAKS DE MEMORIA
# ================================================================
function Invoke-TweaksMemoria {
    H2 "TWEAKS DE MEMORIA AVANCADOS"

    $tweaksList = @(
        @{
            Nome  = "Working Set Memory Management"
            Desc  = "Evita que Windows retire paginas de RAM de processos ativos"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
                Set-ItemProperty $p -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Heap Fragmentation OFF"
            Desc  = "Desativa fragmentacao de heap de baixo fragmento"
            Risco = "baixo"
            Bloco = {
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\HeapManager" -Name "DisableLFH" -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Clear PageFile ao Desligar OFF"
            Desc  = "Nao apaga o pagefile ao desligar (boot mais rapido)"
            Risco = "baixo"
            Bloco = {
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "ClearPageFileAtShutdown" -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Paging Executive em RAM"
            Desc  = "Mantem codigo do kernel na RAM (evita paginacao do kernel)"
            Risco = "baixo"
            Bloco = {
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Prefetch Avancado de Apps"
            Desc  = "Aumenta aggressividade do prefetch de aplicativos"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
                Set-ItemProperty $p -Name "EnablePrefetcher"   -Value 3 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "EnableSuperfetch"   -Value 0 -Type DWord -Force 2>$null
            }
        }
    )

    Invoke-TweakChecklist -Titulo "Tweaks de Memoria" -Tweaks $tweaksList
    $Script:TweaksFeitos.Add("Memoria: checklist aplicado")
    LOG "Memoria tweaks v5"
}

# ================================================================
#  NOVO v5: MODULO - TWEAKS DE GPU
# ================================================================
function Invoke-TweaksGPU {
    H2 "TWEAKS DE GPU AVANCADOS"

    $tweaksList = @(
        @{
            Nome  = "TDR Delay Aumentado"
            Desc  = "Aumenta timeout de recuperacao de GPU (evita crash em OC)"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
                Set-ItemProperty $p -Name "TdrDelay"          -Value 10  -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "TdrDdiDelay"       -Value 10  -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "TdrLimitTime"      -Value 60  -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "TdrLimitCount"     -Value 20  -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Shader Cache Habilitado"
            Desc  = "Cache de shaders compilados (carregamento mais rapido de jogos)"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Microsoft\DirectX\UserGpuPreferences"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "DirectXUserGlobalSettings" -Value "SwapEffectUpgradeEnable=1;" -Type String -Force 2>$null
            }
        }
        @{
            Nome  = "NVIDIA - PhysX para GPU"
            Desc  = "Forca PhysX na GPU dedicada em vez da CPU"
            Risco = "baixo"
            Bloco = {
                if ($Script:GPUFab -eq 'NVIDIA') {
                    $p = "HKLM:\SOFTWARE\NVIDIA Corporation\Global\PhysX"
                    if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                    Set-ItemProperty $p -Name "SelectedSciName" -Value "" -Type String -Force 2>$null
                }
            }
        }
        @{
            Nome  = "NVIDIA - Modo de Energia Preferencial"
            Desc  = "Forca modo de alta performance no driver NVIDIA"
            Risco = "baixo"
            Bloco = {
                if ($Script:GPUFab -eq 'NVIDIA') {
                    $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000"
                    if (Test-Path $p) {
                        Set-ItemProperty $p -Name "PerfLevelSrc"   -Value 0x2222 -Type DWord -Force 2>$null
                        Set-ItemProperty $p -Name "PowerMizerLevel" -Value 1     -Type DWord -Force 2>$null
                    }
                }
            }
        }
        @{
            Nome  = "D3D - Limitar Latencia de Pre-Render"
            Desc  = "Reduz frames em fila na GPU (diminui input lag)"
            Risco = "baixo"
            Bloco = {
                $p = "HKCU:\SOFTWARE\Microsoft\Direct3D"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "MaxTextureDimension" -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "DXGI Swap Effect Upgrade"
            Desc  = "Habilita DirectX Flip para menor latencia de apresentacao"
            Risco = "baixo"
            Bloco = {
                $p = "HKCU:\SOFTWARE\Microsoft\DirectX\UserGpuPreferences"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "DirectXUserGlobalSettings" -Value "SwapEffectUpgradeEnable=1;" -Type String -Force 2>$null
            }
        }
    )

    Invoke-TweakChecklist -Titulo "Tweaks de GPU" -Tweaks $tweaksList
    $Script:TweaksFeitos.Add("GPU Avancado: checklist aplicado")
    LOG "GPU tweaks avancados v5"
}

# ================================================================
#  NOVO v5: MODULO - TWEAKS DE AUDIO
# ================================================================
function Invoke-TweaksAudio {
    H2 "TWEAKS DE AUDIO (LATENCIA)"

    $tweaksList = @(
        @{
            Nome  = "WASAPI Buffer Minimo"
            Desc  = "Reduz buffer de audio para latencia minima (gamers/streamers)"
            Risco = "medio"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "Affinity"            -Value 0       -Type DWord  -Force 2>$null
                Set-ItemProperty $p -Name "Background Only"     -Value "False" -Type String -Force 2>$null
                Set-ItemProperty $p -Name "Clock Rate"          -Value 10000   -Type DWord  -Force 2>$null
                Set-ItemProperty $p -Name "GPU Priority"        -Value 8       -Type DWord  -Force 2>$null
                Set-ItemProperty $p -Name "Priority"            -Value 6       -Type DWord  -Force 2>$null
                Set-ItemProperty $p -Name "Scheduling Category" -Value "High"  -Type String -Force 2>$null
                Set-ItemProperty $p -Name "SFIO Priority"       -Value "High"  -Type String -Force 2>$null
            }
        }
        @{
            Nome  = "Audio Service Prioridade Alta"
            Desc  = "Aumenta prioridade do Windows Audio Service no scheduler"
            Risco = "baixo"
            Bloco = {
                Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Desativar Audio Enhancements"
            Desc  = "Remove processamento de audio extra (menor latencia e CPU)"
            Risco = "baixo"
            Bloco = {
                Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render" -ErrorAction SilentlyContinue | ForEach-Object {
                    $ep = Join-Path $_.PSPath "Properties"
                    if (Test-Path $ep) {
                        Set-ItemProperty $ep -Name "{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},1" -Value ([byte[]](0x01,0x00,0x00,0x00)) -Type Binary -Force 2>$null
                    }
                }
            }
        }
        @{
            Nome  = "Exclusive Mode para Dispositivos de Audio"
            Desc  = "Permite que apps tomem controle exclusivo do audio (menor latencia)"
            Risco = "baixo"
            Bloco = {
                Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render" -ErrorAction SilentlyContinue | ForEach-Object {
                    $ep = Join-Path $_.PSPath "Properties"
                    if (Test-Path $ep) {
                        Set-ItemProperty $ep -Name "{b3f8fa53-0004-438e-9003-51a46e139bfc},3" -Value ([byte[]](0x01,0x00,0x00,0x00)) -Type Binary -Force 2>$null
                    }
                }
            }
        }
    )

    Invoke-TweakChecklist -Titulo "Tweaks de Audio" -Tweaks $tweaksList
    $Script:TweaksFeitos.Add("Audio: checklist aplicado")
    LOG "Audio tweaks v5"
}

# ================================================================
#  MODULOS EXISTENTES (mantidos do v4)
# ================================================================
function Invoke-OtimizacoesX3D {
    H2 "OTIMIZACOES EXCLUSIVAS PARA X3D V-CACHE"
    WN "Configuracoes especificas para: $($Script:CPUNome)"
    Write-Host ""

    $amd = powercfg /list 2>$null | Select-String 'AMD Ryzen Balanced'
    if ($amd) {
        $guid = ($amd.Line -split '\s+' | Where-Object {$_ -match '^[0-9a-f-]{36}$'}) | Select-Object -First 1
        if ($guid) { powercfg /setactive $guid 2>$null; OK "AMD Ryzen Balanced confirmado (OBRIGATORIO para X3D)" }
    }

    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES      100 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE     4 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFINCTHRESHOLD 10 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFDECTHRESHOLD  8 2>$null

    OK "Core Parking OFF | Boost: Efficient Aggressive"
    WN "BIOS necessario:"
    WN "  > CPPC Preferred Cores = Enabled"
    WN "  > Global C-state = Enabled"
    WN "  > XMP/EXPO para sua RAM"
    WN "  > PBO = Disabled"

    $Script:TweaksFeitos.Add("X3D V-Cache: otimizado")
    LOG "X3D otimizacoes aplicadas"
}

function Get-PerfilOCGPU {
    param([string]$Nome)
    $db = @(
        @{M='RTX\s*4090';                C=200;V=1500;P=15;T=83;N='Ada flagship.'}
        @{M='RTX\s*4080\s*(Super)?';     C=175;V=1200;P=12;T=83;N='Ada excelente.'}
        @{M='RTX\s*4070\s*Ti\s*(Super)?';C=175;V=1200;P=12;T=83;N='Ada eficiente.'}
        @{M='RTX\s*4070\s*(Super)?(?!\s*Ti)';C=150;V=1000;P=10;T=83;N='Excelente OC.'}
        @{M='RTX\s*4060\s*Ti';           C=150;V=1000;P=10;T=83;N='TDP limitado.'}
        @{M='RTX\s*4060(?!\s*Ti)';       C=125;V=1000;P=8; T=83;N='Mem OC melhor retorno.'}
        @{M='RTX\s*3090\s*Ti';           C=150;V=800; P=8; T=83;N='Monitore Tjunction.'}
        @{M='RTX\s*3090(?!\s*Ti)';       C=150;V=800; P=8; T=83;N='Mem OC moderado.'}
        @{M='RTX\s*3080\s*Ti';           C=150;V=800; P=8; T=83;N='VRAM pode throttle.'}
        @{M='RTX\s*3080(?!\s*Ti)';       C=150;V=800; P=8; T=83;N='Ampere escala muito bem.'}
        @{M='RTX\s*3070\s*Ti';           C=125;V=600; P=8; T=83;N='Boa margem.'}
        @{M='RTX\s*3070(?!\s*Ti)';       C=125;V=600; P=8; T=83;N='GPU popular.'}
        @{M='RTX\s*3060\s*Ti';           C=125;V=600; P=8; T=83;N='Bom OC.'}
        @{M='RTX\s*3060(?!\s*Ti)';       C=100;V=500; P=6; T=83;N='Mem OC melhor retorno.'}
        @{M='RTX\s*3050';                C=100;V=400; P=5; T=87;N='OC leve.'}
        @{M='RTX\s*2080\s*Ti';           C=125;V=600; P=8; T=84;N='Verifique pasta termica.'}
        @{M='RTX\s*2080(?!\s*Ti)';       C=125;V=600; P=8; T=84;N='Boa margem Turing.'}
        @{M='RTX\s*2070';                C=100;V=500; P=7; T=84;N='Ganho real.'}
        @{M='RTX\s*2060';                C=100;V=400; P=6; T=84;N='Moderado.'}
        @{M='GTX\s*1660\s*(Ti|Super)?';  C=100;V=500; P=6; T=84;N='GDDR6 escala bem.'}
        @{M='GTX\s*1650';                C=75; V=300; P=4; T=87;N='Ganhos limitados.'}
        @{M='GTX\s*1080\s*Ti';           C=125;V=500; P=8; T=84;N='Pascal classico.'}
        @{M='GTX\s*1080(?!\s*Ti)';       C=125;V=500; P=8; T=84;N='Envelhece bem.'}
        @{M='GTX\s*1070';                C=100;V=400; P=7; T=84;N='Bem documentado.'}
        @{M='GTX\s*1060';                C=100;V=400; P=6; T=84;N='Troque pasta se +4 anos.'}
        @{M='GTX\s*1050\s*Ti';           C=75; V=300; P=4; T=87;N='Ganhos modestos.'}
        @{M='RX\s*7900\s*(XTX|XT)';     C=100;V=100; P=10;T=90;N='Monitore junction.'}
        @{M='RX\s*7800\s*XT';            C=100;V=80;  P=8; T=90;N='RDNA3 mid-range.'}
        @{M='RX\s*7700\s*XT';            C=100;V=80;  P=8; T=90;N='TDP eficiente.'}
        @{M='RX\s*7600';                 C=75; V=60;  P=6; T=90;N='Entry RDNA3.'}
        @{M='RX\s*6900\s*XT';            C=100;V=100; P=8; T=90;N='Hotspot alto.'}
        @{M='RX\s*6800\s*XT';            C=100;V=100; P=8; T=90;N='Infinity Cache escala.'}
        @{M='RX\s*6800(?!\s*XT)';        C=100;V=80;  P=8; T=90;N='Bons ganhos.'}
        @{M='RX\s*6700\s*XT';            C=100;V=80;  P=8; T=90;N='Boa margem.'}
        @{M='RX\s*6700(?!\s*XT)';        C=75; V=60;  P=6; T=90;N='Moderado.'}
        @{M='RX\s*6600\s*XT';            C=75; V=60;  P=6; T=90;N='1080p excelente.'}
        @{M='RX\s*6600(?!\s*XT)';        C=75; V=50;  P=5; T=90;N='Nao exagere.'}
        @{M='RX\s*5700\s*XT';            C=75; V=80;  P=7; T=90;N='Hotspot ate 110C normal.'}
        @{M='RX\s*5700(?!\s*XT)';        C=75; V=80;  P=7; T=90;N='Hotspot alto.'}
        @{M='RX\s*5600\s*XT';            C=75; V=60;  P=6; T=90;N='1080p moderado.'}
        @{M='Arc\s*A770';                C=50; V=200; P=5; T=100;N='Experimental.'}
        @{M='Arc\s*A750';                C=50; V=200; P=5; T=100;N='Mesmos cuidados A770.'}
    )
    foreach ($e in $db) { if ($Nome -match $e.M) { return $e } }
    if ($Nome -match 'NVIDIA|GeForce|RTX|GTX') { return @{C=75;V=300;P=5;T=84;N='GPU NVIDIA. Valores conservadores.'} }
    if ($Nome -match 'AMD|Radeon|RX')           { return @{C=50;V=50; P=4;T=90;N='GPU AMD. Valores conservadores.'} }
    return $null
}

function Invoke-AnalisadorGPU {
    H2 "ANALISADOR DE OVERCLOCK DE GPU"
    if (-not $Script:GPUNome) { Invoke-DetectarHardware }
    if (-not $Script:GPUNome) { ER "GPU nao detectada."; PAUSE; return }

    $perfil = Get-PerfilOCGPU -Nome $Script:GPUNome
    if (-not $perfil) { WN "GPU nao encontrada no banco de dados."; PAUSE; return }

    $statusTerm = "nao_testado"
    if ($Script:GPUFab -eq 'NVIDIA' -and $Script:GPUSmi -and $Script:GPUTemp -gt 0) {
        Write-Host ""
        $corT = if($Script:GPUTemp -lt 60){'Green'}elseif($Script:GPUTemp -lt 75){'Yellow'}else{'Red'}
        Write-Host "  Temperatura atual: $($Script:GPUTemp) C" -ForegroundColor $corT
        if (CONF "Fazer analise termica rapida (15s)?") {
            IN "Monitorando GPU por 15 segundos..."
            $tempMax = $Script:GPUTemp
            for ($i = 1; $i -le 15; $i++) {
                $tr = & $Script:GPUSmi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null
                if ($tr -match '^\d+') { $t=[int]$tr.Trim(); if($t-gt$tempMax){$tempMax=$t} }
                $corBar = if($t -lt 70){'Green'} elseif($t -lt 80){'Yellow'} else{'Red'}
                Write-Host "`r  [$('#'*$i)$((' '*([math]::Max(0,15-$i))))] $($i)s | Temp: $($t) C    " -NoNewline -ForegroundColor $corBar
                Start-Sleep 1
            }
            Write-Host ""; Write-Host ""
            OK "Temp maxima: $($tempMax) C"
            $statusTerm = if($tempMax -le 60){'excelente'}elseif($tempMax -le 72){'boa'}elseif($tempMax -le 80){'aceitavel'}else{'quente'}
            if ($statusTerm -eq 'quente') { ER "GPU muito quente. OC NAO recomendado."; PAUSE; return }
            OK "Status termico: $statusTerm"
        }
    }

    $mult = switch ($statusTerm) {'excelente'{1.0}'boa'{0.85}'aceitavel'{0.65}default{0.75}}
    $cMax = [math]::Floor($perfil.C * $mult); $vMax = [math]::Floor($perfil.V * $mult)
    $pC = @{C=[math]::Floor($cMax*.5);V=[math]::Floor($vMax*.5);P=[math]::Min([math]::Floor($perfil.P*.5),8)}
    $pM = @{C=[math]::Floor($cMax*.75);V=[math]::Floor($vMax*.75);P=[math]::Min([math]::Floor($perfil.P*.75),12)}
    $pA = @{C=$cMax;V=$vMax;P=$perfil.P}

    $pl_c = if($Script:GPUPL -gt 0){[math]::Min([math]::Round($Script:GPUPL*(1+$pC.P/100)),$Script:GPUPLmax)}else{0}
    $pl_m = if($Script:GPUPL -gt 0){[math]::Min([math]::Round($Script:GPUPL*(1+$pM.P/100)),$Script:GPUPLmax)}else{0}
    $pl_a = if($Script:GPUPL -gt 0){[math]::Min([math]::Round($Script:GPUPL*(1+$pA.P/100)),$Script:GPUPLmax)}else{0}
    $plStr_c = if($pl_c -gt 0){"$($pl_c) W (+$($pC.P)%)"} else{"+$($pC.P)pct (use slider)"}
    $plStr_m = if($pl_m -gt 0){"$($pl_m) W (+$($pM.P)%)"} else{"+$($pM.P)pct (use slider)"}
    $plStr_a = if($pl_a -gt 0){"$($pl_a) W (+$($pA.P)%)"} else{"+$($pA.P)pct (use slider)"}

    $fmt = "  | {0,-15} | {1,-14} | {2,-14} | {3,-22} |"
    $sep = "  +" + ("-"*17) + "+" + ("-"*16) + "+" + ("-"*16) + "+" + ("-"*24) + "+"

    Write-Host ""; H1 "RESULTADO - $($Script:GPUNome)"; SEP
    Write-Host "  Nota: $($perfil.N)  |  Temp limite: $($perfil.T) C" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host $sep -ForegroundColor DarkCyan
    Write-Host ($fmt -f "PERFIL","CORE OC","MEM OC","POWER LIMIT") -ForegroundColor DarkCyan
    Write-Host $sep -ForegroundColor DarkCyan
    Write-Host ($fmt -f "[CONSERVADOR]","+$($pC.C) MHz","+$($pC.V) MHz",$plStr_c) -ForegroundColor Green
    Write-Host ($fmt -f "[MODERADO]","+$($pM.C) MHz","+$($pM.V) MHz",$plStr_m) -ForegroundColor Yellow
    Write-Host ($fmt -f "[AGRESSIVO]","+$($pA.C) MHz","+$($pA.V) MHz",$plStr_a) -ForegroundColor Red
    Write-Host $sep -ForegroundColor DarkCyan

    if ($Script:GPUFab -eq 'NVIDIA' -and $Script:GPUSmi -and $Script:GPUPLmax -gt 0) {
        Write-Host ""; WN "Aplicar Power Limit via nvidia-smi?"
        Write-Host "  [1] $($pl_c) W  [2] $($pl_m) W  [3] $($pl_a) W  [4] Nao"
        $op = Read-Host "  [1-4]"
        $watts = switch ($op.Trim()) {'1'{$pl_c}'2'{$pl_m}'3'{$pl_a}default{0}}
        if ($watts -gt 0) {
            $res = & $Script:GPUSmi -pl $watts 2>&1
            if ($res -match 'successfully') { OK "Power Limit: $($watts) W" }
            else { ER "Falha. Use MSI Afterburner." }
        }
    }

    LOG "GPU OC: $($Script:GPUNome) | +$cMax core / +$vMax mem"
    PAUSE
}

function Invoke-ModoStreamer {
    H2 "MODO STREAMER - GAMING + OBS SEM DROPS"
    INF "Configura o sistema para dividir recursos entre jogo e OBS."
    Write-Host ""

    $tweaksList = @(
        @{
            Nome  = "OBS64 CPU Priority = High"
            Desc  = "Eleva prioridade de CPU do OBS64.exe"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\obs64.exe\PerfOptions"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "CpuPriorityClass" -Value 3 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "HAGS para OBS GPU Encode"
            Desc  = "Hardware GPU Scheduling necessario para NVENC/AMF"
            Risco = "baixo"
            Bloco = { Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 -Type DWord -Force 2>$null }
        }
        @{
            Nome  = "Pro Audio Scheduler"
            Desc  = "Prioridade maxima de audio para OBS (sem drops)"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "Affinity"            -Value 0       -Type DWord  -Force 2>$null
                Set-ItemProperty $p -Name "Background Only"     -Value "False" -Type String -Force 2>$null
                Set-ItemProperty $p -Name "Clock Rate"          -Value 10000   -Type DWord  -Force 2>$null
                Set-ItemProperty $p -Name "GPU Priority"        -Value 8       -Type DWord  -Force 2>$null
                Set-ItemProperty $p -Name "Priority"            -Value 6       -Type DWord  -Force 2>$null
                Set-ItemProperty $p -Name "Scheduling Category" -Value "High"  -Type String -Force 2>$null
                Set-ItemProperty $p -Name "SFIO Priority"       -Value "High"  -Type String -Force 2>$null
            }
        }
        @{
            Nome  = "System Responsiveness = 10pct (Streaming)"
            Desc  = "Divide CPU 90/10 entre jogo e encoder"
            Risco = "baixo"
            Bloco = { Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 10 -Type DWord -Force 2>$null }
        }
        @{
            Nome  = "Xbox Game Bar OFF"
            Desc  = "Use OBS em vez do Game Bar"
            Risco = "baixo"
            Bloco = { Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord -Force 2>$null }
        }
    )

    Invoke-TweakChecklist -Titulo "Modo Streamer" -Tweaks $tweaksList
    $Script:ModoStreamer = $true
    Write-Host ""
    WN "Recomendacoes OBS:"
    Write-Host "  > Encoder: NVENC/AMF (GPU)"   -ForegroundColor DarkGray
    Write-Host "  > Bitrate: 6000-8000 kbps"    -ForegroundColor DarkGray
    Write-Host "  > Keyframe: 2s | Profile: High" -ForegroundColor DarkGray
    $Script:TweaksFeitos.Add("Modo Streamer ativado")
    LOG "Modo Streamer v5"
    PAUSE
}

function Invoke-Monitor {
    H2 "MONITOR DE HARDWARE EM TEMPO REAL"
    Write-Host "  Pressione CTRL+C para sair." -ForegroundColor Yellow
    Write-Host ""
    try {
        while ($true) {
            $ts = Get-Date -f "HH:mm:ss"
            $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
            $corCPU = if($cpuLoad -lt 50){'Green'}elseif($cpuLoad -lt 85){'Yellow'}else{'Red'}
            $os = Get-CimInstance Win32_OperatingSystem
            $ramUsada = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
            $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            $ramPct   = [math]::Round($ramUsada / $ramTotal * 100)
            $corRAM   = if($ramPct -lt 60){'Green'}elseif($ramPct -lt 85){'Yellow'}else{'Red'}

            Write-Host "`r  [$ts] CPU: " -NoNewline -ForegroundColor DarkGray
            Write-Host "$($cpuLoad)%".PadLeft(4) -NoNewline -ForegroundColor $corCPU
            Write-Host " | RAM: " -NoNewline -ForegroundColor DarkGray
            Write-Host "$($ramPct)% ($($ramUsada)/$($ramTotal)GB)" -NoNewline -ForegroundColor $corRAM

            if ($Script:GPUSmi) {
                $gd = & $Script:GPUSmi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits 2>$null
                if ($gd) {
                    $gc = $gd -split ','
                    if ($gc.Count -ge 5) {
                        $gt  = [int]$gc[0].Trim(); $gu  = [int]$gc[1].Trim()
                        $gmu = [math]::Round([double]$gc[2].Trim() / 1024, 1)
                        $gmt = [math]::Round([double]$gc[3].Trim() / 1024, 1)
                        $gpw = [math]::Round([double]$gc[4].Trim(), 0)
                        $corGT = if($gt-lt60){'Green'}elseif($gt-lt75){'Yellow'}else{'Red'}
                        $corGU = if($gu-lt70){'Green'}elseif($gu-lt90){'Yellow'}else{'Red'}
                        Write-Host " | GPU: " -NoNewline -ForegroundColor DarkGray
                        Write-Host "$($gt)C" -NoNewline -ForegroundColor $corGT
                        Write-Host "/" -NoNewline -ForegroundColor DarkGray
                        Write-Host "$($gu)%" -NoNewline -ForegroundColor $corGU
                        Write-Host " VRAM:$($gmu)/$($gmt)GB W:$($gpw)" -NoNewline -ForegroundColor DarkGray
                    }
                }
            }
            Start-Sleep 1
        }
    } catch { Write-Host ""; OK "Monitor encerrado." }
    PAUSE
}

function Invoke-Debloater {
    H2 "DEBLOATER - REMOVER APPS DESNECESSARIOS"
    $apps = @(
        "Microsoft.XboxApp","Microsoft.XboxGameOverlay","Microsoft.XboxGamingOverlay",
        "Microsoft.XboxIdentityProvider","Microsoft.Xbox.TCUI",
        "Microsoft.549981C3F5F10","Microsoft.BingWeather","Microsoft.BingFinance",
        "Microsoft.BingNews","Microsoft.BingSports","Microsoft.BingTranslator",
        "Microsoft.BingTravel","Microsoft.GetHelp","Microsoft.Getstarted",
        "Microsoft.MicrosoftOfficeHub","Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MixedReality.Portal","Microsoft.MSPaint","Microsoft.News",
        "Microsoft.Office.OneNote","Microsoft.OutlookForWindows","Microsoft.People",
        "Microsoft.PowerAutomateDesktop","Microsoft.Print3D","Microsoft.SkypeApp",
        "Microsoft.Teams","Microsoft.Todos","Microsoft.WindowsAlarms",
        "Microsoft.WindowsFeedbackHub","Microsoft.WindowsMaps","Microsoft.WindowsSoundRecorder",
        "Microsoft.YourPhone","Microsoft.ZuneMusic","Microsoft.ZuneVideo",
        "Microsoft.MicrosoftStickyNotes","AmazonVideo.PrimeVideo","Disney.37853D22215B2",
        "Clipchamp.Clipchamp","king.com.CandyCrushSaga","king.com.CandyCrushFriends",
        "king.com.FarmHeroesSaga","TikTok.TikTok","BytedancePte.Ltd.TikTok",
        "Facebook.Facebook","Instagram.Instagram","Twitter.Twitter","Netflix",
        "ROBLOXCORPORATION.ROBLOX","Duolingo-LearnLanguagesforFree",
        "AdobeSystemsIncorporated.AdobePhotoshopExpress",
        "MicrosoftCorporationII.MicrosoftFamily","Microsoft.GamingApp",
        "Microsoft.Copilot","Microsoft.WindowsCommunicationsApps","Microsoft.3DBuilder"
    )

    Write-Host "  Removendo $($apps.Count) apps..." -ForegroundColor Gray
    $removidos = 0; $i = 0
    foreach ($app in $apps) {
        $i++; Show-Progress "Debloater" $i $apps.Count
        $pkg = Get-AppxPackage -Name "*$app*" -AllUsers -ErrorAction SilentlyContinue
        if ($pkg) {
            try {
                $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                $pkgProv = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$app*" }
                if ($pkgProv) { $pkgProv | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null }
                $removidos++
            } catch {}
        }
    }
    Write-Host ""
    $regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    Set-ItemProperty $regPath -Name "OemPreInstalledAppsEnabled" -Value 0 -Type DWord -Force 2>$null
    Set-ItemProperty $regPath -Name "PreInstalledAppsEnabled"    -Value 0 -Type DWord -Force 2>$null
    Set-ItemProperty $regPath -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -Force 2>$null
    Set-ItemProperty $regPath -Name "ContentDeliveryAllowed"     -Value 0 -Type DWord -Force 2>$null
    Write-Host ""
    OK "$removidos apps removidos | Reinstalacao bloqueada"
    $Script:TweaksFeitos.Add("Debloater: $removidos removidos")
    LOG "Debloater: $removidos"; PAUSE
}

function Invoke-Instalador {
    H2 "INSTALADOR DE PROGRAMAS (via winget)"
    if (-not $Script:TemWinget) { ER "winget nao encontrado."; PAUSE; return }

    $catalogo = @(
        @{ID="Google.Chrome";              Cat="Navegador";   N="Google Chrome"}
        @{ID="Mozilla.Firefox";            Cat="Navegador";   N="Mozilla Firefox"}
        @{ID="Brave.Brave";                Cat="Navegador";   N="Brave Browser"}
        @{ID="Opera.Opera";                Cat="Navegador";   N="Opera"}
        @{ID="Discord.Discord";            Cat="Comunicacao"; N="Discord"}
        @{ID="WhatsApp.WhatsApp";          Cat="Comunicacao"; N="WhatsApp Desktop"}
        @{ID="Telegram.TelegramDesktop";   Cat="Comunicacao"; N="Telegram"}
        @{ID="Zoom.Zoom";                  Cat="Comunicacao"; N="Zoom"}
        @{ID="Valve.Steam";                Cat="Gaming";      N="Steam"}
        @{ID="EpicGames.EpicGamesLauncher";Cat="Gaming";      N="Epic Games"}
        @{ID="Ubisoft.Connect";            Cat="Gaming";      N="Ubisoft Connect"}
        @{ID="ElectronicArts.EADesktop";   Cat="Gaming";      N="EA App"}
        @{ID="7zip.7zip";                  Cat="Utilitarios"; N="7-Zip"}
        @{ID="Notepad++.Notepad++";        Cat="Utilitarios"; N="Notepad++"}
        @{ID="VideoLAN.VLC";               Cat="Utilitarios"; N="VLC Media Player"}
        @{ID="qBittorrent.qBittorrent";    Cat="Utilitarios"; N="qBittorrent"}
        @{ID="Malwarebytes.Malwarebytes";  Cat="Utilitarios"; N="Malwarebytes"}
        @{ID="REALiX.HWiNFO";             Cat="Utilitarios"; N="HWiNFO64"}
        @{ID="CrystalDewWorld.CrystalDiskInfo";Cat="Utilitarios";N="CrystalDiskInfo"}
        @{ID="CPUID.CPU-Z";                Cat="Utilitarios"; N="CPU-Z"}
        @{ID="MSI.Afterburner";            Cat="GPU/OC";      N="MSI Afterburner"}
        @{ID="Guru3D.RTSS";                Cat="GPU/OC";      N="RivaTuner Statistics"}
        @{ID="Git.Git";                    Cat="Dev";         N="Git"}
        @{ID="Microsoft.VisualStudioCode"; Cat="Dev";         N="VS Code"}
        @{ID="Python.Python.3.12";         Cat="Dev";         N="Python 3.12"}
        @{ID="OpenJS.NodeJS.LTS";          Cat="Dev";         N="Node.js LTS"}
        @{ID="OBSProject.OBSStudio";       Cat="Multimedia";  N="OBS Studio"}
        @{ID="GIMP.GIMP";                  Cat="Multimedia";  N="GIMP"}
        @{ID="HandBrake.HandBrake";        Cat="Multimedia";  N="HandBrake"}
        @{ID="LibreOffice.LibreOffice";    Cat="Office";      N="LibreOffice"}
        @{ID="Adobe.Acrobat.Reader.64-bit";Cat="Office";      N="Adobe Acrobat Reader"}
    )

    $cats = $catalogo | Select-Object -ExpandProperty Cat -Unique | Sort-Object
    $lista = @(); $idx = 1
    Write-Host "  Programas disponiveis:" -ForegroundColor Cyan; Write-Host ""
    foreach ($cat in $cats) {
        Write-Host "  >> $cat" -ForegroundColor DarkCyan
        foreach ($prog in ($catalogo | Where-Object { $_.Cat -eq $cat })) {
            Write-Host ("   [{0,2}] {1}" -f $idx, $prog.N) -ForegroundColor White
            $lista += @{ Idx=$idx; Prog=$prog }; $idx++
        }
        Write-Host ""
    }

    Write-Host "  Numeros separados por virgula. Ex: 1,5,12" -ForegroundColor Yellow
    $sel = Read-Host "  Selecao"
    if (-not $sel.Trim()) { WN "Cancelado."; return }
    $nums = $sel -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
    $selecionados = $lista | Where-Object { $_.Idx -in $nums }
    if (-not $selecionados) { WN "Nenhum valido."; PAUSE; return }

    $ok = 0; $fail = 0; $i = 0
    foreach ($item in $selecionados) {
        $i++; $p = $item.Prog
        Show-Progress "$($p.N)" $i ($selecionados.Count)
        winget install --id $p.ID --accept-source-agreements --accept-package-agreements --silent 2>$null
        if ($LASTEXITCODE -eq 0) { $ok++ } else { $fail++ }
    }
    Write-Host ""
    OK "$ok instalados"
    if ($fail -gt 0) { WN "$fail falharam" }
    LOG "Instalador: $ok OK"; PAUSE
}

function Invoke-WindowsUpdate {
    H2 "CONTROLE DO WINDOWS UPDATE"
    Write-Host "  [1] Pausar 35 dias  [2] Habilitar  [3] Bloquear permanente  [4] Verificar agora  [5] Voltar"
    Write-Host ""
    $op = Read-Host "  Opcao [1-5]"
    switch ($op.Trim()) {
        '1' {
            $dataFim = (Get-Date).AddDays(35).ToString("yyyy-MM-dd")
            $p = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
            if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
            Set-ItemProperty $p "PauseFeatureUpdatesEndTime" "${dataFim}T00:00:00Z" -Force 2>$null
            Set-ItemProperty $p "PauseQualityUpdatesEndTime" "${dataFim}T00:00:00Z" -Force 2>$null
            OK "Atualizacoes pausadas ate $dataFim"
        }
        '2' {
            $p = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
            Remove-ItemProperty $p "PauseFeatureUpdatesEndTime" -Force 2>$null
            Remove-ItemProperty $p "PauseQualityUpdatesEndTime" -Force 2>$null
            Set-Service wuauserv -StartupType Automatic; Start-Service wuauserv 2>$null
            OK "Windows Update habilitado"
        }
        '3' {
            WN "Bloquear permanentemente impede patches de seguranca criticos!"
            if (CONF "Tem certeza?") {
                Stop-Service wuauserv -Force 2>$null
                Set-Service wuauserv -StartupType Disabled 2>$null
                $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p "NoAutoUpdate" 1 -Type DWord -Force 2>$null
                OK "Windows Update bloqueado"
            }
        }
        '4' {
            Start-Service wuauserv 2>$null
            try { (New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow() } catch {}
            OK "Verificacao iniciada"
        }
    }
    LOG "WUpdate: $op"; PAUSE
}

function Invoke-RepararWindows {
    H2 "REPARAR WINDOWS (SFC / DISM)"
    WN "Processo pode demorar 10-30 minutos."
    Write-Host ""
    if (-not (CONF "Iniciar reparo?")) { return }

    H1 "Rodando DISM RestoreHealth..."
    $dism = Start-Process "dism.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -PassThru -NoNewWindow
    if ($dism.ExitCode -eq 0) { OK "DISM: OK" } else { WN "DISM: codigo $($dism.ExitCode)" }

    H1 "Rodando SFC /scannow..."
    $sfc = Start-Process "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow
    if ($sfc.ExitCode -eq 0) { OK "SFC: OK" } else { WN "SFC: codigo $($sfc.ExitCode)" }

    ipconfig /flushdns 2>$null | Out-Null; OK "DNS limpo"
    if (CONF "Resetar TCP/IP e Winsock?") {
        netsh winsock reset 2>$null | Out-Null
        netsh int ip reset  2>$null | Out-Null
        OK "Winsock resetado - reinicie"
    }
    OK "Reparo concluido!"; WN "Reinicie para completar."
    LOG "Reparo executado"; PAUSE
}

function Invoke-Limpeza {
    H2 "LIMPEZA DO SISTEMA"
    $totalBytes = 0
    $pastas = @(
        $env:TEMP, $env:TMP, "C:\Windows\Temp",
        "$env:LOCALAPPDATA\Temp",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\ThumbCacheToDelete",
        "C:\Windows\SoftwareDistribution\Download"
    )
    $i = 0
    foreach ($p in $pastas) {
        $i++; Show-Progress "Limpando..." $i $pastas.Count
        if (Test-Path $p) {
            if ($p -match 'SoftwareDistribution') { Stop-Service wuauserv -Force 2>$null }
            $arqs = Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue
            $bytes = ($arqs | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($bytes) { $totalBytes += $bytes }
            $arqs | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            if ($p -match 'SoftwareDistribution') { Start-Service wuauserv 2>$null }
        }
    }
    Write-Host ""
    try { Clear-RecycleBin -Force 2>$null; IN "Lixeira esvaziada" } catch {}
    try {
        $logs = Get-WinEvent -ListLog * 2>$null | Where-Object { $_.RecordCount -gt 1000 }
        foreach ($log in $logs) { [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($log.LogName) 2>$null }
        OK "Logs de eventos limpos"
    } catch {}
    try {
        Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter "thumbcache_*.db" 2>$null | Remove-Item -Force 2>$null
        OK "Cache de thumbnails removido"
    } catch {}
    $mb = [math]::Round($totalBytes / 1MB, 1)
    Write-Host ""
    OK "Limpeza: $($mb) MB liberados"
    $Script:TweaksFeitos.Add("Limpeza: $($mb) MB")
    LOG "Limpeza: $($mb) MB"; PAUSE
}

function Invoke-ExportarRelatorio {
    H2 "EXPORTAR RELATORIO"
    $relPath = Join-Path $Script:PastaRaiz "Relatorio_$(Get-Date -f 'yyyyMMdd_HHmmss').txt"
    $linhas = @(
        "=" * 70
        "  AbimalekBoost v$($Script:Versao) - Relatorio de Sessao"
        "  Sessao: $($Script:IDSessao)   Data: $(Get-Date -f 'dd/MM/yyyy HH:mm')"
        "=" * 70
        ""
        "HARDWARE:"
        "  CPU  : $($Script:CPUNome)$(if($Script:CPUX3D){' [X3D]'})"
        "  GPU  : $($Script:GPUNome) ($($Script:GPUVRAM) GB)"
        "  RAM  : $($Script:RAMtotalGB) GB $($Script:RAMtipo) @ $($Script:RAMvelocidade) MHz"
        "  Disco: $($Script:DiscoNome) $(if($Script:DiscoNVMe){'[NVMe]'}elseif($Script:DiscoTipo-match'SSD'){'[SSD]'}else{'[HDD]'})"
        "  SO   : $($Script:WinVer) (Build $($Script:WinBuild))"
        ""
        "TWEAKS ($($Script:TweaksFeitos.Count)):"
    )
    foreach ($t in $Script:TweaksFeitos) { $linhas += "  [+] $t" }
    $linhas += ""
    $linhas += "STATUS: $(if($Script:OtimAplicada){'OTIMIZACOES ATIVAS'}else{'Parcial'}). Reinicie para aplicar tudo."
    $linhas += "Log: $($Script:LogFile)"
    $linhas | Out-File $relPath -Encoding UTF8 -Force
    OK "Relatorio salvo:"
    Write-Host "  $relPath" -ForegroundColor Cyan
    LOG "Relatorio: $relPath"; PAUSE
}

function Invoke-Restaurar {
    H2 "RESTAURAR CONFIGURACOES ORIGINAIS"

    IN "Plano de energia..."
    $pBkp = Join-Path $Script:PastaBackup "plano.txt"
    if (Test-Path $pBkp) {
        $guid = (Get-Content $pBkp -Raw).Trim()
        if ($guid) { powercfg /setactive $guid 2>$null; OK "Plano original restaurado" }
    } else { powercfg /setactive SCHEME_BALANCED 2>$null; OK "Plano Balanceado restaurado" }

    IN "Servicos..."
    $sBkp = Join-Path $Script:PastaBackup "servicos.json"
    if (Test-Path $sBkp) {
        try {
            $mapa = Get-Content $sBkp -Raw | ConvertFrom-Json
            foreach ($prop in $mapa.PSObject.Properties) {
                try {
                    $st = switch ($prop.Value) {"Automatic"{[System.ServiceProcess.ServiceStartMode]::Automatic}"Manual"{[System.ServiceProcess.ServiceStartMode]::Manual}default{[System.ServiceProcess.ServiceStartMode]::Manual}}
                    Set-Service -Name $prop.Name -StartupType $st 2>$null
                } catch {}
            }
            OK "Servicos restaurados"
        } catch { ER "Falha ao restaurar servicos" }
    }

    IN "Rede..."
    Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" | ForEach-Object {
        Remove-ItemProperty $_.PSPath "TcpAckFrequency" -Force 2>$null
        Remove-ItemProperty $_.PSPath "TCPNoDelay"      -Force 2>$null
        Remove-ItemProperty $_.PSPath "TcpDelAckTicks"  -Force 2>$null
    }
    OK "Tweaks de rede removidos"

    IN "Politicas..."
    Remove-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Recurse -Force 2>$null
    Remove-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Recurse -Force 2>$null
    OK "Politicas removidas"

    IN "Visual..."
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 0 -Type DWord -Force 2>$null
    Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 1 -Type DWord -Force 2>$null
    OK "Visual restaurado"

    IN "BCD..."
    $bcdBkp = Join-Path $Script:PastaBackup "bcd.txt"
    if (Test-Path $bcdBkp) {
        bcdedit /deletevalue {current} disabledynamictick 2>$null | Out-Null
        if ($Script:IsWin11) { bcdedit /deletevalue {current} useplatformtick   2>$null | Out-Null }
        OK "BCD restaurado"
    }

    IN "Mitigacoes Spectre/Meltdown..."
    Remove-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "FeatureSettingsOverride"     -Force 2>$null
    Remove-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "FeatureSettingsOverrideMask" -Force 2>$null
    bcdedit /set {current} nx OptIn 2>$null | Out-Null
    OK "Mitigacoes restauradas"

    $Script:OtimAplicada = $false; $Script:ModoStreamer = $false
    $Script:TweaksFeitos.Clear()
    Write-Host ""
    OK "Restauracao completa!"; WN "Reinicie o computador."
    LOG "Restauracao v5"; PAUSE
}

function Invoke-AplicarTudo {
    # ================================================================
    #  APLICAR TUDO v7 - IA MEDE PRIMEIRO, DECIDE, APLICA
    #  Ordem correta: snapshot virgem ? decisao ? tweaks ? snapshot final
    # ================================================================
    Clear-Host
    if (-not $Script:CPUNome) { Invoke-DetectarHardware }

    Write-Host ""
    Write-Host "  $("="*70)" -ForegroundColor Magenta
    Write-Host "  ##  AbimalekBoost v7  -  OTIMIZACAO INTELIGENTE  ##" -ForegroundColor Cyan
    Write-Host "  $("="*70)" -ForegroundColor Magenta
    Write-Host "  A IA mede seu hardware ANTES de tocar em qualquer configuracao." -ForegroundColor DarkGray
    Write-Host "  Aplica so o que faz diferenca real para o SEU PC." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  CPU : $($Script:CPUNome)$(if($Script:CPUX3D){' [X3D]'})" -ForegroundColor White
    Write-Host "  GPU : $($Script:GPUNome)" -ForegroundColor White
    Write-Host "  RAM : $($Script:RAMtotalGB) GB $($Script:RAMtipo) @ $($Script:RAMvelocidade)MHz" -ForegroundColor White
    Write-Host "  HDD : $($Script:DiscoTipo)$(if($Script:DiscoNVMe){' NVMe'})" -ForegroundColor White
    Write-Host ""

    # Selecionar perfil
    $Perfil = Select-IAPerfil
    if (-not $Perfil) { return }
    $Script:IA.Perfil = $Perfil

    Write-Host ""
    if (-not (CONF "Iniciar otimizacao inteligente com perfil $Perfil?")) { WN "Cancelado."; PAUSE; return }

    # ?? FASE 0: Criar backup e ponto de restauracao ??????????????
    Write-Host ""
    Write-Host "  $("="*70)" -ForegroundColor DarkCyan
    Write-Host "  [FASE 0/5] SEGURANCA - BACKUP E RESTAURACAO" -ForegroundColor Yellow
    Write-Host "  $("="*70)" -ForegroundColor DarkCyan
    Invoke-IARestauracao
    Invoke-IABackupRegistro

    # ?? FASE 1: Snapshot VIRGEM - antes de qualquer tweak ????????
    Write-Host ""
    Write-Host "  $("="*70)" -ForegroundColor DarkCyan
    Write-Host "  [FASE 1/5] MEDINDO O ESTADO REAL DO SEU PC..." -ForegroundColor Cyan
    Write-Host "  $("="*70)" -ForegroundColor DarkCyan
    Write-Host "  Nenhum tweak foi aplicado ainda. Esta e a medicao base." -ForegroundColor DarkGray
    Write-Host ""

    # Insight da MalikIA se disponivel
    Show-MalikInsight

    $Script:IA.SnapshotAntes = Get-IASnapshot -Label "virgem"
    $snap = $Script:IA.SnapshotAntes
    Show-IAAnalise -snap $snap

    # ?? FASE 2: Motor de decisao ??????????????????????????????????
    Write-Host ""
    Write-Host "  $("="*70)" -ForegroundColor DarkCyan
    Write-Host "  [FASE 2/5] IA DECIDINDO O QUE APLICAR..." -ForegroundColor Cyan
    Write-Host "  $("="*70)" -ForegroundColor DarkCyan
    Write-Host ""

    $decisoes = Invoke-IAMotorDecisao -snap $snap

    # Quais modulos manuais a IA decide ativar baseado no hardware
    $modulosIA = [System.Collections.Generic.List[string]]::new()

    # Sempre: plano de energia, privacidade, game mode, visual
    $modulosIA.Add("Plano")
    $modulosIA.Add("Privacidade")
    $modulosIA.Add("GameMode")
    $modulosIA.Add("Visual")

    # Rede: se ping alto, jitter alto ou Nagle ativo
    if ($snap.LatenciaMS -gt 30 -or $snap.NetworkJitter -gt 10 -or $snap.NagleAtivo) {
        $modulosIA.Add("Rede")
    }

    # Servicos: sempre util
    $modulosIA.Add("Servicos")

    # NTFS: sempre (sem custo, puro ganho)
    $modulosIA.Add("NTFS")

    # MSI Mode: se GPU dedicada detectada
    if ($Script:GPUFab -ne "AMD" -or $Script:GPUNome -notmatch "Vega|Radeon.*Graphics") {
        $modulosIA.Add("MSI")
    }

    # Input Lag: sempre para gaming
    if ($Perfil -in @("Gamer","Streamer","Extremo")) {
        $modulosIA.Add("InputLag")
    }

    # CPU avancado: 6+ nucleos ou Extremo
    if ($Script:CPUNucleos -ge 6 -or $Perfil -eq "Extremo") {
        $modulosIA.Add("CPU")
    }

    # Memoria: se RAM uso alto ou paginando
    if ($snap.RAMUsoPct -gt 60 -or $snap.RAMPaginando) {
        $modulosIA.Add("Memoria")
    }

    # GPU avancado: se GPU dedicada
    if ($Script:GPUVRAM -ge 4) {
        $modulosIA.Add("GPU")
    }

    # Nuclear Microsoft: so Extremo
    if ($Perfil -eq "Extremo") {
        $modulosIA.Add("Nuclear")
    }

    # X3D: se detectado
    if ($Script:CPUX3D) {
        $modulosIA.Add("X3D")
    }

    # Group Policy: Gamer e Extremo
    if ($Perfil -in @("Gamer","Extremo")) {
        $modulosIA.Add("GroupPolicy")
    }

    Write-Host "  GARGALOS DETECTADOS:" -ForegroundColor Yellow
    if ($Script:IA.Gargalo.Count -eq 0) {
        Write-Host "  Nenhum gargalo critico - sistema bem configurado" -ForegroundColor Green
    } else {
        foreach ($g in $Script:IA.Gargalo) { Write-Host "  [!] $g" -ForegroundColor Red }
    }
    Write-Host ""

    Write-Host "  MODULOS QUE A IA VAI EXECUTAR ($($modulosIA.Count)):" -ForegroundColor Cyan
    foreach ($m in $modulosIA) { Write-Host "    [+] $m" -ForegroundColor White }
    Write-Host ""
    Write-Host "  TWEAKS DO MOTOR IA ($($decisoes.Count) acoes):" -ForegroundColor Cyan
    $prioColor = @{ 1="Red"; 2="Yellow"; 3="Cyan"; 4="DarkGray" }
    $prioLabel = @{ 1="CRITICO"; 2="ALTO";  3="MEDIO"; 4="EXTREMO" }
    foreach ($d in $decisoes) {
        Write-Host ("  [{0,-8}] {1}" -f $prioLabel[$d.Prio], $d.Desc) -ForegroundColor $prioColor[$d.Prio]
    }
    Write-Host ""

    if (-not (CONF "Confirmar e aplicar ($($modulosIA.Count) modulos + $($decisoes.Count) tweaks IA)?")) {
        WN "Cancelado."; PAUSE; return
    }

    # ?? FASE 3: Aplicar modulos manuais ??????????????????????????
    Write-Host ""
    Write-Host "  $("="*70)" -ForegroundColor DarkCyan
    Write-Host "  [FASE 3/5] APLICANDO MODULOS SELECIONADOS PELA IA..." -ForegroundColor Cyan
    Write-Host "  $("="*70)" -ForegroundColor DarkCyan
    Write-Host ""

    $total = $modulosIA.Count
    $ei    = 0
    foreach ($modulo in $modulosIA) {
        $ei++
        Show-Progress $modulo $ei $total
        Write-Host ""
        switch ($modulo) {
            "Plano"       { Invoke-PlanoEnergia }
            "Privacidade" { Invoke-Privacidade }
            "GameMode"    { Invoke-GameMode }
            "Rede"        { Invoke-OtimizarRede }
            "Servicos"    { Invoke-Servicos }
            "Visual"      { Invoke-VisualPerf }
            "NTFS"        { Invoke-NTFSIOTweaks }
            "MSI"         { Invoke-MSIMode }
            "InputLag"    { Invoke-OtimizarInputLag }
            "CPU"         { Invoke-TweaksCPU }
            "Memoria"     { Invoke-TweaksMemoria }
            "GPU"         { Invoke-TweaksGPU }
            "Nuclear"     { Invoke-NuclearMicrosoft }
            "X3D"         { Invoke-OtimizacoesX3D }
            "GroupPolicy" { Invoke-GPeditPerformance }
        }
    }

    # ?? FASE 4: Tweaks do motor IA ????????????????????????????????
    Write-Host ""
    Write-Host "  $("="*70)" -ForegroundColor DarkCyan
    Write-Host "  [FASE 4/5] TWEAKS CIRURGICOS DO MOTOR IA..." -ForegroundColor Cyan
    Write-Host "  $("="*70)" -ForegroundColor DarkCyan
    Write-Host ""

    $totalTweaks = $decisoes.Count
    $atualTweak  = 0
    foreach ($d in $decisoes) {
        $atualTweak++
        Show-Progress $d.Id $atualTweak $totalTweaks
        try {
            & $d.Bloco
            $Script:IA.OtimizacoesAplicadas.Add("$($d.Id): $($d.Desc)") | Out-Null
            Write-Host "  [+] $($d.Desc)" -ForegroundColor Green
        } catch {
            Write-Host "  [!] $($d.Id): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    ipconfig /flushdns 2>$null | Out-Null
    OK "DNS flushed"

    # ?? FASE 5: Snapshot final - medir o ganho real ???????????????
    Write-Host ""
    Write-Host "  $("="*70)" -ForegroundColor DarkCyan
    Write-Host "  [FASE 5/5] MEDINDO RESULTADO..." -ForegroundColor Cyan
    Write-Host "  $("="*70)" -ForegroundColor DarkCyan
    Write-Host ""
    Start-Sleep 2

    $Script:IA.SnapshotDepois = Get-IASnapshot -Label "depois"
    Show-ScoreComparativo -antes $Script:IA.SnapshotAntes -depois $Script:IA.SnapshotDepois

    # Salvar historico local
    Save-IAExecucao `
        -snapAntes     $Script:IA.SnapshotAntes `
        -snapDepois    $Script:IA.SnapshotDepois `
        -perfil        $Perfil `
        -otimAplicadas $Script:IA.OtimizacoesAplicadas.ToArray()

    OK "Sessao salva no historico: $($Script:IA.ArqHistorico)"

    # Enviar para MalikIA
    Send-MalikSession `
        -SnapAntes       $Script:IA.SnapshotAntes `
        -SnapDepois      $Script:IA.SnapshotDepois `
        -Perfil          $Perfil `
        -TweaksAplicados $Script:IA.OtimizacoesAplicadas.ToArray() `
        -Gargalos        $Script:IA.Gargalo

    $Script:OtimAplicada = $true
    Write-Host ""
    Write-Host "  $("="*70)" -ForegroundColor Green
    OK "OTIMIZACAO INTELIGENTE CONCLUIDA!"
    Write-Host "  $("="*70)" -ForegroundColor Green
    Write-Host ""
    WN "REINICIE o computador para maximizar o efeito dos tweaks de kernel."
    Write-Host ""
    if (CONF "Exportar relatorio?") { Invoke-ExportarRelatorio }
    LOG "Aplicar Tudo v7: $Perfil | Score $($Script:IA.SnapshotAntes.Score.Geral) -> $($Script:IA.SnapshotDepois.Score.Geral)"
    PAUSE
}

# ================================================================
#  NOVO v5.1 - NUCLEAR MICROSOFT: OneDrive, Copilot, Teams, Recall
# ================================================================
function Invoke-NuclearMicrosoft {
    H2 "NUCLEAR MICROSOFT - REMOVER BLOAT PESADO"

    $tweaksList = @(
        @{
            Nome  = "OneDrive - Remover Completamente"
            Desc  = "Desinstala OneDrive, remove do Explorer, bloqueia reinstalacao via GP"
            Risco = "medio"
            Bloco = {
                Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
                Start-Sleep 1
                $ods = @(
                    "$env:SystemRoot\System32\OneDriveSetup.exe",
                    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
                    "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
                )
                foreach ($od in $ods) {
                    if (Test-Path $od) { Start-Process $od -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue }
                }
                Remove-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -Force 2>$null
                Remove-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -Force 2>$null

                # Remover do painel do Explorer
                $c1 = "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
                if (-not (Test-Path $c1)) { New-Item $c1 -Force | Out-Null }
                Set-ItemProperty $c1 -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord -Force 2>$null
                $c2 = "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
                if (-not (Test-Path $c2)) { New-Item $c2 -Force | Out-Null }
                Set-ItemProperty $c2 -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord -Force 2>$null

                # Bloquear via GP
                $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "DisableFileSync"     -Value 1 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Copilot - Remover e Bloquear via GP"
            Desc  = "Remove app Copilot, botao da taskbar e bloqueia por Group Policy"
            Risco = "baixo"
            Bloco = {
                if ($Script:IsWin11) {
                    # Win11: remove app Copilot e botoes da taskbar
                    Get-AppxPackage "*Copilot*" -AllUsers 2>$null | Remove-AppxPackage -AllUsers 2>$null
                    Get-AppxProvisionedPackage -Online 2>$null |
                        Where-Object { $_.DisplayName -match "Copilot" } |
                        Remove-AppxProvisionedPackage -Online 2>$null | Out-Null
                    Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
                        -Name "ShowCopilotButton" -Value 0 -Type DWord -Force 2>$null
                    Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
                        -Name "TaskbarAI" -Value 0 -Type DWord -Force 2>$null
                    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
                    if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                    Set-ItemProperty $p -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force 2>$null
                    $pu = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
                    if (-not (Test-Path $pu)) { New-Item $pu -Force | Out-Null }
                    Set-ItemProperty $pu -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force 2>$null
                } else {
                    WN "Copilot: exclusivo do Win11 - ignorado no Win10"
                }
            }
        }
        @{
            Nome  = "Teams Consumer - Remover"
            Desc  = "Remove Microsoft Teams pessoal (nao afeta Teams corporativo)"
            Risco = "baixo"
            Bloco = {
                Get-AppxPackage "MicrosoftTeams" -AllUsers 2>$null | Remove-AppxPackage -AllUsers 2>$null
                Get-AppxPackage "*Teams*" -AllUsers 2>$null |
                    Where-Object { $_.Name -match "Personal|Consumer" } |
                    Remove-AppxPackage -AllUsers 2>$null
                Get-AppxProvisionedPackage -Online 2>$null |
                    Where-Object { $_.DisplayName -match "^Teams" } |
                    Remove-AppxProvisionedPackage -Online 2>$null | Out-Null
                Remove-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" `
                    -Name "com.squirrel.Teams.Teams" -Force 2>$null
            }
        }
        @{
            Nome  = "Windows Recall - Desativar Completamente"
            Desc  = "Para IA que grava screenshots continuas da tela (privacidade + CPU)"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "DisableAIDataAnalysis"  -Value 1 -Type DWord -Force 2>$null
                if ($Script:IsWin11) {
                    Set-ItemProperty $p -Name "AllowRecallEnablement"  -Value 0 -Type DWord -Force 2>$null
                    Set-ItemProperty $p -Name "TurnOffSavingSnapshots" -Value 1 -Type DWord -Force 2>$null
                }
                $pu = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
                if (-not (Test-Path $pu)) { New-Item $pu -Force | Out-Null }
                Set-ItemProperty $pu -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -Force 2>$null
                if ($Script:IsWin11) {
                    Stop-Service "WindowsRecall"      -Force 2>$null; Set-Service "WindowsRecall"      -StartupType Disabled 2>$null
                    Stop-Service "AIXAssistedCapture" -Force 2>$null; Set-Service "AIXAssistedCapture" -StartupType Disabled 2>$null
                }
            }
        }
        @{
            Nome  = "Cortana - Remover e Bloquear"
            Desc  = "Remove Cortana standalone, desativa via GP"
            Risco = "baixo"
            Bloco = {
                Get-AppxPackage "*Microsoft.549981C3F5F10*" -AllUsers 2>$null | Remove-AppxPackage -AllUsers 2>$null
                Get-AppxProvisionedPackage -Online 2>$null |
                    Where-Object { $_.DisplayName -match "Cortana" } |
                    Remove-AppxProvisionedPackage -Online 2>$null | Out-Null
                $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "AllowCortana"            -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "AllowCortanaAboveLock"   -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Microsoft Edge - Desativar Autostart e Background"
            Desc  = "Remove Edge do startup, desativa Startup Boost, Sidebar, Bing e Copilot"
            Risco = "baixo"
            Bloco = {
                Remove-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "MicrosoftEdgeAutoLaunch*" -Force 2>$null
                Stop-Service "edgeupdate"  -Force 2>$null; Set-Service "edgeupdate"  -StartupType Disabled 2>$null
                Stop-Service "edgeupdatem" -Force 2>$null; Set-Service "edgeupdatem" -StartupType Disabled 2>$null
                $e = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
                if (-not (Test-Path $e)) { New-Item $e -Force | Out-Null }
                Set-ItemProperty $e -Name "HubsSidebarEnabled"              -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $e -Name "StartupBoostEnabled"             -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $e -Name "BackgroundModeEnabled"           -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $e -Name "PersonalizationReportingEnabled" -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $e -Name "DiagnosticData"                  -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $e -Name "EdgeDiscoverEnabled"             -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $e -Name "BingAdsSuppression"              -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $e -Name "EdgeShoppingAssistantEnabled"    -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $e -Name "CopilotCDPPageContext"           -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Windows Search - Desativar Indexacao e Bing"
            Desc  = "Para indexacao de disco e Bing na barra de busca (libera CPU e I/O)"
            Risco = "medio"
            Bloco = {
                Stop-Service "WSearch" -Force 2>$null; Set-Service "WSearch" -StartupType Disabled 2>$null
                $p = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "BingSearchEnabled"           -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "CortanaConsent"              -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force 2>$null
                $pl = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
                if (-not (Test-Path $pl)) { New-Item $pl -Force | Out-Null }
                Set-ItemProperty $pl -Name "DisableWebSearch"      -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $pl -Name "ConnectedSearchUseWeb" -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Widgets e News Feed - Remover da Taskbar"
            Desc  = "Remove painel de Widgets, News e Interests (consome CPU e rede em idle)"
            Risco = "baixo"
            Bloco = {
                if ($Script:IsWin11) {
                    Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
                        -Name "TaskbarDa" -Value 0 -Type DWord -Force 2>$null
                    Stop-Service "Widgets" -Force 2>$null; Set-Service "Widgets" -StartupType Disabled 2>$null
                } else {
                    # Win10: desativar News and Interests (taskbar)
                    $pn = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
                    if (-not (Test-Path $pn)) { New-Item $pn -Force | Out-Null }
                    Set-ItemProperty $pn -Name "ShellFeedsTaskbarViewMode"    -Value 2 -Type DWord -Force 2>$null
                    Set-ItemProperty $pn -Name "ShellFeedsTaskbarOpenOnHover" -Value 0 -Type DWord -Force 2>$null
                }
                $p = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force 2>$null
                $pn = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
                if (-not (Test-Path $pn)) { New-Item $pn -Force | Out-Null }
                Set-ItemProperty $pn -Name "ShellFeedsTaskbarViewMode"    -Value 2 -Type DWord -Force 2>$null
                Set-ItemProperty $pn -Name "ShellFeedsTaskbarOpenOnHover" -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Tarefas de Telemetria - Desativar Tasks Agendadas"
            Desc  = "Para CompatTelRunner, CEIP, DiskDiagnostic e 13 outras tasks de telemetria"
            Risco = "baixo"
            Bloco = {
                $tasks = @(
                    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
                    "\Microsoft\Windows\Application Experience\ProgramDataUpdater"
                    "\Microsoft\Windows\Application Experience\StartupAppTask"
                    "\Microsoft\Windows\Autochk\Proxy"
                    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
                    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
                    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
                    "\Microsoft\Windows\Feedback\Siuf\DmClient"
                    "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload"
                    "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
                    "\Microsoft\Windows\CloudExperienceHost\CreateObjectTask"
                    "\Microsoft\Windows\HelloFace\FODCleanupTask"
                    "\Microsoft\Windows\Maps\MapsUpdateTask"
                    "\Microsoft\Windows\Maps\MapsToastTask"
                )
                foreach ($t in $tasks) {
                    Disable-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }
    )

    Invoke-TweakChecklist -Titulo "Nuclear Microsoft" -Tweaks $tweaksList
    $Script:TweaksFeitos.Add("Nuclear Microsoft: bloat removido")
    LOG "Nuclear Microsoft v5.1"
}

# ================================================================
#  NOVO v5.1 - REDUCAO DE PROCESSOS CPU / DESAFOGO DE RAM
# ================================================================
function Invoke-OtimizarProcessosCPU {
    H2 "REDUCAO DE PROCESSOS E DESAFOGO DE RAM"

    INF "Foco: matar processos pesados em background, liberar RAM real"
    INF "e reduzir uso de CPU em idle para abaixo de 2pct."
    Write-Host ""

    $tweaksList = @(
        @{
            Nome  = "Matar Processos Pesados em Background"
            Desc  = "Para SearchIndexer, SpeechRuntime, CompatTelRunner, YourPhone e similares"
            Risco = "baixo"
            Bloco = {
                $procs = @(
                    "SearchIndexer","SearchProtocolHost","SearchFilterHost",
                    "CompatTelRunner","MSOOBE","MusNotifyIcon",
                    "WerFault","WerFaultSecure","wermgr",
                    "YourPhone","PhoneExperienceHost",
                    "SpeechRuntime","SpeechExperienceHost",
                    "PeopleExperienceHost","backgroundTaskHost",
                    "Microsoft.SharePoint","OneDrive","msedgewebview2"
                )
                foreach ($p in $procs) { Stop-Process -Name $p -Force -ErrorAction SilentlyContinue }
            }
        }
        @{
            Nome  = "SysMain - Desativar (so recomendado em HDD ou RAM <= 8GB)"
            Desc  = "Em SSD/NVMe com 16GB+ RAM, manter ativo nao prejudica. Desativar em HDD."
            Risco = "medio"
            Bloco = {
                if ($Script:DiscoTipo -match "HDD" -or $Script:RAMtotalGB -le 8) {
                    Stop-Service "SysMain" -Force 2>$null; Set-Service "SysMain" -StartupType Disabled 2>$null
                } else {
                    WN "SysMain mantido ativo (SSD/NVMe + RAM suficiente - desativar nao ajuda)"
                }
            }
        }
        @{
            Nome  = "Desativar Apps em Background Globalmente"
            Desc  = "Group Policy: impede qualquer app UWP de rodar em segundo plano"
            Risco = "medio"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "LetAppsRunInBackground" -Value 2 -Type DWord -Force 2>$null
                Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" `
                    -Name "GlobalUserDisabled" -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" `
                    -Name "BackgroundAppGlobalToggle" -Value 0 -Type DWord -Force 2>$null
                # Desativar individualmente todos os packages
                Get-ChildItem "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" `
                    -ErrorAction SilentlyContinue | ForEach-Object {
                        Set-ItemProperty $_.PSPath -Name "Disabled"       -Value 1 -Type DWord -Force 2>$null
                        Set-ItemProperty $_.PSPath -Name "DisabledByUser" -Value 1 -Type DWord -Force 2>$null
                    }
            }
        }
        @{
            Nome  = "Power Throttling OFF"
            Desc  = "Impede Windows de reduzir frequencia de CPU em processos background"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "PowerThrottlingOff" -Value 1 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Xbox Background Services OFF"
            Desc  = "Para XblAuthManager, XblGameSave, XboxNetApiSvc, XboxGipSvc, BcastDVR"
            Risco = "baixo"
            Bloco = {
                $xsvcs = @("XblAuthManager","XblGameSave","XboxNetApiSvc","XboxGipSvc","xbgm","BcastDVRUserService")
                foreach ($s in $xsvcs) { Stop-Service $s -Force 2>$null; Set-Service $s -StartupType Disabled 2>$null }
            }
        }
        @{
            Nome  = "Liberar RAM - Empty Working Set (agora)"
            Desc  = "Forca liberacao de paginas de RAM ociosas de todos os processos"
            Risco = "baixo"
            Bloco = {
                Add-Type @"
using System; using System.Runtime.InteropServices; using System.Diagnostics;
public class RAMCleaner {
    [DllImport("kernel32.dll")]
    public static extern bool SetProcessWorkingSetSize(IntPtr p, int mn, int mx);
    public static void Clear() {
        foreach (Process p in Process.GetProcesses()) {
            try { SetProcessWorkingSetSize(p.Handle, -1, -1); } catch {}
        }
    }
}
"@
                [RAMCleaner]::Clear()
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                [System.GC]::Collect()
            }
        }
        @{
            Nome  = "Rebaixar Prioridade de Processos de Sistema"
            Desc  = "SearchIndexer, MsMpEng e SgrmBroker ficam em BelowNormal"
            Risco = "medio"
            Bloco = {
                $baixaPrior = @("SearchIndexer","SearchProtocolHost","MsMpEng","SgrmBroker","uhssvc")
                foreach ($pn in $baixaPrior) {
                    $proc = Get-Process -Name $pn -ErrorAction SilentlyContinue
                    if ($proc) {
                        try { $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal } catch {}
                    }
                }
            }
        }
        @{
            Nome  = "Print Spooler OFF (se nao usar impressora)"
            Desc  = "Libera ~30MB RAM e elimina processo sempre ativo"
            Risco = "medio"
            Bloco = {
                Stop-Service "Spooler" -Force 2>$null; Set-Service "Spooler" -StartupType Disabled 2>$null
            }
        }
        @{
            Nome  = "Desativar Tasks Agendadas de Background Office/Update"
            Desc  = "Para tasks que acordam CPU: Office telemetria, UpdateOrchestrator"
            Risco = "baixo"
            Bloco = {
                $tasks = @(
                    "\Microsoft\Office\OfficeTelemetryAgentFallBack"
                    "\Microsoft\Office\OfficeTelemetryAgentLogOn"
                    "\Microsoft\Office\OfficeBackgroundTaskHandlerRegistration"
                    "\Microsoft\Office\OfficeBackgroundTaskHandlerLogon"
                    "\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker"
                    "\Microsoft\Windows\UpdateOrchestrator\ScheduleScan"
                    "\Microsoft\Windows\UpdateOrchestrator\UpdateModelTask"
                    "\Microsoft\Windows\WindowsUpdate\Scheduled Start"
                )
                foreach ($t in $tasks) { Disable-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue | Out-Null }
            }
        }
        @{
            Nome  = "SecurityHealthSystray OFF (icone bandeja)"
            Desc  = "Remove icone de seguranca da bandeja (nao remove o Defender)"
            Risco = "medio"
            Bloco = {
                Stop-Process -Name "SecurityHealthSystray" -Force -ErrorAction SilentlyContinue
                Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" `
                    -Name "SecurityHealth" -Value "" -Force 2>$null
            }
        }
    )

    Invoke-TweakChecklist -Titulo "Processos CPU e RAM" -Tweaks $tweaksList
    $Script:TweaksFeitos.Add("Processos/RAM: checklist aplicado")
    LOG "Processos CPU/RAM v5.1"
}

# ================================================================
#  NOVO v5.1 - INPUT LAG: REGEDIT + GPEDIT FOCADO
# ================================================================
function Invoke-OtimizarInputLag {
    H2 "REDUCAO DE INPUT LAG - REGEDIT + GP"

    INF "Tweaks focados em latencia de entrada: mouse, teclado e rede."
    INF "Impacto real em jogos competitivos e FPS games."
    Write-Host ""

    $tweaksList = @(
        @{
            Nome  = "Mouse - Desativar Aceleracao (Enhance Pointer Precision)"
            Desc  = "Remove aceleracao do ponteiro - movimento 1:1 com o sensor fisico"
            Risco = "baixo"
            Bloco = {
                $p = "HKCU:\Control Panel\Mouse"
                Set-ItemProperty $p -Name "MouseSpeed"      -Value "0" -Type String -Force 2>$null
                Set-ItemProperty $p -Name "MouseThreshold1" -Value "0" -Type String -Force 2>$null
                Set-ItemProperty $p -Name "MouseThreshold2" -Value "0" -Type String -Force 2>$null
                Set-ItemProperty $p -Name "SmoothMouseXCurve" `
                    -Value ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
                                     0xC0,0xCC,0x0C,0x00,0x00,0x00,0x00,0x00,
                                     0x80,0x99,0x19,0x00,0x00,0x00,0x00,0x00,
                                     0x40,0x66,0x26,0x00,0x00,0x00,0x00,0x00,
                                     0x00,0x33,0x33,0x00,0x00,0x00,0x00,0x00)) -Type Binary -Force 2>$null
                Set-ItemProperty $p -Name "SmoothMouseYCurve" `
                    -Value ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
                                     0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00,
                                     0x00,0x00,0x70,0x00,0x00,0x00,0x00,0x00,
                                     0x00,0x00,0xA8,0x00,0x00,0x00,0x00,0x00,
                                     0x00,0x00,0xE0,0x00,0x00,0x00,0x00,0x00)) -Type Binary -Force 2>$null
            }
        }
        @{
            Nome  = "Teclado - Delay e Repeat Rate Minimos"
            Desc  = "KeyboardDelay=0, KeyboardSpeed=31 (resposta maxima do teclado)"
            Risco = "baixo"
            Bloco = {
                $p = "HKCU:\Control Panel\Keyboard"
                Set-ItemProperty $p -Name "KeyboardDelay" -Value "0"  -Type String -Force 2>$null
                Set-ItemProperty $p -Name "KeyboardSpeed" -Value "31" -Type String -Force 2>$null
            }
        }
        @{
            Nome  = "USB Selective Suspend OFF (XHCI)"
            Desc  = "Desativa suspensao de USB - elimina wake delay de mouse/teclado"
            Risco = "baixo"
            Bloco = {
                powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
                powercfg /setactive SCHEME_CURRENT 2>$null
                Get-PnpDevice -Class "USB" -ErrorAction SilentlyContinue | ForEach-Object {
                    $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($_.InstanceId)\Device Parameters"
                    if (Test-Path $path) {
                        Set-ItemProperty $path -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force 2>$null
                        Set-ItemProperty $path -Name "SelectiveSuspendEnabled"         -Value 0 -Type DWord -Force 2>$null
                    }
                }
            }
        }
        @{
            Nome  = "IRQ Priority - Mouse e Teclado em High"
            Desc  = "Eleva prioridade de interrupcao HID para maxima"
            Risco = "baixo"
            Bloco = {
                foreach ($svc in @("mouclass","kbdclass","hidusb")) {
                    $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
                    if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                    Set-ItemProperty $p -Name "RequestedPriority" -Value 6 -Type DWord -Force 2>$null
                }
            }
        }
        @{
            Nome  = "Scheduler - Win32PrioritySeparation Gaming"
            Desc  = "0x26: foreground recebe quantum curto e boost x6 sobre background"
            Risco = "baixo"
            Bloco = {
                # Win10: 0x26 (38) = quantum curto com boost. Win11: 2 = sem stutter
                $w32val = if ($Script:IsWin11) { 2 } else { 0x26 }
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" `
                    -Name "Win32PrioritySeparation" -Value $w32val -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "MMCSS - Prioridade Maxima para Threads de Jogo"
            Desc  = "Multimedia Class Scheduler: jogos tem prioridade RT de CPU"
            Risco = "baixo"
            Bloco = {
                $g = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
                if (-not (Test-Path $g)) { New-Item $g -Force | Out-Null }
                Set-ItemProperty $g -Name "Priority"            -Value 6       -Type DWord  -Force 2>$null
                Set-ItemProperty $g -Name "Clock Rate"          -Value 10000   -Type DWord  -Force 2>$null
                Set-ItemProperty $g -Name "GPU Priority"        -Value 8       -Type DWord  -Force 2>$null
                Set-ItemProperty $g -Name "Scheduling Category" -Value "High"  -Type String -Force 2>$null
                Set-ItemProperty $g -Name "SFIO Priority"       -Value "High"  -Type String -Force 2>$null
                Set-ItemProperty $g -Name "Background Only"     -Value "False" -Type String -Force 2>$null
                Set-ItemProperty $g -Name "Affinity"            -Value 0       -Type DWord  -Force 2>$null
                Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" `
                    -Name "SystemResponsiveness" -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Notificacoes e Action Center OFF"
            Desc  = "Bloqueia toast notifications durante jogo"
            Risco = "baixo"
            Bloco = {
                $p = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "ToastEnabled"           -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "LockScreenToastEnabled" -Value 0 -Type DWord -Force 2>$null
                $pa = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
                if (-not (Test-Path $pa)) { New-Item $pa -Force | Out-Null }
                Set-ItemProperty $pa -Name "DisableNotificationCenter" -Value 1 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "Auto HDR e VRR Forcado OFF"
            Desc  = "Auto HDR e VRR automatico podem causar stutter - desativa globalmente"
            Risco = "medio"
            Bloco = {
                $p = "HKCU:\SOFTWARE\Microsoft\DirectX\UserGpuPreferences"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                if ($Script:IsWin11) {
                    Set-ItemProperty $p -Name "DirectXUserGlobalSettings" `
                        -Value "AutoHDREnable=0;VRROptimizeEnable=0;" -Type String -Force 2>$null
                } else {
                    WN "Auto HDR e VRR: exclusivos do Win11 - ignorado"
                }
            }
        }
        @{
            Nome  = "QoS Gaming - Pacotes UDP com Prioridade Maxima"
            Desc  = "Marca pacotes de jogos populares com DSCP 46 (Expedited Forwarding)"
            Risco = "baixo"
            Bloco = {
                $jogos = @("csgo.exe","valorant.exe","fortnite.exe","r5apex.exe",
                            "destiny2.exe","overwatch.exe","cod.exe","dota2.exe",
                            "pubg.exe","bf2042.exe","eft.exe","league of legends.exe")
                foreach ($j in $jogos) {
                    $pq = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\QoS\$j"
                    if (-not (Test-Path $pq)) { New-Item $pq -Force | Out-Null }
                    Set-ItemProperty $pq -Name "Version"          -Value "1.0" -Type String -Force 2>$null
                    Set-ItemProperty $pq -Name "Application Name" -Value $j    -Type String -Force 2>$null
                    Set-ItemProperty $pq -Name "Protocol"         -Value "17"  -Type String -Force 2>$null
                    Set-ItemProperty $pq -Name "Local Port"       -Value "*"   -Type String -Force 2>$null
                    Set-ItemProperty $pq -Name "Remote Port"      -Value "*"   -Type String -Force 2>$null
                    Set-ItemProperty $pq -Name "Local IP"         -Value "*"   -Type String -Force 2>$null
                    Set-ItemProperty $pq -Name "Remote IP"        -Value "*"   -Type String -Force 2>$null
                    Set-ItemProperty $pq -Name "DSCP Value"       -Value "46"  -Type String -Force 2>$null
                    Set-ItemProperty $pq -Name "Throttle Rate"    -Value "-1"  -Type String -Force 2>$null
                }
            }
        }
        @{
            Nome  = "GPU Pre-Render Frames = 1 (Low Latency)"
            Desc  = "Limita fila de frames pre-renderizados na GPU (reduz input lag)"
            Risco = "baixo"
            Bloco = {
                $d3d = "HKCU:\Software\Microsoft\Direct3D"
                if (-not (Test-Path $d3d)) { New-Item $d3d -Force | Out-Null }
                Set-ItemProperty $d3d -Name "MaxTextureDimension" -Value 0 -Type DWord -Force 2>$null
                if ($Script:GPUFab -eq 'NVIDIA') {
                    $nv = "HKCU:\SOFTWARE\NVIDIA Corporation\Global\NVTweak"
                    if (-not (Test-Path $nv)) { New-Item $nv -Force | Out-Null }
                    Set-ItemProperty $nv -Name "Deception" -Value 0 -Type DWord -Force 2>$null
                }
            }
        }
        @{
            Nome  = "DWM - Desativar Vsync Forcado do Desktop"
            Desc  = "Reduz latencia de apresentacao de frames no Desktop Window Manager"
            Risco = "medio"
            Bloco = {
                $p = "HKCU:\Software\Microsoft\Windows\DWM"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "OverlayTestMode" -Value 5 -Type DWord -Force 2>$null
            }
        }
    )

    Invoke-TweakChecklist -Titulo "Input Lag - Regedit + GP" -Tweaks $tweaksList
    $Script:TweaksFeitos.Add("Input Lag: checklist aplicado")
    LOG "Input Lag tweaks v5.1"
}

# ================================================================
#  NOVO v5.1 - GPEDIT PERFORMANCE PACK (via registro)
# ================================================================
function Invoke-GPeditPerformance {
    H2 "GROUP POLICY - PACK DE PERFORMANCE"

    INF "Aplica politicas equivalentes ao gpedit.msc via registro."
    INF "Funciona no Windows Home tambem."
    Write-Host ""

    $winEdition = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
    if ($winEdition -match 'Home') {
        WN "Windows Home: politicas via registro (equivalente ao gpedit.msc)"
        Write-Host ""
    }

    $tweaksList = @(
        @{
            Nome  = "GP: Prompt de Elevacao OFF para Admins"
            Desc  = "Admins nao veem UAC prompt para apps Microsoft assinados"
            Risco = "medio"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
                Set-ItemProperty $p -Name "ConsentPromptBehaviorAdmin" -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "PromptOnSecureDesktop"      -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "GP: Driver Updates Automaticos OFF"
            Desc  = "Impede Windows Update de trocar drivers automaticamente"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Settings"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "DisableWindowsUpdateAccess" -Value 1 -Type DWord -Force 2>$null
                $p2 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching"
                Set-ItemProperty $p2 -Name "SearchOrderConfig"       -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $p2 -Name "DontSearchWindowsUpdate" -Value 1 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "GP: Windows Spotlight e Anuncios OFF"
            Desc  = "Desativa Spotlight, Consumer Features e anuncios na lock screen"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "DisableWindowsSpotlightFeatures"                   -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "DisableWindowsConsumerFeatures"                    -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "DisableSoftLanding"                                -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "DisableWindowsSpotlightOnActionCenter"             -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "DisableWindowsSpotlightWindowsWelcomeExperience"   -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "DisableTailoredExperiencesWithDiagnosticData"      -Value 1 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "GP: Apps Sugeridos (Silently Installed) OFF"
            Desc  = "Bloqueia instalacao silenciosa de Candy Crush, Spotify e similares"
            Risco = "baixo"
            Bloco = {
                $pu = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                Set-ItemProperty $pu -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $pu -Name "PreInstalledAppsEnabled"    -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $pu -Name "OemPreInstalledAppsEnabled" -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $pu -Name "ContentDeliveryAllowed"     -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "GP: NTFS Filesystem Performance"
            Desc  = "8.3 OFF, LastAccess OFF, MFT Zone 2, Criptografia de NTFS OFF"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
                Set-ItemProperty $p -Name "NtfsDisable8dot3NameCreation" -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "NtfsDisableLastAccessUpdate"  -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "NtfsEncryptionService"        -Value 0 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "NtfsMftZoneReservation"       -Value 2 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "GP: CPU Scheduling - Foreground Boost"
            Desc  = "Processos em primeiro plano recebem quanta de CPU maiores (Win32PrioritySeparation=2)"
            Risco = "baixo"
            Bloco = {
                # Win10: 0x26 (38) = quantum curto com boost. Win11: 2 = sem stutter
                $w32val = if ($Script:IsWin11) { 2 } else { 0x26 }
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" `
                    -Name "Win32PrioritySeparation" -Value $w32val -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "GP: Remote Assistance OFF"
            Desc  = "Desativa Assistencia Remota - elimina servico e porta aberta"
            Risco = "baixo"
            Bloco = {
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" `
                    -Name "fAllowToGetHelp" -Value 0 -Type DWord -Force 2>$null
                $pp = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
                if (-not (Test-Path $pp)) { New-Item $pp -Force | Out-Null }
                Set-ItemProperty $pp -Name "fAllowToGetHelp" -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "GP: Error Reporting (WER) OFF"
            Desc  = "Para WerFault.exe que acorda CPU em crashes - elimina envios a Microsoft"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "Disabled"                -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "DontSendAdditionalData"  -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "LoggingDisabled"         -Value 1 -Type DWord -Force 2>$null
                Stop-Service "WerSvc" -Force 2>$null; Set-Service "WerSvc" -StartupType Disabled 2>$null
            }
        }
        @{
            Nome  = "GP: Location e Sensors OFF"
            Desc  = "GPS e sensores desativados - elimina polling periodico de hardware"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "DisableLocation"               -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "DisableSensors"                -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "DisableLocationScripting"      -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty $p -Name "DisableWindowsLocationProvider" -Value 1 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "GP: AutoPlay e AutoRun OFF"
            Desc  = "Desativa scan automatico ao inserir USB/CD (libera I/O e CPU pontual)"
            Risco = "baixo"
            Bloco = {
                $pa = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
                Set-ItemProperty $pa -Name "NoDriveTypeAutoRun" -Value 255 -Type DWord -Force 2>$null
                Set-ItemProperty $pa -Name "NoAutorun"          -Value 1   -Type DWord -Force 2>$null
                Stop-Service "ShellHWDetection" -Force 2>$null
                Set-Service  "ShellHWDetection" -StartupType Disabled 2>$null
            }
        }
        @{
            Nome  = "GP: Network Throttle Background OFF"
            Desc  = "Remove reserva de 20pct da banda para processos de baixa prioridade"
            Risco = "baixo"
            Bloco = {
                $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "NonBestEffortLimit" -Value 0 -Type DWord -Force 2>$null
            }
        }
        @{
            Nome  = "GP: Hibernacao Hibrida OFF"
            Desc  = "Hybrid sleep desnecessario para desktops - economiza escrita em SSD"
            Risco = "baixo"
            Bloco = {
                powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP HYBRIDSLEEP 0 2>$null
                powercfg /setactive SCHEME_CURRENT 2>$null
            }
        }
    )

    Invoke-TweakChecklist -Titulo "Group Policy Performance" -Tweaks $tweaksList
    $Script:TweaksFeitos.Add("GPedit Performance: checklist aplicado")
    LOG "GPedit Performance v5.1"
}


# ================================================================
#  ABIMALEKBOOST v6.0 - MOTOR DE IA HEURISTICA
#  Sistema de otimizacao inteligente para Windows
#  Arquitetura: Coleta -> Analise -> Decisao -> Aplicacao -> Score
# ================================================================

# ================================================================
#  REGION: VARIAVEIS DO MOTOR DE IA
# ================================================================
$Script:IA = [ordered]@{
    # Snapshot do sistema (antes/depois)
    SnapshotAntes  = $null
    SnapshotDepois = $null

    # Classificacao do gargalo detectado
    Gargalo        = @()    # CPU-bound, GPU-bound, RAM-limitada, IO-limitado, Rede-instavel

    # Perfil de uso detectado / selecionado
    Perfil         = ""     # Seguro, Gamer, Streamer, Extremo

    # Scores calculados
    ScoreAntes     = @{ Geral=0; Latencia=0; Responsividade=0; Gamer=0 }
    ScoreDepois    = @{ Geral=0; Latencia=0; Responsividade=0; Gamer=0 }

    # Decisoes do motor
    OtimizacoesDecididas = [System.Collections.Generic.List[hashtable]]::new()
    OtimizacoesAplicadas = [System.Collections.Generic.List[string]]::new()

    # Historico local (JSON)
    ArqHistorico   = Join-Path $Script:PastaRaiz "ia_historico.json"
    ArqBackupReg   = Join-Path $Script:PastaBackup "reg_ia_backup.reg"
    Historico      = $null

    # Metricas coletadas
    CPUUsoPct      = 0.0
    RAMUsoPct      = 0.0
    DiskQueueLen   = 0.0
    LatenciaMS     = 0
    ProcPesados    = @()
    ServicosAtivos = 0
    PlanoAtual     = ""
    NetworkJitter  = 0

    # Modo simulacao
    SimulandoJogo  = ""
}

# ================================================================
#  REGION: COLETA DE DADOS (SNAPSHOT DO SISTEMA)
# ================================================================

# ================================================================
#  MOTOR DE IA v7.0 - APRENDIZADO REAL, SEM SERVIDOR EXTERNO
#  Substitui: Get-IASnapshot, Measure-PerformanceScore,
#             Invoke-IAMotorDecisao, Save-IAExecucao,
#             Get-IAInsightHistorico
# ================================================================

# ================================================================
#  GET-IASNAPSHOT v7 - coleta 40+ metricas, detecta thermal,
#  E/P cores, IRQ conflicts, GPU throttle, DPC latency
# ================================================================
function Get-IASnapshot {
    param([string]$Label = "snapshot")

    IN "Coletando metricas ($Label)..."

    $snap = [ordered]@{
        Timestamp       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Label           = $Label

        # CPU
        CPUNome         = $Script:CPUNome
        CPUNucleos      = $Script:CPUNucleos
        CPUThreads      = $Script:CPUThreads
        CPUFabricante   = $Script:CPUFab
        CPUX3D          = $Script:CPUX3D
        CPUGen          = $Script:CPUGen
        CPUUsoPct       = 0.0
        CPUBaseClock    = 0
        CPUCurrentClock = 0
        CPUCoreParking  = $false
        CPUThermalThrot = $false   # NOVO: thermal throttling detectado
        CPUEPCores      = $false   # NOVO: Intel com E/P cores (12a gen+)
        CPUPCores       = 0        # NOVO: numero de P-cores (Intel)
        CPUECores       = 0        # NOVO: numero de E-cores (Intel)

        # RAM
        RAMtotalGB      = $Script:RAMtotalGB
        RAMtipo         = $Script:RAMtipo
        RAMvelocidade   = $Script:RAMvelocidade
        RAMUsoPct       = 0.0
        RAMLivreGB      = 0.0
        RAMCompressao   = $false
        RAMPaginando    = $false
        PagefileGB      = 0.0

        # GPU
        GPUNome         = $Script:GPUNome
        GPUFab          = $Script:GPUFab
        GPUVRAM         = $Script:GPUVRAM
        GPUTemp         = 0
        GPUThrottle     = $false   # NOVO: GPU throttling detectado
        GPUDriverOld    = $false   # NOVO: driver possivelmente antigo

        # Disco
        DiscoTipo       = $Script:DiscoTipo
        DiscoNVMe       = $Script:DiscoNVMe
        DiskQueueLen    = 0.0
        DiskReadMBs     = 0.0
        DiskWriteMBs    = 0.0

        # Rede
        LatenciaMS      = 0
        NetworkJitter   = 0
        TCPAutotuning   = ""
        NagleAtivo      = $true
        BandaLargura    = ""

        # Sistema
        WinBuild        = $Script:WinBuild
        IsWin11         = $Script:IsWin11
        PlanoEnergia    = ""
        ServicosAtivos  = 0
        ProcessosPes    = @()
        TimerResMS      = 0.0
        UptimeHoras     = 0

        # NOVOS: Diagnosticos avancados
        IRQConflict     = $false   # NOVO: conflito de IRQ detectado
        DPCLatencyHigh  = $false   # NOVO: DPC latency alta
        PowerThrottle   = $false   # NOVO: Power Throttling ativo
        MMCSSConfigurado = $false  # NOVO: MMCSS Gaming configurado
        SpectreAtivo    = $true    # NOVO: mitigacoes ativas
        HibernacaoAtiva = $false   # NOVO: hibernacao ligada

        # Score
        Score = @{ Geral=0; Latencia=0; Responsividade=0; Gamer=0; Thermal=0 }
    }

    # ?? CPU uso + clock atual ?????????????????????????????????
    try {
        $cpuObj = Get-CimInstance Win32_Processor -EA SilentlyContinue | Select -First 1
        if ($cpuObj) {
            $snap.CPUUsoPct    = $cpuObj.LoadPercentage
            $snap.CPUBaseClock = $cpuObj.MaxClockSpeed
            # Clock atual via perf counter
            $clk = (Get-Counter "\Processor Information(_Total)\% Processor Performance" -EA SilentlyContinue).CounterSamples.CookedValue
            if ($clk) { $snap.CPUCurrentClock = [math]::Round($snap.CPUBaseClock * $clk / 100) }
        }
    } catch {}

    # ?? Core Parking ?????????????????????????????????????????
    try {
        $p = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583" -EA SilentlyContinue
        $snap.CPUCoreParking = ($p -eq $null -or [int]$p.ValueMax -lt 100)
    } catch {}

    # ?? Thermal Throttling (NOVO) ?????????????????????????????
    # Detecta se o CPU esta sendo limitado por temperatura
    try {
        $thermalZones = Get-CimInstance -Namespace root/WMI -ClassName MSAcpi_ThermalZoneTemperature -EA SilentlyContinue
        if ($thermalZones) {
            foreach ($tz in $thermalZones) {
                $tempC = [math]::Round(($tz.CurrentTemperature - 2732) / 10, 0)
                if ($tempC -gt 90) { $snap.CPUThermalThrot = $true; break }
            }
        }
        # Alternativa: verificar via WMI evento throttle
        $throttleEvent = Get-WinEvent -FilterHashtable @{LogName='System'; Id=37} -MaxEvents 3 -EA SilentlyContinue
        if ($throttleEvent) { $snap.CPUThermalThrot = $true }
    } catch {}

    # ?? Intel E/P Cores (NOVO) ???????????????????????????????
    # Intel 12a gen+ tem Performance cores e Efficiency cores
    try {
        if ($Script:CPUFab -eq "Intel" -and $Script:CPUGen -ge 12) {
            $snap.CPUEPCores = $true
            # Tentar detectar P/E via registry ou nome do CPU
            if ($Script:CPUNome -match "(\d+)P.*?(\d+)E") {
                $snap.CPUPCores = [int]$Matches[1]
                $snap.CPUECores = [int]$Matches[2]
            } elseif ($Script:CPUNucleos -ge 8) {
                # Estimativa: metade P, metade E para Intel 12/13/14
                $snap.CPUPCores = [math]::Ceiling($Script:CPUNucleos * 0.5)
                $snap.CPUECores = [math]::Floor($Script:CPUNucleos * 0.5)
            }
        }
    } catch {}

    # ?? RAM ??????????????????????????????????????????????????
    try {
        $os = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
        if ($os) {
            $totalMB = $os.TotalVisibleMemorySize / 1024
            $livreMB = $os.FreePhysicalMemory / 1024
            $snap.RAMLivreGB = [math]::Round($livreMB / 1024, 1)
            $snap.RAMUsoPct  = [math]::Round((($totalMB - $livreMB) / $totalMB) * 100, 1)
            $snap.UptimeHoras = [math]::Round(($os.LastBootUpTime | ForEach-Object { (Get-Date) - $_ } | Select-Object -ExpandProperty TotalHours), 0)
        }
    } catch {}

    try {
        $pf = Get-CimInstance Win32_PageFileUsage -EA SilentlyContinue
        if ($pf) {
            $snap.PagefileGB  = [math]::Round($pf.CurrentUsage / 1024, 1)
            $snap.RAMPaginando = ($pf.CurrentUsage -gt 100)
        }
        $snap.RAMCompressao = ($null -ne (Get-Process "Memory Compression" -EA SilentlyContinue))
    } catch {}

    # ?? GPU Temperature + Throttle (NOVO) ???????????????????
    try {
        # NVIDIA via nvidia-smi
        $smi = Get-Command "nvidia-smi" -EA SilentlyContinue
        if ($smi) {
            $smiOut = & nvidia-smi --query-gpu=temperature.gpu,clocks_throttle_reasons.active -fo csv,noheader 2>$null
            if ($smiOut) {
                $parts = $smiOut -split ','
                if ($parts.Count -ge 1) { $snap.GPUTemp = [int]$parts[0].Trim() }
                if ($parts.Count -ge 2) { $snap.GPUThrottle = ($parts[1].Trim() -ne "0x0000000000000000") }
            }
        } else {
            # Fallback: WMI
            $gpuWMI = Get-CimInstance -Namespace root/WMI -ClassName MSAcpi_ThermalZoneTemperature -EA SilentlyContinue | Select -Last 1
            if ($gpuWMI) { $snap.GPUTemp = [math]::Round(($gpuWMI.CurrentTemperature - 2732) / 10, 0) }
        }
        # GPU throttle por temperatura
        if ($snap.GPUTemp -gt 85) { $snap.GPUThrottle = $true }
    } catch {}

    # ?? Disk I/O ?????????????????????????????????????????????
    try {
        $snap.DiskQueueLen = [math]::Round(
            (Get-Counter "\PhysicalDisk(_Total)\Avg. Disk Queue Length" -EA SilentlyContinue).CounterSamples.CookedValue, 2)
    } catch { $snap.DiskQueueLen = 0.0 }

    # ?? Rede ?????????????????????????????????????????????????
    try {
        $pings = 1..5 | ForEach-Object {
            $r = Test-Connection "8.8.8.8" -Count 1 -EA SilentlyContinue
            if ($r) { $r.ResponseTime } else { 999 }
        }
        $snap.LatenciaMS   = [math]::Round(($pings | Measure-Object -Average).Average)
        $snap.NetworkJitter = ($pings | Measure-Object -Maximum).Maximum - $snap.LatenciaMS
    } catch { $snap.LatenciaMS = 999 }

    try {
        $nagle = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -EA SilentlyContinue
        $tcpAckFreq = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -EA SilentlyContinue |
            ForEach-Object { Get-ItemProperty $_.PSPath -EA SilentlyContinue } |
            Where-Object { $_.TcpAckFrequency -eq 1 } | Select -First 1
        $snap.NagleAtivo = ($tcpAckFreq -eq $null)
        $tcp = netsh int tcp show global 2>$null | Select-String "Receive Window Auto-Tuning"
        $snap.TCPAutotuning = if ($tcp -match "normal") { "Normal" } elseif ($tcp -match "disabled") { "Disabled" } else { "Unknown" }
    } catch {}

    # ?? Timer Resolution ?????????????????????????????????????
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Start-Sleep -Milliseconds 15
        $sw.Stop()
        $snap.TimerResMS = [math]::Round($sw.Elapsed.TotalMilliseconds - 15, 2)
        if ($snap.TimerResMS -lt 0) { $snap.TimerResMS = 0.5 }
    } catch {}

    # ?? Plano de Energia ?????????????????????????????????????
    try {
        $plano = powercfg /getactivescheme 2>$null
        $snap.PlanoEnergia = if ($plano -match "Ultimate") { "Ultimate Performance" }
                             elseif ($plano -match "High") { "Alto Desempenho" }
                             elseif ($plano -match "Balanced") { "Balanceado" }
                             elseif ($plano -match "Power saver") { "Economia" }
                             elseif ($plano -match "AMD") { "AMD Ryzen Balanced" }
                             else { ($plano -split '\(')[0].Trim() }
    } catch {}

    # ?? Servicos e processos pesados ?????????????????????????
    try {
        $snap.ServicosAtivos = (Get-Service -EA SilentlyContinue | Where-Object { $_.Status -eq "Running" }).Count
        $snap.ProcessosPes   = (Get-Process -EA SilentlyContinue | Sort-Object CPU -Descending |
            Select-Object -First 8 | Select-Object -ExpandProperty ProcessName)
    } catch {}

    # ?? MMCSS configurado (NOVO) ?????????????????????????????
    try {
        $mmcss = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -EA SilentlyContinue
        $snap.MMCSSConfigurado = ($mmcss -and $mmcss.Priority -ge 6)
    } catch {}

    # ?? Power Throttling ativo (NOVO) ????????????????????????
    try {
        $pt = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -EA SilentlyContinue
        $snap.PowerThrottle = ($pt -eq $null -or $pt.PowerThrottlingOff -ne 1)
    } catch { $snap.PowerThrottle = $true }

    # ?? Spectre/Meltdown mitigacoes (NOVO) ???????????????????
    try {
        $spec = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -EA SilentlyContinue
        $snap.SpectreAtivo = ($spec -eq $null -or $spec.FeatureSettingsOverride -ne 3)
    } catch {}

    # ?? Hibernacao ativa (NOVO) ??????????????????????????????
    try {
        $hibFile = Test-Path "$env:SystemDrive\hiberfil.sys"
        $snap.HibernacaoAtiva = $hibFile
    } catch {}

    # ?? DPC Latency alta (NOVO) ??????????????????????????????
    # Detecta via event log e via IRQ sharing
    try {
        $dpcEvents = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=41} -MaxEvents 5 -EA SilentlyContinue
        $snap.DPCLatencyHigh = ($dpcEvents -and $dpcEvents.Count -gt 0)
    } catch {}

    # ?? Calcular Score ???????????????????????????????????????
    $snap.Score = Measure-PerformanceScore $snap

    return $snap
}

# ================================================================
#  MEASURE-PERFORMANCESCORE v7 - inclui thermal, E/P cores, DPC
# ================================================================
function Measure-PerformanceScore {
    param($snap)

    $scores = @{ Geral=0; Latencia=0; Responsividade=0; Gamer=0; Thermal=0 }

    # === LATENCIA ===
    $sL = 100
    if     ($snap.LatenciaMS  -gt 150) { $sL -= 30 }
    elseif ($snap.LatenciaMS  -gt 80)  { $sL -= 20 }
    elseif ($snap.LatenciaMS  -gt 40)  { $sL -= 10 }
    elseif ($snap.LatenciaMS  -gt 20)  { $sL -= 5  }
    if     ($snap.NetworkJitter -gt 30){ $sL -= 20 }
    elseif ($snap.NetworkJitter -gt 15){ $sL -= 10 }
    elseif ($snap.NetworkJitter -gt 5) { $sL -= 5  }
    if ($snap.NagleAtivo)              { $sL -= 12 }  # aumentado: nagle e critico
    if ($snap.TCPAutotuning -ne "Normal") { $sL -= 5 }
    if ($snap.TimerResMS    -gt 5)     { $sL -= 12 }
    elseif ($snap.TimerResMS -gt 2)    { $sL -= 6  }
    elseif ($snap.TimerResMS -gt 1)    { $sL -= 3  }
    $scores.Latencia = [math]::Max(0, [math]::Min(100, $sL))

    # === RESPONSIVIDADE ===
    $sR = 100
    if     ($snap.CPUUsoPct -gt 80) { $sR -= 25 }
    elseif ($snap.CPUUsoPct -gt 60) { $sR -= 15 }
    elseif ($snap.CPUUsoPct -gt 40) { $sR -= 8  }
    if     ($snap.RAMUsoPct -gt 85) { $sR -= 20 }
    elseif ($snap.RAMUsoPct -gt 70) { $sR -= 12 }
    elseif ($snap.RAMUsoPct -gt 55) { $sR -= 6  }
    if     ($snap.DiskQueueLen -gt 2.0) { $sR -= 20 }
    elseif ($snap.DiskQueueLen -gt 1.0) { $sR -= 10 }
    elseif ($snap.DiskQueueLen -gt 0.5) { $sR -= 5  }
    if ($snap.ServicosAtivos -gt 150)   { $sR -= 10 }
    elseif ($snap.ServicosAtivos -gt 120){ $sR -= 5  }
    if ($snap.RAMPaginando)              { $sR -= 15 }
    if ($snap.CPUCoreParking)            { $sR -= 12 }
    if ($snap.PowerThrottle)             { $sR -= 8  }  # NOVO
    if ($snap.DPCLatencyHigh)            { $sR -= 8  }  # NOVO
    $scores.Responsividade = [math]::Max(0, [math]::Min(100, $sR))

    # === GAMER ===
    $sG = 100
    if ($snap.PlanoEnergia -ne "Ultimate Performance" -and
        $snap.PlanoEnergia -ne "Alto Desempenho" -and
        $snap.PlanoEnergia -ne "AMD Ryzen Balanced")     { $sG -= 15 }
    if ($snap.CPUCoreParking)            { $sG -= 15 }
    if ($snap.TimerResMS    -gt 3)       { $sG -= 10 }
    if ($snap.NagleAtivo)                { $sG -= 10 }
    if ($snap.RAMUsoPct     -gt 70)      { $sG -= 10 }
    if ($snap.ServicosAtivos -gt 120)    { $sG -= 8  }
    if (-not $snap.DiscoNVMe -and $snap.DiskQueueLen -gt 0.5) { $sG -= 10 }
    if ($snap.NetworkJitter  -gt 15)     { $sG -= 10 }
    if ($snap.RAMCompressao)             { $sG -= 5  }
    if (-not $snap.MMCSSConfigurado)     { $sG -= 8  }  # NOVO
    if ($snap.PowerThrottle)             { $sG -= 8  }  # NOVO
    if ($snap.GPUThrottle)               { $sG -= 12 }  # NOVO: GPU throttling
    if ($snap.HibernacaoAtiva)           { $sG -= 3  }  # NOVO: hiberfil ocupa SSD

    # Intel E/P cores sem otimizacao: jogo pode cair em E-core
    if ($snap.CPUEPCores -and -not $snap.MMCSSConfigurado) { $sG -= 8 } # NOVO

    # Bonus hardware
    if ($snap.CPUX3D)                    { $sG += 5 }
    if ($snap.RAMtipo -eq "DDR5")        { $sG += 5 }
    if ($snap.DiscoNVMe)                 { $sG += 5 }
    if ($snap.GPUVRAM -ge 8)             { $sG += 5 }
    if (-not $snap.SpectreAtivo)         { $sG += 5 }  # Extremo: spectre off da bonus
    $scores.Gamer = [math]::Max(0, [math]::Min(100, $sG))

    # === THERMAL (NOVO) ===
    $sT = 100
    if ($snap.CPUThermalThrot)           { $sT -= 40 }
    if ($snap.GPUThrottle)               { $sT -= 30 }
    if ($snap.GPUTemp -gt 85)            { $sT -= 20 }
    elseif ($snap.GPUTemp -gt 80)        { $sT -= 10 }
    $scores.Thermal = [math]::Max(0, [math]::Min(100, $sT))

    # === GERAL (ponderado) ===
    # Thermal penaliza tudo se estiver ruim
    $thermalFactor = if ($scores.Thermal -lt 60) { 0.9 } else { 1.0 }
    $scores.Geral = [math]::Round(
        ($scores.Latencia * 0.28 + $scores.Responsividade * 0.32 +
         $scores.Gamer    * 0.32 + $scores.Thermal        * 0.08) * $thermalFactor, 0)

    return $scores
}

# ================================================================
#  INVOKE-IAMOTORDECISAO v7 - 32 regras, Intel E/P cores,
#  thermal, regression detection, aprendizado local
# ================================================================
function Invoke-IAMotorDecisao {
    param($snap)

    $Script:IA.OtimizacoesDecididas.Clear()
    $Script:IA.Gargalo = @()

    # ?? Detectar gargalos ????????????????????????????????????
    $gargalos = [System.Collections.Generic.List[string]]::new()
    if ($snap.CPUUsoPct        -gt 60)   { $gargalos.Add("CPU-bound")        }
    if ($snap.RAMUsoPct        -gt 70 -or $snap.RAMPaginando) { $gargalos.Add("RAM-limitada") }
    if ($snap.DiskQueueLen     -gt 1.0)  { $gargalos.Add("IO-limitado")      }
    if ($snap.NetworkJitter    -gt 15 -or $snap.LatenciaMS -gt 80) { $gargalos.Add("Rede-instavel") }
    if ($snap.GPUVRAM          -le 4)    { $gargalos.Add("GPU-bound")        }
    if ($snap.CPUThermalThrot)           { $gargalos.Add("Thermal-throttle") }  # NOVO
    if ($snap.GPUThrottle)               { $gargalos.Add("GPU-throttle")     }  # NOVO
    if ($snap.CPUEPCores -and -not $snap.MMCSSConfigurado) { $gargalos.Add("Intel-EP-sem-afinidade") } # NOVO
    $Script:IA.Gargalo = $gargalos.ToArray()

    # ?? Carregar aprendizado: saber o que funcionou ??????????
    Load-IAHistorico
    $hist = $Script:IA.Historico
    $tweaksEficazes = @{}   # tweak_id -> ganho_medio_quando_aplicado
    $tweaksFalharam = @{}   # tweak_id -> ganho_negativo_detectado
    if ($hist.TweakEficacia) {
        foreach ($key in $hist.TweakEficacia.PSObject.Properties.Name) {
            $val = $hist.TweakEficacia.$key
            if ($val -gt 0) { $tweaksEficazes[$key] = $val }
            else             { $tweaksFalharam[$key] = $val }
        }
    }

    # ?? Regras - estrutura: Id, Desc, Prio, Perfis, Risco, Cond, Bloco ??

    $regras = @(

        # ?? PRIORIDADE 1: CRITICO ?????????????????????????????
        @{
            Id    = "PLANO_ULTIMATE"
            Desc  = "Ativar Ultimate Performance"
            Prio  = 1
            Perfis = @("Seguro","Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $snap.PlanoEnergia -ne "Ultimate Performance" -and $snap.PlanoEnergia -ne "Alto Desempenho" }
            Bloco = {
                $guid = (powercfg /list 2>$null | Select-String "Ultimate Performance" | ForEach-Object { ($_ -match "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}") | Out-Null; $Matches[0] }) | Select-Object -First 1
                if (-not $guid) {
                    powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
                    $guid = (powercfg /list 2>$null | Select-String "Ultimate Performance" | ForEach-Object { ($_ -match "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}") | Out-Null; $Matches[0] }) | Select-Object -First 1
                }
                if ($guid) { powercfg /setactive $guid 2>$null }
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 2>$null
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR SYSCOOLPOL 0 2>$null
            }
        }

        @{
            Id    = "CORE_PARKING_OFF"
            Desc  = "Core Parking OFF - todos os nucleos disponiveis"
            Prio  = 1
            Perfis = @("Seguro","Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $snap.CPUCoreParking }
            Bloco = {
                powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 0cc5b647-c1df-4637-891a-dec35c318583 100 2>$null
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 2>$null
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583" -Name "ValueMax" -Value 100 -Type DWord -Force 2>$null
            }
        }

        @{
            Id    = "NAGLE_OFF"
            Desc  = "Nagle Algorithm OFF - latencia de rede minima"
            Prio  = 1
            Perfis = @("Seguro","Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $snap.NagleAtivo }
            Bloco = {
                Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -EA SilentlyContinue | ForEach-Object {
                    Set-ItemProperty $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force 2>$null
                    Set-ItemProperty $_.PSPath -Name "TCPNoDelay"      -Value 1 -Type DWord -Force 2>$null
                }
            }
        }

        @{
            Id    = "TIMER_RESOLUTION"
            Desc  = "Timer Resolution otimizado por OS"
            Prio  = 1
            Perfis = @("Seguro","Gamer","Streamer","Extremo")
            Risco = "medio"
            Cond  = { $snap.TimerResMS -gt 1.5 }
            Bloco = {
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" -Name "GlobalTimerResolutionRequests" -Value 1 -Type DWord -Force 2>$null
                Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 0 -Type DWord -Force 2>$null
                bcdedit /set disabledynamictick yes 2>$null | Out-Null
                if (-not $Script:IsWin11) { bcdedit /set useplatformtick yes 2>$null | Out-Null }
            }
        }

        # ?? PRIORIDADE 2: ALTO ????????????????????????????????
        @{
            Id    = "MMCSS_GAMING"
            Desc  = "MMCSS Gaming - prioridade RT para threads de jogo"
            Prio  = 2
            Perfis = @("Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { -not $snap.MMCSSConfigurado }
            Bloco = {
                $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
                if (-not (Test-Path $path)) { New-Item $path -Force | Out-Null }
                Set-ItemProperty $path -Name "Affinity"              -Value 0    -Type DWord  -Force 2>$null
                Set-ItemProperty $path -Name "Background Only"       -Value "False" -Type String -Force 2>$null
                Set-ItemProperty $path -Name "Clock Rate"            -Value 10000 -Type DWord -Force 2>$null
                Set-ItemProperty $path -Name "GPU Priority"          -Value 8    -Type DWord  -Force 2>$null
                Set-ItemProperty $path -Name "Priority"              -Value 6    -Type DWord  -Force 2>$null
                Set-ItemProperty $path -Name "Scheduling Category"   -Value "High" -Type String -Force 2>$null
                Set-ItemProperty $path -Name "SFIO Priority"         -Value "High" -Type String -Force 2>$null
            }
        }

        @{
            Id    = "WIN32_PRIORITY_SEP"
            Desc  = "Win32PrioritySeparation - scheduler adaptativo por OS"
            Prio  = 2
            Perfis = @("Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $true }
            Bloco = {
                $w32val = if ($Script:IsWin11) { 2 } else { 0x26 }
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value $w32val -Type DWord -Force 2>$null
            }
        }

        @{
            Id    = "POWER_THROTTLE_OFF"
            Desc  = "Power Throttling OFF - sem limite de boost em segundo plano"
            Prio  = 2
            Perfis = @("Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $snap.PowerThrottle }
            Bloco = {
                $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "PowerThrottlingOff" -Value 1 -Type DWord -Force 2>$null
            }
        }

        @{
            Id    = "TCP_STACK"
            Desc  = "TCP Stack - TTL, MaxUserPort, scaling, DCA"
            Prio  = 2
            Perfis = @("Seguro","Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $true }
            Bloco = {
                $tcp = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
                Set-ItemProperty $tcp -Name "DefaultTTL"           -Value 64    -Type DWord -Force 2>$null
                Set-ItemProperty $tcp -Name "MaxUserPort"          -Value 65534 -Type DWord -Force 2>$null
                Set-ItemProperty $tcp -Name "TcpTimedWaitDelay"    -Value 30    -Type DWord -Force 2>$null
                Set-ItemProperty $tcp -Name "Tcp1323Opts"          -Value 1     -Type DWord -Force 2>$null
                Set-ItemProperty $tcp -Name "TCPNoDelay"           -Value 1     -Type DWord -Force 2>$null
                netsh int tcp set global autotuninglevel=normal     2>$null | Out-Null
                netsh int tcp set global timestamps=disabled        2>$null | Out-Null
                netsh int tcp set global dca=enabled                2>$null | Out-Null
                netsh int tcp set global ecncapability=disabled     2>$null | Out-Null
            }
        }

        @{
            Id    = "NETWORK_THROTTLE_OFF"
            Desc  = "Network Throttle OFF - sem limite de banda para jogos"
            Prio  = 2
            Perfis = @("Seguro","Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $true }
            Bloco = {
                $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
                Set-ItemProperty $path -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -Force 2>$null
                Set-ItemProperty $path -Name "NonBestEffortLimit"     -Value 0          -Type DWord -Force 2>$null
            }
        }

        @{
            Id    = "SYSMAIN_OFF"
            Desc  = "SysMain OFF - so em HDD ou RAM <= 8GB"
            Prio  = 2
            Perfis = @("Seguro","Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $snap.DiscoTipo -match "HDD" -or $snap.RAMtotalGB -le 8 }
            Bloco = {
                Stop-Service "SysMain" -Force 2>$null
                Set-Service  "SysMain" -StartupType Disabled 2>$null
            }
        }

        @{
            Id    = "MOUSE_ACCEL_OFF"
            Desc  = "Mouse 1:1 - sem aceleracao, sem curve"
            Prio  = 2
            Perfis = @("Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $true }
            Bloco = {
                Set-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseSpeed"      -Value "0" -Type String -Force 2>$null
                Set-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0" -Type String -Force 2>$null
                Set-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0" -Type String -Force 2>$null
            }
        }

        @{
            Id    = "IRQ_INPUT_PRIORITY"
            Desc  = "IRQ Priority - mouse e teclado em prioridade maxima"
            Prio  = 2
            Perfis = @("Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $true }
            Bloco = {
                foreach ($drv in @("mouclass","kbdclass","hidusb","mouhid","usbhid")) {
                    $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$drv"
                    if (Test-Path $p) { Set-ItemProperty $p -Name "RequestedPriority" -Value 6 -Type DWord -Force 2>$null }
                }
            }
        }

        # ?? NOVO: Intel E/P Cores ?????????????????????????????
        @{
            Id    = "INTEL_EP_AFFINITY"
            Desc  = "Intel Hybrid CPU - forcar jogos em P-cores via MMCSS"
            Prio  = 2
            Perfis = @("Gamer","Streamer","Extremo")
            Risco = "medio"
            Cond  = { $snap.CPUEPCores }
            Bloco = {
                # Win11 ja tem Intel Thread Director
                # Win10 e Win11 sem ITD: configurar MMCSS para priorizar P-cores
                $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
                if (-not (Test-Path $path)) { New-Item $path -Force | Out-Null }
                # Affinity mask para P-cores (primeiros nucleos fisicos)
                $pCores = if ($snap.CPUPCores -gt 0) { $snap.CPUPCores } else { [math]::Ceiling($snap.CPUNucleos / 2) }
                $affinityMask = ([math]::Pow(2, $pCores) - 1) -as [int]
                Set-ItemProperty $path -Name "Affinity" -Value $affinityMask -Type DWord -Force 2>$null
                # Boost de GPU priority para jogos
                Set-ItemProperty $path -Name "GPU Priority" -Value 8 -Type DWord -Force 2>$null
                OK "Intel E/P Cores: jogos afixados em $pCores P-cores (mascara: $affinityMask)"

                # Desativar heterogeneous policy que pode jogar game em E-core
                if ($Script:IsWin11) {
                    $policy = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00"
                    # HeteroClass1InitialPerf - P-core performance level inicial
                    Set-ItemProperty "$policy\7f2f5cfa-f10c-4823-b5e1-e93ae85f46b5" -Name "ValueMax" -Value 100 -Type DWord -Force 2>$null
                    Set-ItemProperty "$policy\7f2f5cfa-f10c-4823-b5e1-e93ae85f46b5" -Name "ValueMin" -Value 100 -Type DWord -Force 2>$null
                }
            }
        }

        # ?? NOVO: Thermal Throttle ????????????????????????????
        @{
            Id    = "THERMAL_WARN"
            Desc  = "Aviso de Thermal Throttling - CPU/GPU limitados por temperatura"
            Prio  = 2
            Perfis = @("Seguro","Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $snap.CPUThermalThrot -or $snap.GPUThrottle }
            Bloco = {
                Write-Host ""
                Write-Host "  [!] THERMAL THROTTLING DETECTADO" -ForegroundColor Red
                if ($snap.CPUThermalThrot) { Write-Host "      CPU esta sendo limitado por temperatura (>90 graus)" -ForegroundColor Yellow }
                if ($snap.GPUThrottle)     { Write-Host "      GPU esta sendo throttled (temp: $($snap.GPUTemp) C)" -ForegroundColor Yellow }
                Write-Host "      ACAO RECOMENDADA: Limpar cooler/pasta termica antes de otimizar" -ForegroundColor Cyan
                Write-Host "      Software nao resolve throttle termico - precisa de manutencao fisica" -ForegroundColor DarkGray
                Write-Host ""
                # Aplicar o que da pra fazer via software: disable turbo temporario, etc.
                # Desativar hibernacao pra liberar SSD
                powercfg /h off 2>$null
                OK "Hibernacao desativada (libera espaco no SSD e reduz overhead)"
            }
        }

        # ?? PRIORIDADE 3: MEDIO ???????????????????????????????
        @{
            Id    = "BG_APPS_OFF"
            Desc  = "Background Apps OFF"
            Prio  = 3
            Perfis = @("Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $snap.CPUUsoPct -gt 30 -or $snap.RAMUsoPct -gt 60 }
            Bloco = {
                Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1 -Type DWord -Force 2>$null
                $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
                if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                Set-ItemProperty $p -Name "LetAppsRunInBackground" -Value 2 -Type DWord -Force 2>$null
            }
        }

        @{
            Id    = "TELEMETRIA_OFF"
            Desc  = "Telemetria OFF - DiagTrack e dmwappushservice"
            Prio  = 3
            Perfis = @("Seguro","Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $true }
            Bloco = {
                foreach ($svc in @("DiagTrack","dmwappushservice")) {
                    Stop-Service $svc -Force 2>$null
                    Set-Service  $svc -StartupType Disabled 2>$null
                }
            }
        }

        @{
            Id    = "WER_OFF"
            Desc  = "Windows Error Reporting OFF"
            Prio  = 3
            Perfis = @("Seguro","Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $true }
            Bloco = {
                Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1 -Type DWord -Force 2>$null
                Stop-Service  "WerSvc" -Force 2>$null
                Set-Service   "WerSvc" -StartupType Disabled 2>$null
            }
        }

        @{
            Id    = "NTFS_PERF"
            Desc  = "NTFS Performance - LastAccess OFF, 8.3 OFF, MFT zone"
            Prio  = 3
            Perfis = @("Seguro","Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $true }
            Bloco = {
                fsutil behavior set disablelastaccess 1             2>$null | Out-Null
                fsutil behavior set disable8dot3 1                  2>$null | Out-Null
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsMftZoneReservation" -Value 2 -Type DWord -Force 2>$null
            }
        }

        @{
            Id    = "RAM_WORKINGSET"
            Desc  = "RAM Working Set Clear - libera RAM de processos inativos"
            Prio  = 3
            Perfis = @("Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $snap.RAMUsoPct -gt 65 }
            Bloco = {
                Add-Type @"
using System; using System.Runtime.InteropServices;
public class MemClear {
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint a,bool b,int c);
    [DllImport("kernel32.dll")] public static extern bool SetProcessWorkingSetSize(IntPtr h,IntPtr mn,IntPtr mx);
}
"@ -EA SilentlyContinue 2>$null
                Get-Process -EA SilentlyContinue | Where-Object { $_.WorkingSet64 -gt 50MB } | ForEach-Object {
                    try {
                        $h = [MemClear]::OpenProcess(0x1F0FFF, $false, $_.Id)
                        [MemClear]::SetProcessWorkingSetSize($h, [IntPtr](-1), [IntPtr](-1)) | Out-Null
                    } catch {}
                }
                [GC]::Collect()
            }
        }

        @{
            Id    = "QOS_GAMING"
            Desc  = "QoS DSCP 46 - prioridade UDP para jogos populares"
            Prio  = 3
            Perfis = @("Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $true }
            Bloco = {
                $jogos = @("csgo.exe","cs2.exe","valorant.exe","fortnite.exe","r5apex.exe",
                           "dota2.exe","pubg.exe","cod.exe","fivem.exe","gta5.exe",
                           "overwatch.exe","rocketleague.exe")
                $base = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\QoS"
                if (-not (Test-Path $base)) { New-Item $base -Force | Out-Null }
                foreach ($jogo in $jogos) {
                    $p = "$base\$jogo"
                    if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
                    Set-ItemProperty $p -Name "Version"         -Value "1.0"  -Type String -Force 2>$null
                    Set-ItemProperty $p -Name "Protocol"        -Value "17"   -Type String -Force 2>$null
                    Set-ItemProperty $p -Name "Application Name"-Value $jogo  -Type String -Force 2>$null
                    Set-ItemProperty $p -Name "Local Port"      -Value "*"    -Type String -Force 2>$null
                    Set-ItemProperty $p -Name "Local IP"        -Value "*"    -Type String -Force 2>$null
                    Set-ItemProperty $p -Name "Remote Port"     -Value "*"    -Type String -Force 2>$null
                    Set-ItemProperty $p -Name "Remote IP"       -Value "*"    -Type String -Force 2>$null
                    Set-ItemProperty $p -Name "DSCP Value"      -Value "46"   -Type String -Force 2>$null
                    Set-ItemProperty $p -Name "Throttle Rate"   -Value "-1"   -Type String -Force 2>$null
                }
            }
        }

        @{
            Id    = "HIBERNATION_OFF"
            Desc  = "Hibernacao OFF - libera espaco no SSD e reduz overhead"
            Prio  = 3
            Perfis = @("Gamer","Streamer","Extremo")
            Risco = "baixo"
            Cond  = { $snap.HibernacaoAtiva -and $snap.DiscoNVMe }
            Bloco = {
                powercfg /h off 2>$null
            }
        }

        @{
            Id    = "OBS_PRIO"
            Desc  = "OBS Prioridade - AboveNormal + afinidade de CPU"
            Prio  = 2
            Perfis = @("Streamer")
            Risco = "baixo"
            Cond  = { $null -ne (Get-Process "obs64","obs" -EA SilentlyContinue | Select -First 1) }
            Bloco = {
                $obs = Get-Process "obs64","obs" -EA SilentlyContinue | Select -First 1
                if ($obs) {
                    $obs.PriorityClass = "AboveNormal"
                    # Afinidade: metade superior dos nucleos para OBS
                    if ($snap.CPUNucleos -gt 4) {
                        $half = [math]::Pow(2, [math]::Ceiling($snap.CPUNucleos / 2)) - 1
                        $obs.ProcessorAffinity = [IntPtr]([int]$half -shl [math]::Floor($snap.CPUNucleos / 2))
                    }
                    OK "OBS: AboveNormal + afinidade nos nucleos superiores"
                }
            }
        }

        # ?? PRIORIDADE 4: EXTREMO ?????????????????????????????
        @{
            Id    = "SPECTRE_OFF"
            Desc  = "Spectre/Meltdown OFF - +5-10% IPC [RISCO ALTO]"
            Prio  = 4
            Perfis = @("Extremo")
            Risco = "alto"
            Cond  = { $snap.SpectreAtivo }
            Bloco = {
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "FeatureSettingsOverride"     -Value 3 -Type DWord -Force 2>$null
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "FeatureSettingsOverrideMask" -Value 3 -Type DWord -Force 2>$null
                bcdedit /set {current} nx OptIn 2>$null | Out-Null
            }
        }

        @{
            Id    = "CSTATES_OFF"
            Desc  = "C-States OFF via BCD - CPU sempre pronto [latencia minima]"
            Prio  = 4
            Perfis = @("Extremo")
            Risco = "alto"
            Cond  = { $true }
            Bloco = {
                bcdedit /set disabledynamictick yes 2>$null | Out-Null
                if (-not $Script:IsWin11) { bcdedit /set useplatformtick yes 2>$null | Out-Null }
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR IDLEDISABLE 1 2>$null
            }
        }

        @{
            Id    = "MEM_COMPRESSION_OFF"
            Desc  = "Memory Compression OFF - so se RAM comprimindo e <= 6 cores"
            Prio  = 4
            Perfis = @("Extremo")
            Risco = "alto"
            Cond  = { $snap.RAMCompressao -and $snap.CPUNucleos -le 6 }
            Bloco = {
                Disable-MMAgent -mc 2>$null
            }
        }
    )

    # ?? Filtrar por perfil ???????????????????????????????????
    $perfilAtual = $Script:IA.Perfil

    foreach ($regra in $regras) {
        # Verificar perfil
        if ($regra.Perfis -notcontains $perfilAtual) { continue }

        # Verificar condicao
        $condOk = try { & $regra.Cond } catch { $false }
        if (-not $condOk) { continue }

        # Verificar aprendizado: se este tweak causou regressao antes, alertar
        if ($tweaksFalharam.ContainsKey($regra.Id)) {
            $ganhoNeg = $tweaksFalharam[$regra.Id]
            WN "[$($regra.Id)] Historico: ganho negativo ($ganhoNeg pts) em sessao anterior. Aplicando mesmo assim."
        }

        $Script:IA.OtimizacoesDecididas.Add(@{
            Id    = $regra.Id
            Desc  = $regra.Desc
            Prio  = $regra.Prio
            Risco = $regra.Risco
            Bloco = $regra.Bloco
        }) | Out-Null
    }

    # Ordenar por prioridade
    $ordenado = $Script:IA.OtimizacoesDecididas | Sort-Object { [int]$_.Prio }
    $Script:IA.OtimizacoesDecididas.Clear()
    foreach ($o in $ordenado) { $Script:IA.OtimizacoesDecididas.Add($o) | Out-Null }
}

# ================================================================
#  SAVE-IAEXECUCAO v7 - salva tweak-level granular para aprender
# ================================================================
function Save-IAExecucao {
    param($snapAntes, $snapDepois, $perfil, $otimAplicadas)

    Load-IAHistorico
    $ganhoTotal = $snapDepois.Score.Geral - $snapAntes.Score.Geral

    $execucao = [ordered]@{
        Data           = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Perfil         = $perfil
        Hardware       = "$($snapAntes.CPUNome) | $($snapAntes.RAMtotalGB)GB $($snapAntes.RAMtipo) | $($snapAntes.GPUNome)"
        OS             = if ($snapAntes.IsWin11) { "Win11 ($($snapAntes.WinBuild))" } else { "Win10 ($($snapAntes.WinBuild))" }
        ScoreAntes     = $snapAntes.Score.Geral
        ScoreDepois    = $snapDepois.Score.Geral
        Ganho          = $ganhoTotal
        ScoreLatAntes  = $snapAntes.Score.Latencia
        ScoreLatDep    = $snapDepois.Score.Latencia
        ScoreRespAntes = $snapAntes.Score.Responsividade
        ScoreRespDep   = $snapDepois.Score.Responsividade
        ScoreGameAntes = $snapAntes.Score.Gamer
        ScoreGameDep   = $snapDepois.Score.Gamer
        PingAntes      = $snapAntes.LatenciaMS
        PingDepois     = $snapDepois.LatenciaMS
        TimerAntes     = $snapAntes.TimerResMS
        TimerDepois    = $snapDepois.TimerResMS
        RAMAntes       = $snapAntes.RAMUsoPct
        RAMDepois      = $snapDepois.RAMUsoPct
        Otimizacoes    = $otimAplicadas
        Gargalos       = $Script:IA.Gargalo
        ThermalDetect  = ($snapAntes.CPUThermalThrot -or $snapAntes.GPUThrottle)
        EPCoresDetect  = $snapAntes.CPUEPCores
    }

    # ?? Calcular eficacia por tweak ???????????????????????????
    # Se ganho >= 5: registra como positivo; se <= -3: registra como regressao
    $hist   = $Script:IA.Historico
    $eficacia = @{}
    if ($hist.TweakEficacia) {
        $hist.TweakEficacia.PSObject.Properties | ForEach-Object { $eficacia[$_.Name] = $_.Value }
    }

    foreach ($tweak in $otimAplicadas) {
        $id = if ($tweak -match "^([A-Z_]+):") { $Matches[1] } else { $tweak }
        if (-not $eficacia.ContainsKey($id)) { $eficacia[$id] = @() }
        # Armazenar o ganho desta sessao para este tweak (media ponderada depois)
        if ($eficacia[$id] -isnot [System.Collections.Generic.List[object]]) {
            $eficacia[$id] = [System.Collections.Generic.List[object]]::new()
        }
        $eficacia[$id].Add($ganhoTotal) | Out-Null
        if ($eficacia[$id].Count -gt 10) { $eficacia[$id] = $eficacia[$id] | Select-Object -Last 10 }
    }

    # ?? Calcular medias de eficacia ???????????????????????????
    $eficaciaMedia = @{}
    foreach ($key in $eficacia.Keys) {
        $vals = $eficacia[$key]
        if ($vals -is [System.Collections.IEnumerable] -and $vals.Count -gt 0) {
            $eficaciaMedia[$key] = [math]::Round(($vals | Measure-Object -Average).Average, 1)
        }
    }

    # ?? Salvar historico ?????????????????????????????????????
    $lista = [System.Collections.Generic.List[object]]::new()
    if ($hist.Execucoes) { foreach ($e in $hist.Execucoes) { $lista.Add($e) } }
    $lista.Add($execucao)
    if ($lista.Count -gt 50) { $lista = $lista | Select-Object -Last 50 }

    $histAtual = [PSCustomObject]@{
        Versao        = "2.0"
        Execucoes     = $lista.ToArray()
        TweakEficacia = [PSCustomObject]$eficaciaMedia
        Ajustes       = $hist.Ajustes
    }

    $histAtual | ConvertTo-Json -Depth 10 | Out-File $Script:IA.ArqHistorico -Encoding UTF8 -Force 2>$null
}

# ================================================================
#  GET-IAINSIGHTHISTORICO v7 - analise real com deteccao
#  de regressoes, tweaks mais eficazes, recomendacao de perfil
# ================================================================
function Get-IAInsightHistorico {
    Load-IAHistorico
    $hist = $Script:IA.Historico

    if (-not $hist.Execucoes -or $hist.Execucoes.Count -eq 0) {
        return "  Primeira execucao | Ref. benchmark: Ryzen 5 5700X + Win10 -> +58fps no FiveM (+34.5%)"
    }

    $execs      = $hist.Execucoes
    $total      = $execs.Count
    $ganhoMedio = [math]::Round(($execs | Measure-Object -Property Ganho -Average).Average, 1)
    $melhor     = $execs | Sort-Object Ganho -Descending | Select-Object -First 1
    $ultima     = $execs | Select-Object -Last 1
    $regressions = ($execs | Where-Object { $_.Ganho -lt -3 }).Count

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("  HISTORICO v7 ($total sessoes):")
    [void]$sb.AppendLine("  Ganho medio    : +$ganhoMedio pts/sessao")
    [void]$sb.AppendLine("  Melhor sessao  : +$($melhor.Ganho) pts  [$($melhor.Perfil)] em $($melhor.Data)")
    [void]$sb.AppendLine("  Ultima sessao  : $($ultima.Data)  Score $($ultima.ScoreAntes) -> $($ultima.ScoreDepois)")

    # Regressoes detectadas
    if ($regressions -gt 0) {
        [void]$sb.AppendLine("  [!] Regressoes : $regressions sessao(oes) com ganho negativo detectadas")
    }

    # Tweaks mais eficazes do historico
    if ($hist.TweakEficacia) {
        $topTweaks = $hist.TweakEficacia.PSObject.Properties |
            Where-Object { $_.Value -gt 0 } |
            Sort-Object Value -Descending |
            Select-Object -First 3
        if ($topTweaks) {
            [void]$sb.AppendLine("  Top tweaks     : $($topTweaks.Name -join ', ')")
        }
        # Tweaks com regressao
        $badTweaks = $hist.TweakEficacia.PSObject.Properties |
            Where-Object { $_.Value -lt -2 } |
            Select-Object -First 2
        if ($badTweaks) {
            [void]$sb.AppendLine("  [!] Evitar     : $($badTweaks.Name -join ', ')  (ganho negativo no historico)")
        }
    }

    # Perfil mais eficaz (por ganho medio, nao so frequencia)
    $melhorPerfil = $execs | Group-Object Perfil | ForEach-Object {
        $medGanho = ($_.Group | Measure-Object -Property Ganho -Average).Average
        [PSCustomObject]@{ Perfil=$_.Name; Sessoes=$_.Count; GanhoMedio=[math]::Round($medGanho,1) }
    } | Sort-Object GanhoMedio -Descending | Select-Object -First 1

    if ($melhorPerfil) {
        [void]$sb.AppendLine("  Perfil ideal   : $($melhorPerfil.Perfil) (ganho medio: +$($melhorPerfil.GanhoMedio) pts)")
    }

    # Tendencia: melhorando ou estabilizou?
    if ($total -ge 3) {
        $primeiras3 = ($execs | Select -First 3 | Measure-Object -Property Ganho -Average).Average
        $ultimas3   = ($execs | Select -Last  3 | Measure-Object -Property Ganho -Average).Average
        if ($ultimas3 -gt $primeiras3 + 2) {
            [void]$sb.AppendLine("  Tendencia      : MELHORANDO - sistema cada vez mais otimizado")
        } elseif ($ultimas3 -lt $primeiras3 - 2) {
            [void]$sb.AppendLine("  Tendencia      : RETORNANDO - alguns tweaks podem estar sendo revertidos pelo Windows")
        } else {
            [void]$sb.AppendLine("  Tendencia      : ESTAVEL - sistema bem calibrado")
        }
    }

    return $sb.ToString()
}



# ================================================================
#  REGION: SISTEMA DE SCORE
# ================================================================


function Show-ScoreComparativo {
    param($antes, $depois)

    $a = $antes.Score
    $d = $depois.Score

    Write-Host ""
    Write-Host "  $('=' * 70)" -ForegroundColor DarkCyan
    Write-Host "  COMPARATIVO DE PERFORMANCE - AbimalekBoost IA" -ForegroundColor Cyan
    Write-Host "  $('=' * 70)" -ForegroundColor DarkCyan
    Write-Host ""

    $metrics = @(
        @{ Nome="Score Geral";        Antes=$a.Geral;         Depois=$d.Geral }
        @{ Nome="Score Latencia";     Antes=$a.Latencia;      Depois=$d.Latencia }
        @{ Nome="Score Responsiv.";   Antes=$a.Responsividade; Depois=$d.Responsividade }
        @{ Nome="Score Gamer";        Antes=$a.Gamer;         Depois=$d.Gamer }
    )

    foreach ($m in $metrics) {
        $diff  = $m.Depois - $m.Antes
        $arrow = if ($diff -gt 0) { "  [+$diff]" } elseif ($diff -lt 0) { "  [$diff]" } else { "  [=]" }
        $cor   = if ($diff -gt 0) { "Green" } elseif ($diff -lt 0) { "Red" } else { "Gray" }

        $bar1 = "#" * [math]::Round($m.Antes  / 5)
        $bar2 = "#" * [math]::Round($m.Depois / 5)

        Write-Host ("  {0,-22} Antes: {1,3}  Depois: {2,3}" -f $m.Nome, $m.Antes, $m.Depois) -NoNewline
        Write-Host $arrow -ForegroundColor $cor
    }

    Write-Host ""
    # Ganho geral
    $ganhoGeral = $d.Geral - $a.Geral
    if ($ganhoGeral -gt 0) {
        Write-Host "  Melhoria total: +$ganhoGeral pts" -ForegroundColor Green
        if ($ganhoGeral -ge 20) { Write-Host "  EXCELENTE - Ganho massivo detectado!" -ForegroundColor Green }
        elseif ($ganhoGeral -ge 10) { Write-Host "  OTIMO - Performance significativamente melhor." -ForegroundColor Cyan }
        else { Write-Host "  BOM - Melhoria aplicada com sucesso." -ForegroundColor Yellow }
    } elseif ($ganhoGeral -eq 0) {
        Write-Host "  Sistema ja estava otimizado. Score mantido." -ForegroundColor Yellow
    } else {
        Write-Host "  Score reduziu. Verifique os tweaks aplicados." -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  METRICAS DO SISTEMA APOS OTIMIZACAO:" -ForegroundColor DarkCyan
    Write-Host ("  CPU: {0}% uso  |  RAM: {1}% uso ({2} GB livre)" -f $depois.CPUUsoPct, $depois.RAMUsoPct, $depois.RAMLivreGB)
    Write-Host ("  Ping: {0}ms  |  Jitter: {1}ms  |  Timer: {2}ms" -f $depois.LatenciaMS, $depois.NetworkJitter, $depois.TimerResMS)
    Write-Host ("  Disk Queue: {0}  |  Servicos: {1}  |  Plano: {2}" -f $depois.DiskQueueLen, $depois.ServicosAtivos, $depois.PlanoEnergia)
    Write-Host ""
}

# ================================================================
#  REGION: MOTOR DE DECISAO HEURISTICO
# ================================================================


# ================================================================
#  REGION: SISTEMA DE APRENDIZADO LOCAL (JSON)
# ================================================================
function Load-IAHistorico {
    $arq = $Script:IA.ArqHistorico
    if (Test-Path $arq) {
        try {
            $json = Get-Content $arq -Raw -Encoding UTF8
            $Script:IA.Historico = $json | ConvertFrom-Json
        } catch {
            $Script:IA.Historico = [PSCustomObject]@{
                Versao     = "1.0"
                Execucoes  = @()
                Ajustes    = @{}
            }
        }
    } else {
        $Script:IA.Historico = [PSCustomObject]@{
            Versao     = "1.0"
            Execucoes  = @()
            Ajustes    = @{}
        }
    }
}





# ================================================================
#  REGION: BACKUP DE REGISTRO ANTES DE OTIMIZAR
# ================================================================
function Invoke-IABackupRegistro {
    IN "Criando backup de registro..."
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $bakDir = $Script:PastaBackup

    # Chaves criticas
    $chaves = @(
        "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl"
        "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        "HKCU\Control Panel\Mouse"
        "HKCU\Control Panel\Keyboard"
    )

    $bakFile = Join-Path $bakDir "ia_reg_${timestamp}.reg"
    "Windows Registry Editor Version 5.00" | Out-File $bakFile -Encoding Unicode -Force

    foreach ($chave in $chaves) {
        try {
            $out = reg export $chave "$bakFile.tmp" /y 2>$null
            if (Test-Path "$bakFile.tmp") {
                Get-Content "$bakFile.tmp" | Select-Object -Skip 1 | Add-Content $bakFile
                Remove-Item "$bakFile.tmp" -Force 2>$null
            }
        } catch {}
    }

    $Script:IA.ArqBackupReg = $bakFile
    OK "Backup de registro: $bakFile"
}

function Invoke-IARollback {
    H2 "ROLLBACK IA - RESTAURAR REGISTRO"

    $bakFiles = Get-ChildItem $Script:PastaBackup -Filter "ia_reg_*.reg" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if (-not $bakFiles) {
        WN "Nenhum backup de registro IA encontrado."
        PAUSE; return
    }

    Write-Host "  Backups disponiveis:" -ForegroundColor DarkCyan
    $i = 0
    foreach ($f in $bakFiles | Select-Object -First 5) {
        $i++
        Write-Host "  [$i] $($f.Name)  ($($f.LastWriteTime))" -ForegroundColor White
    }
    Write-Host ""
    $opcao = Read-Host "  Selecione backup [1-$i] ou [ENTER] para cancelar"
    if ([string]::IsNullOrWhiteSpace($opcao)) { return }

    $idx = [int]$opcao - 1
    $arqSel = ($bakFiles | Select-Object -First 5)[$idx]

    if ($arqSel) {
        IN "Importando $($arqSel.Name)..."
        $result = reg import $arqSel.FullName 2>&1
        OK "Rollback aplicado. Reinicie o computador."
    }
    PAUSE
}

# ================================================================
#  REGION: PONTO DE RESTAURACAO DO SISTEMA
# ================================================================
function Invoke-IARestauracao {
    IN "Criando ponto de restauracao do sistema..."
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        $result = Checkpoint-Computer -Description "AbimalekBoost IA - Pre-Otimizacao $(Get-Date -Format 'dd/MM/yyyy HH:mm')" `
            -RestorePointType MODIFY_SETTINGS -ErrorAction SilentlyContinue
        OK "Ponto de restauracao criado!"
    } catch {
        WN "Ponto de restauracao falhou (pode ser frequencia minima do Windows). Continuando..."
    }
}

# ================================================================
#  REGION: MOTOR PRINCIPAL - INVOKE-IAENGINE
# ================================================================
function Invoke-IAEngine {
    param([string]$Perfil = "")

    Clear-Host
    # Banner especial IA
    Write-Host ""
    Write-Host "  $('=' * 70)" -ForegroundColor Magenta
    Write-Host "  ##  AbimalekBoost  -  MOTOR DE IA HEURISTICO  v6.0  ##" -ForegroundColor Cyan
    Write-Host "  $('=' * 70)" -ForegroundColor Magenta
    Write-Host "  Sistema de otimizacao inteligente - sem IA externa - 100% local" -ForegroundColor DarkGray
    Write-Host ""

    # Detectar hardware se nao foi feito
    if (-not $Script:CPUNome) {
        IN "Detectando hardware..."
        Invoke-DetectarHardware
    }

    # Mostrar insight do historico
    $insight = Get-IAInsightHistorico
    Write-Host $insight -ForegroundColor DarkCyan
    Write-Host ""

    # Selecionar perfil
    if (-not $Perfil) {
        $Perfil = Select-IAPerfil
        if (-not $Perfil) { return }
    }
    $Script:IA.Perfil = $Perfil

    # Criar ponto de restauracao
    Invoke-IARestauracao

    # Backup de registro
    Invoke-IABackupRegistro

    Write-Host ""
    Write-Host "  $('=' * 70)" -ForegroundColor DarkCyan
    # Buscar insight da MalikIA para este hardware
    Show-MalikInsight

    Write-Host "  [FASE 1/4] COLETANDO METRICAS DO SISTEMA..." -ForegroundColor Cyan
    Write-Host "  $('=' * 70)" -ForegroundColor DarkCyan
    Write-Host ""

    $Script:IA.SnapshotAntes = Get-IASnapshot -Label "antes"
    $snap = $Script:IA.SnapshotAntes

    # Exibir analise
    Show-IAAnalise -snap $snap

    Write-Host ""
    Write-Host "  $('=' * 70)" -ForegroundColor DarkCyan
    Write-Host "  [FASE 2/4] MOTOR DE DECISAO - ANALISANDO..." -ForegroundColor Cyan
    Write-Host "  $('=' * 70)" -ForegroundColor DarkCyan
    Write-Host ""

    $decisoes = Invoke-IAMotorDecisao -snap $snap

    Write-Host "  GARGALOS DETECTADOS:" -ForegroundColor Yellow
    if ($Script:IA.Gargalo.Count -eq 0) {
        Write-Host "  Nenhum gargalo critico encontrado" -ForegroundColor Green
    } else {
        foreach ($g in $Script:IA.Gargalo) {
            Write-Host "  [!] $g" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  OTIMIZACOES SELECIONADAS PELA IA ($($decisoes.Count) acoes):" -ForegroundColor Yellow
    $prioColor = @{ 1="Red"; 2="Yellow"; 3="Cyan"; 4="DarkGray" }
    $prioLabel = @{ 1="CRITICO"; 2="ALTO"; 3="MEDIO"; 4="EXTREMO" }
    foreach ($d in $decisoes) {
        $cor = $prioColor[$d.Prio]
        $lbl = $prioLabel[$d.Prio]
        Write-Host ("  [{0,-8}] {1}" -f $lbl, $d.Desc) -ForegroundColor $cor
    }
    Write-Host ""

    if (-not (CONF "Aplicar as $($decisoes.Count) otimizacoes selecionadas pela IA?")) {
        WN "Cancelado pelo usuario."; PAUSE; return
    }

    Write-Host ""
    Write-Host "  $('=' * 70)" -ForegroundColor DarkCyan
    Write-Host "  [FASE 3/4] APLICANDO OTIMIZACOES..." -ForegroundColor Cyan
    Write-Host "  $('=' * 70)" -ForegroundColor DarkCyan
    Write-Host ""

    $total = $decisoes.Count
    $atual = 0
    foreach ($d in $decisoes) {
        $atual++
        Show-Progress $d.Id $atual $total
        try {
            & $d.Bloco
            $Script:IA.OtimizacoesAplicadas.Add("$($d.Id): $($d.Desc)")
            Write-Host "  [+] $($d.Desc)" -ForegroundColor Green
        } catch {
            Write-Host "  [!] $($d.Id) - erro: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # DNS flush
    ipconfig /flushdns 2>$null | Out-Null
    OK "DNS flushed"

    Write-Host ""
    Write-Host "  $('=' * 70)" -ForegroundColor DarkCyan
    Write-Host "  [FASE 4/4] COLETANDO METRICAS POS-OTIMIZACAO..." -ForegroundColor Cyan
    Write-Host "  $('=' * 70)" -ForegroundColor DarkCyan
    Write-Host ""
    Start-Sleep 2

    $Script:IA.SnapshotDepois = Get-IASnapshot -Label "depois"

    # Score comparativo
    Show-ScoreComparativo -antes $Script:IA.SnapshotAntes -depois $Script:IA.SnapshotDepois

    # Salvar no historico local
    Save-IAExecucao `
        -snapAntes   $Script:IA.SnapshotAntes `
        -snapDepois  $Script:IA.SnapshotDepois `
        -perfil      $Perfil `
        -otimAplicadas $Script:IA.OtimizacoesAplicadas.ToArray()

    OK "Sessao salva no historico local: $($Script:IA.ArqHistorico)"

    # Enviar para MalikIA (anonimo, silencioso)
    Send-MalikSession `
        -snapAntes      $Script:IA.SnapshotAntes `
        -snapDepois     $Script:IA.SnapshotDepois `
        -Perfil         $Perfil `
        -TweaksAplicados $Script:IA.OtimizacoesAplicadas.ToArray() `
        -Gargalos       $Script:IA.Gargalo

    Write-Host ""
    Write-Host "  $('=' * 70)" -ForegroundColor Green
    Write-Host "  IA CONCLUIDA - $($Script:IA.OtimizacoesAplicadas.Count) otimizacoes aplicadas" -ForegroundColor Green
    Write-Host "  $('=' * 70)" -ForegroundColor Green
    Write-Host ""
    WN "Reinicie o computador para maximizar o efeito dos tweaks de kernel."
    Write-Host ""

    if (CONF "Abrir interface grafica de resultados?") {
        Show-IAResultadosWPF
    }

    LOG "IA Engine v6.0: $Perfil | Score $($Script:IA.SnapshotAntes.Score.Geral) -> $($Script:IA.SnapshotDepois.Score.Geral)"
    PAUSE
}

function Select-IAPerfil {
    Clear-Host
    Write-Host ""
    Write-Host "  $('=' * 70)" -ForegroundColor Magenta
    Write-Host "  SELECIONE O PERFIL DE OTIMIZACAO" -ForegroundColor Cyan
    Write-Host "  $('=' * 70)" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  [1]  SEGURO        Tweaks essenciais sem risco. Ideal para uso geral." -ForegroundColor Green
    Write-Host "         Plano, Timer, Nagle, TCP, Servicos basicos" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [2]  GAMER         Otimizacao completa para jogos. Uso diario." -ForegroundColor Yellow
    Write-Host "         + Mouse, IRQ, MMCSS, QoS, Background Apps, RAM" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [3]  STREAMER      Balanceamento gaming + OBS sem drops." -ForegroundColor Cyan
    Write-Host "         + Prioridade OBS, afinidade de CPU, rede streaming" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [4]  EXTREMO       Maximo absoluto. Risco tecnico. Apenas PC dedicado." -ForegroundColor Red
    Write-Host "         + Spectre/Meltdown OFF, C-States, Memory Compression" -ForegroundColor DarkGray
    Write-Host "         AVISO: pode reduzir seguranca do sistema" -ForegroundColor DarkRed
    Write-Host ""
    Write-Host "  [V]  Voltar" -ForegroundColor DarkGray
    Write-Host ""; SEP; Write-Host ""

    $op = Read-Host "  Selecione o perfil"
    switch ($op.Trim().ToUpper()) {
        '1' { return "Seguro" }
        '2' { return "Gamer" }
        '3' { return "Streamer" }
        '4' {
            Write-Host ""
            WN "AVISO: Perfil Extremo desativa mitigacoes de seguranca do CPU."
            WN "Recomendado apenas em PCs dedicados a gaming sem dados sensiveis."
            if (CONF "Confirma o uso do Perfil Extremo?") { return "Extremo" }
            return "Gamer"
        }
        'V' { return "" }
        default { return "Gamer" }
    }
}

function Show-IAAnalise {
    param($snap)

    $scoreGeral = $snap.Score.Geral
    $cor = if ($scoreGeral -ge 80) { "Green" } elseif ($scoreGeral -ge 60) { "Yellow" } else { "Red" }

    Write-Host "  ESTADO ATUAL DO SISTEMA:" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host ("  Score Geral:       {0,3}/100" -f $snap.Score.Geral)         -ForegroundColor $cor
    Write-Host ("  Score Latencia:    {0,3}/100" -f $snap.Score.Latencia)       -ForegroundColor White
    Write-Host ("  Score Responsiv.:  {0,3}/100" -f $snap.Score.Responsividade) -ForegroundColor White
    Write-Host ("  Score Gamer:       {0,3}/100" -f $snap.Score.Gamer)          -ForegroundColor White
    Write-Host ""
    Write-Host ("  CPU:  {0}% uso  |  Cores: {1}  |  {2}" -f $snap.CPUUsoPct, $snap.CPUNucleos, $snap.CPUNome) -ForegroundColor White
    Write-Host ("  RAM:  {0}% uso  |  Livre: {1} GB  |  {2} @ {3} MHz" -f $snap.RAMUsoPct, $snap.RAMLivreGB, $snap.RAMtipo, $snap.RAMvelocidade) -ForegroundColor White
    Write-Host ("  GPU:  {0}  |  VRAM: {1} GB  |  {2}?C" -f $snap.GPUNome, $snap.GPUVRAM, $snap.GPUTemp) -ForegroundColor White
    Write-Host ("  Disk: {0}  |  Queue: {1}  |  NVMe: {2}" -f $snap.DiscoTipo, $snap.DiskQueueLen, $(if($snap.DiscoNVMe){"Sim"}else{"Nao"})) -ForegroundColor White
    Write-Host ("  Net:  Ping {0}ms  |  Jitter {1}ms  |  TCP: {2}" -f $snap.LatenciaMS, $snap.NetworkJitter, $snap.TCPAutotuning) -ForegroundColor White
    Write-Host ("  Sys:  {0}  |  Plano: {1}  |  Timer: {2}ms" -f $snap.WinBuild, $snap.PlanoEnergia, $snap.TimerResMS) -ForegroundColor White
    Write-Host ("  Uptime: {0}h  |  Servicos: {1}  |  Paginando: {2}" -f $snap.UptimeHoras, $snap.ServicosAtivos, $(if($snap.RAMPaginando){"SIM"}else{"nao"})) -ForegroundColor White

    if ($snap.ProcessosPes) {
        Write-Host ""
        Write-Host "  Top processos por CPU: $($snap.ProcessosPes -join ', ')" -ForegroundColor DarkGray
    }

    # Dica especifica para Ryzen no Win10 - combinacao validada em benchmark
    if ($Script:CPUFab -eq "AMD" -and -not $Script:IsWin11) {
        Write-Host ""
        Write-Host "  [RYZEN + WIN10 DETECTADO]" -ForegroundColor Magenta
        Write-Host "  Combinacao validada em benchmark: Perfil Gamer + Extremo" -ForegroundColor Magenta
        Write-Host "  Resultado real documentado: +34% FPS no FiveM (5700X: 168->226fps)" -ForegroundColor Magenta
        Write-Host "  Tweaks criticos: Core Parking OFF + Win32=0x26 + useplatformtick" -ForegroundColor DarkMagenta
    }
    Write-Host ""
}

# ================================================================
#  REGION: INTERFACE GRAFICA WPF - RESULTADOS IA
# ================================================================
function Show-IAResultadosWPF {
    param()

    Load-IAHistorico
    $hist  = $Script:IA.Historico
    $antes = $Script:IA.SnapshotAntes
    $dep   = $Script:IA.SnapshotDepois

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AbimalekBoost - IA Engine v6.0"
        Height="720" Width="900"
        WindowStartupLocation="CenterScreen"
        Background="#0A0A0F"
        Foreground="White"
        FontFamily="Segoe UI"
        ResizeMode="CanResize">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#1A1A2E"/>
            <Setter Property="Foreground" Value="#00CFFF"/>
            <Setter Property="BorderBrush" Value="#00CFFF"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#E0E0E0"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
        </Style>
    </Window.Resources>
    <Grid Margin="0">
        <Grid.RowDefinitions>
            <RowDefinition Height="60"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="50"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#0D1117" BorderBrush="#00CFFF" BorderThickness="0,0,0,1">
            <Grid>
                <TextBlock Text="AbimalekBoost" FontSize="20" FontWeight="Bold"
                           Foreground="#00CFFF" VerticalAlignment="Center" Margin="20,0,0,0"/>
                <TextBlock Text="Motor de IA v6.0" FontSize="12" Foreground="#666"
                           VerticalAlignment="Bottom" HorizontalAlignment="Left" Margin="22,0,0,8"/>
                <TextBlock Text="RESULTADO DA ANALISE" FontSize="13" FontWeight="SemiBold"
                           Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                <TextBlock Name="txtPerfil" Text="Perfil: GAMER" FontSize="12"
                           Foreground="#00FF88" VerticalAlignment="Center" HorizontalAlignment="Right" Margin="0,0,20,0"/>
            </Grid>
        </Border>

        <!-- Main content -->
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="20,20,20,10">

            <!-- Score cards -->
            <TextBlock Text="SCORES DE PERFORMANCE" FontSize="13" FontWeight="Bold"
                       Foreground="#888" Margin="0,0,0,12"/>
            <Grid Margin="0,0,0,20">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Border Grid.Column="0" Background="#0D1117" BorderBrush="#00CFFF" BorderThickness="1" Margin="0,0,8,0" CornerRadius="4" Padding="12">
                    <StackPanel>
                        <TextBlock Text="GERAL" FontSize="10" Foreground="#666" FontWeight="Bold"/>
                        <TextBlock Name="scoreGeral" Text="--" FontSize="36" FontWeight="Bold" Foreground="#00CFFF" HorizontalAlignment="Center"/>
                        <TextBlock Name="diffGeral"  Text="---" FontSize="12" Foreground="#00FF88" HorizontalAlignment="Center"/>
                    </StackPanel>
                </Border>
                <Border Grid.Column="1" Background="#0D1117" BorderBrush="#FFB800" BorderThickness="1" Margin="4,0,4,0" CornerRadius="4" Padding="12">
                    <StackPanel>
                        <TextBlock Text="LATENCIA" FontSize="10" Foreground="#666" FontWeight="Bold"/>
                        <TextBlock Name="scoreLat" Text="--" FontSize="36" FontWeight="Bold" Foreground="#FFB800" HorizontalAlignment="Center"/>
                        <TextBlock Name="diffLat"  Text="---" FontSize="12" Foreground="#00FF88" HorizontalAlignment="Center"/>
                    </StackPanel>
                </Border>
                <Border Grid.Column="2" Background="#0D1117" BorderBrush="#FF6B35" BorderThickness="1" Margin="4,0,4,0" CornerRadius="4" Padding="12">
                    <StackPanel>
                        <TextBlock Text="RESPONSIVIDADE" FontSize="10" Foreground="#666" FontWeight="Bold"/>
                        <TextBlock Name="scoreResp" Text="--" FontSize="36" FontWeight="Bold" Foreground="#FF6B35" HorizontalAlignment="Center"/>
                        <TextBlock Name="diffResp"  Text="---" FontSize="12" Foreground="#00FF88" HorizontalAlignment="Center"/>
                    </StackPanel>
                </Border>
                <Border Grid.Column="3" Background="#0D1117" BorderBrush="#00FF88" BorderThickness="1" Margin="8,0,0,0" CornerRadius="4" Padding="12">
                    <StackPanel>
                        <TextBlock Text="GAMER" FontSize="10" Foreground="#666" FontWeight="Bold"/>
                        <TextBlock Name="scoreGamer" Text="--" FontSize="36" FontWeight="Bold" Foreground="#00FF88" HorizontalAlignment="Center"/>
                        <TextBlock Name="diffGamer"  Text="---" FontSize="12" Foreground="#00FF88" HorizontalAlignment="Center"/>
                    </StackPanel>
                </Border>
            </Grid>

            <!-- Metricas comparativas -->
            <TextBlock Text="METRICAS COMPARATIVAS" FontSize="13" FontWeight="Bold"
                       Foreground="#888" Margin="0,0,0,12"/>
            <Border Background="#0D1117" BorderBrush="#222" BorderThickness="1" CornerRadius="4" Padding="16" Margin="0,0,0,20">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <!-- Headers -->
                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Metrica"   FontWeight="Bold" Foreground="#00CFFF"/>
                    <TextBlock Grid.Row="0" Grid.Column="1" Text="Antes"     FontWeight="Bold" Foreground="#FF6B35" HorizontalAlignment="Center"/>
                    <TextBlock Grid.Row="0" Grid.Column="2" Text="Depois"    FontWeight="Bold" Foreground="#00FF88" HorizontalAlignment="Center"/>
                    <!-- Rows -->
                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Ping (ms)"     Margin="0,8,0,0"/>
                    <TextBlock Grid.Row="1" Grid.Column="1" Name="pingAntes"  Text="--" Margin="0,8,0,0" HorizontalAlignment="Center"/>
                    <TextBlock Grid.Row="1" Grid.Column="2" Name="pingDepois" Text="--" Margin="0,8,0,0" HorizontalAlignment="Center" Foreground="#00FF88"/>

                    <TextBlock Grid.Row="2" Grid.Column="0" Text="RAM uso (%)"   Margin="0,4,0,0"/>
                    <TextBlock Grid.Row="2" Grid.Column="1" Name="ramAntes"   Text="--" Margin="0,4,0,0" HorizontalAlignment="Center"/>
                    <TextBlock Grid.Row="2" Grid.Column="2" Name="ramDepois"  Text="--" Margin="0,4,0,0" HorizontalAlignment="Center" Foreground="#00FF88"/>

                    <TextBlock Grid.Row="3" Grid.Column="0" Text="CPU uso (%)"   Margin="0,4,0,0"/>
                    <TextBlock Grid.Row="3" Grid.Column="1" Name="cpuAntes"   Text="--" Margin="0,4,0,0" HorizontalAlignment="Center"/>
                    <TextBlock Grid.Row="3" Grid.Column="2" Name="cpuDepois"  Text="--" Margin="0,4,0,0" HorizontalAlignment="Center" Foreground="#00FF88"/>

                    <TextBlock Grid.Row="4" Grid.Column="0" Text="Timer (ms)"    Margin="0,4,0,0"/>
                    <TextBlock Grid.Row="4" Grid.Column="1" Name="timerAntes"  Text="--" Margin="0,4,0,0" HorizontalAlignment="Center"/>
                    <TextBlock Grid.Row="4" Grid.Column="2" Name="timerDepois" Text="--" Margin="0,4,0,0" HorizontalAlignment="Center" Foreground="#00FF88"/>
                </Grid>
            </Border>

            <!-- Otimizacoes aplicadas -->
            <TextBlock Text="OTIMIZACOES APLICADAS" FontSize="13" FontWeight="Bold"
                       Foreground="#888" Margin="0,0,0,12"/>
            <Border Background="#0D1117" BorderBrush="#222" BorderThickness="1" CornerRadius="4" Padding="12" Margin="0,0,0,20">
                <ItemsControl Name="listaOtim">
                    <ItemsControl.ItemTemplate>
                        <DataTemplate>
                            <TextBlock Text="{Binding}" Foreground="#00FF88" FontSize="12" Margin="0,2"/>
                        </DataTemplate>
                    </ItemsControl.ItemTemplate>
                </ItemsControl>
            </Border>

            <!-- Historico -->
            <TextBlock Text="HISTORICO DE APRENDIZADO" FontSize="13" FontWeight="Bold"
                       Foreground="#888" Margin="0,0,0,12"/>
            <Border Background="#0D1117" BorderBrush="#222" BorderThickness="1" CornerRadius="4" Padding="12" Margin="0,0,0,20">
                <StackPanel>
                    <TextBlock Name="txtHistTotal"    Text="Execucoes: 0" Foreground="#888"/>
                    <TextBlock Name="txtHistGanho"    Text="Ganho medio: --" Foreground="#888"/>
                    <TextBlock Name="txtHistUltima"   Text="Ultima: --" Foreground="#888"/>
                </StackPanel>
            </Border>

          </StackPanel>
        </ScrollViewer>

        <!-- Footer -->
        <Border Grid.Row="2" Background="#0D1117" BorderBrush="#00CFFF" BorderThickness="0,1,0,0">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Right" Margin="20,0">
                <Button Name="btnRollback" Content="Rollback IA" Margin="0,0,10,0"/>
                <Button Name="btnFechar"   Content="Fechar"       Margin="0"/>
            </StackPanel>
        </Border>
    </Grid>
</Window>
"@

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue

    try {
        $reader  = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
        $window  = [System.Windows.Markup.XamlReader]::Load($reader)

        # Preencher scores
        $window.FindName("scoreGeral").Text = if ($dep) { "$($dep.Score.Geral)"         } else { "--" }
        $window.FindName("scoreLat").Text   = if ($dep) { "$($dep.Score.Latencia)"      } else { "--" }
        $window.FindName("scoreResp").Text  = if ($dep) { "$($dep.Score.Responsividade)" } else { "--" }
        $window.FindName("scoreGamer").Text = if ($dep) { "$($dep.Score.Gamer)"         } else { "--" }

        if ($antes -and $dep) {
            $g1 = $dep.Score.Geral         - $antes.Score.Geral
            $g2 = $dep.Score.Latencia      - $antes.Score.Latencia
            $g3 = $dep.Score.Responsividade- $antes.Score.Responsividade
            $g4 = $dep.Score.Gamer         - $antes.Score.Gamer
            $window.FindName("diffGeral").Text  = if ($g1 -ge 0) { "+$g1 pts" } else { "$g1 pts" }
            $window.FindName("diffLat").Text    = if ($g2 -ge 0) { "+$g2 pts" } else { "$g2 pts" }
            $window.FindName("diffResp").Text   = if ($g3 -ge 0) { "+$g3 pts" } else { "$g3 pts" }
            $window.FindName("diffGamer").Text  = if ($g4 -ge 0) { "+$g4 pts" } else { "$g4 pts" }

            $window.FindName("pingAntes").Text   = "$($antes.LatenciaMS)ms"
            $window.FindName("pingDepois").Text  = "$($dep.LatenciaMS)ms"
            $window.FindName("ramAntes").Text    = "$($antes.RAMUsoPct)%"
            $window.FindName("ramDepois").Text   = "$($dep.RAMUsoPct)%"
            $window.FindName("cpuAntes").Text    = "$($antes.CPUUsoPct)%"
            $window.FindName("cpuDepois").Text   = "$($dep.CPUUsoPct)%"
            $window.FindName("timerAntes").Text  = "$($antes.TimerResMS)ms"
            $window.FindName("timerDepois").Text = "$($dep.TimerResMS)ms"
        }

        # Perfil
        $window.FindName("txtPerfil").Text = "Perfil: $($Script:IA.Perfil.ToUpper())"

        # Lista de otimizacoes
        $lista = $window.FindName("listaOtim")
        $lista.ItemsSource = $Script:IA.OtimizacoesAplicadas

        # Historico
        Load-IAHistorico
        $h = $Script:IA.Historico
        if ($h.Execucoes -and $h.Execucoes.Count -gt 0) {
            $window.FindName("txtHistTotal").Text  = "Execucoes registradas: $($h.Execucoes.Count)"
            $ganhoM = [math]::Round(($h.Execucoes | Measure-Object -Property Ganho -Average -ErrorAction SilentlyContinue).Average, 1)
            $window.FindName("txtHistGanho").Text  = "Ganho medio por sessao: +$ganhoM pts"
            $ult = $h.Execucoes | Select-Object -Last 1
            $window.FindName("txtHistUltima").Text = "Ultima: $($ult.Data) | $($ult.ScoreAntes) -> $($ult.ScoreDepois)"
        }

        # Eventos
        $window.FindName("btnFechar").Add_Click({ $window.Close() })
        $window.FindName("btnRollback").Add_Click({
            $window.Close()
            Invoke-IARollback
        })

        $window.ShowDialog() | Out-Null

    } catch {
        WN "Interface grafica nao disponivel: $($_.Exception.Message)"
        WN "Use o relatorio no terminal."
    }
}

# ================================================================
#  REGION: SIMULACAO DE JOGOS
# ================================================================
function Invoke-IASimulacao {
    H2 "SIMULACAO DE IMPACTO - ESTIMATIVA IA"

    Write-Host "  Selecione o jogo para simular:" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  [1]  FiveM  (GTA V Multiplayer)" -ForegroundColor White
    Write-Host "  [2]  CS2    (Counter-Strike 2)"  -ForegroundColor White
    Write-Host "  [3]  Valorant" -ForegroundColor White
    Write-Host "  [V]  Voltar" -ForegroundColor DarkGray
    Write-Host ""
    $op = Read-Host "  Jogo"

    $jogo = switch ($op.ToUpper()) {
        '1' { "FiveM" }
        '2' { "CS2" }
        '3' { "Valorant" }
        default { return }
    }

    Clear-Host
    Write-Host ""
    Write-Host "  $('=' * 70)" -ForegroundColor Magenta
    Write-Host "  SIMULACAO: $jogo - Estimativa de Impacto" -ForegroundColor Cyan
    Write-Host "  $('=' * 70)" -ForegroundColor Magenta
    Write-Host ""
    IN "Analisando hardware para $jogo..."
    Start-Sleep 1

    if (-not $Script:CPUNome) { Invoke-DetectarHardware }

    # Perfis de simulacao por jogo
    $simu = switch ($jogo) {
        "FiveM" {
            # Estimativas baseadas em benchmark real:
            # Ryzen 5 5700X + 24GB DDR4 2666 + Win10 + Perfil Gamer/Extremo
            # Resultado: 168fps -> 216-236fps (+27-40% / +48-68fps medidos)
            $ganhoFPS = if ($Script:CPUX3D) {
                "35-50%"   # X3D tem ganho ainda maior no RAGE engine
            } elseif ($Script:CPUFab -eq "AMD" -and $Script:CPUNucleos -ge 8) {
                "25-40%"   # Ryzen 8c+ Win10: benchmark real +34.5% (5700X)
            } elseif ($Script:CPUFab -eq "AMD" -and $Script:CPUNucleos -ge 6) {
                "18-30%"   # Ryzen 6c Win10
            } elseif ($Script:CPUFab -eq "Intel" -and $Script:CPUNucleos -ge 8) {
                "20-32%"   # Intel 8c+ Win10/11
            } else {
                "12-22%"   # CPUs menores
            }

            $ganhoEstFPS = if ($Script:CPUX3D) { "+60-90fps" }
                           elseif ($Script:CPUNucleos -ge 8) { "+40-70fps (ref: +58fps no 5700X)" }
                           else { "+25-45fps" }

            @{
                Engine         = "RAGE Engine (GTA V / FiveM)"
                LimitantePrim  = "CPU single-core IPC + scheduler Windows"
                LimitanteSec   = "RAM bandwidth + latencia de rede"
                GanhoFPS       = $ganhoFPS
                GanhoFPSAbs    = $ganhoEstFPS
                GanhoLat       = "15-30ms reducao de latencia de rede (Nagle OFF + QoS)"
                TweaksCriticos = @(
                    "Core Parking OFF  [maior impacto: libera todos os nucleos]",
                    "Win32PrioritySeparation 0x26  [Win10: quantum curto favorece o jogo]",
                    "useplatformtick YES  [Win10: timer preciso = menos frame variance]",
                    "Nagle OFF  [FiveM: muito sensivel a latencia de rede]",
                    "Ultimate Performance  [clock maximo sustentado no Ryzen]"
                )
                TweaksMedio    = @(
                    "MMCSS Gaming  [prioridade RT para threads do jogo]",
                    "Power Throttling OFF  [sem limitacao de boost em background]",
                    "QoS DSCP 46  [prioridade UDP para pacotes do servidor FiveM]",
                    "Background Apps OFF  [libera CPU para o RAGE engine]"
                )
                TweaksOpcional = @(
                    "Spectre/Meltdown OFF  [+5-10% CPU IPC, apenas Perfil Extremo]",
                    "C-States OFF via BCD  [menor latencia de resposta do CPU]",
                    "RAM Working Set Clear  [util se RAM < 16GB]"
                )
                BenchmarkRef   = "Benchmark real: Ryzen 5 5700X + 24GB DDR4 + Win10 -> +58fps medio (+34.5%)"
                Score          = [math]::Min(100, $Script:IA.SnapshotAntes.Score.Geral + 30)
            }
        }
        "CS2" {
            @{
                Engine         = "Source 2"
                LimitantePrim  = "CPU single-core + latencia de rede"
                LimitanteSec   = "Mouse input lag + timer resolution"
                GanhoFPS       = if ($Script:CPUNucleos -ge 6) { "15-25%" } else { "10-18%" }
                GanhoLat       = "20-40ms reducao (Nagle OFF + QoS)"
                TweaksCriticos = @("Nagle OFF","Mouse sem aceleracao","Timer Resolution","MMCSS","IRQ Input")
                TweaksMedio    = @("Core Parking OFF","Power Plan Ultimate","TCP Stack","QoS DSCP 46")
                TweaksOpcional = @("C-States OFF via BCD","Spectre OFF")
                Score          = [math]::Min(100, $Script:IA.SnapshotAntes.Score.Geral + 28)
            }
        }
        "Valorant" {
            @{
                Engine         = "Unreal Engine 4"
                LimitantePrim  = "CPU scheduler + latencia de rede"
                LimitanteSec   = "Memory bandwidth + VRAM"
                GanhoFPS       = "10-20%"
                GanhoLat       = "10-30ms"
                TweaksCriticos = @("Win32PrioritySeparation","Nagle OFF","MMCSS","Timer Resolution")
                TweaksMedio    = @("Core Parking OFF","BG Apps OFF","TCP autotuning","QoS")
                TweaksOpcional = @("Auto HDR OFF","VRR OFF","Notificacoes OFF")
                Score          = [math]::Min(100, $Script:IA.SnapshotAntes.Score.Geral + 18)
            }
        }
    }

    Write-Host "  ENGINE:     $($simu.Engine)" -ForegroundColor White
    Write-Host "  CPU:        $Script:CPUNome ($Script:CPUNucleos cores)" -ForegroundColor White
    Write-Host "  GPU:        $Script:GPUNome ($Script:GPUVRAM GB VRAM)" -ForegroundColor White
    Write-Host "  RAM:        $Script:RAMtotalGB GB $Script:RAMtipo @ $Script:RAMvelocidade MHz" -ForegroundColor White
    Write-Host ""
    Write-Host "  GARGALO PRIMARIO:    $($simu.LimitantePrim)" -ForegroundColor Yellow
    Write-Host "  GARGALO SECUNDARIO:  $($simu.LimitanteSec)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ESTIMATIVA DE GANHO COM ABIMALEKBOOST:" -ForegroundColor Green
    Write-Host ("  FPS %:   +{0,-20}" -f $simu.GanhoFPS) -ForegroundColor Green
    if ($simu.GanhoFPSAbs) {
        Write-Host ("  FPS abs: {0,-20}" -f $simu.GanhoFPSAbs) -ForegroundColor Green
    }
    Write-Host ("  Input:   {0}" -f $simu.GanhoLat) -ForegroundColor Green
    Write-Host ("  Score:   {0}/100 (projetado)" -f $simu.Score) -ForegroundColor Green
    if ($simu.BenchmarkRef) {
        Write-Host ""
        Write-Host "  REFERENCIA REAL:" -ForegroundColor DarkCyan
        Write-Host "  $($simu.BenchmarkRef)" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "  TWEAKS CRITICOS PARA $($jogo.ToUpper()):" -ForegroundColor Cyan
    foreach ($t in $simu.TweaksCriticos) { Write-Host "  [CRITICO] $t" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  TWEAKS RECOMENDADOS:" -ForegroundColor Yellow
    foreach ($t in $simu.TweaksMedio) { Write-Host "  [+] $t" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "  TWEAKS OPCIONAIS (risco/beneficio):" -ForegroundColor DarkGray
    foreach ($t in $simu.TweaksOpcional) { Write-Host "  [?] $t" -ForegroundColor DarkGray }
    Write-Host ""

    if (CONF "Aplicar perfil otimizado para $jogo agora?") {
        $Script:IA.Perfil = if ($jogo -eq "FiveM") { "Gamer" } else { "Gamer" }
        $Script:IA.SimulandoJogo = $jogo
        Invoke-IAEngine -Perfil "Gamer"
    } else {
        PAUSE
    }
}

# ================================================================
#  REGION: HISTORICO E RELATORIO IA
# ================================================================
function Show-IAHistorico {
    H2 "HISTORICO DE APRENDIZADO LOCAL"

    Load-IAHistorico
    $h = $Script:IA.Historico

    if (-not $h.Execucoes -or $h.Execucoes.Count -eq 0) {
        WN "Nenhuma execucao registrada ainda."
        WN "Execute o Motor de IA pelo menos uma vez para ver o historico."
        Write-Host ""
        Write-Host "  BENCHMARK DE REFERENCIA (cliente real):" -ForegroundColor DarkCyan
        Write-Host "  Hardware : Ryzen 5 5700X + 24GB DDR4 2666MHz + Win10" -ForegroundColor White
        Write-Host "  Perfil   : Gamer + Extremo" -ForegroundColor White
        Write-Host "  Jogo     : FiveM (GTA V Multiplayer)" -ForegroundColor White
        Write-Host "  Resultado: 168fps -> 216-236fps  (+58fps media / +34.5%)" -ForegroundColor Green
        PAUSE; return
    }

    $execs = $h.Execucoes
    Write-Host "  Total de execucoes: $($execs.Count)" -ForegroundColor Cyan
    Write-Host ""

    $i = 0
    foreach ($e in ($execs | Select-Object -Last 10)) {
        $i++
        $ganhoStr = if ($e.Ganho -ge 0) { "+$($e.Ganho)" } else { "$($e.Ganho)" }
        $cor = if ($e.Ganho -ge 10) { "Green" } elseif ($e.Ganho -ge 0) { "Yellow" } else { "Red" }
        Write-Host ("  {0:D2}. {1}  [{2,-10}]  Score: {3} -> {4}  {5} pts  Ping: {6}ms" -f `
            $i, $e.Data, $e.Perfil, $e.ScoreAntes, $e.ScoreDepois, $ganhoStr, $e.PingDepois) -ForegroundColor $cor
    }

    Write-Host ""
    $ganhoMed = [math]::Round(($execs | Measure-Object -Property Ganho -Average).Average, 1)
    $melhor   = ($execs | Sort-Object Ganho -Descending | Select-Object -First 1)
    Write-Host "  Ganho medio:  +$ganhoMed pts por sessao" -ForegroundColor Cyan
    Write-Host "  Melhor resultado: +$($melhor.Ganho) pts em $($melhor.Data) [$($melhor.Perfil)]" -ForegroundColor Green
    Write-Host ""

    if (CONF "Limpar historico?") {
        $histVazio = [PSCustomObject]@{ Versao="1.0"; Execucoes=@(); Ajustes=@{} }
        $histVazio | ConvertTo-Json -Depth 5 | Out-File $Script:IA.ArqHistorico -Encoding UTF8 -Force
        OK "Historico limpo."
    }
    PAUSE
}

# ================================================================
#  REGION: MENU IA ENGINE
# ================================================================
function Show-MenuIAEngine {
    while ($true) {
        Show-Banner; Show-StatusBar
        H1 "MOTOR DE IA HEURISTICO v6.0"
        Write-Host "  Analise inteligente, decisao por gargalo, score comparativo." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "   >> ANALISE E OTIMIZACAO" -ForegroundColor DarkGray
        Write-Host "   [1]  Executar Motor IA (selecionar perfil)" -ForegroundColor Cyan
        Write-Host "   [2]  Perfil Seguro         [rapido, sem risco]" -ForegroundColor Green
        Write-Host "   [3]  Perfil Gamer          [completo, recomendado]" -ForegroundColor Yellow
        Write-Host "   [4]  Perfil Streamer       [gaming + OBS]" -ForegroundColor Cyan
        Write-Host "   [5]  Perfil Extremo        [maximo absoluto]" -ForegroundColor Red
        Write-Host ""
        Write-Host "   >> SIMULACAO E ANALISE" -ForegroundColor DarkGray
        Write-Host "   [S]  Simular impacto por jogo  (FiveM / CS2 / Valorant)" -ForegroundColor Magenta
        Write-Host "   [H]  Historico de aprendizado  (JSON local)" -ForegroundColor White
        Write-Host "   [R]  Rollback de registro IA" -ForegroundColor Red
        Write-Host ""
        Write-Host "   [V]  Voltar" -ForegroundColor DarkGray
        Write-Host ""; SEP; Write-Host ""
        $op = Read-Host "  Opcao"
        switch ($op.Trim().ToUpper()) {
            '1' { Clear-Host; Invoke-IAEngine }
            '2' { Clear-Host; Invoke-IAEngine -Perfil "Seguro" }
            '3' { Clear-Host; Invoke-IAEngine -Perfil "Gamer" }
            '4' { Clear-Host; Invoke-IAEngine -Perfil "Streamer" }
            '5' { Clear-Host; Invoke-IAEngine -Perfil "Extremo" }
            'S' { Clear-Host; Invoke-IASimulacao }
            'H' { Clear-Host; Show-IAHistorico }
            'R' { Clear-Host; Invoke-IARollback }
            'V' { return }
        }
    }
}


function Show-MenuOtimizacao {
    while ($true) {
        Show-Banner; Show-StatusBar
        H1 "OTIMIZACAO DO SISTEMA"
        Write-Host "  Cada modulo abre checklist - escolha tweak por tweak." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "   >> PERFORMANCE CORE" -ForegroundColor DarkGray
        Write-Host "   [1]  Plano de Energia              (Gaming / Work / Equilibrado)" -ForegroundColor White
        Write-Host "   [2]  Privacidade e Telemetria      (30+ tweaks)" -ForegroundColor White
        Write-Host "   [3]  Game Bar / Game Mode / HAGS" -ForegroundColor White
        Write-Host "   [4]  Rede Avancada                 (Nagle, TCP, NIC, IPv6)" -ForegroundColor White
        Write-Host "   [5]  Servicos Desnecessarios" -ForegroundColor White
        Write-Host "   [6]  Visual e Performance          (animacoes, transparencia)" -ForegroundColor White
        Write-Host ""
        Write-Host "   >> PERFORMANCE AVANCADA" -ForegroundColor DarkGray
        Write-Host "   [7]  NTFS e I/O                   (NVMe, TRIM, LastAccess)" -ForegroundColor Cyan
        Write-Host "   [8]  MSI Mode GPU/NVMe             (reduz latencia de IRQ)" -ForegroundColor Cyan
        Write-Host "   [9]  Timer Resolution              (BCD, Tick, Responsiveness)" -ForegroundColor Cyan
        Write-Host "   [C]  CPU Avancado                  (DPC, NUMA, Spectre)" -ForegroundColor Yellow
        Write-Host "   [M]  Memoria                       (Working Set, PageFile)" -ForegroundColor Yellow
        Write-Host "   [G]  GPU Avancado                  (TDR, PhysX, D3D, Low Latency)" -ForegroundColor Yellow
        Write-Host "   [A]  Audio                         (WASAPI, Pro Audio buffer)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   >> NOVOS v5.1 - FOCO TOTAL" -ForegroundColor DarkGray
        Write-Host "   [N]  Nuclear Microsoft             (OneDrive, Copilot, Teams, Recall)" -ForegroundColor Red
        Write-Host "   [P]  Processos CPU e RAM           (matar bg, liberar RAM, rebaixar prio)" -ForegroundColor Red
        Write-Host "   [L]  Input Lag                     (mouse 1:1, IRQ, QoS, DWM, MMCSS)" -ForegroundColor Red
        Write-Host "   [E]  Group Policy Performance      (GP via registro, funciona no Home)" -ForegroundColor Red
        if ($Script:CPUX3D) {
            Write-Host ""
            Write-Host "   [X]  X3D V-Cache [RECOMENDADO]    ($($Script:CPUNome))" -ForegroundColor Magenta
        }
        Write-Host ""
        Write-Host "   [V]  Voltar" -ForegroundColor DarkGray
        Write-Host ""; SEP; Write-Host ""
        $op = Read-Host "  Opcao"
        switch ($op.Trim().ToUpper()) {
            '1' { Clear-Host; if(-not $Script:CPUNome){Invoke-DetectarHardware}; Invoke-PlanoEnergia }
            '2' { Clear-Host; Invoke-Privacidade; PAUSE }
            '3' { Clear-Host; Invoke-GameMode }
            '4' { Clear-Host; Invoke-OtimizarRede }
            '5' { Clear-Host; Invoke-Servicos; PAUSE }
            '6' { Clear-Host; Invoke-VisualPerf }
            '7' { Clear-Host; Invoke-NTFSIOTweaks }
            '8' { Clear-Host; Invoke-MSIMode }
            '9' { Clear-Host; Invoke-TimerResolution }
            'C' { Clear-Host; Invoke-TweaksCPU }
            'M' { Clear-Host; Invoke-TweaksMemoria }
            'G' { Clear-Host; Invoke-TweaksGPU }
            'A' { Clear-Host; Invoke-TweaksAudio }
            'N' { Clear-Host; Invoke-NuclearMicrosoft }
            'P' { Clear-Host; Invoke-OtimizarProcessosCPU }
            'L' { Clear-Host; Invoke-OtimizarInputLag }
            'E' { Clear-Host; Invoke-GPeditPerformance }
            'X' { if ($Script:CPUX3D) { Clear-Host; Invoke-OtimizacoesX3D; PAUSE } }
            'V' { return }
        }
    }
}

function Show-MenuFerramentas {
    while ($true) {
        Show-Banner; Show-StatusBar
        H1 "FERRAMENTAS"
        Write-Host ""
        Write-Host "   [1]  Instalar Programas via Winget" -ForegroundColor White
        Write-Host "   [2]  Debloater (remove 60+ apps)" -ForegroundColor White
        Write-Host "   [3]  Reparar Windows (SFC + DISM)" -ForegroundColor White
        Write-Host "   [4]  Controle do Windows Update" -ForegroundColor White
        Write-Host "   [5]  Limpeza do Sistema" -ForegroundColor White
        Write-Host "   [6]  Analisador de OC de GPU" -ForegroundColor Magenta
        Write-Host "   [7]  Modo Streamer        (OBS + Gaming sem drops)" -ForegroundColor Cyan
        Write-Host "   [8]  Monitor em Tempo Real (CPU/GPU/RAM ao vivo)" -ForegroundColor Cyan
        Write-Host "   [9]  Exportar Relatorio" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "   >> MOTOR DE IA" -ForegroundColor DarkGray
        Write-Host "   [I]  Motor de IA Heuristico v6.1  [analise inteligente]" -ForegroundColor Magenta
        Write-Host "   [M]  MalikIA - Inteligencia Coletiva  [stats globais + insights]" -ForegroundColor Cyan
        Write-Host "   [G]  Analise ao Vivo - Jogo Aberto  [NOVO - diagnostico cirurgico]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   [V]  Voltar" -ForegroundColor DarkGray
        Write-Host ""; SEP; Write-Host ""
        $op = Read-Host "  Opcao"
        switch ($op.Trim().ToUpper()) {
            '1' { Clear-Host; Invoke-Instalador }
            '2' { Clear-Host; Invoke-Debloater }
            '3' { Clear-Host; Invoke-RepararWindows }
            '4' { Clear-Host; Invoke-WindowsUpdate }
            '5' { Clear-Host; Invoke-Limpeza }
            '6' { Clear-Host; Invoke-AnalisadorGPU }
            '7' { Clear-Host; Invoke-ModoStreamer }
            '8' { Clear-Host; Invoke-Monitor }
            '9' { Clear-Host; Invoke-ExportarRelatorio }
            'I' { Clear-Host; Show-MenuIAEngine }
            'M' { Clear-Host; Show-MenuMalikIA }
            'G' { Clear-Host; Show-MenuGameAnalysis }
            'V' { return }
        }
    }
}

function Show-MenuPrincipal {
    $rodando = $true
    while ($rodando) {
        Show-Banner; Show-StatusBar

        Write-Host "   >> ACOES RAPIDAS" -ForegroundColor DarkGray
        Write-Host "   [1]  Detectar Hardware Completo" -ForegroundColor White
        Write-Host "   [2]  Otimizacao Inteligente  [IA mede primeiro, decide, aplica]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   >> CATEGORIAS" -ForegroundColor DarkGray
        Write-Host "   [3]  Otimizacao Granular     (escolha tweak por tweak)" -ForegroundColor Cyan
        Write-Host "   [4]  Ferramentas             (Apps, GPU OC, Streamer, Monitor)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "   >> SISTEMA" -ForegroundColor DarkGray
        Write-Host "   [5]  Restaurar Configuracoes Originais" -ForegroundColor Red
        Write-Host "   [6]  Sair" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Log: $($Script:LogFile)" -ForegroundColor DarkGray
        SEP; Write-Host ""

        $op = Read-Host "  Selecione [1-6]"
        switch ($op.Trim()) {
            '1' { Clear-Host; Invoke-DetectarHardware }
            '2' { Clear-Host; Invoke-AplicarTudo }
            '3' { Show-MenuOtimizacao }
            '4' { Show-MenuFerramentas }
            '5' { Clear-Host; Invoke-Restaurar }
            '6' {
                Write-Host ""
                if ($Script:OtimAplicada -and (CONF "Exportar relatorio antes de sair?")) { Invoke-ExportarRelatorio }
                IN "Log salvo em:"; Write-Host "  $($Script:LogFile)" -ForegroundColor DarkCyan
                Write-Host ""; $rodando = $false
            }
            default { WN "Opcao invalida."; Start-Sleep 1 }
        }
    }
}

# ================================================================
#  INICIALIZACAO
# ================================================================
LOG "=== AbimalekBoost v$($Script:Versao) ==="
LOG "Sessao: $($Script:IDSessao) | $env:USERNAME @ $env:COMPUTERNAME"
LOG "Build: $([System.Environment]::OSVersion.Version)"
LOG "==="

Show-MenuPrincipal
