# App

HTTP API for the take-home. Three routes only:

| Method | Path | Behavior |
|--------|------|----------|
| GET | `/` | hello |
| GET | `/healthz` | `SELECT 1` against Postgres |
| GET | `/metrics` | Prometheus metrics |

I turned off FastAPI's default `/docs` / `/redoc` / OpenAPI so random extra
routes do not show up.

Needs `DATABASE_URL` at runtime.

```bash
pip install -r requirements.txt
export DATABASE_URL='postgresql://app:...@localhost:5432/app'
uvicorn main:app --host 0.0.0.0 --port 8080
```

```bash
docker build -t lokeshwarreddyyarava/qoves-api:v1.0.1 .
```
