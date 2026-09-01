# DAM405 · Assignment 2 — Wine-Cultivar Prediction Service

A containerised ML prediction API with a full CI/CD pipeline, built for
**DAM405 Machine Learning Operations, Programming Assignment 2**.

- **Model**: `RandomForestClassifier` (scikit-learn) trained on the UCI Wine
  recognition dataset (`sklearn.datasets.load_wine`) — bundled with
  scikit-learn, so training is 100% reproducible offline / in CI.
- **Service**: Flask API (`/predict`, `/health`, `/version`) served in
  production by gunicorn.
- **Container**: multi-stage `Dockerfile`, slim base image, non-root user,
  `.dockerignore`, container `HEALTHCHECK`.
- **CD pipeline**: GitHub Actions — lint → train → unit test → build →
  container smoke test → publish to GHCR → gated blue-green deploy.
- **IaC**: `docker-compose.yml` (primary) + `deployment/main.tf`
  (illustrative Terraform alternative).
- **Rollout strategy**: blue-green via an nginx reverse proxy
  (`deployment/nginx.conf`), with `deployment/switch_traffic.sh` and
  `deployment/rollback.sh`.

## Repository layout

```
.
├── app/main.py                  # Flask API
├── model/train.py               # training script -> model.joblib, metadata.json
├── model/model.joblib           # persisted trained model (committed for reproducibility)
├── model/metadata.json          # feature schema, classes, metrics
├── tests/test_api.py            # pytest unit/API tests (11 tests)
├── tests/smoke_test.py          # container-level HTTP smoke test
├── Dockerfile
├── .dockerignore
├── requirements.txt / requirements-dev.txt
├── docker-compose.yml           # IaC: blue/green services + nginx proxy
├── deployment/
│   ├── nginx.conf                # routes to the current live slot
│   ├── switch_traffic.sh         # blue-green cutover
│   ├── rollback.sh               # instant rollback
│   └── main.tf                   # alternative Terraform IaC (illustrative)
├── .github/workflows/ci-cd.yml  # CI/CD pipeline
├── diagrams/                    # architecture + edge-porting diagrams
└── evidence/                    # captured request/response transcripts, logs
```

## Setup & run

### 1. Local (no Docker)
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
python model/train.py            # trains and saves model/model.joblib
python app/main.py               # serves on http://localhost:8000
```

### 2. Run tests
```bash
pytest tests/test_api.py -v
```

### 3. Docker
```bash
docker build -t dam405-wine-predict-api:local .
docker run -d -p 8000:8000 --name wine-api dam405-wine-predict-api:local
curl http://localhost:8000/health
python tests/smoke_test.py --host http://localhost:8000
```

### 4. Full blue-green stack (Compose)
```bash
docker compose up -d --build
curl http://localhost:8080/health           # routed via nginx to the live slot
./deployment/switch_traffic.sh green        # cut over to the other slot
./deployment/rollback.sh blue               # roll back if something's wrong
```

## Example request

```bash
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"features": {"alcohol": 13.2, "malic_acid": 1.78, "ash": 2.14,
       "alcalinity_of_ash": 11.2, "magnesium": 100.0, "total_phenols": 2.65,
       "flavanoids": 2.76, "nonflavanoid_phenols": 0.26, "proanthocyanins": 1.28,
       "color_intensity": 4.38, "hue": 1.05,
       "od280/od315_of_diluted_wines": 3.4, "proline": 1050.0}}'
```
```json
{"model_version":"1.0.0","prediction":"class_0","prediction_index":0,
 "probabilities":{"class_0":0.9796,"class_1":0.0104,"class_2":0.01}}
```

## Evidence

See `evidence/` for captured, real request/response transcripts and logs:
- `request_response_transcript.txt` — every endpoint, success and failure paths
- `test_run_output.txt` — the full test suite passing (11/11)
- `blue_green_rollout_transcript.txt` — a live cutover + rollback demonstration
- `server.log`, `server_green.log`, `proxy.log` — raw process logs

## AI tool use declaration

Portions of this repository's scaffolding (Flask app structure, GitHub
Actions YAML, Dockerfile) were drafted with the assistance of an AI
coding assistant (Anthropic Claude) and reviewed/adapted by the author.
Model training approach, dataset choice and pipeline design decisions
are the author's own. Please adapt this declaration to reflect your
actual process, per your module and institutional AI-use policy.

## License / academic integrity

Submitted as coursework for DAM405. Dataset: UCI Wine recognition
dataset, distributed with scikit-learn (BSD-licensed).
# AS2025_DAM405_02230289_PA2
