"""
tests/test_api.py
------------------
Automated API tests run both locally and inside the GitHub Actions CD
pipeline (see .github/workflows/ci-cd.yml). These are executed against
the Flask test client for fast unit-level checks, and the same requests
are replayed with `requests` against a running container for the
container-level smoke test (scripts/smoke_test.py).

Run with:  pytest tests/ -v
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest
from app.main import app, FEATURE_NAMES


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


VALID_FEATURES = {
    "alcohol": 13.2,
    "malic_acid": 1.78,
    "ash": 2.14,
    "alcalinity_of_ash": 11.2,
    "magnesium": 100.0,
    "total_phenols": 2.65,
    "flavanoids": 2.76,
    "nonflavanoid_phenols": 0.26,
    "proanthocyanins": 1.28,
    "color_intensity": 4.38,
    "hue": 1.05,
    "od280/od315_of_diluted_wines": 3.4,
    "proline": 1050.0,
}


def test_health_endpoint_returns_200(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["status"] == "healthy"
    assert "model_version" in body


def test_version_endpoint(client):
    resp = client.get("/version")
    assert resp.status_code == 200
    body = resp.get_json()
    assert "model_version" in body
    assert "test_accuracy" in body


def test_predict_valid_payload(client):
    resp = client.post("/predict", json={"features": VALID_FEATURES})
    assert resp.status_code == 200
    body = resp.get_json()
    assert "prediction" in body
    assert "probabilities" in body
    assert sum(body["probabilities"].values()) == pytest.approx(1.0, abs=0.01)


def test_predict_missing_features_key(client):
    resp = client.post("/predict", json={"wrong_key": VALID_FEATURES})
    assert resp.status_code == 400
    assert "error" in resp.get_json()


def test_predict_missing_individual_feature(client):
    incomplete = dict(VALID_FEATURES)
    del incomplete["alcohol"]
    resp = client.post("/predict", json={"features": incomplete})
    assert resp.status_code == 400
    body = resp.get_json()
    assert "alcohol" in body["detail"]


def test_predict_non_numeric_feature(client):
    bad = dict(VALID_FEATURES)
    bad["alcohol"] = "not-a-number"
    resp = client.post("/predict", json={"features": bad})
    assert resp.status_code == 400


def test_predict_unexpected_feature(client):
    extra = dict(VALID_FEATURES)
    extra["extra_field"] = 1.0
    resp = client.post("/predict", json={"features": extra})
    assert resp.status_code == 400


def test_predict_non_json_content_type(client):
    resp = client.post("/predict", data="not json", content_type="text/plain")
    assert resp.status_code == 415


def test_predict_empty_body(client):
    resp = client.post("/predict", json={})
    assert resp.status_code == 400


def test_unknown_route_returns_404(client):
    resp = client.get("/does-not-exist")
    assert resp.status_code == 404


def test_feature_schema_has_13_features():
    assert len(FEATURE_NAMES) == 13
