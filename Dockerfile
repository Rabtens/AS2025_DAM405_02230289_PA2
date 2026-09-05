# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1: builder — installs dependencies into a virtualenv.
# Kept separate from the runtime stage so build tools (gcc, headers, pip
# cache) never end up in the final image, which is the main lever for
# keeping the shipped image small.
# ---------------------------------------------------------------------------
FROM python:3.12-slim AS builder

WORKDIR /build

# Only the dependency manifest is copied first. Docker caches this layer
# and only re-installs packages when requirements.txt actually changes,
# instead of on every source-code edit.
COPY requirements.txt .

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ---------------------------------------------------------------------------
# Stage 2: runtime — slim image, non-root user, only what's needed to serve.
# ---------------------------------------------------------------------------
FROM python:3.12-slim AS runtime

# Metadata (visible via `docker inspect`)
LABEL org.opencontainers.image.title="dam405-wine-predict-api" \
      org.opencontainers.image.description="Wine cultivar classifier prediction service (DAM405 Assignment 2)" \
      org.opencontainers.image.source="https://github.com/Rabtens/AS2025_DAM405_02230289_PA2"

# Create an unprivileged user/group to run the process as (never run as root).
RUN groupadd --gid 1000 appuser && \
    useradd --uid 1000 --gid appuser --shell /bin/false --create-home appuser

# Bring in the pre-built virtualenv from the builder stage only —
# no compilers, caches or build artefacts are carried over.
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

WORKDIR /app

# Application code and the pre-trained model artefact are copied last,
# since they change most often — this keeps the expensive dependency
# layer above cached across most CI runs.
COPY app/ ./app/
COPY model/model.joblib model/metadata.json ./model/

# Hand ownership of the app directory to the non-root user and drop
# privileges for every subsequent instruction and at runtime.
RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# Container-level health check, polled by the Docker/orchestrator runtime
# independently of the app's own /health route logic.
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status==200 else 1)"

# gunicorn: production WSGI server, 2 workers is enough for this small model;
# tune via GUNICORN_WORKERS at deploy time if needed.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-", "app.main:app"]
