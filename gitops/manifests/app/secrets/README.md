# Sealed secret for the app

Only ciphertext goes in git. File: `qoves-db.sealedsecret.yaml`
(`DATABASE_URL`, `POSTGRES_PASSWORD`).

```bash
export POSTGRES_PASSWORD="$(openssl rand -base64 24)"
./scripts/seal-db-secret.sh
unset POSTGRES_PASSWORD
```

After a cluster recreate, seal again (new key).
