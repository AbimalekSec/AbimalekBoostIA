"""
MalikIA — Analisador de Sessão de Jogo
Recebe métricas coletadas ao vivo, diagnostica gargalos,
retorna tweaks cirúrgicos ordenados por impacto real.
"""

import logging
import numpy as np
from typing import Dict, List, Any, Optional

log = logging.getLogger("MalikGame")

# ── Perfis de jogo — pesos de impacto por métrica ───────────────
GAME_PROFILES = {
    "FiveM": {
        "engine":        "RAGE Engine",
        "cpu_weight":    0.45,   # FiveM é muito CPU single-core
        "gpu_weight":    0.20,
        "ram_weight":    0.20,
        "net_weight":    0.15,
        "fps_alvo":      144,
        "bottleneck_threshold": {
            "cpu_game_p95": 75,
            "gpu_uso_p95":  95,
            "ram_p95":      80,
            "ping_p95":     60,
        },
        # Impacto estimado de cada tweak neste jogo (% ganho FPS esperado)
        "tweak_impact": {
            "CORE_PARKING_OFF":   {"fps_pct": 8,  "desc": "Core Parking OFF — Ryzen/Intel burst desbloqueado"},
            "WIN32_PRIORITY_SEP": {"fps_pct": 6,  "desc": "Scheduler OS — quantum curto favorece GTA engine"},
            "NAGLE_OFF":          {"fps_pct": 5,  "desc": "Nagle OFF — latência de rede FiveM reduzida"},
            "TIMER_RESOLUTION":   {"fps_pct": 4,  "desc": "Timer 0.5ms — frame pacing mais estável"},
            "MMCSS_GAMING":       {"fps_pct": 4,  "desc": "MMCSS — threads do jogo em prioridade RT"},
            "POWER_THROTTLE_OFF": {"fps_pct": 3,  "desc": "Power Throttling OFF — CPU sem limitação"},
            "QOS_GAMING":         {"fps_pct": 2,  "desc": "QoS UDP 46 — pacotes FiveM priorizados"},
            "BG_APPS_OFF":        {"fps_pct": 3,  "desc": "Background apps OFF — CPU livre para o jogo"},
            "SYSMAIN_OFF":        {"fps_pct": 2,  "desc": "SysMain OFF — prefetch desnecessário em SSD"},
            "SPECTRE_OFF":        {"fps_pct": 5,  "desc": "Spectre/Meltdown OFF — +5-8% IPC [risco alto]"},
        }
    },
    "CS2": {
        "engine":        "Source 2",
        "cpu_weight":    0.35,
        "gpu_weight":    0.25,
        "ram_weight":    0.15,
        "net_weight":    0.25,   # CS2: rede é crítica
        "fps_alvo":      300,
        "bottleneck_threshold": {
            "cpu_game_p95": 70,
            "gpu_uso_p95":  95,
            "ram_p95":      75,
            "ping_p95":     40,
        },
        "tweak_impact": {
            "NAGLE_OFF":          {"fps_pct": 8,  "desc": "Nagle OFF — hitreg e latência melhorados"},
            "TIMER_RESOLUTION":   {"fps_pct": 7,  "desc": "Timer 0.5ms — input lag reduzido"},
            "IRQ_INPUT_PRIORITY": {"fps_pct": 6,  "desc": "IRQ mouse/teclado — polling mais preciso"},
            "MOUSE_ACCEL_OFF":    {"fps_pct": 0,  "desc": "Mouse 1:1 — aim sem distorção [crucial]"},
            "MMCSS_GAMING":       {"fps_pct": 5,  "desc": "MMCSS — renderização Source 2 priorizada"},
            "CORE_PARKING_OFF":   {"fps_pct": 4,  "desc": "Core Parking OFF — sem stutter de CPU"},
            "WIN32_PRIORITY_SEP": {"fps_pct": 4,  "desc": "Scheduler — foreground maximizado"},
            "TCP_STACK":          {"fps_pct": 3,  "desc": "TCP tuning — conexão com servidores CS2"},
            "QOS_GAMING":         {"fps_pct": 3,  "desc": "QoS UDP — pacotes CS2 priorizados no roteador"},
            "POWER_THROTTLE_OFF": {"fps_pct": 3,  "desc": "Power Throttling OFF — CPU consistente"},
        }
    },
    "Valorant": {
        "engine":        "Unreal Engine 4",
        "cpu_weight":    0.35,
        "gpu_weight":    0.30,
        "ram_weight":    0.20,
        "net_weight":    0.15,
        "fps_alvo":      240,
        "bottleneck_threshold": {
            "cpu_game_p95": 72,
            "gpu_uso_p95":  95,
            "ram_p95":      78,
            "ping_p95":     50,
        },
        "tweak_impact": {
            "WIN32_PRIORITY_SEP": {"fps_pct": 7,  "desc": "Scheduler — UE4 render thread priorizado"},
            "MMCSS_GAMING":       {"fps_pct": 6,  "desc": "MMCSS — game thread em RT priority"},
            "NAGLE_OFF":          {"fps_pct": 5,  "desc": "Nagle OFF — hit registration melhorado"},
            "TIMER_RESOLUTION":   {"fps_pct": 5,  "desc": "Timer 0.5ms — frame time estável"},
            "CORE_PARKING_OFF":   {"fps_pct": 4,  "desc": "Core Parking OFF — todos núcleos disponíveis"},
            "POWER_THROTTLE_OFF": {"fps_pct": 4,  "desc": "Power Throttling OFF — CPU boost consistente"},
            "BG_APPS_OFF":        {"fps_pct": 3,  "desc": "Background apps OFF — VRAM e RAM liberadas"},
            "QOS_GAMING":         {"fps_pct": 2,  "desc": "QoS UDP — pacotes Valorant priorizados"},
            "TCP_STACK":          {"fps_pct": 2,  "desc": "TCP tuning — conexão Riot servers"},
            "RAM_WORKINGSET":     {"fps_pct": 3,  "desc": "RAM Working Set Clear — VRAM e RAM limpas"},
        }
    }
}


class GameSessionAnalyzer:
    def __init__(self, ml_engine=None):
        self.ml = ml_engine

    # ════════════════════════════════════════════════════════════
    #  ANALISAR SESSÃO — entrada principal
    # ════════════════════════════════════════════════════════════
    def analyze(self, session_data: Dict) -> Dict:
        jogo    = session_data.get("Jogo", "FiveM")
        profile = GAME_PROFILES.get(jogo, GAME_PROFILES["FiveM"])
        stats   = session_data  # vem do PowerShell já calculado

        # 1. Identificar gargalo dominante
        bottleneck = self._identify_bottleneck(stats, profile)

        # 2. Calcular ganho FPS previsto
        ganho_fps = self._estimate_fps_gain(stats, profile, bottleneck)

        # 3. Ranquear tweaks por impacto real (baseado no gargalo)
        tweaks = self._rank_tweaks(stats, profile, bottleneck)

        # 4. Diagnóstico textual
        diagnostico = self._generate_diagnosis(stats, profile, bottleneck)

        # 5. Comparar com casos similares (se ML disponível)
        similar_info = None
        if self.ml and self.ml.is_trained:
            hw = stats.get("Hardware", {})
            try:
                pred = self.ml.predict_fps_gain({
                    "cpu_vendor":  hw.get("CPU", "").split()[1] if " " in hw.get("CPU","") else "AMD",
                    "cpu_cores":   8,
                    "cpu_is_x3d":  False,
                    "ram_gb":      int(hw.get("RAM", "16GB").split("GB")[0]),
                    "gpu_vram":    8,
                    "disk_nvme":   True,
                    "is_win11":    hw.get("OS","") == "Win11",
                    "perfil":      "Gamer",
                    "game":        jogo,
                })
                similar_info = pred
            except Exception as e:
                log.warning(f"ML predict falhou: {e}")

        return {
            "jogo":              jogo,
            "engine":            profile["engine"],
            "amostras":          stats.get("Amostras", 0),
            "duracao_seg":       stats.get("DuracaoSeg", 0),

            # Métricas chave
            "cpu_media":         stats.get("CPU", {}).get("Media"),
            "cpu_p95":           stats.get("CPU", {}).get("P95"),
            "cpu_game_p95":      stats.get("CPUGame", {}).get("P95"),
            "gpu_media":         stats.get("GPU", {}).get("Media"),
            "gpu_temp_max":      stats.get("GPUTemp", {}).get("Max"),
            "ram_p95":           stats.get("RAM", {}).get("P95"),
            "ping_p95":          stats.get("Ping", {}).get("P95"),
            "fps_media":         stats.get("FPS", {}).get("Media") if stats.get("FPS") else None,
            "fps_1pct_lows":     stats.get("FPS", {}).get("P5")   if stats.get("FPS") else None,
            "gpu_throttle_pct":  stats.get("GPUThrottlePct", 0),

            # Diagnóstico
            "gargalo_principal": bottleneck["tipo"],
            "gargalo_desc":      bottleneck["desc"],
            "severidade":        bottleneck["severidade"],
            "diagnostico":       diagnostico,

            # Ganho previsto
            "ganho_fps_previsto": ganho_fps["total_pct"],
            "ganho_fps_detalhado": ganho_fps["por_tweak"],

            # Tweaks cirúrgicos ranqueados
            "tweaks_cirurgicos": tweaks,

            # Contexto ML
            "ml_similar":        similar_info,
            "ml_trained":        self.ml.is_trained if self.ml else False,
        }

    # ════════════════════════════════════════════════════════════
    #  IDENTIFICAR GARGALO DOMINANTE
    # ════════════════════════════════════════════════════════════
    def _identify_bottleneck(self, stats: Dict, profile: Dict) -> Dict:
        thresh = profile["bottleneck_threshold"]

        cpu_game_p95 = (stats.get("CPUGame") or {}).get("P95", 0) or 0
        gpu_p95      = (stats.get("GPU")     or {}).get("P95", 0) or 0
        ram_p95      = (stats.get("RAM")     or {}).get("P95", 0) or 0
        ping_p95     = (stats.get("Ping")    or {}).get("P95", 0) or 0
        gpu_throttle = stats.get("GPUThrottlePct", 0) or 0
        gpu_temp_max = (stats.get("GPUTemp") or {}).get("Max", 0) or 0

        # GPU 100% + CPU normal = GPU bound (aumentar resolução/qualidade não vai ajudar)
        if gpu_p95 >= 98 and cpu_game_p95 < thresh["cpu_game_p95"]:
            return {
                "tipo":      "GPU_BOUND",
                "severidade":"alta",
                "desc":      f"GPU a {gpu_p95:.0f}% (CPU jogo apenas {cpu_game_p95:.0f}%) — limite é a GPU, não CPU",
                "conselho":  "Reduzir qualidade gráfica ou resolução dá mais FPS do que qualquer tweak de SO"
            }

        # CPU jogo alto + GPU ociosa = CPU bound (tweaks de scheduler ajudam muito)
        if cpu_game_p95 > thresh["cpu_game_p95"] and gpu_p95 < 80:
            return {
                "tipo":      "CPU_BOUND",
                "severidade":"alta",
                "desc":      f"CPU jogo a {cpu_game_p95:.0f}% P95, GPU apenas {gpu_p95:.0f}% — gargalo é o processador",
                "conselho":  "Core parking OFF + scheduler + timer resolution têm maior impacto aqui"
            }

        # GPU throttle = thermal ou power limit
        if gpu_throttle > 30:
            return {
                "tipo":      "GPU_THROTTLE",
                "severidade":"alta",
                "desc":      f"GPU fazendo throttle em {gpu_throttle:.0f}% das amostras (temp máx: {gpu_temp_max:.0f}°C)",
                "conselho":  "Limpeza do cooler da GPU + reaplicação de pasta antes de qualquer tweak de SO"
            }

        # RAM quase cheia = stutters e load times altos
        if ram_p95 > thresh["ram_p95"]:
            return {
                "tipo":      "RAM_PRESSAO",
                "severidade":"alta",
                "desc":      f"RAM a {ram_p95:.0f}% P95 — sistema sob pressão de memória",
                "conselho":  "Background apps OFF + Working Set Clear liberam RAM para o jogo"
            }

        # Rede instável = hitreg ruim, stutters de sincronização
        if ping_p95 > thresh["ping_p95"]:
            return {
                "tipo":      "REDE",
                "severidade":"media",
                "desc":      f"Ping P95 {ping_p95:.0f}ms — conexão instável afeta hitreg e experiência",
                "conselho":  "Nagle OFF + QoS UDP + TCP stack tuning têm maior impacto aqui"
            }

        # GPU quente mas não throttlando ainda
        if gpu_temp_max > 83:
            return {
                "tipo":      "GPU_TEMP",
                "severidade":"media",
                "desc":      f"GPU a {gpu_temp_max:.0f}°C máx — próximo do limite, throttle iminente",
                "conselho":  "Limpeza preventiva do cooler recomendada"
            }

        # Balanceado — nenhum gargalo dominante
        return {
            "tipo":      "BALANCEADO",
            "severidade":"baixa",
            "desc":      f"CPU {cpu_game_p95:.0f}% / GPU {gpu_p95:.0f}% / RAM {ram_p95:.0f}% — sistema balanceado",
            "conselho":  "Tweaks de scheduler e timer têm maior impacto em sistemas já balanceados"
        }

    # ════════════════════════════════════════════════════════════
    #  ESTIMAR GANHO FPS
    # ════════════════════════════════════════════════════════════
    def _estimate_fps_gain(self, stats: Dict, profile: Dict, bottleneck: Dict) -> Dict:
        impacts = profile["tweak_impact"]
        por_tweak = []
        total = 0.0

        # Fator multiplicador baseado no gargalo
        mults = {
            "CPU_BOUND":   1.4,   # tweaks de CPU têm mais impacto
            "GPU_BOUND":   0.5,   # tweaks de SO ajudam menos quando GPU é o limite
            "GPU_THROTTLE":0.3,   # thermal — SO não resolve
            "RAM_PRESSAO": 1.1,
            "REDE":        1.2,   # tweaks de rede têm mais impacto
            "GPU_TEMP":    0.6,
            "BALANCEADO":  1.0,
        }
        mult = mults.get(bottleneck["tipo"], 1.0)

        for tweak_id, info in impacts.items():
            adjusted = round(info["fps_pct"] * mult, 1)
            if adjusted > 0:
                por_tweak.append({
                    "tweak":   tweak_id,
                    "fps_pct": adjusted,
                    "desc":    info["desc"]
                })
            total += adjusted

        # Cap realista
        total = min(total, 55.0)

        # Referência ao benchmark real se aplicável
        ref = None
        hw = stats.get("Hardware", {})
        if "5700X" in hw.get("CPU","") or (
            "AMD" in hw.get("CPU","") and "5700" in hw.get("CPU","")
        ):
            if stats.get("Jogo") == "FiveM":
                ref = {"hw": "Ryzen 5 5700X + Win10", "ganho_fps": 58, "ganho_pct": 34.5}

        return {
            "total_pct": round(total, 1),
            "por_tweak": sorted(por_tweak, key=lambda x: x["fps_pct"], reverse=True)[:6],
            "benchmark_ref": ref,
        }

    # ════════════════════════════════════════════════════════════
    #  RANQUEAR TWEAKS POR IMPACTO REAL
    # ════════════════════════════════════════════════════════════
    def _rank_tweaks(self, stats: Dict, profile: Dict, bottleneck: Dict) -> List[Dict]:
        impacts  = profile["tweak_impact"]
        bot_tipo = bottleneck["tipo"]

        # Ajuste de prioridade baseado no gargalo
        priority_boost = {
            "CPU_BOUND":   ["CORE_PARKING_OFF", "WIN32_PRIORITY_SEP", "MMCSS_GAMING",
                            "POWER_THROTTLE_OFF", "TIMER_RESOLUTION"],
            "GPU_BOUND":   ["BG_APPS_OFF", "MMCSS_GAMING", "RAM_WORKINGSET"],
            "GPU_THROTTLE":["BG_APPS_OFF"],
            "RAM_PRESSAO": ["BG_APPS_OFF", "RAM_WORKINGSET", "SYSMAIN_OFF"],
            "REDE":        ["NAGLE_OFF", "QOS_GAMING", "TCP_STACK", "TIMER_RESOLUTION"],
            "BALANCEADO":  [],
        }.get(bot_tipo, [])

        ranked = []
        for tweak_id, info in impacts.items():
            score = info["fps_pct"]
            if tweak_id in priority_boost:
                score *= 1.5   # boost no gargalo dominante

            # Risco
            risco = "alto" if tweak_id in ["SPECTRE_OFF", "CSTATES_OFF"] else "baixo"

            ranked.append({
                "id":     tweak_id,
                "desc":   info["desc"],
                "fps_pct": info["fps_pct"],
                "score":  score,
                "risco":  risco,
                "motivo": "gargalo dominante" if tweak_id in priority_boost else "impacto geral",
            })

        ranked.sort(key=lambda x: x["score"], reverse=True)

        # Adicionar ordem
        for i, t in enumerate(ranked):
            t["ordem"] = i + 1

        return ranked[:8]   # top 8

    # ════════════════════════════════════════════════════════════
    #  DIAGNÓSTICO TEXTUAL
    # ════════════════════════════════════════════════════════════
    def _generate_diagnosis(self, stats: Dict, profile: Dict, bottleneck: Dict) -> str:
        jogo     = stats.get("Jogo", "")
        cpu_p95  = (stats.get("CPUGame") or {}).get("P95", 0) or 0
        gpu_p95  = (stats.get("GPU")     or {}).get("P95", 0) or 0
        ram_p95  = (stats.get("RAM")     or {}).get("P95", 0) or 0
        ping_p95 = (stats.get("Ping")    or {}).get("P95", 0) or 0
        hw       = stats.get("Hardware", {})

        tipo = bottleneck["tipo"]

        if tipo == "CPU_BOUND":
            return (
                f"Seu {hw.get('CPU','CPU')} está sendo o gargalo no {jogo}. "
                f"O processo do jogo usa {cpu_p95:.0f}% do CPU (P95) enquanto a GPU fica em apenas {gpu_p95:.0f}%. "
                f"Core Parking OFF + Win32PrioritySeparation + MMCSS vão liberar os núcleos para o jogo "
                f"e reduzir a latência do scheduler — impacto direto em FPS e stutter."
            )
        elif tipo == "GPU_BOUND":
            return (
                f"A GPU está sendo o limite no {jogo} ({gpu_p95:.0f}% P95). "
                f"Tweaks de SO ajudam pouco quando a GPU está saturada. "
                f"O que vai realmente ajudar: reduzir qualidade gráfica (shadows, reflexos) ou resolução. "
                f"Mesmo assim, MMCSS e Background Apps OFF liberam VRAM e CPU para a GPU trabalhar melhor."
            )
        elif tipo == "GPU_THROTTLE":
            return (
                f"A GPU está sofrendo throttle térmico ou de power limit. "
                f"Isso faz a GPU reduzir clock automaticamente, causando quedas de FPS imprevisíveis. "
                f"Limpeza do cooler e reaplicação de pasta térmica resolvem isso — nenhum tweak de SO vai ajudar "
                f"enquanto o throttle estiver ativo."
            )
        elif tipo == "RAM_PRESSAO":
            return (
                f"Com {ram_p95:.0f}% de RAM usada durante o {jogo}, o sistema está sob pressão. "
                f"Stutters de carregamento e frame drops acontecem quando o Windows precisa paginar memória. "
                f"Background Apps OFF + Working Set Clear liberam RAM sem reiniciar."
            )
        elif tipo == "REDE":
            return (
                f"O ping de {ping_p95:.0f}ms P95 está afetando a experiência no {jogo}. "
                f"Nagle Algorithm OFF é o tweak mais impactante para latência de rede — "
                f"ele elimina o buffer de pacotes que o Windows usa por padrão. "
                f"QoS DSCP 46 prioriza os pacotes UDP do jogo no roteador."
            )
        else:
            return (
                f"Seu sistema está bem balanceado no {jogo} — CPU {cpu_p95:.0f}%, GPU {gpu_p95:.0f}%, RAM {ram_p95:.0f}%. "
                f"Não há um gargalo dominante. Tweaks de timer resolution e scheduler "
                f"vão reduzir frame time variance e melhorar consistência de FPS."
            )
