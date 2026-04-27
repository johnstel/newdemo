# Teardown — Safe Deletion & Cleanup

**Date:** 2026-04-27  
**Status:** Demo-ready  
**Audience:** Operators, cleanup engineers, compliance officers

---

## Overview

This guide covers **safe deletion** of demo resources while preserving immutable backup storage. Key point:

- ✅ **Delete primary resource group** (all compute, ingestion, exports)
- ❌ **DO NOT delete retention resource group** (immutable storage must stay until retention period expires)
- ⏰ **Wait 1+ days** (demo immutability: 1 day; production: 2555 days ≈ 7 years)
- 🗑️ **Delete retention RG only after immutability expires**

---

## 1. Pre-Teardown Verification

Before you delete anything, verify the state:

### 1.1 Verify Both Resource Groups Exist

```bash
# Primary RG
az group show \
  --name "cosmos-backup-demo-dev-rg" \
  --query '{name: name, location: location}' \
  --output table

# Retention RG
az group show \
  --name "cosmos-backup-retention-dev-rg" \
  --query '{name: name, location: location}' \
  --output table
```

**Expected output:**
```
Name                               Location
─────────────────────────────────  ──────────
cosmos-backup-demo-dev-rg          eastus2
cosmos-backup-retention-dev-rg     eastus2
```

### 1.2 Verify Immutable Storage Has Data

```bash
# Check retention storage
RETENTION_STORAGE="cosmos-backup-retention-dev"  # Actual name from Bicep outputs

az storage account show \
  --name "$RETENTION_STORAGE" \
  --resource-group "cosmos-backup-retention-dev-rg" \
  --query '{name: name, tier: accessTier}'

# List blobs in retention storage
az storage blob list \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --query "[].{name: name, size: properties.contentLength}" \
  --output table
```

**Expected output:**
```
Name                                          Size
────────────────────────────────────────────  ────
exports/2026/04/27/14-00/data.json            25600
exports/2026/04/27/14-00/manifest.json        820
```

### 1.3 Document Immutability Expiry

Before deleting, record when immutability expires:

```bash
# Check expiry on one blob
az storage blob show \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "exports/2026/04/27/14-00/data.json" \
  --query 'immutabilityPolicy.expiresOn'
```

**Record this timestamp.** Blobs cannot be deleted until this time passes.

```
Example: 2026-04-28T14:01:30Z (1 day from now)
→ Can safely delete after 2026-04-28 14:02:00 UTC
```

---

## 2. Teardown Procedure — Phase 1 (Delete Primary RG)

### 2.1 Stop Ingestion & Export Jobs

Gracefully stop the workloads before deletion:

```bash
# Option A: Stop ingestion container via Container Apps
az container stop \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --name "ingestor"

# Option B: Scale down Container App to 0 (if using Container Apps)
az containerapp update \
  --name "ingestor" \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --min-replicas 0

# Wait for graceful shutdown (~5 seconds)
sleep 5
```

### 2.2 Export Final Snapshot (Optional)

If you want a last snapshot before deletion:

```bash
# Trigger export container job manually
# (if using on-demand trigger instead of scheduled)
# This is optional; scheduled exports already run every 6 hours

echo "Final export triggered (if manual trigger available)"
sleep 30
```

### 2.3 Delete Primary Resource Group

```bash
# List resources to be deleted
az resource list \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --query "[].{type: type, name: name}" \
  --output table

# Delete the primary RG (all compute resources)
az group delete \
  --name "cosmos-backup-demo-dev-rg" \
  --yes \
  --no-wait

echo "Deletion started (no-wait; will complete in background)"
```

**Wait for confirmation:**

```bash
# Poll deletion status every 30 seconds
for i in {1..20}; do
  STATUS=$(az group exists --name "cosmos-backup-demo-dev-rg")
  if [ "$STATUS" = "false" ]; then
    echo "✅ Primary RG deleted successfully"
    break
  fi
  echo "Deletion in progress... ($((i*30)) seconds elapsed)"
  sleep 30
done
```

**Typical deletion time:** 5–10 minutes

---

## 3. Verify Primary RG is Deleted

```bash
# Attempt to list resources (should fail with 404)
az resource list \
  --resource-group "cosmos-backup-demo-dev-rg" 2>&1 | grep -i "not found\|does not exist"

# Or simpler:
az group exists --name "cosmos-backup-demo-dev-rg"
# Output: false (✅ deleted)
```

**Expected output:**
```
false
```

### 3.1 Verify Retention RG is Still Intact

```bash
# Retention RG should still exist
az group show \
  --name "cosmos-backup-retention-dev-rg" \
  --query '{name: name, provisioning: provisioningState}' \
  --output table

# List blobs (should still be there)
az storage blob list \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --query "[].name" \
  --output table
```

**Expected output:**
```
Name
─────────────────────────────────
exports/2026/04/27/14-00/data.json
exports/2026/04/27/14-00/manifest.json
```

✅ **Phase 1 complete:** Primary RG deleted, retention RG preserved.

---

## 4. Wait for Immutability to Expire

### 4.1 Set Reminder

For demo (1-day retention):

```bash
# Set system reminder
at now + 1 day << 'EOF'
echo "ALERT: Immutability period expired. Can now delete retention RG." | mail -s "Demo Cleanup Ready" ops@example.com
EOF

# Or manual calendar reminder
echo "⏰ Immutability expires: 2026-04-28 14:02:00 UTC"
echo "   (Check this timestamp before proceeding to Phase 2)"
```

For production (7-year retention):

```bash
# Schedule yearly cleanup reminders
# Document in team calendar: "Annual backup retention review — delete if no longer needed"
```

### 4.2 Daily Check (During 1-Day Wait)

```bash
# Every 12 hours, verify blobs are still locked
EXPIRY=$(az storage blob show \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "exports/2026/04/27/14-00/data.json" \
  --query 'immutabilityPolicy.expiresOn' \
  -o tsv)

CURRENT=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
echo "Current time: $CURRENT"
echo "Expiry time:  $EXPIRY"
echo "Locked:       Yes (until $EXPIRY)"
```

---

## 5. Teardown Procedure — Phase 2 (Delete Retention RG) [AFTER 1 DAY]

⚠️ **WAIT UNTIL IMMUTABILITY EXPIRES BEFORE PROCEEDING**

### 5.1 Verify Immutability Has Expired

```bash
# Check if blob is still protected
az storage blob show \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "exports/2026/04/27/14-00/data.json" \
  --query 'immutabilityPolicy'
```

**If expired, output should be empty or show `null`:**
```
null
```

**If NOT expired, output shows expiry time:**
```
{
  "expiresOn": "2026-04-28T14:01:30Z",
  "policyMode": "Locked"
}
```

⚠️ **DO NOT proceed if blobs are still locked.**

### 5.2 (Optional) Manually Delete Individual Blobs

If you want to be selective (keep some exports, delete others):

```bash
# Delete one specific blob (after immutability expires)
az storage blob delete \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "exports/2026/04/27/14-00/data.json"

# Verify deletion
az storage blob exists \
  --account-name "$RETENTION_STORAGE" \
  --container-name "exports-archive" \
  --name "exports/2026/04/27/14-00/data.json"
# Output: "false" (✅ deleted)
```

### 5.3 Delete Entire Retention Resource Group

```bash
# Delete retention RG (all remaining storage)
az group delete \
  --name "cosmos-backup-retention-dev-rg" \
  --yes \
  --no-wait

echo "Retention RG deletion started"
```

**Wait for confirmation:**

```bash
# Poll deletion status
for i in {1..20}; do
  STATUS=$(az group exists --name "cosmos-backup-retention-dev-rg")
  if [ "$STATUS" = "false" ]; then
    echo "✅ Retention RG deleted successfully"
    break
  fi
  echo "Deletion in progress... ($((i*30)) seconds elapsed)"
  sleep 30
done
```

### 5.4 Verify Both RGs are Deleted

```bash
# Check both RGs
az group exists --name "cosmos-backup-demo-dev-rg"
# Output: false ✅

az group exists --name "cosmos-backup-retention-dev-rg"
# Output: false ✅

echo "✅ All demo resources deleted successfully"
```

---

## 6. Automated Teardown Scripts

### 6.1 Phase 1 Cleanup Script

Save as `scripts/teardown-phase1.sh`:

```bash
#!/bin/bash
set -e

PREFIX="cosmos-backup"
ENV="dev"
PRIMARY_RG="${PREFIX}-demo-${ENV}-rg"

echo "=== Phase 1: Delete Primary RG ==="
echo "This will delete: Cosmos DB, Storage (exports), Containers, Monitoring"
echo "The retention RG (immutable storage) will be preserved."
read -p "Continue? (yes/no) " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo "Deleting primary RG: $PRIMARY_RG"
az group delete --name "$PRIMARY_RG" --yes --no-wait

echo "Waiting for deletion..."
while az group exists --name "$PRIMARY_RG" > /dev/null 2>&1; do
  echo -n "."
  sleep 10
done

echo ""
echo "✅ Primary RG deleted successfully"
echo ""
echo "⏰ Next step: Wait 1 day for immutability to expire"
echo "   Then run: ./scripts/teardown-phase2.sh"
```

### 6.2 Phase 2 Cleanup Script

Save as `scripts/teardown-phase2.sh`:

```bash
#!/bin/bash
set -e

PREFIX="cosmos-backup"
ENV="dev"
RETENTION_RG="${PREFIX}-retention-${ENV}-rg"

echo "=== Phase 2: Delete Retention RG ==="
echo "This will delete: Immutable storage (AFTER 1-day retention expires)"
echo ""

# Verify immutability has expired
read -p "Have you waited for immutability to expire? (yes/no) " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted. Please wait and try again."
  exit 1
fi

echo "Deleting retention RG: $RETENTION_RG"
az group delete --name "$RETENTION_RG" --yes --no-wait

echo "Waiting for deletion..."
while az group exists --name "$RETENTION_RG" > /dev/null 2>&1; do
  echo -n "."
  sleep 10
done

echo ""
echo "✅ Retention RG deleted successfully"
echo "✅ All demo resources have been cleaned up"
```

---

## 7. Partial Cleanup (Keep Some Resources)

If you want to keep some resources (e.g., storage for audit):

### 7.1 Keep Retention Storage; Delete Primary RG Only

```bash
# Follow Phase 1 (delete primary RG)
# Skip Phase 2 (do NOT delete retention RG)

# Result: Cosmos DB and containers gone; immutable backups remain
# Useful for: Audit trail preservation after demo
```

### 7.2 Keep Cosmos DB; Delete Exports

```bash
# Manually delete export storage account (in primary RG)
az storage account delete \
  --name "cosmos-backup-exports-dev" \
  --resource-group "cosmos-backup-demo-dev-rg" \
  --yes

# Keep primary RG (Cosmos DB still running)
# Keep retention RG (immutable archives)

# Result: Cosmos DB active; backups preserved; exports deleted
# Useful for: Continue ingestion, preserve archives, reduce cost
```

---

## 8. Cleanup Validation Checklist

After teardown, verify:

- [ ] **Primary RG deleted**
  ```bash
  az group exists --name "cosmos-backup-demo-dev-rg"
  # Output: false
  ```

- [ ] **Retention RG still exists** (until immutability expires)
  ```bash
  az group exists --name "cosmos-backup-retention-dev-rg"
  # Output: true (until Phase 2)
  ```

- [ ] **No orphaned storage accounts**
  ```bash
  az storage account list --query "[].name" -o table
  # Should not see cosmos-backup-exports-dev or cosmos-backup-retention-dev
  ```

- [ ] **No orphaned Cosmos accounts**
  ```bash
  az cosmosdb list --query "[].name" -o table
  # Should not see cosmos-backup-cosmos-dev
  ```

- [ ] **Billing stopped for deleted resources** (verify after 24 hours)
  ```bash
  # Check Azure Cost Management
  # Previous day should show $0 for deleted services
  ```

---

## 9. Disaster: Accidental Deletion

If you accidentally delete the retention RG before immutability expires:

### 9.1 Can We Recover?

**Yes, if within 14 days:**

```bash
# Restore RG from soft delete
az group recover --name "cosmos-backup-retention-dev-rg"
```

**If deleted >14 days ago:** Data is gone (no recovery).

### 9.2 Prevention

```bash
# Enable delete lock on retention RG (prevents accidental deletion)
az lock create \
  --name "retention-rg-lock" \
  --resource-group "cosmos-backup-retention-dev-rg" \
  --lock-type CanNotDelete

# Verify lock
az lock list \
  --resource-group "cosmos-backup-retention-dev-rg" \
  --query "[].name"
```

---

## 10. Cost Analysis After Cleanup

### 10.1 Verify Charges Have Stopped

```bash
# Monitor cost for next billing cycle
# Azure Cost Management → Usage details → filter by date

# Expected:
# Before cleanup: ~$10–25/month
# After cleanup: ~$0 (except if retention RG still active = <$1/month)
```

### 10.2 Understanding Residual Costs

If you see small charges after deletion:

| Charge | Reason | How to Stop |
|--------|--------|-----------|
| Storage | Retention RG still exists | Run Phase 2 after immutability expires |
| Data egress | Archive rehydration | Don't download after deletion |
| Transaction logs | Last month's partial usage | None; will drop next month |

---

## 11. Cleanup Runbook Summary

### Quick Reference

| Phase | Action | Time | Command |
|-------|--------|------|---------|
| **Pre** | Verify RGs exist; record immutability expiry | 2 min | `az group show` + `az storage blob show` |
| **1a** | Stop ingestion | 1 min | `az container stop` |
| **1b** | Delete primary RG | 5–10 min | `az group delete --name ...` |
| **1c** | Verify primary RG gone | 1 min | `az group exists` |
| **Wait** | Wait for immutability | 1 day (demo) | Set reminder |
| **2a** | Verify immutability expired | 1 min | `az storage blob show` |
| **2b** | Delete retention RG | 5–10 min | `az group delete --name ...` |
| **2c** | Verify all deleted | 1 min | `az group exists` (both RGs) |
| **Done** | Check billing | Next cycle | Azure Cost Management |

---

## 12. Post-Demo Documentation

After cleanup, record:

```markdown
## Teardown Completed — 2026-04-28

- **Primary RG deleted:** 2026-04-27 15:30 UTC
- **Retention RG deleted:** 2026-04-28 15:35 UTC (after 1-day immutability expiry)
- **Total cost (demo):** $12.50 (2-day runtime)
- **Backup exports:** 4 exports created before deletion; all immutably stored then deleted
- **Incidents:** None
- **Lessons learned:**
  - Immutability enforcement works as expected
  - Deletion took ~10 min per RG
  - No orphaned resources remaining
```

---

## 13. Next Steps

- **Archive this document** in your team wiki or compliance folder (useful for next demo)
- **Share cleanup costs** with finance (budget variance)
- **Update procedures** based on lessons learned
- **Plan next demo** if needed

---

**Cleanup complete. All demo resources have been safely removed while preserving immutable backup storage until retention expired.**
