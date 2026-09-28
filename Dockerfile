# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (production-ready)
#
#   Stage 1 `builder`: tạo virtualenv ở /opt/venv và cài dependency.
#   Stage 2 `runtime`: chỉ copy /opt/venv + source code sang một image
#                      slim sạch → không mang theo cache pip, build tool.
#
# Build:  docker build -t day12-agent:prod .
# Run:    docker run --rm -p 8000:8000 --env-file .env day12-agent:prod
# ═══════════════════════════════════════════════════════════════════

# ── Stage 1: builder ───────────────────────────────────────────────
FROM python:3.11-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /build

# Chỉ copy requirements.txt trước → layer cài thư viện được cache,
# sửa code không làm pip install chạy lại.
COPY requirements.txt .
RUN pip install -r requirements.txt


# ── Stage 2: runtime ───────────────────────────────────────────────
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# User thường, UID cố định 10001 (không trùng user nào trên host)
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --chown=app:app app/ ./app/
COPY --chown=app:app utils/ ./utils/

USER app

EXPOSE 8000

# Image slim không có curl → dùng python stdlib để gọi /health
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT', '8000'), timeout=3)" || exit 1

# sh -c để nội suy ${PORT:-8000} (cloud tự gán PORT);
# exec để uvicorn thành PID 1 và nhận SIGTERM trực tiếp → graceful shutdown.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
