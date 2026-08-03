# API + netpol + ingress + HPA

- `api.yaml` — Deployment (image `lokeshwarreddyyarava/qoves-api:v1.0.1`), Service, Ingress for `qoves.local`, HPA
- `networkpolicies.yaml` — default deny plus the allow rules I need

API reads `DATABASE_URL` from Secret `qoves-db`.
