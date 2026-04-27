# Backup & Restore Runbook — Azure Cosmos DB Demo

**Date:** 2026-04-27  
**Status:** Demo-ready  
**Audience:** Operators, DBAs, incident responders

---

## Overview

This runbook covers:
- **Native backup configuration** (Cosmos DB continuous backup)
- **Custom archive configuration** (scheduled exports to immutable Blob Storage)
- **Point-in-time restore** (PITR) to a new account
- **Archive restore** (import from Blob Storage)
- **Immutable storage behavior** (WORM constraints, expiry timeline)
- **Evidence & auditability** (validation checklists, hashes, manifests)

---

## 1. Native Backup Configuration

### 1.1 Verifying Backup Policy

After deployment, verify that Cosmos DB has the correct backup policy:

```bash
COSMOS_ACCOUNT_NAME="cosmos-backup-cosmos-dev"
RESOURCE_GROUP="cosmos-backup-demo-dev-rg"

az cosmosdb show \
  --name "$COSMOS_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query '{
    backupPolicy: backupPolicy,
    createMode: createMode,
    defaultIdentity: defaultIdentity
  }' \
  --output json
```

**Expected output:**

```json
{
  "backupPolicy": {
    "type": "Continuous",
    "continuousModeProperties": {
      "retentionInMinutes": 43200
    }
  },
  "createMode": "Default",
  "defaultIdentity": "FirstWritableLocation"
}
```

**Interpretation:**
- `type: Continuous` — ✅ PITR is enabled
- `retentionInMinutes: 43200` — ✅ 30 days (43200 min ÷ 60 ÷ 24 = 30 days)
- If `Continuous7Days`: `retentionInMinutes: 10080` (7 days)

### 1.2 Adjusting Backup Retention

If you need to change retention (e.g., from 30 to 7 days):

```bash
# Edit infra/main.bicepparam or infra/parameters/dev.bicepparam
# Change:
#   cosmosContinuousBackupTier: 'Continuous30Days'
# To:
#   cosmosContinuousBackupTier: 'Continuous7Days'

# Redeploy:
az deployment sub create \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam \
  --location eastus2
```

**Note:** Changing retention may require account recreation in some cases. Check [design-review.md](design-review.md) for current Azure behavior.

---

## 2. Custom Archive Configuration

### 2.1 Export Storage Verification

After deployment, verify that export storage is configured:

```bash
EXPORT_STORAGE="cosmos-backup-exports-dev"  # Or actual account name from Bicep outputs

az storage account show \
  --name "$EXPORT_STORAGE" \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --query '{
    tier: accessTier,
    lifecycle: managementPolicies,
    containers: "See below"
  }'

# List containers
az storage container list \
  --account-name "$EXPORT_STORAGE" \
  --query "[].name"
```

**Expected output:**
```
[
  "exports",
  "imports"
]
```

### 2.2 Lifecycle Rules (Optional Cost Optimization)

Check if lifecycle rules are configured to transition to Archive:

```bash
# View current lifecycle rules
az storage account management-policy show \
  --account-name "$EXPORT_STORAGE" \
  --resource-group "cosmos-backup-demo-dev-rg"
```

**Expected lifecycle rule** (if configured):
```json
{
  "rules": [
    {
      "name": "TransitionToArchive",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "actions": {
          "baseBlob": {
            "tierToCool": {
              "daysAfterModificationGreaterThan": 7
            },
            "tierToArchive": {
              "daysAfterModificationGreaterThan": 30
            }
          }
        },
        "filters": {
          "blobTypes": ["blockBlob"]
        }
      }
    }
  ]
}
```

---

## 3. Point-in-Time Restore (Native PITR)

### 3.1 Restore Workflow — Step by Step

**Scenario:** You need to recover data from 2 hours ago due to accidental corruption.

**Step 1: Determine restore timestamp**

```bash
# Get current time (UTC)
date -u +'%Y-%m-%dT%H:%M:%SZ'
# Example output: 2026-04-27T14:30:15Z

# Restore point: 2 hours ago = 2026-04-27T12:30:15Z
# Verify this time is within retention window (30 days back from now)
```

**Step 2: Trigger restore via CLI**

```bash
COSMOS_ACCOUNT="cosmos-backup-cosmos-dev"
RESOURCE_GROUP="cosmos-backup-demo-dev-rg"
TARGET_ACCOUNT="cosmos-backup-restored-dev"
RESTORE_TIMESTAMP="2026-04-27T12:30:15Z"  # Adjust to your needed time
LOCATION="eastus2"

# Start restore job
az cosmosdb restore \
  --account-name "$TARGET_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --restore-source-account "$COSMOS_ACCOUNT" \
  --restore-timestamp "$RESTORE_TIMESTAMP" \
  --location "$LOCATION"
```

**Step 3: Wait for restore to complete** (~1–2 hours)

```bash
# Check restore status every 10 minutes
while true; do
  STATUS=$(az cosmosdb show \
    --name "$TARGET_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query 'restoreParameters.restoreSource' \
    -o tsv)
  
  if [ -n "$STATUS" ]; then
    echo "Restore in progress..."
    sleep 10
  else
    echo "Restore completed or not started."
    break
  fi
done

# Verify target account exists and has data
az cosmosdb database list \
  --account-name "$TARGET_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP"
```

### 3.2 Validate Restored Data

**Step 1: Query document count**

```bash
# Connect to restored account using Azure CLI or Cosmos SDK
# Example: Use Data Explorer in Azure Portal or SDKs

# For CLI validation, query via script:
cat > validate_restore.sh << 'EOF'
#!/bin/bash
TARGET_ACCOUNT="cosmos-backup-restored-dev"
RESOURCE_GROUP="cosmos-backup-demo-dev-rg"

# Get connection string
CONN_STR=$(az cosmosdb keys list \
  --name "$TARGET_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --type connection-strings \
  --query 'connectionStrings[0].connectionString' \
  -o tsv)

# Query via Python SDK (requires @azure/cosmos package)
python3 << PYEOF
import json
from azure.cosmos import CosmosClient

client = CosmosClient.from_connection_string("$CONN_STR")
db = client.get_database_client("demo")
container = db.get_container_client("weather")

# Count documents
query = "SELECT VALUE COUNT(1) FROM c"
items = list(container.query_items(query=query, enable_cross_partition_query=True))
print(f"Document count: {items[0] if items else 'Error'}")

# Get latest document
query_latest = "SELECT * FROM c ORDER BY c._ts DESC LIMIT 1"
latest = list(container.query_items(query=query_latest, enable_cross_partition_query=True))
if latest:
    print(f"Latest doc: {json.dumps(latest[0], indent=2)}")
PYEOF
EOF

bash validate_restore.sh
```

**Step 2: Compare with pre-corruption baseline**

| Metric | Before Corruption | After Restore | Status |
|--------|-------------------|---------------|--------|
| Document count | 45,000 | 45,000 | ✅ Match |
| Max timestamp | 2026-04-27T12:30:00Z | 2026-04-27T12:30:00Z | ✅ Match |
| Sample city IDs | [nyc, la, chi, ...] | [nyc, la, chi, ...] | ✅ Match |
| Latest temp range | 65–75°F | 65–75°F | ✅ Match |

### 3.3 Cutover to Restored Account

Once validation passes:

```bash
# Option A: Update connection strings in app config
# (Repoint application to: cosmos-backup-restored-dev)
az containerapp update \
  --name ingestor \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --set-env-vars \
    COSMOS_ENDPOINT="https://cosmos-backup-restored-dev.documents.azure.com:443/" \
    COSMOS_DATABASE="demo" \
    COSMOS_CONTAINER="weather"

# Option B: Rename old account (danger zone — not recommended for demo)
# (Don't do this; keep both accounts for audit trail)

echo "Application cutover complete. Monitor logs for errors."
```

### 3.4 Cleanup After Cutover

```bash
# Delete the old (corrupted) account
az cosmosdb delete \
  --name "cosmos-backup-cosmos-dev" \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --yes

# Rename restored account to be the primary
az cosmosdb update \
  --name "cosmos-backup-restored-dev" \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --new-name "cosmos-backup-cosmos-dev"
```

---

## 4. Archive Restore (Custom Long-Term Recovery)

### 4.1 Locate Archive Export

**Scenario:** You need to restore data from 2 weeks ago (outside 30-day PITR window).

**Step 1: Find the right export**

```bash
RETENTION_STORAGE="cosmosbckpretentiondev"  # Actual name from Bicep outputs
RETENTION_RG="cosmos-backup-retention-dev-rg"

# List available exports
az storage blob list \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --query "[].name" \
  | grep "2026/04/13"  # Date 2 weeks ago

# Example output:
# exports/2026/04/13/06-00/data.json
# exports/2026/04/13/12-00/data.json
# exports/2026/04/13/18-00/data.json
```

### 4.2 Download and Validate Export

```bash
EXPORT_PATH="exports/2026/04/13/12-00"

# Download manifest
az storage blob download \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "$EXPORT_PATH/manifest.json" \
  --file manifest.json

# Download data
az storage blob download \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "$EXPORT_PATH/data.json" \
  --file data.json

# Verify SHA-256 hash
EXPECTED_HASH=$(jq -r '.dataSha256' manifest.json)
ACTUAL_HASH=$(sha256sum data.json | awk '{print $1}')

if [ "$EXPECTED_HASH" = "$ACTUAL_HASH" ]; then
  echo "✅ Hash validation passed"
else
  echo "❌ Hash mismatch! File corrupted."
  exit 1
fi

# Display manifest
cat manifest.json | jq '.'
```

### 4.3 Restore Archive Data to New Cosmos Account

```bash
IMPORT_ACCOUNT="cosmos-backup-archive-restore-$(date +%s)"
RESOURCE_GROUP="cosmos-backup-demo-dev-rg"

# Create new Cosmos account (simplified; Bicep would do this in production)
az cosmosdb create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$IMPORT_ACCOUNT" \
  --locations regionName="eastus2" \
  --default-consistency-level "Session" \
  --enable-automatic-failover false

# Wait for account to be ready
sleep 30

# Create database and container
az cosmosdb sql database create \
  --account-name "$IMPORT_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --name "demo"

az cosmosdb sql container create \
  --account-name "$IMPORT_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --database-name "demo" \
  --name "weather" \
  --partition-key-path "/cityId"

# Bulk import JSON documents
python3 << 'PYEOF'
import json
from azure.cosmos import CosmosClient
import os

# Get connection string for new account
new_account_name = os.getenv("IMPORT_ACCOUNT")
conn_str = f"AccountEndpoint=https://{new_account_name}.documents.azure.com:443/;..."  # Fetch via CLI

client = CosmosClient.from_connection_string(conn_str)
container = client.get_database_client("demo").get_container_client("weather")

# Load and import documents
with open("data.json", "r") as f:
    documents = json.load(f)

for doc in documents:
    try:
        container.create_item(doc)
    except Exception as e:
        print(f"Error importing {doc.get('id')}: {e}")

print(f"Imported {len(documents)} documents")
PYEOF
```

### 4.4 Validate Archive Restore

```bash
# Query imported data
python3 << 'PYEOF'
import json
from azure.cosmos import CosmosClient

# Connect and query
client = CosmosClient.from_connection_string("...")  # Connection string
container = client.get_database_client("demo").get_container_client("weather")

# Count
count_query = "SELECT VALUE COUNT(1) FROM c"
count = list(container.query_items(query=count_query, enable_cross_partition_query=True))[0]
print(f"Imported count: {count}")

# Get time range
time_query = """
SELECT MIN(c._ts) as min_ts, MAX(c._ts) as max_ts FROM c
"""
time_range = list(container.query_items(query=time_query, enable_cross_partition_query=True))[0]
print(f"Time range: {time_range}")

# Sample records
sample_query = "SELECT * FROM c LIMIT 5"
samples = list(container.query_items(query=sample_query, enable_cross_partition_query=True))
print(f"Sample docs: {json.dumps(samples, indent=2)}")
PYEOF
```

---

## 5. Immutable Storage Behavior & Constraints

### 5.1 Immutability Timeline

```
Day 0 — 08:00 UTC:  Export written to retention storage
                    Version 1 created with 1-day immutability lock

Day 0 — 09:00 UTC:  Can't delete (still locked)
                    Can't modify (WORM enforced)

Day 1 — 08:00 UTC:  Immutability lock expires
                    Blob now deletable

Day 1 — 09:00 UTC:  Can delete blob
```

### 5.2 Constraints on Locked Blobs

While immutability is active, you **cannot**:

❌ **Delete** the blob  
❌ **Overwrite** the blob  
❌ **Modify** blob properties (metadata, tags, tier)  
❌ **Move** the blob to another container  

You **can** (read-only):

✅ **Read/download** the blob  
✅ **List** the blob  
✅ **Query** the manifest  

### 5.3 Legal Hold (Compliance)

In production, you can enable **legal hold** to make blobs undeletable indefinitely (until hold is released):

```bash
# Enable legal hold (optional, not in v1 demo)
az storage blob legal-hold set \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "exports/2026/04/27/14-30/data.json" \
  --legal-hold true

# Blob is now locked until explicitly released
az storage blob legal-hold clear \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "exports/2026/04/27/14-30/data.json"
```

### 5.4 Versioning Immutability

Immutable Blob Storage uses **version-level immutability**:
- Each blob version is independently protected
- Deleting the current version doesn't delete older versions
- Useful for audit trails: all versions remain locked

```bash
# List all versions of a blob
az storage blob list-versions \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "exports/2026/04/27/14-30/data.json"

# Download a specific version
az storage blob download \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "exports/2026/04/27/14-30/data.json" \
  --version-id "VERSION_ID" \
  --file data-v1.json
```

---

## 6. Auditability & Evidence

### 6.1 Restore Evidence Checklist

After **any restore** (PITR or archive), document:

```markdown
## Restore Evidence — 2026-04-27

**Incident:** Data corruption in weather container

**Restore Details:**
- Source account: cosmos-backup-cosmos-dev
- Restore timestamp: 2026-04-27T12:30:15Z
- Target account: cosmos-backup-restored-dev
- Requested by: ops-team@example.com
- Approved by: engineering-lead@example.com
- Restore start time: 2026-04-27T14:40:00Z
- Restore completion time: 2026-04-27T16:10:00Z (90 min)

**Validation:**
- [ ] Document count matches: 45,000 docs
- [ ] Max timestamp matches: 2026-04-27T12:30:00Z
- [ ] Sample records verified: 10 random docs checked
- [ ] No corruption in restored data: ✅
- [ ] Application cutover successful: ✅

**Hash/Manifest:**
- Source backup manifest SHA-256: abc123...
- Restored data hash verified: abc123... (match ✅)

**Post-Restore Actions:**
- [ ] Old account deleted: 2026-04-27T16:30:00Z
- [ ] New account renamed to primary
- [ ] Monitoring resumed
- [ ] Team notified

**Retention:** Keep this record for 7 years (immutable archive backup)
```

### 6.2 Export Manifest Auditing

Every export includes a manifest with:

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

**Verify manifest integrity:**

```bash
# Download manifest
az storage blob download \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "exports/2026/04/27/14-30/manifest.json" \
  --file manifest.json

# Compute hash of manifest itself
EXPECTED_MANIFEST_HASH=$(jq -r '.manifestSha256' manifest.json)
ACTUAL_MANIFEST_HASH=$(cat manifest.json | jq -S '.' | sha256sum | awk '{print $1}')

echo "Expected: $EXPECTED_MANIFEST_HASH"
echo "Actual:   $ACTUAL_MANIFEST_HASH"

# (Note: Manifest hash will differ if whitespace varies; verify data.json hash instead)
```

---

## 7. Monitoring Backup Health

### 7.1 Alert Rules

Ensure these alerts are configured (see [Architecture](docs/architecture.md) for details):

| Alert | Query | Threshold | Action |
|-------|-------|-----------|--------|
| **429 Throttling** | Cosmos 429 count | >5 in 5 min | Email ops |
| **Ingestion gap** | No docs written | >60 seconds | Email ops |
| **Export failure** | Export job status | Failed 2×  | Page on-call |

### 7.2 Backup Health Dashboard (Log Analytics)

```kusto
// Query: PITR retention window
let retention_days = 30;
AzureMetrics
| where ResourceType == "MICROSOFT.DOCUMENTDB/DATABASEACCOUNTS"
| where MetricName == "ReplicationLatency"
| where TimeGenerated > ago(24h)
| summarize AvgLatency = avg(Average) by bin(TimeGenerated, 1h)
| render timechart

// Query: Export job success rate
ContainerLogv2
| where LogEntry contains "export"
| where TimeGenerated > ago(7d)
| summarize SuccessCount = countif(LogEntry contains "completed"),
            FailureCount = countif(LogEntry contains "failed")
            by bin(TimeGenerated, 6h)
| project SuccessRate = (SuccessCount * 100 / (SuccessCount + FailureCount)),
          TimeGenerated
| render timechart

// Query: Storage immutability policy status
AzureMetrics
| where ResourceType == "MICROSOFT.STORAGE/STORAGEACCOUNTS"
| where MetricName == "BlobCount"
| where TimeGenerated > ago(1d)
| project TimeGenerated, Average
```

---

## 8. Troubleshooting

### Restore Fails with "Source Account Not Found"

**Symptom:** `az cosmosdb restore` returns 404.

**Causes:**
- Source account was deleted
- Wrong resource group name
- Source account not in same region

**Fix:**
```bash
# Verify source account exists
az cosmosdb show \
  --name "cosmos-backup-cosmos-dev" \
  --resource-group "cosmos-backup-demo-dev-rg"

# If not found, restore from archive instead (see §4)
```

### Restored Account Has No Data

**Symptom:** Query returns 0 documents after restore completes.

**Causes:**
- Restore timestamp was after the demo ended
- Restore is still in progress (check status again in 5 min)
- Wrong database/container name

**Fix:**
```bash
# Check restore status
az cosmosdb show \
  --name "cosmos-backup-restored-dev" \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --query 'restoreParameters'

# If status shows "Restoring", wait longer
# If status is empty, restore is complete; check container name
az cosmosdb sql container list \
  --account-name "cosmos-backup-restored-dev" \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --database-name "demo"
```

### Archive Blob Cannot Be Deleted (Still Locked)

**Symptom:** `az storage blob delete` returns "Blob is protected by immutability policy."

**Causes:**
- Immutability retention period hasn't expired yet
- Legal hold is enabled

**Fix:**
```bash
# Check immutability policy
az storage blob show \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "exports/2026/04/27/14-30/data.json" \
  --query '{immutabilityPolicy: immutabilityPolicy, legalHold: legalHold}'

# If legal hold is on, release it
az storage blob legal-hold clear \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "exports/2026/04/27/14-30/data.json"

# Wait for immutability to expire, then retry delete
```

### Export Job Logs Show "403 Forbidden"

**Symptom:** Container logs show `ExportJob: Failed to write blob (403 Forbidden)`.

**Causes:**
- Managed identity RBAC missing on storage account
- Storage account firewall blocking access

**Fix:**
```bash
# Re-apply RBAC (if using Bicep RBAC module)
az deployment group create \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --template-file infra/modules/rbac.bicep \
  --parameters \
    exportIdentityObjectId="..." \
    exportStorageAccountId="..."

# Or manually add role
az role assignment create \
  --assignee "EXPORTER_IDENTITY_OBJECT_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/{subId}/resourceGroups/cosmos-backup-demo-dev-rg/providers/Microsoft.Storage/storageAccounts/..."
```

---

## 9. Runbook Quick Reference

| Task | Command | Time |
|------|---------|------|
| **Verify backup policy** | `az cosmosdb show ... --query backupPolicy` | 1 min |
| **Trigger PITR restore** | `az cosmosdb restore ...` | 2 min setup + 60–90 min restore |
| **Validate restore** | Query restored account, compare doc count | 5 min |
| **Cutover to restored account** | Update app config, restart containers | 5 min |
| **Locate archive export** | `az storage blob list ... --query "[].name"` | 2 min |
| **Download & verify archive** | Download JSON + manifest, verify hash | 3 min |
| **Restore from archive** | Create account, bulk-import JSON, validate | 15 min |
| **Check immutability status** | `az storage blob show ... --query immutabilityPolicy` | 1 min |
| **Wait for immutability to expire** | Set alarm for N days | N days |
| **Delete immutable blob** | `az storage blob delete ...` | 1 min (after expiry) |

---

## 10. Related Documentation

- **Architecture:** See [Architecture](docs/architecture.md) for concepts
- **Demo script:** See [Demo Walkthrough](docs/demo-walkthrough.md) for hands-on walkthrough
- **Compliance:** See [Compliance & Well-Architected](docs/compliance-and-well-architected.md)
- **Cleanup:** See [Teardown](docs/teardown.md)

---

**Backup & restore procedures are now ready. Proceed to [Demo Walkthrough](docs/demo-walkthrough.md) for a scripted presentation.**
