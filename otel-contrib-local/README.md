# otel-contrib-local

Local playground for testing changes to `opentelemetry-collector-contrib` receiver components against a real Postgres instance, with metrics visible in Prometheus and Grafana.

## Architecture

```
Postgres → postgresqlreceiver → prometheus exporter → :9464/metrics ← Prometheus → Grafana
```

| Service    | URL                          |
|------------|------------------------------|
| Metrics    | http://localhost:9464/metrics |
| Prometheus | http://localhost:9090         |
| Grafana    | http://localhost:3000         |

## Prerequisites

- Docker with BuildKit enabled
- Local clone of `opentelemetry-collector-contrib` at `/Users/kartikgola/github.com/kartikgola/opentelemetry-collector-contrib`

The `additional_contexts` in `docker-compose.yaml` points to that path. Update it if your clone is elsewhere.

## First-time setup

```bash
docker compose up -d
```

The first build takes a few minutes — it compiles the collector from source.

## Making and testing local changes

### 1. Edit the receiver source

Changes go in the local `opentelemetry-collector-contrib` clone. For example:

```
/Users/kartikgola/github.com/kartikgola/opentelemetry-collector-contrib/receiver/postgresqlreceiver/client.go
```

### 2. Add a replace directive for the component you changed

`otelcol-builder-config.yaml` must have a replace entry for every component module you modify. `opentelemetry-collector-contrib` is a **multi-module repo** — each component has its own `go.mod`, so a top-level replace is not enough.

Example: if you changed `postgresqlreceiver`, ensure both entries exist in `otelcol-builder-config.yaml`:

```yaml
replaces:
  - github.com/open-telemetry/opentelemetry-collector-contrib => /workspace/opentelemetry-collector-contrib
  - github.com/open-telemetry/opentelemetry-collector-contrib/receiver/postgresqlreceiver => /workspace/opentelemetry-collector-contrib/receiver/postgresqlreceiver
```

To find a component's module path, check its `go.mod`:

```bash
head -1 receiver/postgresqlreceiver/go.mod
# module github.com/open-telemetry/opentelemetry-collector-contrib/receiver/postgresqlreceiver
```

### 3. Rebuild and redeploy

```bash
# Clear BuildKit cache first — required to pick up source changes.
# --no-cache alone is NOT enough because Go's build cache mount persists across builds.
docker buildx prune -f

docker compose build --no-cache otelcol
docker compose up -d otelcol
```

### 4. Verify the fix is in the binary

Before redeploying, confirm your change made it into the compiled binary:

```bash
docker run --rm --entrypoint="" otel-contrib-local-otelcol:latest grep -ac "some string from your change" /otelcontribcol
# should print 1
```

If it prints 0, the binary doesn't have your change — re-check the replace directives and repeat step 3.

### 5. Check metrics

```bash
curl -s http://localhost:9464/metrics | head -30
```

## Debugging empty metrics

If `http://localhost:9464/metrics` returns nothing:

**Check for blocked receiver connections:**
```bash
docker exec otel-contrib-local-postgres-1 psql -U root -d postgres \
  -c "SELECT pid, wait_event, datname, left(query,60) FROM pg_stat_activity WHERE usename='otelu'"
```

If connections show `wait_event = relation`, the receiver is blocked by a lock on a user table. Common causes:
- `VACUUM FULL` running
- `ALTER TABLE` / `TRUNCATE` in progress
- An orphaned prepared transaction (check `SELECT * FROM pg_prepared_xacts`)
- An open transaction holding `LOCK TABLE ... IN ACCESS EXCLUSIVE MODE`

**Check for orphaned prepared transactions:**
```bash
docker exec otel-contrib-local-postgres-1 psql -U root -d postgres \
  -c "SELECT * FROM pg_prepared_xacts"
```

Roll back any orphaned ones:
```bash
docker exec otel-contrib-local-postgres-1 psql -U root -d postgres \
  -c "ROLLBACK PREPARED 'name_from_above'"
```

**Check otelcol logs:**
```bash
docker compose logs otelcol | grep -v "signal.*logs\|resource logs"
```

## Common pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| Binary doesn't contain your change after rebuild | Go build cache mount survives `--no-cache` | Run `docker buildx prune -f` before rebuilding |
| Change compiles but has no effect | Component has its own `go.mod` but no replace directive for it | Add the component-level replace to `otelcol-builder-config.yaml` |
| All metrics go dark | `AccessExclusiveLock` on a user table blocks `pg_relation_size` in the receiver | Release the lock or apply the xlock filter fix |
| `database.locks` metric never shows a lock | Same as above — the blocked collection prevents the locks scraper from running | Same fix |
