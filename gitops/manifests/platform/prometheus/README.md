# Prometheus

Scrapes the API `/metrics`. Alert `ApiDatabaseUnreachable` if `qoves_db_up` stays 0 for 5m.
Image: `prom/prometheus:v2.54.1`.
