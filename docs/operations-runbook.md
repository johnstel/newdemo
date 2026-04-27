# Operations Runbook — Azure Cosmos DB Backup Demo

**Date:** 2026-04-27  
**Status:** Demo-ready  
**Audience:** Operators, on-call engineers

> For restore procedures see [Restore & Validation](restore-and-validation.md).  
> For full backup procedures see [Backup & Restore Runbook](backup-restore-runbook.md).

---

## Quick Reference

| Task | Command |
|------|---------|
| Deploy | `az deployment sub create --template-file infra/main.bicep ...` |
| Smoke check | `bash scripts/validate-deployment.sh` |
| Check ingestion | `bash scripts/validate-ingestion.sh` |
| Check backup | `bash scripts/validate-backup.sh` |
| Trigger restore | `bash scripts/validate-restore.sh` |
| Teardown demo | `bash scripts/teardown.sh` |
| Verify cleanup | `bash scripts/validate-cleanup.sh` |

---

## Daily Operations

### Confirming Ingestion is Running

The weather ingestor writes one document every 20 seconds. Validate with:

```bash
bash scripts/validate-ingestion.sh
```

If ingestion has stopped, check Container App logs:

```bash
az containerapp logs show \
  --name "${PREFIX}-ingestor-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --tail 50
```

### Confirming Export Jobs are Running

The backup exporter runs every 6 hours via Container App Job schedule (`0 */6 * * *`).

```bash
# List recent job executions
az containerapp job execution list \
  --name "${PREFIX}-exporter-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --output table

# View logs for most recent execution
az containerapp job execution show \
  --name "${PREFIX}-exporter-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --job-execution-name <execution-name>
```

### Confirming Blobs are Reaching Retention Storage

```bash
RETENTION_STORAGE="${PREFIX//[-_]/}ret${ENV}"

az storage blob list \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports" \
  --auth-mode login \
  --output table | tail -10
```

---

## Alert Responses

### Alert: Cosmos 429 Throttling

**Cause:** Request units (RUs) exhausted — ingestor is writing faster than provisioned throughput.

**Action:**
1. Check current RU consumption in Azure Portal → Cosmos DB → Metrics → Total Request Units.
2. For serverless: this is expected at high burst rate; requests will retry automatically.
3. For provisioned throughput: increase RU setting in `infra/modules/cosmos.bicep` and redeploy.

### Alert: Ingestion Gap (no writes for >2 min)

**Cause:** Container App replica stopped or crashed.

**Action:**
```bash
# Check replica status
az containerapp show \
  --name "${PREFIX}-ingestor-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --query "properties.runningStatus" -o tsv

# Restart by updating a dummy env var to trigger revision
az containerapp update \
  --name "${PREFIX}-ingestor-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --set-env-vars "RESTART_TS=$(date +%s)"
```

### Alert: Export Job Failure

**Cause:** Exporter Container App Job exited non-zero.

**Action:**
```bash
# Find the failed execution
az containerapp job execution list \
  --name "${PREFIX}-exporter-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --query "[?properties.status=='Failed']" -o table

# View failure logs
az containerapp job execution show \
  --name "${PREFIX}-exporter-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --job-execution-name <failed-execution-name>
```

Common causes: RBAC not propagated yet (wait 5–10 minutes after deploy), container image not pushed to ACR.

---

## Routine Maintenance

### Updating Container Images

```bash
ACR=$(az acr list --resource-group "${PREFIX}-demo-${ENV}-rg" --query "[0].loginServer" -o tsv)
az acr login --name "${ACR%%.*}"

docker build -t "$ACR/weather-ingestor:latest" apps/weather-ingestor/ && docker push "$ACR/weather-ingestor:latest"
docker build -t "$ACR/backup-exporter:latest" apps/backup-exporter/ && docker push "$ACR/backup-exporter:latest"

# Trigger new Container Apps revision
az containerapp update --name "${PREFIX}-ingestor-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --image "$ACR/weather-ingestor:latest"
```

### Checking Cost

```bash
az consumption usage list \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --query "[].{service:instanceName, cost:pretaxCost}" \
  -o table
```

---

## Escalation Path

1. Review Container App logs and alert details.
2. Run `bash scripts/validate-deployment.sh` to identify which component is unhealthy.
3. Check Log Analytics workspace (`{prefix}-law-{env}`) for correlated errors.
4. If data loss is suspected, initiate PITR restore — see [Restore & Validation](restore-and-validation.md).

---

## Related Documents

- [Deployment Guide](deployment-guide.md) — Initial setup
- [Backup & Retention](backup-and-retention.md) — Backup tier configuration
- [Restore & Validation](restore-and-validation.md) — Restore procedures
- [Cleanup Guide](cleanup.md) — Safe teardown
