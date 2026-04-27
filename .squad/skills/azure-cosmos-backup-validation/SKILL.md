---
name: "azure-cosmos-backup-validation"
description: "Validation pattern for Azure Cosmos DB backup demos with native short-term restore and long-term archive retention"
domain: "testing"
confidence: "high"
source: "extracted from Cosmos DB enterprise backup demo validation work on 2026-04-27T11:47:49.954-04:00"
---

## Context

Use this skill when validating an Azure Cosmos DB backup or restore demo that combines Bicep deployment, continuous ingestion, native Cosmos backup, and long-term archive retention.

## Patterns

- Separate validation into local, deployment, ingestion, backup, restore, and cleanup stages — each as an independent parameterized script.
- Mark live Azure checks explicitly; do not present local smoke checks as proof of backup or restore behavior.
- Validate native Cosmos backup for short-term restore and validate long-term retention through archive/export storage controls.
- Treat seven-year retention as 2555 days unless the project documents a different leap-year policy.
- Require restore rehearsal to a separate target account before enterprise demo approval.
- Verify ingestion by count delta across at least one full cadence interval plus buffer (20s cadence → 25s wait).
- Secret scan in `.env.example` must strip comment lines (`grep -v '^\s*#'`) before regex matching to avoid false positives on commented example values.
- WORM delete test: warn (not fail) when immutability policy is unlocked; document the lock command and require it for full production evidence.
- Include a safety guard in restore scripts: exit immediately if restore target == source account.
- Unit test stubs must use a monotonic counter or UUID for ID generation; `Date.now()` alone produces duplicates in synchronous test loops.

## Script Structure (per script)

```bash
set -euo pipefail
# Parameterized defaults: PREFIX, ENV, LOCATION
# Color helpers: PASS(), FAIL(), WARN(), INFO(), HEADER()
# FAILURES counter: increments on FAIL
# Exit: 0 if FAILURES==0, else 1
```

## Examples

- Local: `validate-local.sh` — Bicep build + file presence + `.env.example` hygiene. Azure-free.
- Deployment: `validate-deployment.sh` — resource groups, Cosmos account, backup policy, partition key, identities, tags.
- Ingestion: `validate-ingestion.sh` — T0 count, 25s wait, T1 count, delta ≥ 1, schema check.
- Backup: `validate-backup.sh` — Cosmos backup policy type, lifecycle rules, immutability, WORM delete test, manifest field check.
- Restore: `validate-restore.sh` — safety check, delete sample, PITR trigger, poll loop, restored count verification.
- Cleanup: `validate-cleanup.sh` — primary RG deleted, retention RG present, blobs intact.

## Anti-Patterns

- Claiming Cosmos native backup alone satisfies seven-year point-in-time restore.
- Restoring into the source account or active demo container.
- Using a single successful deployment as proof that backup retention works.
- Grepping `.env.example` without excluding comment lines — causes false positives.
- Treating an unlocked immutability policy as equivalent to a locked one for compliance evidence.
- Using `Date.now()` as a unique ID stub in unit tests — creates duplicate IDs in synchronous loops.
