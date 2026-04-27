# Demo Walkthrough — 15–20 Minute Presentation

**Date:** 2026-04-27  
**Duration:** 15–20 minutes  
**Audience:** IT decision makers, business stakeholders, technical decision makers

---

## Pre-Demo Checklist

Before you begin, verify that:

- [ ] Infrastructure deployed (see [Deployment Guide](docs/deployment-guide.md))
- [ ] Ingestion running (documents writing every 20 seconds)
- [ ] Export storage populated with at least one export
- [ ] Azure Portal access ready (optional, shows real resources)
- [ ] Terminal or shell access ready (for CLI commands)
- [ ] Slide deck or notes prepared (slides not included; use talking points below)

**Setup time:** ~30 minutes  
**Running time:** ~5 minutes (while you present)

---

## Demo Script — 15–20 Minutes

### **Segment 1: Problem & Solution (2 minutes)**

**SETUP:** Display problem slide or verbal intro.

**TALKING POINTS:**

> **For IT Decision Makers:**
> 
> "Azure Cosmos DB stores critical application data. If we accidentally delete data, corrupt records, or face a regional outage, we need to recover within hours. But Cosmos DB's native backup only keeps 30 days of history. For compliance and long-term retention, we need a separate archival strategy.
> 
> This demo shows how we can layer two backup approaches:
> 1. **Native PITR** (Point-in-Time Restore) — built into Cosmos, 30 days, restores in about an hour
> 2. **Custom Archive** — exports to immutable storage, supports 7-year retention, keeps full audit trail
> 
> Both are zero-trust: managed identity, no account keys, everything audited in Azure Monitor."

> **For Business Stakeholders:**
> 
> "Data loss = revenue loss and trust damage. This demo shows how we protect against both. We have two safety nets: a 30-day hot backup for quick recovery, and a 7-year cold archive for compliance. If something breaks, we can get back to a known-good state in hours, not days."

---

### **Segment 2: Architecture Overview (2 minutes)**

**SETUP:** Show architecture diagram or terminal with resource list.

**DEMO COMMAND:**

```bash
# Show deployed resources
az group show \
  --name "cosmos-backup-demo-dev-rg" \
  --query '{
    name: name,
    location: location,
    id: id
  }' \
  --output table

# List resources in the group
az resource list \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --query "[].{type: type, name: name}" \
  --output table
```

**EXPECTED OUTPUT:**
```
Type                                      Name
────────────────────────────────────────  ────────────────────────────
Microsoft.DocumentDB/databaseAccounts     cosmos-backup-cosmos-dev
Microsoft.Storage/storageAccounts         cosmosbackupexportsdev
Microsoft.App/containerApps               ingestor
Microsoft.ContainerRegistry/registries    (if built locally)
Microsoft.OperationalInsights/workspaces  workspace-...
Microsoft.Insights/actionGroups           ...
```

**TALKING POINTS:**

> "Here's what we've deployed:
> - **Cosmos DB account** — The main database, configured with 30-day continuous backup
> - **Storage account (exports)** — Where we write 6-hourly snapshots of data
> - **Container App (ingestor)** — Continuously writes synthetic weather data every 20 seconds
> - **Log Analytics workspace** — Captures all audit logs, alerts, and diagnostics
> 
> Everything uses **managed identity** — no passwords, no account keys. Each service authenticates via Azure AD."

---

### **Segment 3: Live Ingestion (2 minutes)**

**SETUP:** Terminal ready to show ingestion logs.

**DEMO COMMAND:**

```bash
# Query Cosmos DB document count
az cosmosdb sql container throughput show \
  --account-name "cosmos-backup-cosmos-dev" \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --database-name "demo" \
  --name "weather" \
  --query 'resource.throughput' \
  --output table

# Count documents (via portal or SDK)
# Or query from ingestor logs
az container logs \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --name "ingestor" \
  --tail 10
```

**EXPECTED OUTPUT:**
```
Document count: 45,230
Latest write: 2026-04-27T14:25:33Z
Ingestion rate: 3 docs/min (expected: 3 = 1 per 20 sec)
```

**TALKING POINTS:**

> "While I'm speaking, this application is continuously writing weather data to Cosmos DB—one document every 20 seconds. Over the course of this demo, we'll watch the document count grow in real time.
> 
> Each document includes: city, temperature, humidity, timestamp. Totally synthetic, but it simulates a realistic application that writes operational data."

*(Pause 10–20 seconds for effect; note the document count increasing)*

---

### **Segment 4: Native Backup (PITR) (3 minutes)**

**SETUP:** Azure Portal open to Cosmos DB account, or use CLI to show backup policy.

**DEMO COMMAND:**

```bash
# Show backup policy
az cosmosdb show \
  --name "cosmos-backup-cosmos-dev" \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --query 'backupPolicy' \
  --output json
```

**EXPECTED OUTPUT:**
```json
{
  "type": "Continuous",
  "continuousModeProperties": {
    "retentionInMinutes": 43200
  }
}
```

**TALKING POINTS:**

> "Cosmos DB's **continuous backup** is always on. We get 30 days of automatic, point-in-time recovery at no extra cost — it's included in our pricing.
> 
> If someone accidentally deletes 10,000 records at 2 PM, we can restore the entire database to 1:59 PM in about an hour. The restored data goes into a **separate account** (we never restore in place), so we can validate before cutting over.
> 
> Cost: **Zero extra**—it's automatic and included."

---

### **Segment 5: Export & Archive (3 minutes)**

**SETUP:** Terminal ready to show export storage, or Azure Portal Storage browser.

**DEMO COMMAND:**

```bash
# Show export storage account
EXPORT_STORAGE="cosmos-backup-exports-dev"  # Adjust to actual name
az storage account show \
  --name "$EXPORT_STORAGE" \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --query '{
    name: name,
    accessTier: accessTier,
    primaryEndpoints: primaryEndpoints
  }' \
  --output table

# List exports
az storage blob list \
  --account-name "$EXPORT_STORAGE" \
  --container-name "exports" \
  --query "[].{name: name, size: properties.contentLength, modified: properties.lastModified}" \
  --output table
```

**EXPECTED OUTPUT:**
```
Name                                                   Size    Modified
─────────────────────────────────────────────────────  ──────  ───────────────────────
exports/2026/04/27/08-00/data.json                    24,000  2026-04-27T08:01:30Z
exports/2026/04/27/08-00/manifest.json                  800   2026-04-27T08:01:30Z
exports/2026/04/27/14-00/data.json                    25,600  2026-04-27T14:01:15Z
exports/2026/04/27/14-00/manifest.json                  820   2026-04-27T14:01:15Z
```

**TALKING POINTS:**

> "Every 6 hours, we export a snapshot of all documents to immutable Blob Storage. These exports are **WORM** — Write Once Read Many. Once written, they can't be deleted or modified for the retention period (7 years in production, 1 day in this demo).
> 
> Each export includes:
> - **data.json**: All documents from that 6-hour window
> - **manifest.json**: Metadata—document count, SHA-256 hash, timestamps, source account
> 
> If we ever need to recover data from 2 months ago (beyond the 30-day PITR window), we download the nearest export, verify the hash, and bulk-import the data to a new account."

---

### **Segment 6: Immutability & Compliance (2 minutes)**

**SETUP:** Terminal or Portal ready to show immutability policy.

**DEMO COMMAND:**

```bash
# Show retention storage account (immutable)
RETENTION_STORAGE="cosmos-backup-retention-dev"  # Adjust
az storage account show \
  --name "$RETENTION_STORAGE" \
  --resource-group "cosmos-backup-retention-dev-rg" \
  --query '{
    name: name,
    accessTier: accessTier
  }' \
  --output table

# Show immutability policy on a blob (if available)
az storage blob show \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "exports/2026/04/27/14-00/data.json" \
  --query 'immutabilityPolicy' \
  --output json
```

**EXPECTED OUTPUT:**
```json
{
  "expiresOn": "2026-04-28T14:01:30Z",
  "policyMode": "Locked",
  "updateHistory": [ ... ]
}
```

**TALKING POINTS:**

> "These exports go into a **separate resource group** with immutable storage. This is key for compliance:
> 
> - **WORM enforcement**: Azure locks each blob for a minimum period (1 day in demo, 7 years in production). Even the storage admin can't delete it.
> - **Versioning**: If the same file is uploaded twice, both versions are locked independently. Audit trail is preserved.
> - **Legal hold capability**: For sensitive data, we can add a legal hold that prevents deletion indefinitely (until explicitly released by authorized users).
> 
> This satisfies compliance requirements: **immutable backups, audit trail, no way to erase history**."

---

### **Segment 7: Point-in-Time Restore Demo (3–5 minutes)** [OPTIONAL]

*If you have time and a pre-staged restore account, show a live restore. Otherwise, describe the process.*

**IF LIVE RESTORE:**

```bash
# Trigger a restore (assumes source account is active)
RESTORE_ACCOUNT="cosmos-backup-restored-demo-$(date +%s)"

# This takes 60–90 minutes in real Azure, so you'd usually prepare this in advance
# For the demo, you could show a previously-restored account

# If pre-staged, show it:
az cosmosdb show \
  --name "$RESTORE_ACCOUNT" \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --query '{
    name: name,
    backupPolicy: backupPolicy,
    restoreParameters: restoreParameters
  }' \
  --output json
```

**TALKING POINTS:**

> "To demonstrate recovery, I've pre-staged a restored account from 2 hours ago. In production, this restore takes about an hour. Let me show you what that looks like:
> 
> (Show restored account in portal or CLI)
> 
> This account has all the data from 2 hours ago. We can query it, validate that the right data is there, then decide whether to cut over applications or do more testing.
> 
> The key point: **the original account is untouched** during the entire restore process. We restore to a new account, validate, then decide what to do next. Zero risk of data loss."

**IF NOT LIVE RESTORE:**

> "Normally, restoring takes about 60 minutes. I'll walk through what that looks like, but we won't wait for it live. 
> 
> (Show screenshot or describe process)
> 
> You specify a point-in-time, Azure creates a new account with data from that moment, and you validate before cutting over."

---

### **Segment 8: Monitoring & Alerts (1–2 minutes)**

**SETUP:** Log Analytics portal or sample alert query ready.

**DEMO COMMAND:**

```bash
# Show Alert Rules
az monitor metrics alert list \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --query "[].{name: name, condition: 'See Portal'}" \
  --output table

# Show logs (if accessible)
az monitor log-analytics query \
  --workspace "WORKSPACE_ID" \
  --analytics-query "
    ContainerLogv2
    | where LogEntry contains 'export'
    | where TimeGenerated > ago(24h)
    | summarize count() by Status
  "
```

**TALKING POINTS:**

> "All of this is monitored continuously. We have alerts for:
> - **Cosmos DB throttling (429 errors)** → indicates we're over-provisioned or need more RUs
> - **Ingestion gaps** → if no documents are written for over 60 seconds, we get alerted
> - **Export job failures** → if the backup export fails, we know immediately
> 
> All logs flow into **Azure Monitor**, which we can query, dashboard, and alert on. This is your **audit trail** for compliance."

---

### **Segment 9: Cost & Cleanup (1–2 minutes)**

**SETUP:** Cost table or calculator ready.

**TALKING POINTS:**

> **Cost:**
> - **Cosmos DB (serverless, dev)**: $0–$15/month
> - **Storage (exports)**: <$1/month
> - **Container running**: $0–$5/month
> - **Log Analytics**: $0–$5/month
> - **Total (dev)**: **~$10–$25/month**
> 
> Production would be higher (provisioned RUs, multi-region), but the pattern is the same.

> **Cleanup:**
> When this demo is done, we delete the primary resource group (all the compute resources). But we **preserve the immutable storage** for the minimum 1-day retention period. This shows the compliance pattern: data is locked and can't be deleted prematurely.
> 
> Once 1 day expires, we can delete the immutable storage if needed."

---

### **Segment 10: Wrap-Up & Q&A (1–2 minutes)**

**TALKING POINTS:**

> "**Summary:**
> 1. **Native PITR**: 30-day automatic backup, restore in ~1 hour, zero extra cost
> 2. **Custom archive**: 6-hourly exports to immutable storage, 7-year retention, audit trail
> 3. **Compliance**: WORM enforcement, versioning, legal hold capability
> 4. **Managed identity**: Zero passwords, no account keys, Azure AD auth
> 5. **Monitoring**: Alerts, logs, dashboards in Azure Monitor
> 
> This approach gives us **both** operational recovery (PITR for quick fixes) **and** long-term compliance (immutable archive).
> 
> Questions?"

---

## Backup Slides (Text Only, for Your Use)

### Slide 1: Problem
- Data loss = revenue loss
- Cosmos DB native backup only covers 30 days
- Compliance requires 7-year retention
- Need automated, auditable backup strategy

### Slide 2: Solution — Two-Tier Backup
- **Tier 1 (Hot):** Native PITR, 30 days, restores in 1 hour
- **Tier 2 (Cold):** Custom exports to immutable storage, 7 years, audit trail
- Both use managed identity (zero trust)

### Slide 3: Architecture
```
Ingestion (20 sec cadence)
    ↓
Cosmos DB (Continuous Backup)
    ↓
├─→ PITR restore (new account, 1 hour)
├─→ Scheduled export (6 hourly)
    ├─→ Export Storage (Cool/Archive lifecycle)
    └─→ Retention Storage (Immutable WORM)
```

### Slide 4: PITR Demo
- Restore to separate account
- Validate data
- Decide cutover

### Slide 5: Archive Demo
- Find export from N weeks ago
- Verify hash/manifest
- Bulk-import to new account
- Restore beyond 30 days

### Slide 6: Immutability
- WORM: can't delete for retention period
- Versioning: audit trail preserved
- Legal hold: indefinite lock if needed

### Slide 7: Compliance & Cost
- **Cost (dev):** $10–$25/month
- **Cost (prod):** $500–$700/month
- Audit trail, RPO/RTO targets, managed identity
- Well-Architected aligned

---

## Interactive Elements (Optional)

### Live Ingestion Monitor
Display a live query showing document count incrementing:

```bash
# Every 10 seconds, show document count
while true; do
  COUNT=$(az cosmosdb sql container show \
    --account-name "cosmos-backup-cosmos-dev" \
    --resource-group "cosmos-backup-demo-dev-rg" \
    --database-name "demo" \
    --name "weather" \
    --query 'resource.documentCount' \
    -o tsv)
  
  echo "Current documents: $COUNT (growing in real time...)"
  sleep 10
done
```

### Portal Demo
- Show Cosmos DB resource
- Show Storage accounts
- Show Container Apps/ACI running
- Show Log Analytics queries
- Show Alert Rules

---

## Troubleshooting During Demo

| Issue | Fix |
|-------|-----|
| "Connection refused" | Verify resources deployed; check managed identity RBAC |
| "No documents in Cosmos" | Ingestion may not have started; restart container |
| "No exports in storage" | Export job may not have run yet; manually trigger or wait 6 hours |
| "Restore failed" | Ensure pre-staged restore account was created before demo; or show previous recording |

---

## Demo Files & Artifacts

All commands above reference real Azure resources and real CLI commands. **Test the demo locally first** before showing to stakeholders.

**Files you'll need:**
- Resource group name: `cosmos-backup-demo-dev-rg`
- Retention RG name: `cosmos-backup-retention-dev-rg`
- Cosmos account: `cosmos-backup-cosmos-dev`
- Export storage: Name from Bicep outputs
- Container app/ACI: Name from Bicep outputs

---

## Demo Duration Summary

| Segment | Time |
|---------|------|
| Intro (problem & solution) | 2 min |
| Architecture overview | 2 min |
| Live ingestion | 2 min |
| Native PITR explanation | 3 min |
| Exports & archive | 3 min |
| Immutability & compliance | 2 min |
| Restore demo or explanation | 3–5 min |
| Monitoring & alerts | 1–2 min |
| Cost & cleanup | 1–2 min |
| Wrap-up & Q&A | 1–2 min |
| **Total** | **15–20 min** |

---

**Next:** After the demo, proceed to [Backup & Restore Runbook](docs/backup-restore-runbook.md) for operational details, or [Teardown](docs/teardown.md) to clean up resources.
