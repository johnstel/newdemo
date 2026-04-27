# Architecture — Azure Cosmos DB Backup & Recovery Demo

**Date:** 2026-04-27  
**Status:** Demo-ready  
**Audience:** Technical leads, architects, operators

---

## 1. System Overview

This demo implements a **two-tier backup strategy** for Azure Cosmos DB:

- **Tier 1 (Hot):** Native Cosmos DB continuous backup (PITR) — 7 or 30 days
- **Tier 2 (Cold):** Custom exports to immutable Blob Storage — up to 7 years

Data flows from an **ingestion workload** (writing weather documents) into **Cosmos DB**, which is backed up via:
- **Native PITR** (automatic, included in Cosmos pricing)
- **Scheduled exports** (every 6 hours, custom job to Blob Storage)

Both paths are monitored via **Azure Monitor**, with alerts for throttling and ingestion gaps.

---

## 2. Architecture Diagram

```
┌───────────────────────────────────────────────────────────────────────┐
│                         Azure Subscription                             │
├───────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────────────────── PRIMARY DEMO RG ─────────────────┐ │
│  │ {prefix}-demo-{env}-rg                                           │ │
│  │                                                                   │ │
│  │  ┌─────────────────────────┐                                   │ │
│  │  │ Managed Identities      │                                   │ │
│  │  ├─────────────────────────┤                                   │ │
│  │  │ • ingestor-identity     │                                   │ │
│  │  │ • exporter-identity     │                                   │ │
│  │  └─────────────────────────┘                                   │ │
│  │           │                                                      │ │
│  │  ┌────────┴────────────────────────────┐                       │ │
│  │  │                                      │                       │ │
│  │  ▼                                      ▼                       │ │
│  │ ┌──────────────────────┐        ┌──────────────────────┐      │ │
│  │ │ Ingestion Container  │        │ Export Container Job │      │ │
│  │ │ (Container Apps/ACI) │        │ (Scheduled Trigger)  │      │ │
│  │ │                      │        │                      │      │ │
│  │ │ • Timer-based        │        │ • Every 6 hours      │      │ │
│  │ │ • 20s interval       │        │ • Reads Cosmos       │      │ │
│  │ │ • Synthetic weather  │        │ • Writes manifest    │      │ │
│  │ │ • Managed identity   │        │ • SHA-256 hash       │      │ │
│  │ └──────────┬───────────┘        └──────────┬───────────┘      │ │
│  │            │                                │                  │ │
│  │            │ (via RBAC +                    │ (via RBAC +      │ │
│  │            │  managed identity)             │  managed identity)
│  │            │                                │                  │ │
│  │            ▼                                ▼                  │ │
│  │  ┌─────────────────────────────────────────────────────┐      │ │
│  │  │          Cosmos DB Account                           │      │ │
│  │  ├─────────────────────────────────────────────────────┤      │ │
│  │  │ • Continuous Backup: Continuous30Days              │      │ │
│  │  │ • Database: demo                                    │      │ │
│  │  │ • Container: weather (partition key: /cityId)      │      │ │
│  │  │ • Managed identity for ingestor (data-plane RBAC)  │      │ │
│  │  │ • No account keys; RBAC only                       │      │ │
│  │  └─────────────────────────────────────────────────────┘      │ │
│  │            │                         │                        │ │
│  │   ┌────────┴─ PITR restore           │                        │ │
│  │   │          (on-demand)             │                        │ │
│  │   │                            ┌─────┴──────────┐             │ │
│  │   │                            │                │             │ │
│  │   │                            ▼                ▼             │ │
│  │   │                   ┌──────────────────────────────┐        │ │
│  │   │                   │ Export Storage Account       │        │ │
│  │   │                   │ ({prefix}exportsdev...)      │        │ │
│  │   │                   ├──────────────────────────────┤        │ │
│  │   │                   │ • Cool tier (7 days)         │        │ │
│  │   │                   │ • Archive tier (30+ days)    │        │ │
│  │   │                   │ • Lifecycle: Cool→Archive    │        │ │
│  │   │                   │ • No versioning (export tier)│        │ │
│  │   │                   │ • Path: exports/{yyyy}/{MM}/ │        │ │
│  │   │                   │         {dd}/{HH}-{mm}/      │        │ │
│  │   │                   └──────────────────────────────┘        │ │
│  │   │                            │                              │ │
│  │   │  ┌────────────────────────┴──────────────┐               │ │
│  │   │  │ (Copy to retention RG at end-of-day) │               │ │
│  │   │  └────────────────────────┬──────────────┘               │ │
│  │   │                           │                              │ │
│  │   │  ┌─────────────────────────┴────────────────┐            │ │
│  │   │  │ Monitoring                               │            │ │
│  │   │  ├─────────────────────────────────────────┤            │ │
│  │   │  │ • Log Analytics Workspace                │            │ │
│  │   │  │ • Cosmos diag settings → LAW             │            │ │
│  │   │  │ • Storage diag settings → LAW            │            │ │
│  │   │  │ • Container logs → LAW                   │            │ │
│  │   │  │ • Alerts: 429s, ingestion gap, export err│            │ │
│  │   │  └─────────────────────────────────────────┘            │ │
│  │   │                                                           │ │
│  │   │  ┌─────────────────────────────────────────┐            │ │
│  │   │  │ Key Vault (provisioned, empty in v1)     │            │ │
│  │   │  └─────────────────────────────────────────┘            │ │
│  │   │                                                           │ │
│  └─┬─┴──────────────────────────────────────────────────────────┘ │
│    │                                                               │
│    │                                                               │
│  ┌─┴──────────────────────── RETENTION RG ──────────────────────┐ │
│  │ {prefix}-retention-{env}-rg                                  │ │
│  │ (NOT deleted during demo teardown)                           │ │
│  │                                                               │ │
│  │  ┌──────────────────────────────────────────────────────┐   │ │
│  │  │ Immutable Storage Account                            │   │ │
│  │  │ ({prefix}retentiondev...)                            │   │ │
│  │  ├──────────────────────────────────────────────────────┤   │ │
│  │  │ • Version-level immutability (1-day minimum, demo)    │   │ │
│  │  │ • WORM versioning enabled                            │   │ │
│  │  │ • Soft delete disabled (production: enable)          │   │ │
│  │  │ • Can be extended to 7 years (2555-day param)        │   │ │
│  │  │ • Container: exports-archive/                        │   │ │
│  │  │ • Content: nightly copy of exports from primary RG  │   │ │
│  │  │ • Legal hold capability (not enabled by default)    │   │ │
│  │  └──────────────────────────────────────────────────────┘   │ │
│  │                                                               │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Data Flow — Ingestion

```
Every 20 seconds:
1. Ingestion container wakes up
2. Generates synthetic weather JSON (cityId, temp, humidity, timestamp)
3. Uses managed identity to acquire token
4. POST to Cosmos DB (weather collection)
5. Logs success/failure
6. Sleeps 20 seconds
```

**Example ingestion document:**

```json
{
  "id": "weather-nyc-2026-04-27T11-47-49",
  "cityId": "nyc",
  "temperature": 72.5,
  "humidity": 65,
  "timestamp": "2026-04-27T11:47:49Z",
  "_ts": 1704067669,
  "_etag": "...",
  "_rid": "..."
}
```

**Authentication:**  
- Managed identity (system-assigned or user-assigned)
- `@azure/identity` `DefaultAzureCredential`
- Cosmos DB data-plane RBAC: `Cosmos DB Built-in Data Contributor`

**Error handling:**
- 429 (throttled) — retry with exponential backoff
- 400 (bad document) — log and skip
- Network timeout — log and retry next interval
- Graceful shutdown on SIGINT/SIGTERM

---

## 4. Native Backup — Cosmos DB Continuous Backup (PITR)

### 4.1 How It Works

Cosmos DB **continuous backup** automatically maintains a point-in-time recovery window:

- **Default retention:** 30 days (`Continuous30Days`)
- **Optional retention:** 7 days (`Continuous7Days`)
- **RTO:** ~1 hour (restore to new account is slow)
- **RPO:** ~100 seconds (continuous ingestion into backup storage)

When you restore:
1. Specify a point-in-time (UTC timestamp)
2. Cosmos DB creates a **new account** with the restored data
3. You test the new account
4. If valid, you can cut over (repoint applications)

### 4.2 Restore Workflow (Native PITR)

```
Current account: cosmos-backup-cosmos-dev
Current time: 2026-04-28 14:30:00 UTC

User requests PITR to: 2026-04-28 12:00:00 UTC (2.5 hours ago)

Azure Portal → Cosmos DB → "Restore" 
→ Set restore time
→ Specify target account: cosmos-backup-restored-dev
→ Wait 60–90 min
→ New account created with data from 12:00:00 UTC

Operator:
• Runs validation queries on restored account
• Verifies document count, latest timestamp, sample records
• Compares against known baselines
• If OK: documents new account name, timestamps, validation hash
• If bad: delete restored account, try different timestamp
```

### 4.3 Key Constraints

- **Restore always creates a new account** (never in-place restore)
- **Can only restore to same region** (cross-region restore requires multi-region replication, out of scope)
- **Full account recovery** (can't restore individual databases or containers)
- **No data-plane filtering** (no "restore only documents matching predicate X")

**Therefore:** We always restore to a **staging account** (`{prefix}-restored-{env}`) for validation before cutover.

---

## 5. Custom Backup — Scheduled Exports to Immutable Blob Storage

### 5.1 How It Works

Every 6 hours, an **export job** runs:

1. Query Cosmos DB for recent documents (last 6 hours + 30-min overlap)
2. Serialize to JSON (array of documents)
3. Compute SHA-256 hash of JSON payload
4. Write to export storage: `exports/{yyyy}/{MM}/{dd}/{HH}-{mm}/data.json`
5. Write manifest: `exports/{yyyy}/{MM}/{dd}/{HH}-{mm}/manifest.json`
6. At end of day, copy exports from **export storage** (in primary RG) to **retention storage** (in retention RG)

### 5.2 Export Manifest Format

```json
{
  "exportId": "2026-04-27-14-30",
  "exportTimestamp": "2026-04-27T14:30:15Z",
  "sourceAccount": "cosmos-backup-cosmos-dev",
  "sourceDatabase": "demo",
  "sourceContainer": "weather",
  "dataTimeWindowStart": "2026-04-27T14:00:00Z",
  "dataTimeWindowEnd": "2026-04-27T14:30:00Z",
  "documentCount": 1234,
  "filePath": "exports/2026/04/27/14-30/data.json",
  "dataSha256": "abc123...",
  "manifestSha256": "def456...",
  "status": "completed"
}
```

### 5.3 Restore Workflow (Custom Archive)

```
User needs data from: 2026-04-25 10:00:00 UTC

Operator:
• Query retention storage: exports/2026/04/25/*/manifest.json
• Find export nearest to 10:00:00 (e.g., 10-00-00 or 10-30-00)
• Download data.json + manifest.json
• Verify SHA-256: computed hash ≟ manifest.dataSha256
• Create new Cosmos account (or staging container)
• Bulk-import JSON documents
• Run validation queries
• If OK: complete; if bad: try different export or escalate
```

### 5.4 Key Constraints

- **Not point-in-time** (only periodic snapshots; 6-hour granularity in this demo)
- **Requires manual import** to restore (must create Cosmos account first, then bulk-insert)
- **Evidence required** (manifests, hashes, validation checklists must be kept)
- **Immutability enforced** (once written, data can't be modified until retention expires)

**Therefore:** Custom archive is a **compliance/audit tool**, not an operational recovery path. Use native PITR for day-to-day recovery; use archive for long-term retention and regulatory compliance.

---

## 6. Immutable Blob Storage (Retention RG)

### 6.1 Immutability Policy

The **retention resource group** contains immutable Blob Storage configured with:

- **Version-level immutability** (not container-level)
- **Minimum retention (demo):** 1 day (allows fast cleanup during dev)
- **Minimum retention (production):** 2555 days (≈7 years, use different parameter file)
- **WORM enabled:** Blobs can't be deleted or modified until retention period expires
- **Versioning:** Each upload creates a new version; old versions are also protected

### 6.2 Lifecycle Management

Blobs in retention storage follow a **lifecycle transition** (optional, for cost optimization):

```
Day 0–7:    Cool tier      ($0.01/GB/month read operations)
Day 7–30:   Archive tier   ($0.002/GB/month, slower access, higher rehydration cost)
Day 30+:    Stays Archive  (until retention expires)
```

*Note: Archive blobs require rehydration (1–15 hours) before access. Demo uses Cool tier for fast access; production may prefer Archive for cost.*

### 6.3 Retention Expiry (Safe Deletion)

When **1-day retention expires** (demo), you can:

```bash
# Day 0: Demo ends, export stored with 1-day immutability
# Day 1 08:00 UTC: Retention period expires for oldest exports
# Day 1 08:05: Delete blob (finally allowed)

# Manual deletion when ready (after immutability expires):
az storage blob delete \
  --account-name "${PREFIX}retentiondev..." \
  --container-name exports-archive \
  --name "exports/2026/04/27/14-30/data.json"
```

**Key rule:** You **cannot delete** until immutability expires. This is a feature for compliance, but it means demo cleanup takes 1+ days.

---

## 7. Monitoring & Observability

All resources write logs to **Azure Monitor** (Log Analytics Workspace).

### 7.1 Diagnostic Settings

| Source | Logs Sent to LAW | Queries |
|--------|------------------|---------|
| **Cosmos DB** | `CosmosDiagnosticLogEnabled` | Reads, writes, throttles (429s), RUs used |
| **Storage Account** | `StorageRead`, `StorageWrite` | Blob uploads, downloads, failures |
| **Container Apps/ACI** | STDOUT/STDERR via container runtime | Ingestor logs, exporter logs |

### 7.2 Sample Queries

```kusto
// Ingestion rate (docs/min)
AzureActivity
| where ResourceProvider == "Microsoft.DocumentDB"
| where OperationName == "Write"
| where TimeGenerated > ago(1h)
| summarize WriteCount = count() by bin(TimeGenerated, 1m)
| render timechart

// Throttling events (429s)
AzureMetrics
| where ResourceType == "MICROSOFT.DOCUMENTDB/DATABASEACCOUNTS"
| where MetricName == "ServerSideLatency"
| where TimeGenerated > ago(24h)
| where ConflictingOperations > 0

// Export success/failure
ContainerLogv2
| where LogEntry contains "export"
| where TimeGenerated > ago(6h)
| summarize count() by Status
```

### 7.3 Alert Rules

| Alert | Condition | Action |
|-------|-----------|--------|
| **Cosmos 429s** | >5 throttle events in 5 min | Email ops team |
| **Ingestion gap** | No docs written for >60 sec | Email ops team |
| **Export failure** | Export job fails 2× in a row | Email ops team, page on-call |

---

## 8. Network & Security Baseline

### 8.1 v1 Configuration (This Demo)

- **Public endpoints** for all services (Cosmos, Storage, Container host)
- **IP firewall rules** to restrict access (whitelist your IP or deployment network)
- **Managed identity** for all workload authentication (no account keys exported)
- **RBAC assignments** scoped to data-plane roles
- **Key Vault** provisioned (empty in v1, used for secrets in production)

### 8.2 v2 Enhancement (Private Endpoints)

Future variant will add:
- **VNet + subnets** for Cosmos, Storage, Container host
- **Private endpoints** for zero-internet exposure
- **Private DNS zones** for internal DNS resolution
- **Network security groups** with ingress/egress rules
- **Estimated cost delta:** +$10–15/month per endpoint

Private endpoints are **optional** for demo (demo-ready with public endpoints + firewall).

---

## 9. Cost Model

### 9.1 Baseline (Development)

| Resource | Consumption | Monthly (Dev) |
|----------|-------------|---------------|
| **Cosmos DB** | Serverless, 20 writes/sec avg | $0–15 |
| **Storage (export)** | ~100 MB/month (6hr exports) | <$1 |
| **Storage (retention)** | ~3 GB for 30 days of data | <$1 |
| **Container Apps** | 730 hrs × 0.1 vCPU | $0–5 |
| **Log Analytics** | ~50 MB ingestion | $0–5 |
| **Key Vault** | <100 operations/month | <$1 |
| **Total** | | **~$10–25/month** |

### 9.2 Production (Scaled)

| Resource | Consumption | Monthly (Prod) |
|----------|-------------|-----------------|
| **Cosmos DB** | 10,000 RU/s provisioned | $250–400 |
| **Storage (export)** | ~5 GB/month | $0.10 |
| **Storage (retention)** | ~500 GB (7-year retention) | $5–20 |
| **Container Apps** | 730 hrs × 2 vCPU | $100–150 |
| **Log Analytics** | ~5 GB ingestion | $50 |
| **Key Vault** | 10,000 operations/month | $0.34 |
| **Private Endpoints** | 5 endpoints × $7.30 each | $37 |
| **Total** | | **~$450–700/month** |

**Cost optimization strategies:**
- Use **Cosmos serverless** instead of provisioned RU for dev/test
- Transition **export storage to Archive tier** after 30 days (saves 90% vs Cool)
- Use **consumption-based Container Apps** instead of dedicated plans
- Archive **old Log Analytics data** (30+ days) to cold storage

---

## 10. Failure Modes & Recovery

### 10.1 Ingestion Container Crashes

| Failure | Detection | Recovery |
|---------|-----------|----------|
| OOM kill | Container restarts | Container orchestrator (Container Apps) auto-restarts |
| Network timeout | Logs "ECONNREFUSED" | Retry loop built into app; manual restart if persistent |
| Auth failure (managed identity) | Logs 401 Unauthorized | Re-run RBAC setup; restart container |

### 10.2 Cosmos DB Throttling (429)

| Failure | Detection | Recovery |
|---------|-----------|----------|
| RU exhaustion | Ingestion sees 429 responses | Increase RU allocation (Bicep parameter) or reduce write volume |
| Connection limit | Logs "Too many connections" | Increase Cosmos connection pool size; add retry backoff |

### 10.3 Export Job Failure

| Failure | Detection | Recovery |
|---------|-----------|----------|
| Blob upload fails | Export logs "403 Forbidden" | Check managed identity RBAC on storage account |
| Change feed read fails | Export logs "404 Not Found" | Verify container exists; re-run RBAC assignment |
| Manifest write fails | Alert "Export failed" | Check storage account authentication; retry manually |

### 10.4 Restore Fails

| Failure | Detection | Recovery |
|---------|-----------|----------|
| Restore times out (>2h) | Portal shows "Failed" | Check target account quota; try smaller time window |
| Restored account has no data | Validation query returns 0 rows | Check restore time window; try different timestamp |
| RBAC missing on restored account | Ingestion identity can't write to restored account | Apply RBAC to new account; use Bicep RBAC module |

---

## 11. Key Assumptions

✅ **Implemented in v1:**
- Single-region (eastus2)
- Two-tier backup (native PITR + custom archive)
- Continuous synthetic data ingestion
- Managed identity + RBAC everywhere
- Public endpoints with IP firewall

🔄 **Deferred to v2:**
- Multi-region (cross-region restore, failover)
- Private endpoints (VNet, NSGs, private DNS)
- Warm snapshot tier (intermediate storage tier)
- Real-time change feed export (instead of 6-hour interval)
- CMK encryption for Cosmos DB

❌ **Out of scope:**
- HIPAA, FedRAMP, PCI compliance certification (demo only)
- Data encryption at rest with customer-managed keys
- Multi-tenant isolation
- Application-level sharding/geo-distribution

---

## 12. Rollback & Runbook Decision Tree

```
INCIDENT: Data is corrupted in live Cosmos DB account

1. Assess:
   • When was data corrupted? (timestamp)
   • What's the healthy restore point? (go back 1–2 hours)

2. Options:
   a. Use native PITR (if within 30-day window, ≈1 hour to restore)
      → Restore to {prefix}-restored-{env}
      → Validate data
      → If OK, repoint applications
   
   b. Use custom archive (if corruption > 30 days old)
      → Find export near healthy timestamp
      → Download and validate manifest + hash
      → Create new Cosmos account
      → Bulk-import JSON
      → Repoint applications

3. Communication:
   • Document restore timestamp, source account, target account
   • Get approval before cutover
   • Post-incident: update on-call playbook

4. Verification:
   • Count documents (before ≟ after)
   • Spot-check records vs. known good baseline
   • Monitor ingestion rate for next 30 min
```

---

## 13. Related Documentation

- **Deployment:** See [Deployment Guide](docs/deployment-guide.md)
- **Operations:** See [Backup & Restore Runbook](docs/backup-restore-runbook.md)
- **Demo script:** See [Demo Walkthrough](docs/demo-walkthrough.md)
- **Compliance:** See [Compliance & Well-Architected](docs/compliance-and-well-architected.md)
- **Teardown:** See [Teardown](docs/teardown.md)

---

**Next:** Proceed to [Deployment Guide](docs/deployment-guide.md) for step-by-step setup.
