# Validation & Test Plan — Azure Cosmos DB Backup Demo

**Author:** Bishop (Tester)  
**Date:** 2026-04-27T11:47:49.954-04:00  
**Status:** Active  
**Aligns with:** `docs/design-review.md` §5 — Validation & Reviewer Gates

---

## Overview

This document is the authoritative test plan for the Azure Cosmos DB backup demo. It defines the six reviewer gates (G1–G6), the evidence required to pass each gate, and the boundary between local/static checks and deployed-environment checks.

### Validation Tiers

| Tier | Where it runs | Azure required? | Script |
|------|--------------|-----------------|--------|
| **Local / Static** | Developer machine, CI | ❌ No | `scripts/validate-local.sh` |
| **Deployment smoke** | Against deployed Azure resources | ✅ Yes | `scripts/validate-deployment.sh` |
| **Ingestion** | Against running ingestor + Cosmos | ✅ Yes | `scripts/validate-ingestion.sh` |
| **Backup/WORM** | Against deployed storage + Cosmos | ✅ Yes | `scripts/validate-backup.sh` |
| **Restore (PITR)** | Triggers live Cosmos restore | ✅ Yes + cost | `scripts/validate-restore.sh` |
| **Cleanup** | After teardown | ✅ Yes | `scripts/validate-cleanup.sh` |

> ⚠️ **Important:** Local validation proves syntax and structure only. It does **not** prove backup retention, restore correctness, ingestion cadence, or WORM policy behavior. Those require a live Azure subscription and deployed resources.

---

## Gate Definitions

### G1 — Bicep Build ✅/❌

**Trigger:** Dallas delivers `infra/` module set.  
**Reviewers:** Bishop + Ripley  
**Script:** `scripts/validate-local.sh`

#### Pass Criteria

| Check | Method | Evidence |
|-------|--------|----------|
| `az bicep build` exits 0 on `infra/main.bicep` | `validate-local.sh` | Script output shows `[PASS] az bicep build succeeded` |
| All modules in `infra/modules/*.bicep` build clean | `validate-local.sh` | Each module: `[PASS] Module build OK: <name>.bicep` |
| Parameter files present for dev/test/prod | `validate-local.sh` | 3× `[PASS] File present: infra/parameters/<env>.bicepparam` |
| `az deployment sub what-if` produces no destructive actions | Manual / preflight CI | Reviewer screenshots `what-if` output; no deletions of existing resources |
| No account keys, tenant IDs, or subscription IDs hard-coded | Grep in CI or `validate-local.sh` | No `[FAIL]` on secret pattern scan |

#### Fail Conditions

- `az bicep build` exits non-zero on any module.
- `what-if` shows unintended resource deletions.
- Any account key or hard-coded secret found.

---

### G2 — App Build ✅/❌

**Trigger:** Parker delivers `apps/weather-ingestor/` and `apps/backup-exporter/`.  
**Reviewers:** Bishop  
**Prerequisite:** G1 passed.

#### Pass Criteria

| Check | Method | Evidence |
|-------|--------|----------|
| `docker build` exits 0 for weather-ingestor | `docker build -t ingestor:test apps/weather-ingestor` | Build log shows `Successfully built` |
| `docker build` exits 0 for backup-exporter | `docker build -t exporter:test apps/backup-exporter` | Build log shows `Successfully built` |
| No secrets in source (`cosmos-client.ts` uses `DefaultAzureCredential`) | Code review + `validate-local.sh` `.env.example` check | No `[FAIL]` on secret hygiene |
| `.env.example` files present and contain no real values | `validate-local.sh` | `[PASS] No embedded secrets detected` |
| Unit tests pass | `cd tests && npm ci && npm test` | All tests green with ≥70% coverage |

#### Fail Conditions

- `docker build` fails for either app.
- Any account key found in source or image.
- Unit tests fail.

---

### G3 — Deployment Smoke ✅/❌

**Trigger:** Dallas and Parker deploy to dev environment.  
**Reviewers:** Bishop  
**Prerequisites:** G1 + G2 passed.  
**Script:** `scripts/validate-deployment.sh` + `scripts/validate-ingestion.sh`

#### Pass Criteria

| Check | Method | Evidence |
|-------|--------|----------|
| Primary RG exists and is `Succeeded` | `validate-deployment.sh` | `[PASS] Resource group exists: cosmos-backup-demo-dev-rg` |
| Retention RG exists and is `Succeeded` | `validate-deployment.sh` | `[PASS] Resource group exists: cosmos-backup-retention-dev-rg` |
| Cosmos account exists with `Continuous` backup | `validate-deployment.sh` | `[PASS] Cosmos backup type: Continuous` |
| Cosmos backup tier matches parameter (default `Continuous30Days`) | `validate-deployment.sh` | `[PASS] Backup tier matches expected` |
| Cosmos database `demo` and container `weather` exist | `validate-deployment.sh` | `[PASS]` for both |
| Partition key is `/cityId` | `validate-deployment.sh` | `[PASS] Partition key is /cityId` |
| Managed identities present | `validate-deployment.sh` | `[PASS]` for ingestor + exporter identities |
| Container host running | `validate-deployment.sh` | `[PASS] Container host running` |
| Required tags on primary RG | `validate-deployment.sh` | `[PASS]` for project, environment, owner, costCenter, createdBy |
| Ingestor writing ≥1 document per 25 seconds | `validate-ingestion.sh` | `[PASS] Ingestion active — delta X >= required 1` |
| Document schema: id, cityId, timestamp present | `validate-ingestion.sh` | `[PASS]` for all three fields |
| Timestamp is ISO 8601 | `validate-ingestion.sh` | `[PASS] Timestamp is ISO 8601 format` |

#### Fail Conditions

- Any resource group missing or not provisioned.
- Backup policy not `Continuous`.
- Partition key not `/cityId`.
- Zero new documents in 25-second window.
- Document missing required fields.

---

### G4 — Backup & Restore ✅/❌

**Trigger:** Full backup/restore cycle executed.  
**Reviewers:** Bishop + Ripley  
**Prerequisites:** G3 passed; at least 30+ minutes of ingestion history.  
**Scripts:** `scripts/validate-backup.sh` + `scripts/validate-restore.sh`

#### Pass Criteria — Backup

| Check | Method | Evidence |
|-------|--------|----------|
| Cosmos backup type is `Continuous` | `validate-backup.sh` | `[PASS] Cosmos backup type: Continuous` |
| Cosmos account appears in restorable accounts list | `validate-backup.sh` | `[PASS] Cosmos account appears in restorable accounts list` |
| Export storage lifecycle: Cool ≤7 days | `validate-backup.sh` | `[PASS] Cool tier rule present` |
| Export storage lifecycle: Archive ≤30 days | `validate-backup.sh` | `[PASS] Archive tier rule present` |
| Retention storage: version-level immutability enabled | `validate-backup.sh` | `[PASS] Version-level immutability enabled` |
| Immutability period ≥1 day | `validate-backup.sh` | `[PASS] Immutability period X days >= minimum 1` |
| Delete attempt blocked by WORM policy | `validate-backup.sh` | `[PASS] Delete correctly blocked by immutability policy` OR blob persists after delete attempt |
| Export blobs present with valid manifest | `validate-backup.sh` | `[PASS] Manifest field present: itemCount`, sha256, exportedAt, sourceFrom, sourceTo |

#### Pass Criteria — Restore (PITR)

| Check | Method | Evidence |
|-------|--------|----------|
| Restore targets a NEW account (not the live one) | `validate-restore.sh` | `[PASS] Safety: restore target != live account` |
| Restore completed (`provisioningState: Succeeded`) | `validate-restore.sh` (polls) | `[PASS] Restore completed successfully` |
| Restored account endpoint is distinct from live | `validate-restore.sh` | `[PASS] Restored account endpoint is distinct from live account` |
| Container `weather` exists in restored account | `validate-restore.sh` | `[PASS] Container 'weather' exists in restored account` |
| Restored document count > 0 | `validate-restore.sh` | `[PASS] Restored account contains N documents` |
| Deleted documents are present in restored account | `validate-restore.sh` | Restored count ≥ pre-loss count |

#### Fail Conditions

- Cosmos backup policy is `Periodic` instead of `Continuous`.
- Immutability not enabled on retention storage.
- WORM delete attempt succeeds AND blob is gone (policy unlocked or inactive).
- Restore account == live account.
- Restored container empty or missing.
- Manifest fields missing.

> ⚠️ **Seven-year retention note:** Cosmos native backup does NOT support 7-year PITR. The 2555-day (≈7 year) retention window is validated entirely through the immutability policy on retention storage and the lifecycle rules on export storage. Any claim that Cosmos native backup covers multi-year retention is a **documentation error** and grounds for immediate G4 rejection.

---

### G5 — Documentation ✅/❌

**Trigger:** Lambert completes `docs/`.  
**Reviewers:** Ripley  
**Prerequisites:** None — runs in parallel with Phases 2–4.  
**Script:** `scripts/validate-local.sh` (file presence section)

#### Pass Criteria

| Check | Method | Evidence |
|-------|--------|----------|
| All required docs present | `validate-local.sh` | `[PASS] File present: docs/<name>.md` for all 9 docs |
| `README.md` present at repo root | `validate-local.sh` | `[PASS] File present: README.md` |
| No compliance claims without caveats | Human review | Reviewer confirms no uncaveated regulatory claims |
| Demo walkthrough references real scripts/commands | Human review | Reviewer spot-checks 3+ commands in `docs/demo-walkthrough.md` |
| Cost estimates present in deployment guide | Human review | `docs/deployment-guide.md` contains cost table |
| All docs cross-link; README is the hub | Human review | Each doc links back to README; README links to each doc |

#### Fail Conditions

- Any required doc file missing.
- Any statement claiming 7-year Cosmos native backup without caveat.
- Demo walkthrough contains hypothetical commands not present in `scripts/`.

---

### G6 — Demo Ready ✅/❌

**Trigger:** All previous gates passed.  
**Reviewers:** Ripley (final approval)  
**Prerequisites:** G1–G5 all passed.

#### Pass Criteria

| Check | Method | Evidence |
|-------|--------|----------|
| All scripts exit 0 against dev environment | Re-run all validate-*.sh | Full green output saved as evidence |
| End-to-end walkthrough executed in 15–20 minutes | Ripley live demo | Timestamped walkthrough log or recording |
| Restore rehearsal completed (restored account cleaned up) | Post-G4 teardown | Restored account deleted; `validate-cleanup.sh` for restored account passes |
| No open critical issues | GitHub Issues check | Zero open issues tagged `severity:critical` |

#### Fail Conditions

- Any validate script fails at G6 re-run.
- Walkthrough cannot be completed in 20 minutes.
- Open critical issues remain.

---

## Data Loss Simulation Procedure

The following is the documented procedure for simulating data loss and verifying recovery. This is the sequence for G4.

### Step 1 — Establish baseline
```bash
PREFIX=cosmos-backup ENV=dev bash scripts/validate-ingestion.sh
```
Record the document count. Allow at least 30 minutes of ingestion before proceeding.

### Step 2 — Capture restore timestamp
```bash
T_RESTORE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "Restore timestamp: $T_RESTORE"
```

### Step 3 — Delete sample documents
The `validate-restore.sh` script handles this automatically, but you can also run:
```bash
# Manual: delete a known document
az cosmosdb sql container delete-item \
  --account-name cosmos-backup-cosmos-dev \
  --resource-group cosmos-backup-demo-dev-rg \
  --database-name demo \
  --name weather \
  --item-id "<doc-id>" \
  --partition-key-value "<cityId>"
```

### Step 4 — Trigger restore
```bash
PREFIX=cosmos-backup ENV=dev LOCATION=eastus2 \
  bash scripts/validate-restore.sh
```
This script:
1. Captures T0 count.
2. Deletes `DELETE_SAMPLE_SIZE` documents (default: 5).
3. Triggers PITR restore to `cosmos-backup-restored-dev`.
4. Polls until complete (up to 90 minutes).
5. Verifies restored document count.

### Step 5 — Verify recovery
The script outputs `[PASS] RESTORE VALIDATION PASSED` when recovery is confirmed.

### Step 6 — Clean up restored account
```bash
az cosmosdb delete \
  --name cosmos-backup-restored-dev \
  --resource-group cosmos-backup-demo-dev-rg \
  --yes
```

---

## Immutability Behavior Validation

The WORM validation in `validate-backup.sh` tests immutability by:

1. Writing a test blob to the retention container.
2. Attempting deletion.
3. Checking whether the blob survives the delete attempt.

### Expected outcomes by policy state

| Policy state | Expected delete result | Script outcome |
|---|---|---|
| Unlocked (demo mode) | Delete may succeed | `[WARN] Test blob was deleted — immutability policy may be unlocked` |
| Locked (production mode) | Delete blocked with `BlobImmutableDueToPolicy` | `[PASS] Delete correctly blocked` |

### Locking the policy (for full G4 proof)
```bash
# Lock the immutability policy (irreversible for the retention period)
az storage container immutability-policy lock \
  --account-name cosmosbackupretdev \
  --container-name backups \
  --resource-group cosmos-backup-retention-dev-rg \
  --if-match "<etag-from-show-output>"
```

> ⚠️ After locking, the policy cannot be reduced or deleted until the retention period expires. For a 1-day demo policy, wait 24 hours before cleanup. Use `SKIP_CONFIRM=true bash scripts/teardown.sh` for primary RG teardown only.

---

## Cleanup Validation Procedure

After demo teardown, verify with:
```bash
PREFIX=cosmos-backup ENV=dev bash scripts/validate-cleanup.sh
```

### Expected state after teardown

| Resource | Expected state |
|---|---|
| `cosmos-backup-demo-dev-rg` | Deleted (NOT_FOUND) |
| `cosmos-backup-retention-dev-rg` | Present (Succeeded) |
| Retention blobs | Present |
| `cosmos-backup-restored-dev` | Deleted |

---

## Unit Test Coverage

Unit tests live in `tests/unit/` and cover the app code contracts:

| Test file | What it tests | Gate |
|---|---|---|
| `data-generator.test.ts` | Weather doc schema, partition key, ID uniqueness, no secrets in payload | G2 |
| `manifest.test.ts` | SHA-256 determinism, ISO 8601 timestamps, export path format, empty batch | G2 |
| `cosmos-client.test.ts` | Env var contract, forbidden keys/secrets, DefaultAzureCredential requirement | G2 |

### Running tests

```bash
cd tests
npm ci
npm test
```

Tests are stubbed until `apps/` is implemented. The stubs pass with the stub implementations. Once Parker delivers `apps/`, update the import statements from the stub implementations to the real ones.

### Coverage threshold

70% line/branch/function coverage is required for G2. Raise to 80% before G6 if Parker adds more logic.

---

## Common Failure Modes & Remediation

| Symptom | Likely cause | Fix |
|---|---|---|
| Ingestion delta = 0 | Container host not running or RBAC missing | Check container logs; verify `Cosmos DB Built-in Data Contributor` RBAC on database |
| Backup policy `Periodic` instead of `Continuous` | Wrong Bicep parameter or account type | Check `cosmos.bicep` `backupPolicy` property; re-deploy |
| Immutability `false` | Storage account not configured for version-level immutability | Verify `infra/modules/storage-retention.bicep` sets `isVersioningEnabled` and `immutableStorageWithVersioning.enabled` |
| Restore account empty | RBAC missing on restored account | Assign `Cosmos DB Built-in Data Reader` to validator identity |
| `az cosmosdb sql query` unavailable | CLI extension not installed | `az extension add --name cosmosdb-preview` |
| Export blobs missing | Exporter never triggered | Trigger: `az container restart --name cosmos-backup-exporter-dev --resource-group cosmos-backup-demo-dev-rg` |
| Manifest field missing | Parker's `manifest.ts` incomplete | Refer to `tests/unit/manifest.test.ts` for required fields |

---

## Evidence Checklist

When submitting for G4 approval, provide the following evidence files (e.g., in a GitHub PR comment or attached artifacts):

- [ ] `validate-local.sh` output (all `[PASS]`)
- [ ] `validate-deployment.sh` output (all `[PASS]`)
- [ ] `validate-ingestion.sh` output (delta ≥ 1, schema checks green)
- [ ] `validate-backup.sh` output (all backup + WORM checks green)
- [ ] `validate-restore.sh` output (restore completed, count matches)
- [ ] Screenshot: Azure Portal showing restored Cosmos account with documents
- [ ] Screenshot: Azure Portal showing immutability policy on retention storage
- [ ] `npm test` output from `tests/` (all unit tests green)

---

*This document is maintained by Bishop. Updates require a new entry in `.squad/agents/bishop/history.md`.*
