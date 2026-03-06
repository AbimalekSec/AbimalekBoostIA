-- ================================================================
--  MalikIA v7 — Schema Supabase (PostgreSQL)
--  Execute no SQL Editor do Supabase
--  Projeto: https://app.supabase.com → SQL Editor → New Query
-- ================================================================

-- ────────────────────────────────────────────────────────────────
--  TABELA PRINCIPAL: sessions
--  Cada linha = uma otimização feita por um cliente
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sessions (
    id              BIGSERIAL PRIMARY KEY,
    created_at      TIMESTAMPTZ DEFAULT NOW(),

    -- Hardware (anonimizado — só hash)
    hardware_id     TEXT        NOT NULL,
    local_id        INTEGER,            -- ID local do SQLite do cliente

    -- CPU
    cpu_model       TEXT,
    cpu_vendor      TEXT,               -- 'AMD' ou 'Intel'
    cpu_cores       INTEGER,
    cpu_threads     INTEGER,
    cpu_is_x3d      BOOLEAN DEFAULT FALSE,
    cpu_gen         INTEGER,            -- geração (ex: 5 para Ryzen 5xxx, 12 para Intel 12th)

    -- RAM
    ram_gb          INTEGER,
    ram_type        TEXT,               -- DDR4, DDR5
    ram_mhz         INTEGER,

    -- GPU
    gpu_model       TEXT,
    gpu_vram        INTEGER,            -- GB

    -- Armazenamento e OS
    disk_nvme       BOOLEAN DEFAULT FALSE,
    is_win11        BOOLEAN DEFAULT FALSE,
    os_build        INTEGER,

    -- Sessão de otimização
    perfil          TEXT,               -- Seguro, Gamer, Streamer, Extremo
    score_antes     INTEGER,
    score_depois    INTEGER,
    score_ganho     INTEGER GENERATED ALWAYS AS (score_depois - score_antes) STORED,

    -- Métricas antes
    lat_antes       INTEGER,            -- ping ms
    ram_uso_antes   REAL,               -- % uso RAM
    timer_antes     REAL,               -- timer resolution ms

    -- Métricas depois
    lat_depois      INTEGER,
    ram_uso_dep     REAL,
    timer_dep       REAL,

    -- Tweaks e diagnóstico
    tweaks          JSONB DEFAULT '[]', -- array de tweaks aplicados
    gargalos        JSONB DEFAULT '[]', -- array de gargalos detectados
    thermal_detect  BOOLEAN DEFAULT FALSE,
    ep_cores        BOOLEAN DEFAULT FALSE,

    -- FPS (opcional — quando cliente informa)
    game            TEXT,
    fps_antes       INTEGER,
    fps_depois      INTEGER,

    script_version  TEXT DEFAULT '7.3.0'
);

-- Índices para performance das queries ML
CREATE INDEX IF NOT EXISTS idx_sessions_hw        ON sessions(hardware_id);
CREATE INDEX IF NOT EXISTS idx_sessions_perfil    ON sessions(perfil);
CREATE INDEX IF NOT EXISTS idx_sessions_cpu       ON sessions(cpu_model);
CREATE INDEX IF NOT EXISTS idx_sessions_vendor    ON sessions(cpu_vendor);
CREATE INDEX IF NOT EXISTS idx_sessions_score     ON sessions(score_ganho DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_game      ON sessions(game);
CREATE INDEX IF NOT EXISTS idx_sessions_created   ON sessions(created_at DESC);

-- ────────────────────────────────────────────────────────────────
--  TABELA: benchmarks
--  FPS voluntário — quando cliente registra antes/depois
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS benchmarks (
    id          BIGSERIAL PRIMARY KEY,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    hardware_id TEXT        NOT NULL,
    session_id  BIGINT REFERENCES sessions(id) ON DELETE SET NULL,
    game        TEXT        NOT NULL,
    fps_antes   INTEGER,
    fps_depois  INTEGER,
    fps_ganho   INTEGER GENERATED ALWAYS AS (fps_depois - fps_antes) STORED,
    fps_pct     REAL,
    perfil      TEXT
);

CREATE INDEX IF NOT EXISTS idx_bench_hw   ON benchmarks(hardware_id);
CREATE INDEX IF NOT EXISTS idx_bench_game ON benchmarks(game);

-- ────────────────────────────────────────────────────────────────
--  TABELA: game_sessions
--  Sessões ao vivo com jogo aberto (nova feature v7.2)
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS game_sessions (
    id              BIGSERIAL PRIMARY KEY,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    hardware_id     TEXT,
    jogo            TEXT,               -- FiveM, CS2, Valorant
    engine          TEXT,
    duracao_seg     INTEGER,
    amostras        INTEGER,

    -- Métricas P95 coletadas ao vivo
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

    -- Diagnóstico
    gargalo_principal   TEXT,
    ganho_fps_previsto  REAL,
    diagnostico         TEXT,

    -- Hardware resumido
    cpu_model       TEXT,
    gpu_model       TEXT,
    ram_gb          INTEGER,
    is_win11        BOOLEAN
);

CREATE INDEX IF NOT EXISTS idx_gs_jogo ON game_sessions(jogo);
CREATE INDEX IF NOT EXISTS idx_gs_hw   ON game_sessions(hardware_id);

-- ────────────────────────────────────────────────────────────────
--  VIEWS úteis para analytics
-- ────────────────────────────────────────────────────────────────

-- Estatísticas globais (usado no GET /stats)
CREATE OR REPLACE VIEW stats_global AS
SELECT
    COUNT(*)                                    AS total_sessoes,
    COUNT(DISTINCT hardware_id)                 AS hardware_unicos,
    ROUND(AVG(score_ganho)::NUMERIC, 1)         AS ganho_medio,
    ROUND(MAX(score_ganho)::NUMERIC, 1)         AS melhor_ganho,
    COUNT(*) FILTER (WHERE is_win11)            AS usuarios_win11,
    COUNT(*) FILTER (WHERE NOT is_win11)        AS usuarios_win10,
    COUNT(*) FILTER (WHERE cpu_vendor = 'AMD')  AS cpus_amd,
    COUNT(*) FILTER (WHERE cpu_vendor = 'Intel')AS cpus_intel,
    COUNT(*) FILTER (WHERE cpu_is_x3d)          AS cpus_x3d,
    COUNT(*) FILTER (WHERE disk_nvme)           AS discos_nvme,
    ROUND(AVG(fps_depois - fps_antes) FILTER (
        WHERE fps_antes IS NOT NULL AND fps_depois IS NOT NULL
    )::NUMERIC, 1)                              AS ganho_fps_medio,
    MAX(created_at)                             AS ultima_sessao
FROM sessions;

-- Top perfis por ganho médio
CREATE OR REPLACE VIEW stats_perfis AS
SELECT
    perfil,
    COUNT(*)                            AS total,
    ROUND(AVG(score_ganho)::NUMERIC, 1) AS ganho_medio,
    ROUND(MAX(score_ganho)::NUMERIC, 1) AS melhor_ganho,
    ROUND(MIN(score_ganho)::NUMERIC, 1) AS pior_ganho
FROM sessions
WHERE perfil IS NOT NULL
GROUP BY perfil
ORDER BY ganho_medio DESC;

-- Top hardware por ganho
CREATE OR REPLACE VIEW stats_hardware AS
SELECT
    cpu_model,
    cpu_vendor,
    cpu_cores,
    ram_gb,
    COUNT(*)                            AS sessoes,
    ROUND(AVG(score_ganho)::NUMERIC, 1) AS ganho_medio
FROM sessions
WHERE cpu_model IS NOT NULL
GROUP BY cpu_model, cpu_vendor, cpu_cores, ram_gb
HAVING COUNT(*) >= 2
ORDER BY ganho_medio DESC
LIMIT 20;

-- ────────────────────────────────────────────────────────────────
--  ROW LEVEL SECURITY — deixar público para inserção
--  (o server.py usa a service_role key internamente)
-- ────────────────────────────────────────────────────────────────
ALTER TABLE sessions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE benchmarks    ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_sessions ENABLE ROW LEVEL SECURITY;

-- Permitir INSERT anônimo (clientes enviam dados sem login)
CREATE POLICY "insert_anon_sessions"
    ON sessions FOR INSERT
    WITH CHECK (true);

CREATE POLICY "insert_anon_benchmarks"
    ON benchmarks FOR INSERT
    WITH CHECK (true);

CREATE POLICY "insert_anon_game_sessions"
    ON game_sessions FOR INSERT
    WITH CHECK (true);

-- SELECT só com service_role (seu server.py)
CREATE POLICY "select_service_sessions"
    ON sessions FOR SELECT
    USING (auth.role() = 'service_role');

CREATE POLICY "select_service_benchmarks"
    ON benchmarks FOR SELECT
    USING (auth.role() = 'service_role');

CREATE POLICY "select_service_game_sessions"
    ON game_sessions FOR SELECT
    USING (auth.role() = 'service_role');

-- ────────────────────────────────────────────────────────────────
--  DADOS DE EXEMPLO para teste (opcional — delete depois)
-- ────────────────────────────────────────────────────────────────
-- INSERT INTO sessions (
--     hardware_id, cpu_model, cpu_vendor, cpu_cores, cpu_is_x3d,
--     cpu_gen, ram_gb, gpu_vram, disk_nvme, is_win11,
--     perfil, score_antes, score_depois,
--     lat_antes, lat_depois, ram_uso_antes, ram_uso_dep,
--     timer_antes, timer_dep, tweaks, gargalos, game, fps_antes, fps_depois
-- ) VALUES
-- ('abc123def456abc123def456abc12345', 'AMD Ryzen 5 5700X', 'AMD', 8, false,
--  5, 24, 8, true, false,
--  'Gamer', 62, 84,
--  28, 16, 58.0, 47.0,
--  4.2, 0.5, '["CORE_PARKING_OFF","NAGLE_OFF","MMCSS_GAMING"]',
--  '["CPU-bound"]', 'FiveM', 148, 206);
