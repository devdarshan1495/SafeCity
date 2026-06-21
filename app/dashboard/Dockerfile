# ── SafeCity Dashboard ───────────────────────────────────────────
# Multi-stage build · Non-root · Health-checked
# ─────────────────────────────────────────────────────────────────

FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Runtime ──────────────────────────────────────────────────────

FROM python:3.12-slim

LABEL maintainer="SafeCity DevOps Team"
LABEL description="SafeCity Public Safety Dashboard"

COPY --from=builder /install /usr/local

RUN groupadd -r safecity && useradd -r -g safecity -d /app -s /sbin/nologin safecity

WORKDIR /app
COPY . .

RUN chown -R safecity:safecity /app
USER safecity

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "120", "app:app"]
