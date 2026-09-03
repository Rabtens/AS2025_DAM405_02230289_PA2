"""
app/main.py
-----------
Prediction API for the DAM405 Assignment 2 wine-cultivar classifier.

Endpoints:
    GET  /health   -> liveness/readiness probe (used by Docker HEALTHCHECK,
                       the orchestrator, and the CD pipeline's smoke test)
    POST /predict  -> returns a class prediction + probabilities for a
                       single feature vector, with strict input validation
    GET  /version  -> exposes the currently loaded model version (used to
                       verify canary / blue-green rollouts)

Run directly:  python app/main.py
Run with a WSGI server (used in the container): gunicorn -b 0.0.0.0:8000 app.main:app
"""
import logging
import os
import time
from pathlib import Path

import joblib
import json
from flask import Flask, jsonify, request

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
logger = logging.getLogger("wine-predict-api")

BASE_DIR = Path(__file__).resolve().parent.parent
MODEL_PATH = Path(os.environ.get("MODEL_PATH", BASE_DIR / "model" / "model.joblib"))
METADATA_PATH = Path(os.environ.get("METADATA_PATH", BASE_DIR / "model" / "metadata.json"))
SERVICE_START_TIME = time.time()

app = Flask(__name__)

# ---------------------------------------------------------------------------
# Model loading (fail fast at startup rather than on first request)
# ---------------------------------------------------------------------------
_model = None
_metadata = None
_load_error = None

try:
    _model = joblib.load(MODEL_PATH)
    with open(METADATA_PATH) as f:
        _metadata = json.load(f)
    logger.info("Model loaded: version=%s features=%d", _metadata["model_version"], _metadata["n_features"])
except Exception as exc:  # noqa: BLE001 - we want to serve a clear health failure, not crash silently
    _load_error = str(exc)
    logger.exception("Failed to load model artefacts")

FEATURE_NAMES = _metadata["feature_names"] if _metadata else []
CLASS_NAMES = _metadata["class_names"] if _metadata else []


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------
class ValidationError(Exception):
    def __init__(self, message):
        super().__init__(message)
        self.message = message


def validate_payload(payload):
    """Validate a /predict request body.

    Expected shape:
        {"features": {"alcohol": 13.2, "malic_acid": 1.78, ... (13 keys)}}

    Raises ValidationError with a human-readable reason on any problem.
    Returns an ordered list of floats matching FEATURE_NAMES.
    """
    if not isinstance(payload, dict):
        raise ValidationError("Request body must be a JSON object.")

    if "features" not in payload:
        raise ValidationError("Missing required field: 'features'.")

    features = payload["features"]
    if not isinstance(features, dict):
        raise ValidationError("'features' must be a JSON object of {feature_name: value}.")

    missing = [name for name in FEATURE_NAMES if name not in features]
    if missing:
        raise ValidationError(f"Missing required feature(s): {missing}")

    unexpected = [name for name in features if name not in FEATURE_NAMES]
    if unexpected:
        raise ValidationError(f"Unexpected feature(s) not in model schema: {unexpected}")

    ordered_values = []
    for name in FEATURE_NAMES:
        value = features[name]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValidationError(f"Feature '{name}' must be numeric, got {type(value).__name__}.")
        ordered_values.append(float(value))

    return ordered_values


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.route("/health", methods=["GET"])
def health():
    """Liveness/readiness probe. Returns 200 only if the model is loaded."""
    if _model is None:
        return jsonify(
            {
                "status": "unhealthy",
                "reason": _load_error or "model not loaded",
            }
        ), 503

    return jsonify(
        {
            "status": "healthy",
            "model_version": _metadata["model_version"],
            "uptime_seconds": round(time.time() - SERVICE_START_TIME, 2),
        }
    ), 200


@app.route("/version", methods=["GET"])
def version():
    if _metadata is None:
        return jsonify({"error": "metadata unavailable"}), 503
    return jsonify(
        {
            "model_version": _metadata["model_version"],
            "algorithm": _metadata["algorithm"],
            "trained_at_utc": _metadata["trained_at_utc"],
            "test_accuracy": _metadata["test_accuracy"],
        }
    ), 200


@app.route("/predict", methods=["POST"])
def predict():
    if _model is None:
        logger.error("Predict called but model is not loaded: %s", _load_error)
        return jsonify({"error": "Model not available", "detail": _load_error}), 503

    if not request.is_json:
        return jsonify({"error": "Content-Type must be application/json"}), 415

    try:
        payload = request.get_json(silent=False)
    except Exception:
        return jsonify({"error": "Malformed JSON body"}), 400

    try:
        ordered_values = validate_payload(payload)
    except ValidationError as ve:
        logger.warning("Validation failed: %s", ve.message)
        return jsonify({"error": "Invalid input", "detail": ve.message}), 400

    try:
        import numpy as np

        X = np.array([ordered_values])
        pred_idx = int(_model.predict(X)[0])
        proba = _model.predict_proba(X)[0].tolist()
        response = {
            "prediction": CLASS_NAMES[pred_idx],
            "prediction_index": pred_idx,
            "probabilities": {CLASS_NAMES[i]: round(p, 4) for i, p in enumerate(proba)},
            "model_version": _metadata["model_version"],
        }
        logger.info("Prediction served: %s", response["prediction"])
        return jsonify(response), 200
    except Exception as exc:  # noqa: BLE001
        logger.exception("Inference error")
        return jsonify({"error": "Inference failed", "detail": str(exc)}), 500


@app.errorhandler(404)
def not_found(_e):
    return jsonify({"error": "Not found", "detail": "Valid endpoints: /health, /version, /predict"}), 404


@app.errorhandler(405)
def method_not_allowed(_e):
    return jsonify({"error": "Method not allowed"}), 405


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    app.run(host="0.0.0.0", port=port)
