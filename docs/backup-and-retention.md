# Backup & Retention — Azure Cosmos DB Demo

**Date:** 2026-04-27  
**Status:** Demo-ready  
**Audience:** Operators, DBAs, compliance reviewers

> For step-by-step restore procedures see [Restore & Validation](restore-and-validation.md).  
> For full operational procedures see [Backup & Restore Runbook](backup-restore-runbook.md).

---

## Overview: Two-Tier Backup Strategy

This demo implements two complementary backup tiers:

| Tier | Mechanism | Retention | RTO | RPO |
|------|-----------|-----------|-----|-----|
| **Hot (native PITR)** | Cosmos DB Continuous Backup | 7–30 days | ~1 hour | ~1 minute |
| **Cold (custom archive)** | Scheduled JSON exports → immutable Blob Storage | Up to 7 years | Hours–days | 6 hours |

---

## Tier 1 — Native Cosmos DB PITR

### How It Works

Azure Cosmos DB Continuous Backup takes automatic incremental backups of all writes in real time. Point-in-time restore (PITR) creates a **new Cosmos account** from the backup at any timestamp within the retention window.

### Configuration

| Setting | Value (dev) | Value (prod) |
|---------|------------|-------------|
| `backupPolicy.type` | `Continuous` | `Continuous` |
| `continuousModeProperties.tier` | `Continuous30Days` | `Continuous7Days` |
| `disableLocalAuth` | `true` | `true` |

> ⚠️ **Important:** PITR restores to a **new account**. The original account is unaffected. DNS, connection strings, and RBAC must be updated manually after restore.

### Verifying the Policy

```bash
az cosmosdb show \
  --name "${PREFIX}-cosmos-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --query "backupPolicy" -o json
```

---

## Tier 2 — Custom Archive (WORM Export)

### How It Works

A scheduled **Container App Job** (the `backup-exporter`) runs every 6 hours and:

1. Queries Cosmos DB for documents in the most recent 6-hour aligned window
2. Serializes them to JSONL format
3. Computes a SHA-256 hash and writes a manifest
4. Uploads `data.jsonl` + `manifest.json` to **both** storage accounts:
   - **Export storage** (`{prefix}exp{env}`) — in the primary RG, lifecycle-tiered to Cool → Archive
   - **Retention storage** (`{prefix}ret{env}`) — in the separate retention RG, WORM immutable

### Blob Path Format

```
exports/{yyyy}/{MM}/{dd}/{HH}-{mm}/data.jsonl
exports/{yyyy}/{MM}/{dd}/{HH}-{mm}/manifest.json
```

Example: `exports/2026/04/27/06-00/data.jsonl`

### Storage Account Names (Bicep-computed)

| Variable | Formula | Example (`cosmos-backup`, `dev`) |
|----------|---------|----------------------------------|
| Export | `{prefix-no-hyphens}exp{env}` | `cosmosbackupexpdev` |
| Retention | `{prefix-no-hyphens}ret{env}` | `cosmosbackupretdev` |

### WORM Immutability

The retention storage container uses **version-level immutability** (Azure Blob Storage immutable storage):

- Container: `exports`
- Policy: `immutabilityPeriodSinceCreationInDays: 1` (demo-friendly; extend for production)
- `allowProtectedAppendWrites: false` — strictest WORM mode
- Policy is **unlocked** by default so the demo can be redeployed; lock it in production

> ⚠️ **Compliance disclaimer:** This WORM pattern demonstrates the *architecture* of long-term immutable retention. It does not constitute a certified compliance solution. Consult your compliance team for regulatory requirements.

---

## Lifecycle Policy (Export Storage)

Blobs in the export storage are automatically tiered:

| Days After Write | Tier |
|-----------------|------|
| 0–7 | Hot |
| 7–30 | Cool |
| 30–2555 | Archive |
| >2555 (~7 years) | Deleted |

---

## Manifest Structure

Each export bundle includes a `manifest.json` with:

```json
{
  "windowStart": "2026-04-27T00:00:00.000Z",
  "windowEnd":   "2026-04-27T06:00:00.000Z",
  "exportTimestamp": "2026-04-27T06:01:23.456Z",
  "itemCount": 1080,
  "sha256": "abc123...",
  "cosmosDatabase": "demo",
  "cosmosContainer": "weather",
  "source": "cosmos-backup-cosmos-dev"
}
```

The SHA-256 hash is computed over the raw JSONL bytes and can be used to verify integrity of archived data.

---

## Monitoring Alerts

Three Azure Monitor alerts are configured:

| Alert | Condition | Severity |
|-------|-----------|----------|
| Cosmos 429 Throttling | Request rate limited | 2 |
| Ingestion Gap | No writes for >2 min | 2 |
| Export Job Failure | Container job exits non-zero | 1 |

See the Log Analytics workspace (`{prefix}-law-{env}`) for raw telemetry.

---

## Related Documents

- [Restore & Validation](restore-and-validation.md) — How to restore from each tier
- [Backup & Restore Runbook](backup-restore-runbook.md) — Full operational procedures
- [Architecture](architecture.md) — System design and data flow
