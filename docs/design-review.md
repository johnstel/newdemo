# Design Review — Azure Cosmos DB Backup & Recovery Demo

**Date:** 2026-04-27T11:47:49.954-04:00
**Facilitator:** Ripley (Lead Architect)
**Ceremony:** Pre-Work Design Review
**Status:** Active — Alignment artifact for all agents

---

## 1. Architecture Decisions & Boundaries

### 1.1 Two-Tier Backup Model (NOT Three)

The demo implements **two tiers** of backup, not three. Lambert's documentation decision referenced a warm snapshot tier; that is **out of scope** for the first build. Warm snapshots are a future enhancement the docs may mention as a variant, but no agent should implement them now.

| Tier | Mechanism | Retention | Owner |
|------|-----------|-----------|-------|
| **Short-term (Hot)** | Cosmos DB native continuous backup (PITR) | 7 or 30 days (parameterized, default `Continuous30Days`) | Dallas (Bicep) |
| **Long-term (Cold)** | Custom export → Immutable Blob Storage (Cool tier → Archive lifecycle) | Parameterized in days, default 2555 (≈7 years) | Dallas (Bicep for storage), Parker (export job code) |

### 1.2 WORM / Immutable Retention Storage

A **separate resource group** (`{prefix}-retention-rg`) holds immutable Blob Storage with:
- Version-level immutability policy, 1-day minimum retention (demo-friendly).
- Lifecycle rule: move to Cool after 7 days, Archive after 30 days.
- This resource group is **excluded from teardown** of the primary demo RG.
- Dallas owns the Bicep; Lambert documents the teardown exception.

### 1.3 Native Cosmos DB Capabilities — What Is and Isn't Supported

| Capability | Native? | Notes |
|------------|---------|-------|
| Continuous backup / PITR | ✅ Yes | 7-day or 30-day window. Restore creates a new account. |
| Periodic backup (legacy) | ✅ Yes | Not used in this demo; continuous is the enterprise path. |
| 7-year retention | ❌ No | Must be custom export to Blob. No agent may claim otherwise. |
| Restore to same account | ❌ No | Restore always creates a new account; we restore to `{prefix}-restored`. |
| Cross-region restore | ⚠️ Limited | Supported for multi-region accounts only; not in scope (single-region demo). |

### 1.4 Ingestion Workload

- **Runtime:** Node.js containerized app (not Azure Functions for v1). Container Apps or Container Instances, Dallas's choice based on Bicep simplicity.
- **Cadence:** One synthetic weather document every 20 seconds, configurable via `INGEST_INTERVAL_MS`.
- **Auth:** Managed identity + Cosmos DB data-plane RBAC. No account keys in code.
- **Data model:** `/cityId` partition key, database `demo`, container `weather`.

### 1.5 Export / Long-Term Retention Job

- **Runtime:** Same container host as ingestion OR a separate scheduled container job. Parker owns the code; Dallas provides the container host and schedule trigger.
- **Behavior:** Reads recent Cosmos DB documents via change feed or time-window query, writes JSON + manifest + SHA-256 hash to immutable Blob Storage.
- **Frequency:** Every 6 hours for the demo (parameterized).
- **Output format:** `exports/{yyyy}/{MM}/{dd}/{HH}-{mm}/data.json` + `manifest.json` with item count, hash, source timestamp range, export timestamp.

### 1.6 Observability

- Azure Monitor workspace + Log Analytics workspace in the primary RG.
- Cosmos DB diagnostic settings → Log Analytics (all categories).
- Container host logs → Log Analytics.
- Storage diagnostic settings → Log Analytics.
- Alert rules: Cosmos DB throttling (429s), ingestion gap > 60 seconds, export job failure.
- Dallas owns all Bicep for this. Lambert documents the dashboard walkthrough.

### 1.7 Security Baseline

- Managed identity everywhere; no account keys exported or used.
- RBAC assignments: ingestion identity gets `Cosmos DB Built-in Data Contributor` on the database; export identity gets the same plus `Storage Blob Data Contributor` on the retention storage.
- Key Vault for any future secrets (provisioned but may be empty in v1).
- Private endpoints are a **documented enhancement**, not required for v1 demo. Public endpoints with firewall IP rules are acceptable for the first build to reduce complexity and cost.

### 1.8 Region & Naming

- **Region:** `eastus2` default, parameterized as `location`.
- **Naming convention:** `{prefix}-{service}-{env}` where `prefix` defaults to `cosmos-backup`, `env` is `dev`/`test`/`prod`.
- **Tagging:** All resources tagged with `project=cosmos-backup-demo`, `environment={env}`, `owner=demo-team`, `costCenter=demo`.

---

## 2. File & Module Contracts

### 2.1 Dallas — Azure Infra Dev

**Owns:** Everything under `infra/`.

```
infra/
  main.bicep                    # Orchestrator; references all modules
  main.bicepparam               # Default parameter file (dev)
  parameters/
    dev.bicepparam
    test.bicepparam
    prod.bicepparam
  modules/
    cosmos.bicep                # Cosmos DB account, database, container, backup policy
    storage-retention.bicep     # Immutable Blob Storage in retention RG
    storage-exports.bicep       # Export target storage in primary RG (Cool/Archive lifecycle)
    container-host.bicep        # Container Apps or ACI for ingestion + export jobs
    monitoring.bicep             # Log Analytics, diagnostic settings, alert rules
    identity.bicep              # User-assigned managed identities
    rbac.bicep                  # Role assignments (Cosmos data plane, Storage data plane)
    keyvault.bicep              # Key Vault (future use)
    resource-groups.bicep       # Primary RG + retention RG (subscription-level deployment)
```

**Contracts:**
- `main.bicep` outputs: `cosmosAccountEndpoint`, `cosmosDatabaseName`, `cosmosContainerName`, `exportStorageAccountName`, `retentionStorageAccountName`, `containerHostName`, `ingestionIdentityClientId`, `exportIdentityClientId`.
- Idempotent: repeated deployments produce no errors and no drift.
- Environment-parameterized: `environmentName` controls naming, SKU selection, retention windows.
- Subscription-level deployment for resource groups; resource-level deployments nested inside.

### 2.2 Parker — Data App Dev

**Owns:** Everything under `apps/`.

```
apps/
  weather-ingestor/
    src/
      index.ts                  # Entry point: timer loop, graceful shutdown
      cosmos-client.ts          # Cosmos DB client setup (managed identity)
      data-generator.ts         # Synthetic weather document generator
    package.json
    Dockerfile
    .env.example                # Documents expected env vars; NOT committed with values
  backup-exporter/
    src/
      index.ts                  # Scheduled export job entry point
      cosmos-reader.ts          # Read recent documents (time-window query)
      blob-writer.ts            # Write export payload + manifest to Blob
      manifest.ts               # SHA-256 hash, item count, timestamp range
    package.json
    Dockerfile
    .env.example
```

**Contracts:**
- Both apps read env vars matching Dallas's Bicep outputs (see §2.1).
- Both apps use `@azure/identity` `DefaultAzureCredential` for auth.
- Both apps handle `SIGINT`/`SIGTERM` for clean shutdown.
- Weather ingestor writes one document per interval; no batch writes.
- Backup exporter writes one export bundle per invocation; idempotent (same time window = same output overwritten).

### 2.3 Lambert — Documentation Lead

**Owns:** Everything under `docs/` plus root `README.md`.

```
README.md                       # Hub: overview, quick start pointer, architecture summary
docs/
  design-review.md              # THIS DOCUMENT (Ripley-owned, Lambert maintains formatting)
  architecture.md               # System design, tier model, security, cost
  deployment-guide.md           # Step-by-step Bicep deployment + verification
  backup-and-retention.md       # Native PITR + custom archive operations
  restore-and-validation.md     # Restore workflows, evidence checklists
  demo-walkthrough.md           # Scripted 15–20 minute demo with timestamps
  operations-runbook.md         # Monitoring, alerts, maintenance, compliance
  cleanup.md                    # Teardown primary RG, preserve retention RG
  assumptions.md                # Known limits, open questions, compliance caveats
```

**Contracts:**
- No compliance claims without caveats (per Lambert's accepted decision).
- Demo walkthrough must reference actual scripts and CLI commands, not hypothetical ones.
- All docs cross-link; README is the hub.
- Cost estimates in deployment guide, updated after Dallas finalizes SKUs.

### 2.4 Bishop — Tester

**Owns:** Everything under `scripts/` (validation scripts) and reviewer gates.

```
scripts/
  validate-local.sh             # Bicep build, lint, file presence checks
  validate-deployment.sh        # Post-deploy: resource existence, config verification
  validate-ingestion.sh         # Document count delta over 25+ seconds
  validate-backup.sh            # Cosmos backup policy, storage immutability, lifecycle
  validate-restore.sh           # Trigger restore, verify restored account/data
  validate-cleanup.sh           # Verify primary RG deleted, retention RG intact
  teardown.sh                   # az group delete for primary RG only
```

**Contracts:**
- Scripts are idempotent and safe to re-run.
- Each script exits 0 on pass, non-zero on fail, with human-readable output.
- Restore validation targets a separate account (`{prefix}-restored-{env}`); never the live account.
- Bishop reviews all agent work before demo-ready approval.

---

## 3. Naming, Tagging & Resource Group Rules

### 3.1 Resource Groups

| Resource Group | Purpose | Teardown? |
|----------------|---------|-----------|
| `{prefix}-demo-{env}-rg` | Primary: Cosmos, container host, monitoring, export storage, Key Vault, identities | ✅ Yes |
| `{prefix}-retention-{env}-rg` | WORM: Immutable Blob Storage for long-term retention | ❌ No — preserved on teardown |

### 3.2 Naming Pattern

`{prefix}-{service}-{env}` — examples:
- `cosmos-backup-cosmos-dev` (Cosmos account)
- `cosmos-backup-ingestor-dev` (Container app)
- `cosmosbackupretdev` (Storage account — no hyphens, 24 char max)

### 3.3 Required Tags

| Tag | Value | Required? |
|-----|-------|-----------|
| `project` | `cosmos-backup-demo` | ✅ |
| `environment` | `dev` / `test` / `prod` | ✅ |
| `owner` | `demo-team` | ✅ |
| `costCenter` | `demo` | ✅ |
| `createdBy` | `bicep` | ✅ |

---

## 4. Cosmos Native vs. Custom Backup — Capability Matrix

This table is the **authoritative reference** for the entire team. If you're unsure whether something is native, check here first.

| Feature | Native Cosmos DB | Custom (Our Export) |
|---------|-----------------|---------------------|
| Point-in-time restore | ✅ Within retention window | ❌ Not point-in-time; periodic snapshots |
| Retention ≤ 30 days | ✅ Continuous30Days | N/A (use native) |
| Retention > 30 days | ❌ Not supported | ✅ Immutable Blob archive |
| Retention ≈ 7 years | ❌ Not supported | ✅ 2555-day immutability policy |
| Restore target | New Cosmos account (always) | Requires import back to Cosmos |
| Restore granularity | Per-account, per-database, per-container | Per-export-bundle (time window) |
| Compliance / WORM | N/A | ✅ Immutable Blob with legal hold option |
| Cost | Included in Cosmos pricing | Storage + compute for export job |

---

## 5. Validation & Reviewer Gates

### 5.1 Gate Schedule

| Gate | Trigger | Reviewer | Pass Criteria |
|------|---------|----------|---------------|
| G1: Bicep Build | Dallas completes `infra/` | Bishop + Ripley | `az bicep build` succeeds; `az deployment sub what-if` clean; parameters for dev/test/prod present |
| G2: App Build | Parker completes `apps/` | Bishop | `docker build` succeeds for both apps; no secrets in source; env vars documented |
| G3: Deployment Smoke | Dallas + Parker deploy to dev | Bishop | All resources exist; ingestion writing; Cosmos backup policy correct |
| G4: Backup & Restore | Full cycle executed | Bishop + Ripley | PITR restore succeeds to separate account; export bundle in retention storage with valid manifest |
| G5: Documentation | Lambert completes `docs/` | Ripley | All docs present; no false compliance claims; demo walkthrough references real commands |
| G6: Demo Ready | All gates passed | Ripley | End-to-end 15–20 min walkthrough executed successfully |

### 5.2 Rejection Protocol

Per team skill `.copilot/skills/reviewer-protocol/SKILL.md`:
- Rejected work is **locked out** from the original author.
- A different agent must revise.
- Deadlock → escalate to John.

---

## 6. Key Architectural Decisions for Decision Log

These decisions are recorded in `.squad/decisions/inbox/ripley-design-review.md`:

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Two-tier backup (native PITR + custom archive), not three | Warm snapshots add complexity without demo value in v1. |
| D2 | Container Apps or ACI for workloads, not Azure Functions v1 | Simpler Dockerfile-based deployment; no Function plan SKU verification needed. |
| D3 | Public endpoints with IP firewall for v1 | Private endpoints add ~$10/mo per endpoint and VNet complexity; not justified for a demo. Documented as enhancement. |
| D4 | Single-region (eastus2) only | Multi-region adds cost and cross-region restore complexity; out of scope. |
| D5 | Separate retention RG excluded from teardown | Demonstrates WORM compliance pattern; prevents accidental archive deletion. |
| D6 | 1-day minimum immutability for demo, parameterized for production | Keeps demo fast to clean up while showing the pattern. |
| D7 | Export every 6 hours (parameterized), not real-time change feed | Simpler to implement and explain; change feed export is a documented enhancement. |
| D8 | No compliance claims without caveats | Aligns with Lambert's accepted documentation decision. |
| D9 | Restore always to a new/separate account | Cosmos DB PITR creates a new account; we don't attempt in-place restore. |
| D10 | Managed identity + RBAC everywhere; no account keys | Zero-trust baseline for enterprise demo credibility. |

---

## 7. Work Sequence & Dependencies

```
Phase 1 — Infrastructure (Dallas)
  ├── resource-groups.bicep
  ├── identity.bicep
  ├── cosmos.bicep
  ├── storage-retention.bicep
  ├── storage-exports.bicep
  ├── monitoring.bicep
  ├── rbac.bicep
  ├── keyvault.bicep
  ├── container-host.bicep
  └── main.bicep + parameter files
  → Gate G1: Bishop + Ripley review

Phase 2 — Applications (Parker, parallel with Phase 1 after identity/cosmos contracts agreed)
  ├── weather-ingestor app
  └── backup-exporter app
  → Gate G2: Bishop review

Phase 3 — Integration (Dallas + Parker)
  ├── Deploy to dev environment
  └── Verify end-to-end
  → Gate G3: Bishop review

Phase 4 — Backup & Restore Cycle (Bishop leads validation)
  ├── Trigger PITR restore
  ├── Verify export to retention storage
  └── Evidence collection
  → Gate G4: Bishop + Ripley review

Phase 5 — Documentation (Lambert, parallel with Phases 2–4)
  ├── All docs from §2.3
  └── Demo walkthrough script
  → Gate G5: Ripley review

Phase 6 — Demo Ready (Ripley)
  └── End-to-end walkthrough execution
  → Gate G6: Ripley final approval
```

---

## 8. Cost Awareness

| Resource | Estimated Monthly (Dev) | Notes |
|----------|------------------------|-------|
| Cosmos DB (serverless or 400 RU/s) | $0–25 | Serverless preferred for dev |
| Container Apps (consumption) | $0–5 | Minimal compute for 20s interval |
| Storage (Cool + Archive) | < $1 | Tiny data volume in demo |
| Log Analytics | $0–5 | Small ingestion volume |
| Key Vault | < $1 | Minimal operations |
| **Total (dev)** | **~$10–35/month** | |

Dallas should prefer serverless Cosmos DB for dev, provisioned throughput for prod parameter file.

---

## 9. Open Items / Parking Lot

| Item | Owner | Status |
|------|-------|--------|
| Private endpoint variant | Dallas | Future enhancement; documented, not built |
| Warm snapshot tier | Ripley | Deferred to v2 |
| Change feed export (real-time) | Parker | Deferred to v2 |
| Multi-region | Ripley | Out of scope |
| CMK encryption | Dallas | Documented as prod requirement, not implemented |
| GitHub Actions CI/CD | Dallas | Nice-to-have; not blocking demo |

---

*This document is the alignment contract for all agents. If your work conflicts with a decision here, raise it with Ripley before proceeding.*
