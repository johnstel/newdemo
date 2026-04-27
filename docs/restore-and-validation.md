# Restore & Validation — Azure Cosmos DB Demo

**Date:** 2026-04-27  
**Status:** Demo-ready  
**Audience:** Operators, DBAs, incident responders

> For backup configuration details see [Backup & Retention](backup-and-retention.md).  
> For full runbook procedures see [Backup & Restore Runbook](backup-restore-runbook.md).

---

## Restore Paths

| Scenario | Tier Used | Procedure |
|----------|-----------|-----------|
| Recent data loss (<30 days) | Native PITR | Section 1 |
| Long-term archive restore (>30 days) | Custom WORM export | Section 2 |
| Verify backup health | Both | Section 3 |

---

## 1. Native PITR Restore (Cosmos DB)

### When to Use

- Data corruption or accidental deletion within the last 7–30 days
- Point-in-time recovery to a known-good state

### Procedure

```bash
# Set variables
COSMOS_ACCOUNT="${PREFIX}-cosmos-${ENV}"
RESOURCE_GROUP="${PREFIX}-demo-${ENV}-rg"
RESTORE_ACCOUNT="${PREFIX}-restored-${ENV}"
RESTORE_TIMESTAMP="2026-04-27T06:00:00Z"   # adjust to desired point in time

# Trigger PITR restore to a new account
az cosmosdb restore \
  --account-name "$COSMOS_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --target-database-account-name "$RESTORE_ACCOUNT" \
  --restore-timestamp "$RESTORE_TIMESTAMP" \
  --location eastus2
```

> ⚠️ Restore creates a **new Cosmos account**. The original account is untouched. Expect 15–60 minutes for the restore to complete for demo-sized datasets.

### Verify Restore

```bash
# Check restore status
az cosmosdb show \
  --name "$RESTORE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "provisioningState" -o tsv

# Count documents in restored account
az cosmosdb sql container show \
  --account-name "$RESTORE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --database-name "demo" \
  --name "weather" \
  --query "resource.partitionKey.paths" -o tsv
```

### Run Automated Validation

```bash
PREFIX=$PREFIX ENV=$ENV bash scripts/validate-restore.sh
```

### Post-Restore Cleanup

```bash
# Delete the temporary restore account when done
az cosmosdb delete \
  --name "$RESTORE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --yes
```

---

## 2. Archive Restore (WORM Export)

### When to Use

- Data older than the PITR retention window (>30 days)
- Compliance audit requiring historical data export
- Re-importing specific time windows

### Locate the Archive Blob

```bash
RETENTION_STORAGE="${PREFIX//[-_]/}ret${ENV}"   # e.g. cosmosbackupretdev
RETENTION_RG="${PREFIX}-retention-${ENV}-rg"
TARGET_WINDOW="exports/2026/01/15/06-00"        # adjust to desired window

# List blobs in target window
az storage blob list \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports" \
  --prefix "$TARGET_WINDOW/" \
  --auth-mode login \
  --output table
```

### Download and Verify Integrity

```bash
# Download data and manifest
az storage blob download \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports" \
  --name "${TARGET_WINDOW}/data.jsonl" \
  --file restore-data.jsonl \
  --auth-mode login

az storage blob download \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports" \
  --name "${TARGET_WINDOW}/manifest.json" \
  --file restore-manifest.json \
  --auth-mode login

# Verify SHA-256 integrity
EXPECTED_SHA=$(jq -r '.sha256' restore-manifest.json)
ACTUAL_SHA=$(shasum -a 256 restore-data.jsonl | awk '{print $1}')

if [[ "$EXPECTED_SHA" == "$ACTUAL_SHA" ]]; then
  echo "PASS: SHA-256 matches — data integrity confirmed"
else
  echo "FAIL: SHA-256 mismatch — data may be corrupted"
fi
```

### Re-import to Cosmos DB

JSONL files can be imported with the Azure Cosmos DB Bulk Executor or the [Azure Cosmos DB Data Migration Tool](https://aka.ms/cosmosdb-datamigration).

```bash
# Example using jq + az cosmosdb (small datasets)
while IFS= read -r doc; do
  az cosmosdb sql document create \
    --account-name "$COSMOS_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --database-name "demo" \
    --container-name "weather" \
    --body "$doc"
done < restore-data.jsonl
```

---

## 3. Backup Health Validation

### Automated Checks

```bash
# Pre-deployment (no Azure auth needed)
bash scripts/validate-local.sh

# Post-deployment smoke check
PREFIX=$PREFIX ENV=$ENV bash scripts/validate-deployment.sh

# Backup policy and WORM immutability
PREFIX=$PREFIX ENV=$ENV bash scripts/validate-backup.sh

# Ingestion health (documents flowing)
bash scripts/validate-ingestion.sh
```

### Manual Spot Checks

```bash
# Confirm backup policy is Continuous
az cosmosdb show \
  --name "${PREFIX}-cosmos-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --query "backupPolicy" -o json

# Confirm export blobs exist in retention storage
az storage blob list \
  --account-name "${PREFIX//[-_]/}ret${ENV}" \
  --container-name "exports" \
  --auth-mode login \
  --output table | head -20
```

---

## Related Documents

- [Backup & Retention](backup-and-retention.md) — How backups are configured
- [Backup & Restore Runbook](backup-restore-runbook.md) — Full operational procedures  
- [Operations Runbook](operations-runbook.md) — Day-to-day operations
