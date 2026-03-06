"""
MalikIA — Camada de Banco de Dados
Supabase (primário) + SQLite local (fallback automático)
"""

import os, json, sqlite3, hashlib, logging
from datetime import datetime
from typing import Optional, List, Dict, Any
import urllib.request, urllib.parse

log = logging.getLogger("MalikDB")

# ── Configuração Supabase ────────────────────────────────────────
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
DB_PATH      = os.getenv("DB_PATH", "malikia.db")


class MalikDB:
    def __init__(self):
        self.use_supabase = bool(SUPABASE_URL and SUPABASE_KEY)
        self._init_sqlite()

        if self.use_supabase:
            log.info(f"Supabase configurado: {SUPABASE_URL[:40]}...")
        else:
            log.info("Supabase não configurado — usando SQLite local.")

    # ════════════════════════════════════════════════════════════
    #  SQLite — banco local (fallback e cache)
    # ════════════════════════════════════════════════════════════
    def _init_sqlite(self):
        self.conn = sqlite3.connect(DB_PATH, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.execute("PRAGMA synchronous=NORMAL")
        self._create_tables()
        log.info(f"SQLite inicializado: {DB_PATH}")

    def _create_tables(self):
        self.conn.executescript("""
        CREATE TABLE IF NOT EXISTS sessions (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            hardware_id   TEXT NOT NULL,
            created_at    TEXT DEFAULT (datetime('now')),

            -- Hardware
            cpu_model     TEXT,
            cpu_vendor    TEXT,
            cpu_cores     INTEGER,
            cpu_threads   INTEGER,
            cpu_is_x3d    INTEGER DEFAULT 0,
            cpu_gen       INTEGER,
            ram_gb        INTEGER,
            ram_type      TEXT,
            ram_mhz       INTEGER,
            gpu_model     TEXT,
            gpu_vram      INTEGER,
            disk_nvme     INTEGER DEFAULT 0,
            is_win11      INTEGER DEFAULT 0,
            os_build      INTEGER,

            -- Sessão
            perfil        TEXT,
            score_antes   INTEGER,
            score_depois  INTEGER,
            score_ganho   INTEGER GENERATED ALWAYS AS (score_depois - score_antes) STORED,
            lat_antes     INTEGER,
            lat_depois    INTEGER,
            ram_uso_antes REAL,
            ram_uso_dep   REAL,
            timer_antes   REAL,
            timer_dep     REAL,
            tweaks        TEXT,   -- JSON array
            gargalos      TEXT,   -- JSON array
            thermal_detect INTEGER DEFAULT 0,
            ep_cores      INTEGER DEFAULT 0,

            -- Benchmarks FPS (opcionais)
            game          TEXT,
            fps_antes     INTEGER,
            fps_depois    INTEGER,

            script_version TEXT DEFAULT '7.0.0',
            synced         INTEGER DEFAULT 0   -- 0=local only, 1=synced to Supabase
        );

        CREATE INDEX IF NOT EXISTS idx_hw    ON sessions(hardware_id);
        CREATE INDEX IF NOT EXISTS idx_perf  ON sessions(perfil);
        CREATE INDEX IF NOT EXISTS idx_cpu   ON sessions(cpu_model);
        CREATE INDEX IF NOT EXISTS idx_score ON sessions(score_ganho DESC);

        CREATE TABLE IF NOT EXISTS benchmarks (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            hardware_id TEXT NOT NULL,
            session_id  INTEGER REFERENCES sessions(id),
            created_at  TEXT DEFAULT (datetime('now')),
            game        TEXT NOT NULL,
            fps_antes   INTEGER,
            fps_depois  INTEGER,
            fps_ganho   INTEGER GENERATED ALWAYS AS (fps_depois - fps_antes) STORED,
            fps_pct     REAL,
            perfil      TEXT
        );

        CREATE TABLE IF NOT EXISTS game_sessions (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at      TEXT DEFAULT (datetime('now')),
            hardware_id     TEXT,
            jogo            TEXT,
            engine          TEXT,
            duracao_seg     INTEGER,
            amostras        INTEGER,
            cpu_media       REAL,
            cpu_p95         REAL,
            cpu_game_p95    REAL,
            gpu_media       REAL,
            gpu_temp_max    REAL,
            ram_p95         REAL,
            ping_p95        REAL,
            fps_media       REAL,
            fps_1pct_lows   REAL,
            gpu_throttle_pct REAL,
            gargalo_principal TEXT,
            ganho_fps_previsto REAL,
            diagnostico     TEXT,
            cpu_model       TEXT,
            gpu_model       TEXT,
            ram_gb          INTEGER,
            is_win11        INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS model_state (
            id          INTEGER PRIMARY KEY,
            trained_at  TEXT,
            n_samples   INTEGER,
            accuracy    REAL,
            model_blob  BLOB
        );
        """)
        self.conn.commit()

    # ════════════════════════════════════════════════════════════
    #  Supabase — HTTP REST
    # ════════════════════════════════════════════════════════════
    def _supabase_request(self, method: str, endpoint: str, body: dict = None) -> Optional[dict]:
        if not self.use_supabase:
            return None
        try:
            url     = f"{SUPABASE_URL}/rest/v1/{endpoint}"
            headers = {
                "apikey":        SUPABASE_KEY,
                "Authorization": f"Bearer {SUPABASE_KEY}",
                "Content-Type":  "application/json",
                "Prefer":        "return=representation",
            }
            data = json.dumps(body).encode() if body else None
            req  = urllib.request.Request(url, data=data, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=6) as resp:
                return json.loads(resp.read())
        except Exception as e:
            log.warning(f"Supabase {method} {endpoint} falhou: {e}")
            return None

    # ════════════════════════════════════════════════════════════
    #  SAVE SESSION
    # ════════════════════════════════════════════════════════════
    def save_session(self, data: dict) -> int:
        tweaks   = json.dumps(data.get("tweaks",   []))
        gargalos = json.dumps(data.get("gargalos", []))

        cur = self.conn.execute("""
        INSERT INTO sessions (
            hardware_id, cpu_model, cpu_vendor, cpu_cores, cpu_threads,
            cpu_is_x3d, cpu_gen, ram_gb, ram_type, ram_mhz,
            gpu_model, gpu_vram, disk_nvme, is_win11, os_build,
            perfil, score_antes, score_depois,
            lat_antes, lat_depois, ram_uso_antes, ram_uso_dep,
            timer_antes, timer_dep, tweaks, gargalos,
            thermal_detect, ep_cores, game, fps_antes, fps_depois,
            script_version
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (
            data["hardware_id"],
            data.get("cpu_model"),    data.get("cpu_vendor"),
            data.get("cpu_cores"),    data.get("cpu_threads"),
            int(data.get("cpu_is_x3d", False)),
            data.get("cpu_gen"),
            data.get("ram_gb"),       data.get("ram_type"),
            data.get("ram_mhz"),
            data.get("gpu_model"),    data.get("gpu_vram"),
            int(data.get("disk_nvme", False)),
            int(data.get("is_win11",  False)),
            data.get("os_build"),
            data.get("perfil",        "Gamer"),
            data.get("score_antes",   0),
            data.get("score_depois",  0),
            data.get("lat_antes"),    data.get("lat_depois"),
            data.get("ram_uso_antes"),data.get("ram_uso_dep"),
            data.get("timer_antes"),  data.get("timer_dep"),
            tweaks, gargalos,
            int(data.get("thermal_detect", False)),
            int(data.get("ep_cores",        False)),
            data.get("game"),         data.get("fps_antes"),
            data.get("fps_depois"),
            data.get("script_version", "7.0.0"),
        ))
        self.conn.commit()
        session_id = cur.lastrowid
        log.info(f"Sessão salva: id={session_id} hw={data['hardware_id'][:12]}... ganho={data.get('score_depois',0)-data.get('score_antes',0)}")

        # Sync assíncrono para Supabase
        if self.use_supabase:
            self._sync_to_supabase(data, session_id)

        return session_id

    def _sync_to_supabase(self, data: dict, local_id: int):
        payload = {k: v for k, v in data.items()}
        payload["local_id"] = local_id
        result = self._supabase_request("POST", "sessions", payload)
        if result:
            self.conn.execute("UPDATE sessions SET synced=1 WHERE id=?", (local_id,))
            self.conn.commit()

    # ════════════════════════════════════════════════════════════
    #  QUERIES
    # ════════════════════════════════════════════════════════════
    def count_sessions(self) -> int:
        return self.conn.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]

    def get_all_sessions(self) -> List[Dict]:
        rows = self.conn.execute("""
            SELECT * FROM sessions ORDER BY created_at
        """).fetchall()
        return [dict(r) for r in rows]

    def get_sessions_for_training(self) -> List[Dict]:
        """Retorna sessões com score_ganho calculável para treinar o modelo."""
        rows = self.conn.execute("""
            SELECT cpu_vendor, cpu_cores, cpu_is_x3d, cpu_gen,
                   ram_gb, ram_mhz, gpu_vram, disk_nvme, is_win11,
                   perfil, score_antes, score_ganho,
                   lat_antes, ram_uso_antes, timer_antes,
                   thermal_detect, ep_cores,
                   game, fps_antes,
                   CASE WHEN fps_depois IS NOT NULL
                        THEN CAST(fps_depois - fps_antes AS REAL) / NULLIF(fps_antes, 0) * 100
                        ELSE NULL END AS fps_ganho_pct
            FROM sessions
            WHERE score_depois IS NOT NULL AND score_antes IS NOT NULL
        """).fetchall()
        return [dict(r) for r in rows]

    def get_global_stats(self) -> Dict:
        row = self.conn.execute("""
            SELECT
                COUNT(*)                               AS total_sessoes,
                COUNT(DISTINCT hardware_id)            AS total_maquinas,
                ROUND(AVG(score_ganho), 1)             AS ganho_medio,
                ROUND(MAX(score_ganho), 0)             AS melhor_ganho,
                ROUND(AVG(lat_antes - lat_depois), 1)  AS reducao_ping,
                ROUND(AVG(ram_uso_antes - ram_uso_dep),1) AS reducao_ram,
                COUNT(CASE WHEN is_win11=1 THEN 1 END) AS win11_count,
                COUNT(CASE WHEN is_win11=0 THEN 1 END) AS win10_count,
                COUNT(CASE WHEN cpu_vendor='AMD' THEN 1 END)   AS amd_count,
                COUNT(CASE WHEN cpu_vendor='Intel' THEN 1 END) AS intel_count
            FROM sessions
        """).fetchone()

        perfis = self.conn.execute("""
            SELECT perfil,
                   COUNT(*)                   AS sessoes,
                   ROUND(AVG(score_ganho), 1) AS ganho_medio
            FROM sessions GROUP BY perfil
            ORDER BY ganho_medio DESC
        """).fetchall()

        top_cpus = self.conn.execute("""
            SELECT cpu_model, cpu_vendor,
                   COUNT(*)                   AS sessoes,
                   ROUND(AVG(score_ganho), 1) AS ganho_medio
            FROM sessions
            WHERE cpu_model IS NOT NULL
            GROUP BY cpu_model
            HAVING COUNT(*) >= 1
            ORDER BY ganho_medio DESC LIMIT 10
        """).fetchall()

        bench = self.conn.execute("""
            SELECT game,
                   COUNT(*)                       AS amostras,
                   ROUND(AVG(fps_ganho_pct), 1)   AS ganho_pct_medio
            FROM (
                SELECT game,
                       CAST(fps_depois - fps_antes AS REAL) / NULLIF(fps_antes,0) * 100 AS fps_ganho_pct
                FROM sessions
                WHERE fps_antes IS NOT NULL AND fps_depois IS NOT NULL AND game IS NOT NULL
            )
            GROUP BY game ORDER BY ganho_pct_medio DESC
        """).fetchall()

        return {
            "resumo":    dict(row) if row else {},
            "perfis":    [dict(r) for r in perfis],
            "top_cpus":  [dict(r) for r in top_cpus],
            "benchmarks":[dict(r) for r in bench],
            "timestamp": datetime.now().isoformat(),
        }

    def find_similar(self, hardware_id: str, cpu_vendor: str,
                     cpu_cores: int, ram_gb: int,
                     is_win11: bool, limit: int = 5) -> List[Dict]:
        """Encontra sessões com hardware similar para comparação."""
        rows = self.conn.execute("""
            SELECT hardware_id, cpu_model, cpu_vendor, cpu_cores,
                   ram_gb, is_win11, perfil,
                   score_ganho,
                   lat_antes, lat_depois,
                   fps_antes, fps_depois, game,
                   ABS(cpu_cores - ?) +
                   ABS(ram_gb    - ?) * 0.5 +
                   CASE WHEN cpu_vendor = ? THEN 0 ELSE 2 END +
                   CASE WHEN is_win11 = ?   THEN 0 ELSE 1 END AS dist
            FROM sessions
            WHERE hardware_id != ?
            ORDER BY dist ASC, score_ganho DESC
            LIMIT ?
        """, (cpu_cores, ram_gb, cpu_vendor, int(is_win11), hardware_id, limit)).fetchall()
        return [dict(r) for r in rows]


    def save_game_session(self, data: dict) -> int:
        """Salva sessão ao vivo com jogo aberto."""
        cur = self.conn.execute("""
        INSERT INTO game_sessions (
            hardware_id, jogo, engine, duracao_seg, amostras,
            cpu_media, cpu_p95, cpu_game_p95,
            gpu_media, gpu_temp_max, ram_p95, ping_p95,
            fps_media, fps_1pct_lows, gpu_throttle_pct,
            gargalo_principal, ganho_fps_previsto, diagnostico,
            cpu_model, gpu_model, ram_gb, is_win11
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (
            data.get("hardware_id",""),
            data.get("jogo",""),
            data.get("engine",""),
            data.get("duracao_seg", 0),
            data.get("amostras", 0),
            data.get("cpu_media"),
            data.get("cpu_p95"),
            data.get("cpu_game_p95"),
            data.get("gpu_media"),
            data.get("gpu_temp_max"),
            data.get("ram_p95"),
            data.get("ping_p95"),
            data.get("fps_media"),
            data.get("fps_1pct_lows"),
            data.get("gpu_throttle_pct", 0),
            data.get("gargalo_principal",""),
            data.get("ganho_fps_previsto", 0),
            data.get("diagnostico",""),
            data.get("cpu_model",""),
            data.get("gpu_model",""),
            data.get("ram_gb"),
            data.get("is_win11", False),
        ))
        self.conn.commit()
        local_id = cur.lastrowid

        # Sync para Supabase
        if self.use_supabase:
            try:
                self._supabase_request("POST", "game_sessions", {
                    **data,
                    "local_id": local_id,
                })
            except Exception as e:
                log.warning(f"Supabase game_session sync falhou: {e}")

        return local_id

    def save_model(self, blob: bytes, accuracy: float, n_samples: int):
        self.conn.execute("DELETE FROM model_state")
        self.conn.execute("""
            INSERT INTO model_state (trained_at, n_samples, accuracy, model_blob)
            VALUES (?, ?, ?, ?)
        """, (datetime.now().isoformat(), n_samples, accuracy, blob))
        self.conn.commit()

    def load_model(self) -> Optional[bytes]:
        row = self.conn.execute("SELECT model_blob FROM model_state ORDER BY id DESC LIMIT 1").fetchone()
        return row[0] if row else None
