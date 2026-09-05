# Screenshot capture guide

Thirteen screenshots are referenced in `report/REPORT.md` as `**[SCREENSHOT n — ...]**`
placeholders. Capture each one, save it as `report/screenshots/screenshot-NN-<slug>.png`,
and replace the placeholder block in the report with:

```markdown
![Caption](screenshots/screenshot-01-training.png)
*Figure 3 — Caption.*
```

**Before you start:** maximise the terminal, use a readable font size (14 pt+), and
capture the *command as well as its output* in the same frame — a screenshot of output
alone doesn't prove what produced it.

Screenshots 1–9 you can capture right now on your own machine. Screenshots 10–13 require
pushing to GitHub first (see §B).

---

## A. Local screenshots (1–9)

Run everything from the repository root with the virtualenv active:

```bash
cd "<repo root>"
source .venv/bin/activate
```

### SCREENSHOT 1 — Training run
*Proves training is reproducible and produces a versioned artefact.*
```bash
python model/train.py
```
Capture: the two "Saved …" lines and the accuracy/F1 line.

### SCREENSHOT 2 — Test suite passing
*Proves the API's logic and every error branch are covered.*
```bash
pytest tests/test_api.py -v
```
Capture: all 11 test lines with `PASSED` and the green `11 passed` summary. Scroll so the
summary and at least most test names are in one frame.

### SCREENSHOT 3 — Container running and healthy
*Proves the image starts and the container-level HEALTHCHECK works.*
```bash
docker build -t dam405-wine-predict-api:1.0.0 .
docker run -d -p 8000:8000 --name wine-api dam405-wine-predict-api:1.0.0
# wait ~15s for the HEALTHCHECK to report
docker ps
```
Capture: the `docker ps` row showing `STATUS` as `Up ... (healthy)`. **Wait for the
`(healthy)` marker** — a screenshot taken during `(health: starting)` is much weaker
evidence.

### SCREENSHOT 4 — A live prediction
*This is the assignment's "evidence the container serves correct predictions".*
```bash
curl -s -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"features": {"alcohol": 13.2, "malic_acid": 1.78, "ash": 2.14,
   "alcalinity_of_ash": 11.2, "magnesium": 100.0, "total_phenols": 2.65,
   "flavanoids": 2.76, "nonflavanoid_phenols": 0.26, "proanthocyanins": 1.28,
   "color_intensity": 4.38, "hue": 1.05,
   "od280/od315_of_diluted_wines": 3.4, "proline": 1050.0}}' | python -m json.tool
```
Capture: the full request and the pretty-printed JSON response showing `prediction`,
`probabilities` and `model_version`.

### SCREENSHOT 5 — Graceful error handling
*Proves input validation returns a helpful 4xx, not a 500.*
```bash
# missing a required feature
curl -s -i -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"features": {"alcohol": 13.2}}'

# wrong content type
curl -s -i -X POST http://localhost:8000/predict \
  -H "Content-Type: text/plain" -d 'not json'
```
Capture: both, showing `HTTP/1.1 400` with the `detail` naming the missing features, and
`HTTP/1.1 415`. The `-i` flag is what puts the status code in the frame — don't omit it.

### SCREENSHOT 6 — Image size
*Backs the containerisation best-practice claims in §4 of the report.*
```bash
docker images dam405-wine-predict-api
```
Optional but stronger — show the multi-stage saving by comparing against the non-slim
base:
```bash
docker images | grep -E "dam405|python"
```

### SCREENSHOT 7 — The full blue-green stack
*Proves the IaC file actually stands up the declared topology.*
```bash
docker compose up -d --build
docker compose ps
curl -s http://localhost:8080/health
```
Capture: `docker compose ps` showing all three services (`wine-api-blue`,
`wine-api-green`, `wine-api-proxy`) up, plus the healthy response through the proxy on
port 8080.

### SCREENSHOT 8 — Blue-green cutover
*The single most important rollout screenshot.*
```bash
curl -s http://localhost:8080/health          # served by BLUE
grep "server wine-api" deployment/nginx.conf  # shows blue is live
./deployment/switch_traffic.sh green
grep "server wine-api" deployment/nginx.conf  # now shows green
curl -s http://localhost:8080/health          # served by GREEN, still 200
```
Capture: the before/after `grep` lines around the script output, and a successful health
response on **both** sides of the cutover. That pairing is what demonstrates zero
downtime — the script output alone doesn't.

### SCREENSHOT 9 — Rollback
```bash
./deployment/rollback.sh blue
grep "server wine-api" deployment/nginx.conf
curl -s http://localhost:8080/health
```
Capture: the rollback output including its verification smoke test passing, and the
config back on blue.

Tear down when done:
```bash
docker compose down
docker rm -f wine-api
```

---

## B. GitHub screenshots (10–13)

These need the repo pushed to GitHub, and screenshots 12–13 need one push to `main`.

### One-time setup

1. **Create the repository on GitHub** (named e.g. `AS2025_DAM405_02230289_PA2`).
2. **Update the image source label.** `Dockerfile` still contains a placeholder:
   ```
   org.opencontainers.image.source="https://github.com/<your-org>/<your-repo>"
   ```
   Replace it with your real repository URL before pushing — a marker may notice it.
3. **Create the `production` environment** — this is what produces SCREENSHOT 13:
   *Settings → Environments → New environment → name it `production` →
   tick **Required reviewers** → add yourself → Save.*
   Without this the deploy job runs unattended and there is no approval gate to show.
4. **Allow the workflow to publish packages:**
   *Settings → Actions → General → Workflow permissions → **Read and write permissions***.
5. Push:
   ```bash
   git remote add origin https://github.com/<you>/AS2025_DAM405_02230289_PA2.git
   git push -u origin main
   ```

### SCREENSHOT 10 — A green pipeline run
*Actions* tab → the run for your push. Capture the run summary page showing all four
jobs (`lint-and-test`, `build-and-container-test`, `publish`, `deploy-blue-green`) with
green ticks and the dependency graph between them. **This is the key LO5 evidence** —
if you capture only one GitHub screenshot, make it this one.

### SCREENSHOT 11 — The container test stage
Open the `build-and-container-test` job and expand the **Container smoke test** step.
Capture the log showing the `[PASS]` lines and `All 5 smoke checks passed.` This proves
the pipeline tests a *running container over HTTP*, not just the code.

### SCREENSHOT 12 — The published image
Repository main page → **Packages** (right sidebar) → click the package. Capture the page
showing `dam405-wine-predict-api` with both the commit-SHA tag and `latest`.
Alternatively capture the *Push Docker image* step log showing the digest.

### SCREENSHOT 13 — The approval gate
With required reviewers configured, the `deploy-blue-green` job pauses. Capture the run
page showing **"Review pending deployments"** / the `production` environment awaiting
approval. This is the evidence that your pipeline is *continuous delivery with a human
gate* rather than unreviewed auto-deploy — a point the report argues explicitly in §3.

---

## C. Checklist

| # | Screenshot | Where | Report §  |
|---|---|---|---|
| 1 | Training run | local | 7.1 |
| 2 | 11 tests passing | local | 7.2 |
| 3 | `docker ps` healthy | local | 7.3 |
| 4 | Live prediction | local | 7.3 |
| 5 | Error handling 400/415 | local | 7.3 |
| 6 | Image size | local | 7.4 |
| 7 | Compose stack up | local | 7.5 |
| 8 | Blue-green cutover | local | 7.5 |
| 9 | Rollback | local | 7.5 |
| 10 | Green Actions run | GitHub | 7.6 |
| 11 | Container smoke test log | GitHub | 7.6 |
| 12 | Published GHCR image | GitHub | 7.6 |
| 13 | Production approval gate | GitHub | 7.6 |

**If you are short on time**, the four that carry the most marks are
**2** (tests), **4** (a real prediction), **8** (the cutover) and **10** (the green
pipeline) — they map directly to the four functional requirements in the brief.
