"""
MalikIA — Servidor Python
Flask + scikit-learn + Supabase

Endpoints:
  POST /session      — recebe dados de uma sessao, salva, treina modelo
  GET  /insight/<hw> — retorna recomendacao ML para um hardware
  GET  /predict      — prevê ganho de FPS para um hardware+perfil
  GET  /stats        — estatísticas globais
  GET  /similar/<hw> — casos similares no banco
  GET  /health       — status do servidor e modelo
  POST /game-session  — recebe sessão ao vivo com jogo aberto
"""

import os, json, hashlib, logging
from datetime import datetime
from pathlib import Path
from flask import Flask, request, jsonify

# ── Carregar .env automaticamente (se existir) ──────────────────
_env_file = Path(__file__).parent / ".env"
if _env_file.exists():
    for _line in _env_file.read_text().splitlines():
        _line = _line.strip()
        if _line and not _line.startswith("#") and "=" in _line:
            _k, _v = _line.split("=", 1)
            os.environ.setdefault(_k.strip(), _v.strip())
from malik_db    import MalikDB
from malik_ml    import MalikML
from game_analyzer import GameSessionAnalyzer

# ── Config ──────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("MalikIA")

app = Flask(__name__)
db  = MalikDB()
ml  = MalikML(db)
game_analyzer = GameSessionAnalyzer(ml_engine=ml)

# ── Middleware: CORS + logging ───────────────────────────────────
@app.after_request
def after_request(response):
    response.headers.update({
        "Access-Control-Allow-Origin":  "*",
        "Access-Control-Allow-Headers": "Content-Type, X-API-Key",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    })
    return response

@app.before_request
def log_request():
    log.info(f"{request.method} {request.path}")

# ── Autenticação simples por API key ────────────────────────────
API_KEY = os.getenv("MALIKIA_KEY", "malikia-dev-2025")

def check_auth():
    key = request.headers.get("X-API-Key", "")
    if key != API_KEY:
        return jsonify({"error": "unauthorized"}), 401
    return None

# ════════════════════════════════════════════════════════════════
#  POST /session — PowerShell envia dados após cada otimização
# ════════════════════════════════════════════════════════════════
@app.route("/session", methods=["POST", "OPTIONS"])
def post_session():
    if request.method == "OPTIONS":
        return jsonify({}), 200

    auth = check_auth()
    if auth: return auth

    try:
        data = request.get_json(force=True)
        if not data:
            return jsonify({"error": "body vazio"}), 400

        # Validar campos obrigatórios
        required = ["hardware_id", "cpu_model", "cpu_vendor", "cpu_cores",
                    "ram_gb", "perfil", "score_antes", "score_depois"]
        missing = [f for f in required if f not in data]
        if missing:
            return jsonify({"error": f"campos faltando: {missing}"}), 422

        # Salvar no banco
        session_id = db.save_session(data)

        # Retreinar modelo se tiver dados suficientes (async-like: só se vale a pena)
        total_sessions = db.count_sessions()
        if total_sessions >= 5 and total_sessions % 5 == 0:
            log.info(f"Retreinando modelo com {total_sessions} sessões...")
            ml.train()

        # Gerar insight imediato para retornar ao PowerShell
        insight = ml.get_insight(
            hardware_id  = data["hardware_id"],
            cpu_model    = data.get("cpu_model", ""),
            cpu_vendor   = data.get("cpu_vendor", ""),
            cpu_cores    = data.get("cpu_cores", 4),
            ram_gb       = data.get("ram_gb", 8),
            is_win11     = data.get("is_win11", False),
            disk_nvme    = data.get("disk_nvme", False),
            gpu_vram     = data.get("gpu_vram", 4),
        )

        return jsonify({
            "session_id":   session_id,
            "total_sessions": total_sessions + 1,
            "insight":      insight,
            "model_trained": ml.is_trained,
        }), 201

    except Exception as e:
        log.error(f"Erro em /session: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


# ════════════════════════════════════════════════════════════════
#  GET /insight/<hardware_id> — recomendação ML por hardware
# ════════════════════════════════════════════════════════════════
@app.route("/insight/<hardware_id>", methods=["GET"])
def get_insight(hardware_id):
    auth = check_auth()
    if auth: return auth

    try:
        cpu_model  = request.args.get("cpu_model",  "")
        cpu_vendor = request.args.get("cpu_vendor", "AMD")
        cpu_cores  = int(request.args.get("cpu_cores",  "4"))
        ram_gb     = int(request.args.get("ram_gb",     "8"))
        is_win11   = request.args.get("is_win11",  "false").lower() == "true"
        disk_nvme  = request.args.get("disk_nvme", "false").lower() == "true"
        gpu_vram   = int(request.args.get("gpu_vram",   "4"))

        insight = ml.get_insight(
            hardware_id=hardware_id,
            cpu_model=cpu_model,
            cpu_vendor=cpu_vendor,
            cpu_cores=cpu_cores,
            ram_gb=ram_gb,
            is_win11=is_win11,
            disk_nvme=disk_nvme,
            gpu_vram=gpu_vram,
        )
        return jsonify(insight)

    except Exception as e:
        log.error(f"Erro em /insight: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


# ════════════════════════════════════════════════════════════════
#  GET /predict — prevê ganho de FPS para hardware+jogo
# ════════════════════════════════════════════════════════════════
@app.route("/predict", methods=["GET"])
def predict_fps():
    auth = check_auth()
    if auth: return auth

    try:
        params = {
            "cpu_vendor": request.args.get("cpu_vendor", "AMD"),
            "cpu_cores":  int(request.args.get("cpu_cores", "4")),
            "cpu_is_x3d": request.args.get("cpu_is_x3d", "false").lower() == "true",
            "ram_gb":     int(request.args.get("ram_gb", "8")),
            "ram_mhz":    int(request.args.get("ram_mhz", "3200")),
            "gpu_vram":   int(request.args.get("gpu_vram", "4")),
            "disk_nvme":  request.args.get("disk_nvme", "false").lower() == "true",
            "is_win11":   request.args.get("is_win11", "false").lower() == "true",
            "perfil":     request.args.get("perfil", "Gamer"),
            "game":       request.args.get("game", "FiveM"),
        }
        prediction = ml.predict_fps_gain(params)
        return jsonify(prediction)

    except Exception as e:
        log.error(f"Erro em /predict: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


# ════════════════════════════════════════════════════════════════
#  GET /similar/<hardware_id> — casos similares no banco
# ════════════════════════════════════════════════════════════════
@app.route("/similar/<hardware_id>", methods=["GET"])
def get_similar(hardware_id):
    auth = check_auth()
    if auth: return auth

    try:
        limit  = int(request.args.get("limit", "5"))
        cpu_vendor = request.args.get("cpu_vendor", "")
        cpu_cores  = int(request.args.get("cpu_cores", "0"))
        ram_gb     = int(request.args.get("ram_gb", "0"))
        is_win11   = request.args.get("is_win11", "false").lower() == "true"

        similar = db.find_similar(
            hardware_id=hardware_id,
            cpu_vendor=cpu_vendor,
            cpu_cores=cpu_cores,
            ram_gb=ram_gb,
            is_win11=is_win11,
            limit=limit
        )
        return jsonify({"cases": similar, "total": len(similar)})

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ════════════════════════════════════════════════════════════════
#  GET /stats — estatísticas globais
# ════════════════════════════════════════════════════════════════
@app.route("/stats", methods=["GET"])
def get_stats():
    try:
        stats = db.get_global_stats()
        stats["model_trained"]  = ml.is_trained
        stats["model_accuracy"] = ml.last_accuracy
        stats["model_samples"]  = ml.last_n_samples
        return jsonify(stats)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ════════════════════════════════════════════════════════════════
#  GET /health
# ════════════════════════════════════════════════════════════════
@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status":        "ok",
        "version":       "7.0.0",
        "db_sessions":   db.count_sessions(),
        "model_trained": ml.is_trained,
        "timestamp":     datetime.now().isoformat(),
    })



# ════════════════════════════════════════════════════════════════
#  POST /game-session — sessão ao vivo com jogo aberto
#  Recebe stats calculados pelo PowerShell, retorna diagnóstico ML
# ════════════════════════════════════════════════════════════════
@app.route("/game-session", methods=["POST", "OPTIONS"])
def post_game_session():
    if request.method == "OPTIONS":
        return jsonify({}), 200

    auth = check_auth()
    if auth: return auth

    try:
        data = request.get_json(force=True)
        if not data:
            return jsonify({"error": "body vazio"}), 400

        jogo = data.get("Jogo", "Desconhecido")
        log.info(f"Game session recebida: {jogo} — {data.get('Amostras',0)} amostras")

        # Analisar com o GameSessionAnalyzer
        diagnostico = game_analyzer.analyze(data)

        # Salvar no banco como sessão com métricas do jogo
        hw = data.get("Hardware", {})
        cpu_parts = hw.get("CPU", "").split()
        vendor = "AMD" if any("amd" in p.lower() or "ryzen" in p.lower() for p in cpu_parts) else "Intel"
        ram_str = hw.get("RAM", "8GB DDR4 @ 3200MHz")
        try:
            ram_gb = int(ram_str.split("GB")[0].strip())
        except:
            ram_gb = 8

        hw_id = __import__("hashlib").sha256(hw.get("CPU","?").encode()).hexdigest()[:32]

        session_payload = {
            "hardware_id":  hw_id,
            "cpu_model":    hw.get("CPU", ""),
            "cpu_vendor":   vendor,
            "cpu_cores":    8,
            "cpu_threads":  16,
            "cpu_is_x3d":   False,
            "ram_gb":       ram_gb,
            "disk_nvme":    hw.get("Disco","") == "NVMe",
            "is_win11":     hw.get("OS","") == "Win11",
            "perfil":       "Gamer",
            "score_antes":  0,
            "score_depois": 0,
            "game":         jogo,
            "tweaks":       data.get("TweaksRecomendados", []),
            "gargalos":     [g.get("Tipo","") for g in data.get("Gargalos", [])],
            # Métricas ao vivo
            "lat_antes":    int(data.get("Ping", {}).get("Media", 0) or 0),
            "ram_uso_antes":float(data.get("RAM",  {}).get("Media", 0) or 0),
        }

        try:
            # Salvar na tabela dedicada game_sessions
            db.save_game_session({
                "hardware_id":         hw_id,
                "jogo":                jogo,
                "engine":              diagnostico.get("engine",""),
                "duracao_seg":         data.get("DuracaoSeg", 0),
                "amostras":            data.get("Amostras", 0),
                "cpu_media":           (data.get("CPU") or {}).get("Media"),
                "cpu_p95":             (data.get("CPU") or {}).get("P95"),
                "cpu_game_p95":        (data.get("CPUGame") or {}).get("P95"),
                "gpu_media":           (data.get("GPU") or {}).get("Media"),
                "gpu_temp_max":        (data.get("GPUTemp") or {}).get("Max"),
                "ram_p95":             (data.get("RAM") or {}).get("P95"),
                "ping_p95":            (data.get("Ping") or {}).get("P95"),
                "fps_media":           (data.get("FPS") or {}).get("Media"),
                "fps_1pct_lows":       (data.get("FPS") or {}).get("P5"),
                "gpu_throttle_pct":    data.get("GPUThrottlePct", 0),
                "gargalo_principal":   diagnostico.get("gargalo_principal",""),
                "ganho_fps_previsto":  diagnostico.get("ganho_fps_previsto", 0),
                "diagnostico":         diagnostico.get("diagnostico",""),
                "cpu_model":           hw.get("CPU",""),
                "gpu_model":           hw.get("GPU",""),
                "ram_gb":              ram_gb,
                "is_win11":            hw.get("OS","") == "Win11",
            })
        except Exception as e:
            log.warning(f"Erro ao salvar game session: {e}")

        return jsonify(diagnostico), 200

    except Exception as e:
        log.error(f"Erro em /game-session: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


# ── Treinar modelo na inicialização se houver dados ─────────────
if __name__ == "__main__":
    log.info("=" * 50)
    log.info("  MalikIA v7.0 — Iniciando...")
    log.info("=" * 50)

    sessions = db.count_sessions()
    log.info(f"  Sessões no banco: {sessions}")

    if sessions >= 5:
        log.info("  Treinando modelo ML inicial...")
        ml.train()
        log.info(f"  Modelo treinado! Acurácia: {ml.last_accuracy:.2%}")
    else:
        log.info(f"  Modelo aguarda {5 - sessions} sessões para treinar.")

    log.info(f"  API Key: {API_KEY}")
    log.info("  Servidor: http://localhost:8000")
    log.info("=" * 50)

    app.run(host="0.0.0.0", port=8000, debug=False)
