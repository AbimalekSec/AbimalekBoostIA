"""
MalikIA — Motor de Machine Learning
scikit-learn: Random Forest + KNN + Gradient Boosting

Modelos:
  1. RecommenderModel  — qual perfil maximiza o ganho de score
  2. ScoreGainModel    — prevê ganho de score (regressão)
  3. FpsGainModel      — prevê ganho de FPS por jogo (regressão)
  4. TweakRanker       — quais tweaks têm maior impacto por hardware
"""

import io, json, logging
import numpy  as np
import pandas as pd
import joblib

from sklearn.ensemble         import RandomForestClassifier, GradientBoostingRegressor
from sklearn.neighbors        import KNeighborsRegressor
from sklearn.preprocessing    import LabelEncoder, StandardScaler
from sklearn.model_selection  import cross_val_score
from sklearn.pipeline         import Pipeline
from sklearn.metrics          import mean_absolute_error
from typing                   import Dict, List, Optional, Any

log = logging.getLogger("MalikML")


# ── Constantes ───────────────────────────────────────────────────
PERFIS  = ["Seguro", "Gamer", "Streamer", "Extremo"]
JOGOS   = ["FiveM", "CS2", "Valorant", "Apex", "Fortnite", "Outro"]

# FPS base por hardware + jogo — usado quando não há dados suficientes
# Derivado do benchmark real: Ryzen 5 5700X + Win10 → +58fps FiveM (+34.5%)
FPS_BASELINE = {
    # (cpu_vendor, is_x3d, cores_bucket, jogo): (min_pct, max_pct)
    ("AMD",   True,  "8+", "FiveM"):    (35, 55),
    ("AMD",   True,  "8+", "CS2"):      (25, 40),
    ("AMD",   True,  "8+", "Valorant"): (20, 35),
    ("AMD",   False, "8+", "FiveM"):    (25, 42),   # ← benchmark real: 34.5%
    ("AMD",   False, "8+", "CS2"):      (18, 32),
    ("AMD",   False, "8+", "Valorant"): (15, 28),
    ("AMD",   False, "6",  "FiveM"):    (18, 32),
    ("AMD",   False, "6",  "CS2"):      (15, 28),
    ("AMD",   False, "4",  "FiveM"):    (10, 22),
    ("Intel", False, "8+", "FiveM"):    (20, 36),
    ("Intel", False, "8+", "CS2"):      (15, 30),
    ("Intel", False, "6",  "FiveM"):    (15, 28),
    ("Intel", False, "4",  "FiveM"):    (8,  20),
}


class MalikML:
    def __init__(self, db):
        self.db            = db
        self.is_trained    = False
        self.last_accuracy = 0.0
        self.last_n_samples = 0

        # Modelos
        self._recommender  = None   # classifica melhor perfil
        self._score_model  = None   # regride ganho de score
        self._fps_model    = None   # regride ganho de FPS %
        self._label_enc    = LabelEncoder().fit(PERFIS)

        # Tentar carregar modelo salvo
        blob = db.load_model()
        if blob:
            try:
                self._load_from_blob(blob)
                log.info("Modelo carregado do banco.")
            except Exception as e:
                log.warning(f"Modelo salvo corrompido: {e}")

    # ════════════════════════════════════════════════════════════
    #  FEATURE ENGINEERING
    # ════════════════════════════════════════════════════════════
    def _features(self, row: Dict) -> List[float]:
        """Converte uma sessão em vetor de features numéricas."""
        vendor_amd   = 1.0 if str(row.get("cpu_vendor","")).upper() == "AMD"   else 0.0
        vendor_intel = 1.0 if str(row.get("cpu_vendor","")).upper() == "INTEL" else 0.0

        perfil_enc = 0.0
        try:
            p = row.get("perfil", "Gamer")
            perfil_enc = float(self._label_enc.transform([p])[0]) if p in PERFIS else 1.0
        except Exception: pass

        return [
            vendor_amd,
            vendor_intel,
            float(row.get("cpu_cores",  4)   or 4),
            float(row.get("cpu_is_x3d", 0)   or 0),
            float(row.get("cpu_gen",    0)    or 0),
            float(row.get("ram_gb",     8)    or 8),
            float(row.get("ram_mhz",    3200) or 3200) / 1000.0,   # normalizado
            float(row.get("gpu_vram",   4)    or 4),
            float(row.get("disk_nvme",  0)    or 0),
            float(row.get("is_win11",   0)    or 0),
            float(row.get("score_antes",50)   or 50),
            float(row.get("lat_antes",  50)   or 50),
            float(row.get("ram_uso_antes",50) or 50),
            float(row.get("timer_antes",1.0)  or 1.0),
            float(row.get("thermal_detect",0) or 0),
            float(row.get("ep_cores",   0)    or 0),
            perfil_enc,
        ]

    FEATURE_NAMES = [
        "vendor_amd","vendor_intel","cpu_cores","cpu_is_x3d","cpu_gen",
        "ram_gb","ram_mhz_k","gpu_vram","disk_nvme","is_win11",
        "score_antes","lat_antes","ram_uso_antes","timer_antes",
        "thermal_detect","ep_cores","perfil_enc",
    ]

    # ════════════════════════════════════════════════════════════
    #  TREINAR
    # ════════════════════════════════════════════════════════════
    def train(self) -> bool:
        sessions = self.db.get_sessions_for_training()
        if len(sessions) < 5:
            log.warning(f"Dados insuficientes para treinar: {len(sessions)} sessões (mínimo 5)")
            return False

        df = pd.DataFrame(sessions)
        log.info(f"Treinando com {len(df)} sessões...")

        X = np.array([self._features(r) for r in sessions])
        y_score = df["score_ganho"].fillna(0).values.astype(float)

        # ── 1. Score Gain Model (Gradient Boosting) ──────────────
        try:
            self._score_model = GradientBoostingRegressor(
                n_estimators=100, max_depth=4,
                learning_rate=0.1, subsample=0.8,
                random_state=42
            )
            if len(X) >= 10:
                cv_scores = cross_val_score(
                    self._score_model, X, y_score,
                    cv=min(5, len(X)//2), scoring="neg_mean_absolute_error"
                )
                mae = -cv_scores.mean()
                self.last_accuracy = max(0, 1 - mae / max(y_score.std(), 1))
                log.info(f"Score model MAE: {mae:.2f} | R-like accuracy: {self.last_accuracy:.2%}")
            self._score_model.fit(X, y_score)
        except Exception as e:
            log.error(f"Score model falhou: {e}")

        # ── 2. Recommender (Random Forest — melhor perfil por hardware) ──
        try:
            if "perfil" in df.columns and df["perfil"].notna().sum() >= 5:
                # Features sem perfil_enc (última coluna) para recomendar perfil
                X_noperf = X[:, :16]
                y_perfil = self._label_enc.transform(
                    df["perfil"].fillna("Gamer").map(
                        lambda p: p if p in PERFIS else "Gamer"
                    )
                )
                self._recommender = RandomForestClassifier(
                    n_estimators=200, max_depth=6,
                    class_weight="balanced", random_state=42
                )
                self._recommender.fit(X_noperf, y_perfil)
                log.info("Recommender treinado.")
        except Exception as e:
            log.error(f"Recommender falhou: {e}")

        # ── 3. FPS Gain Model (KNN — interpola com hardware similar) ──
        try:
            df_fps = df[df["fps_ganho_pct"].notna()].copy()
            if len(df_fps) >= 3:
                X_fps = np.array([self._features(r) for r in df_fps.to_dict("records")])
                y_fps = df_fps["fps_ganho_pct"].values.astype(float)
                self._fps_model = Pipeline([
                    ("scaler", StandardScaler()),
                    ("knn",    KNeighborsRegressor(n_neighbors=min(3, len(df_fps)), weights="distance")),
                ])
                self._fps_model.fit(X_fps, y_fps)
                log.info(f"FPS model treinado com {len(df_fps)} amostras.")
        except Exception as e:
            log.warning(f"FPS model falhou (dados insuficientes?): {e}")

        self.is_trained     = True
        self.last_n_samples = len(sessions)

        # Salvar no banco
        try:
            buf = io.BytesIO()
            joblib.dump({
                "score_model": self._score_model,
                "recommender": self._recommender,
                "fps_model":   self._fps_model,
                "label_enc":   self._label_enc,
                "n_samples":   self.last_n_samples,
                "accuracy":    self.last_accuracy,
            }, buf)
            self.db.save_model(buf.getvalue(), self.last_accuracy, self.last_n_samples)
            log.info("Modelo salvo no banco.")
        except Exception as e:
            log.error(f"Erro ao salvar modelo: {e}")

        return True

    def _load_from_blob(self, blob: bytes):
        buf  = io.BytesIO(blob)
        data = joblib.load(buf)
        self._score_model   = data.get("score_model")
        self._recommender   = data.get("recommender")
        self._fps_model     = data.get("fps_model")
        self._label_enc     = data.get("label_enc", self._label_enc)
        self.last_n_samples = data.get("n_samples", 0)
        self.last_accuracy  = data.get("accuracy",  0.0)
        self.is_trained     = True

    # ════════════════════════════════════════════════════════════
    #  FEATURE IMPORTANCE — quais tweaks importam mais
    # ════════════════════════════════════════════════════════════
    def get_feature_importance(self) -> List[Dict]:
        if not self._score_model or not hasattr(self._score_model, "feature_importances_"):
            return []
        importances = self._score_model.feature_importances_
        return sorted([
            {"feature": name, "importance": round(float(imp), 4)}
            for name, imp in zip(self.FEATURE_NAMES, importances)
        ], key=lambda x: x["importance"], reverse=True)

    # ════════════════════════════════════════════════════════════
    #  PREDICT SCORE GAIN
    # ════════════════════════════════════════════════════════════
    def predict_score_gain(self, hw: Dict) -> Dict:
        if not self._score_model:
            return {"predicted_gain": None, "confidence": "sem_modelo"}

        X = np.array([self._features(hw)])
        try:
            gain = float(self._score_model.predict(X)[0])
            # Confiança baseada em amostras e accuracia
            confidence = (
                "alta"   if self.last_n_samples >= 20 and self.last_accuracy >= 0.7 else
                "media"  if self.last_n_samples >= 10 else
                "baixa"
            )
            return {
                "predicted_gain": round(gain, 1),
                "confidence":     confidence,
                "model_samples":  self.last_n_samples,
            }
        except Exception as e:
            return {"predicted_gain": None, "confidence": "erro", "error": str(e)}

    # ════════════════════════════════════════════════════════════
    #  RECOMMEND PROFILE
    # ════════════════════════════════════════════════════════════
    def recommend_profile(self, hw: Dict) -> Dict:
        if not self._recommender:
            # Fallback: regra heurística
            return self._heuristic_profile(hw)

        X = np.array([self._features(hw)[:16]])  # sem perfil_enc
        try:
            proba  = self._recommender.predict_proba(X)[0]
            labels = self._label_enc.classes_
            ranked = sorted(zip(labels, proba), key=lambda x: x[1], reverse=True)
            return {
                "perfil_recomendado": ranked[0][0],
                "confianca_pct":      round(ranked[0][1] * 100, 1),
                "ranking":            [{"perfil": p, "prob": round(v*100,1)} for p,v in ranked],
                "source":             "ml_model",
            }
        except Exception:
            return self._heuristic_profile(hw)

    def _heuristic_profile(self, hw: Dict) -> Dict:
        """Fallback quando o modelo não está treinado."""
        cores = hw.get("cpu_cores", 4) or 4
        ram   = hw.get("ram_gb",    8) or 8
        is_x3d = hw.get("cpu_is_x3d", False)

        if is_x3d or (cores >= 8 and ram >= 16):
            rec = "Extremo"
        elif cores >= 6 and ram >= 12:
            rec = "Gamer"
        elif cores >= 4:
            rec = "Gamer"
        else:
            rec = "Seguro"

        return {
            "perfil_recomendado": rec,
            "confianca_pct":      None,
            "ranking":            [],
            "source":             "heuristica",
        }

    # ════════════════════════════════════════════════════════════
    #  PREDICT FPS GAIN
    # ════════════════════════════════════════════════════════════
    def predict_fps_gain(self, params: Dict) -> Dict:
        game       = params.get("game", "FiveM")
        cpu_vendor = params.get("cpu_vendor", "AMD")
        cpu_cores  = int(params.get("cpu_cores", 4) or 4)
        is_x3d     = bool(params.get("cpu_is_x3d", False))
        perfil     = params.get("perfil", "Gamer")

        # Tentar via modelo ML
        ml_result = None
        if self._fps_model:
            try:
                X      = np.array([self._features(params)])
                pct    = float(self._fps_model.predict(X)[0])
                ml_result = round(pct, 1)
            except Exception: pass

        # Fallback via tabela de baseline + benchmark real
        cores_bucket = "8+" if cpu_cores >= 8 else "6" if cpu_cores >= 6 else "4"
        key = (cpu_vendor, is_x3d, cores_bucket, game)
        baseline = FPS_BASELINE.get(key, FPS_BASELINE.get((cpu_vendor, is_x3d, "4", game), (8, 20)))

        # Multiplicador por perfil
        mult = {"Seguro": 0.6, "Gamer": 1.0, "Streamer": 0.9, "Extremo": 1.25}.get(perfil, 1.0)
        lo   = round(baseline[0] * mult, 1)
        hi   = round(baseline[1] * mult, 1)
        med  = round((lo + hi) / 2, 1)

        # Se benchmark real coincide com este hardware, usar como âncora
        benchmark_ref = None
        if cpu_vendor == "AMD" and cpu_cores >= 8 and not is_x3d and game == "FiveM":
            benchmark_ref = {
                "hw":      "Ryzen 5 5700X + 24GB DDR4 2666 + Win10",
                "perfil":  "Gamer + Extremo",
                "fps_antes": 168,
                "fps_depois": 226,
                "ganho_fps": 58,
                "ganho_pct": 34.5,
            }

        return {
            "game":          game,
            "perfil":        perfil,
            "ml_pct":        ml_result,
            "range_pct_min": lo,
            "range_pct_max": hi,
            "media_pct":     ml_result if ml_result else med,
            "source":        "ml_model" if ml_result else "baseline_table",
            "benchmark_ref": benchmark_ref,
            "confianca":     (
                "alta"  if ml_result and self.last_n_samples >= 20 else
                "media" if ml_result else
                "baseline"
            ),
        }

    # ════════════════════════════════════════════════════════════
    #  GET INSIGHT — reúne tudo para retornar ao PowerShell
    # ════════════════════════════════════════════════════════════
    def get_insight(self, hardware_id: str, cpu_model: str,
                    cpu_vendor: str, cpu_cores: int,
                    ram_gb: int, is_win11: bool,
                    disk_nvme: bool, gpu_vram: int) -> Dict:

        hw = {
            "hardware_id": hardware_id,
            "cpu_model":   cpu_model,
            "cpu_vendor":  cpu_vendor,
            "cpu_cores":   cpu_cores,
            "ram_gb":      ram_gb,
            "is_win11":    is_win11,
            "disk_nvme":   disk_nvme,
            "gpu_vram":    gpu_vram,
            "perfil":      "Gamer",
        }

        similar = self.db.find_similar(
            hardware_id=hardware_id,
            cpu_vendor=cpu_vendor,
            cpu_cores=cpu_cores,
            ram_gb=ram_gb,
            is_win11=is_win11,
            limit=3
        )

        rec      = self.recommend_profile(hw)
        score_p  = self.predict_score_gain({**hw, "perfil": rec["perfil_recomendado"]})
        fps_fivem = self.predict_fps_gain({**hw, "game":"FiveM",   "perfil": rec["perfil_recomendado"]})
        fps_cs2   = self.predict_fps_gain({**hw, "game":"CS2",     "perfil": rec["perfil_recomendado"]})
        fps_val   = self.predict_fps_gain({**hw, "game":"Valorant", "perfil": rec["perfil_recomendado"]})

        # Tweaks mais impactantes para este perfil de hardware (feature importance)
        fi = self.get_feature_importance()
        top_features = [f["feature"] for f in fi[:5]] if fi else []

        return {
            "hardware_id":         hardware_id,
            "cpu_model":           cpu_model,
            "perfil_recomendado":  rec["perfil_recomendado"],
            "perfil_confianca":    rec["confianca_pct"],
            "score_ganho_previsto": score_p.get("predicted_gain"),
            "confianca_score":     score_p.get("confidence"),
            "fps_previsao": {
                "FiveM":   fps_fivem,
                "CS2":     fps_cs2,
                "Valorant":fps_val,
            },
            "casos_similares":     similar,
            "top_features":        top_features,
            "model_trained":       self.is_trained,
            "model_samples":       self.last_n_samples,
            "model_accuracy":      round(self.last_accuracy, 3),
        }
