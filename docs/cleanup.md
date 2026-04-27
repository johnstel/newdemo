# Cleanup Guide — Azure Cosmos DB Backup Demo

**Date:** 2026-04-27  
**Status:** Demo-ready  
**Audience:** Operators, lab engineers

> For the teardown script reference, also see [Teardown](teardown.md).

---

## Overview

The demo uses two resource groups with **intentionally different teardown behavior**:

| Resource Group | Contents | Teardown behavior |
|----------------|----------|-------------------|
| `{prefix}-demo-{env}-rg` | Cosmos DB, Container Apps, monitoring, export storage, Key Vault | **Deleted** by `teardown.sh` |
| `{prefix}-retention-{env}-rg` | WORM immutable Blob Storage | **Preserved** — never deleted by scripts |

This separation ensures the compliance archive survives accidental or routine cleanup.

---

## Standard Teardown (Primary RG Only)

```bash
# Set variables (must match your deployment)
export PREFIX="cosmos-backup"
export ENV="dev"

# Confirm what will be deleted before running
bash scripts/teardown.sh
```

The script will:
1. Verify you are logged into Azure.
2. Confirm the retention RG will **not** be touched.
3. Prompt you to type the full resource group name to confirm deletion.
4. Submit an async delete for the primary RG.

To skip the confirmation prompt (CI/CD use only):

```bash
SKIP_CONFIRM=true PREFIX=$PREFIX ENV=$ENV bash scripts/teardown.sh
```

---

## Post-Teardown Validation

After deletion completes (typically 5–15 minutes), run the cleanup validation:

```bash
PREFIX=$PREFIX ENV=$ENV bash scripts/validate-cleanup.sh
```

This checks:
- Primary RG is deleted or empty.
- Retention RG still exists and was not deleted.
- Retention storage blobs are still present.
- Restored Cosmos account (if any) has been removed.

---

## Manually Deleting the Retention RG

The WORM immutability policy prevents blob deletion until the retention period expires. For demo purposes, the policy is **unlocked** and set to 1 day minimum, so blobs can be deleted after 24 hours.

When you are ready to remove the retention archive:

```bash
RETENTION_RG="${PREFIX}-retention-${ENV}-rg"

# Option 1: Delete the entire retention RG
az group delete --name "$RETENTION_RG" --yes

# Option 2: Delete only the storage account (keeps the RG shell)
RETENTION_STORAGE="${PREFIX//[-_]/}ret${ENV}"
az storage account delete --name "$RETENTION_STORAGE" --resource-group "$RETENTION_RG" --yes
```

> ⚠️ If the immutability policy is **locked**, Azure will refuse deletion until the retention period expires. This is the intended compliance behavior. In production, do not delete the retention RG — contact your compliance team.

---

## Re-Deploying After Cleanup

After full cleanup, re-deploy using:

```bash
cd infra
az deployment sub create \
  --template-file main.bicep \
  --parameters prefix="$PREFIX" environmentName="$ENV" location="$LOCATION" \
  --location "$LOCATION"
```

All Bicep resources are **idempotent** — re-running the deployment recreates everything cleanly.

---

## Cost Implications After Teardown

- The primary RG deletion stops Cosmos DB, Container Apps, and monitoring charges immediately.
- Export storage in the primary RG is deleted with the RG.
- Retention storage in the retention RG **continues to accrue minimal storage costs** until you delete it.
- At demo scale, retention storage costs are <$1/month.

---

## Related Documents

- [Teardown](teardown.md) — Teardown script reference
- [Operations Runbook](operations-runbook.md) — Day-to-day operations
- [Deployment Guide](deployment-guide.md) — How to redeploy
