"""QOVES take-home API.

GET /         hello
GET /healthz  SELECT 1 against Postgres (200 / 503)
GET /metrics  Prometheus format

DATABASE_URL comes from the environment (Secret at runtime). Not hard-coded.
"""

from __future__ import annotations

import os
import threading
import time
from contextlib import contextmanager

import psycopg
from fastapi import FastAPI, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

DATABASE_URL = os.getenv("DATABASE_URL")

REQUESTS = Counter(
    "qoves_http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)
LATENCY = Histogram(
    "qoves_http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
)
DB_UP = Gauge(
    "qoves_db_up",
    "1 if the API can run SELECT 1 against Postgres, else 0",
)

# keep only the three routes from the brief
app = FastAPI(
    title="qoves-api",
    version="1.0.1",
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)


def _check_db() -> bool:
    try:
        with db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
        return True
    except Exception:
        return False


def _db_probe_loop() -> None:
    while True:
        DB_UP.set(1 if _check_db() else 0)
        time.sleep(15)


@app.on_event("startup")
def start_db_probe() -> None:
    t = threading.Thread(target=_db_probe_loop, name="db-probe", daemon=True)
    t.start()


@contextmanager
def db_connection():
    if not DATABASE_URL:
        raise RuntimeError("DATABASE_URL is not set")
    conn = psycopg.connect(DATABASE_URL, connect_timeout=3)
    try:
        yield conn
    finally:
        conn.close()


@app.get("/")
def hello() -> dict[str, str]:
    start = time.perf_counter()
    status = "200"
    try:
        return {"message": "hello from the QOVES take-home API"}
    finally:
        LATENCY.labels("GET", "/").observe(time.perf_counter() - start)
        REQUESTS.labels("GET", "/", status).inc()


@app.get("/healthz")
def healthz(response: Response) -> dict[str, str]:
    start = time.perf_counter()
    status = "200"
    try:
        with db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
        return {"status": "ok"}
    except Exception as exc:
        status = "503"
        response.status_code = 503
        return {"status": "unavailable", "error": str(exc)}
    finally:
        LATENCY.labels("GET", "/healthz").observe(time.perf_counter() - start)
        REQUESTS.labels("GET", "/healthz", status).inc()


@app.get("/metrics")
def metrics() -> Response:
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
