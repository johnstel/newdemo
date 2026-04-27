# Bishop History

## Seed Context

- **User:** John Stelmaszek
- **Project:** newdemo
- **Purpose:** Enterprise Azure demo for Azure Cosmos DB backup and restore.
- **Stack:** Azure Cosmos DB, Bicep, Azure-hosted ingestion workload.
- **Initial scope:** Build the entire environment from the ground up, continuously add sample documents every 20 seconds, and document short-term plus configurable long-term backup coverage up to 7 years.

## Learnings

- 2026-04-27T11:22:37.720-04:00 — Added validation runbook at `docs/restore-and-validation.md` covering local Bicep validation, preflight what-if, deployment smoke checks, 20-second ingestion proof, Cosmos backup policy checks, short-term restore rehearsal, long-term archive retention up to 2555 days, failure modes, and cleanup validation.
- 2026-04-27T11:22:37.720-04:00 — Added starter validation harness at `scripts/validate-demo.sh`; `local` mode is Azure-free, while `preflight`, `postdeploy`, `ingestion`, `backup`, and `cleanup` are explicit Azure/post-deployment checks.
- 2026-04-27T11:22:37.720-04:00 — Captured validation decision in `.squad/decisions/inbox/bishop-validation-strategy.md`: seven-year retention must be shown via archive/export controls, not by claiming Cosmos native backup alone provides seven-year PITR.
- 2026-04-27T11:22:37.720-04:00 — Extracted reusable skill `.squad/skills/azure-cosmos-backup-validation/SKILL.md` for Cosmos backup demo validation patterns.
- 2026-04-27T11:47:49.954-04:00 — Delivered full validation layer: 6 dedicated scripts (`validate-local.sh`, `validate-deployment.sh`, `validate-ingestion.sh`, `validate-backup.sh`, `validate-restore.sh`, `validate-cleanup.sh`) + `teardown.sh` + `docs/validation-and-test-plan.md` + `tests/unit/` (28 passing unit tests). Each script is idempotent, parameterized via env vars, exits 0/non-zero for CI gates.
- 2026-04-27T11:47:49.954-04:00 — Key design: `.env.example` secret scan must exclude comment lines (`grep -v '^\s*#'`) before regex matching; otherwise lines like `# AccountKey=C2y6...` trigger false positives.
- 2026-04-27T11:47:49.954-04:00 — WORM delete test: when immutability policy is unlocked (demo mode), a blob CAN be deleted. Script warns rather than FAILs; reviewer must lock the policy for production-grade G4 evidence. Lock command documented in `docs/validation-and-test-plan.md`.
- 2026-04-27T11:47:49.954-04:00 — `validate-restore.sh` includes a safety guard: exits immediately if `RESTORE_ACCOUNT == COSMOS_ACCOUNT` to prevent accidental restore-over-live.
- 2026-04-27T11:47:49.954-04:00 — Unit test stubs use a monotonic counter for ID generation to guarantee uniqueness within synchronous test runs; Parker's real implementation should use `crypto.randomUUID()` or equivalent.
- 2026-04-27T11:47:49.954-04:00 — Key file paths: `scripts/validate-local.sh`, `scripts/validate-deployment.sh`, `scripts/validate-ingestion.sh`, `scripts/validate-backup.sh`, `scripts/validate-restore.sh`, `scripts/validate-cleanup.sh`, `scripts/teardown.sh`, `docs/validation-and-test-plan.md`, `tests/unit/*.test.ts`, `tests/package.json`, `tests/tsconfig.json`.
- 2026-04-27T11:47:49.954-04:00 — Reviewer gate run. VERDICT: REJECTED. Blocking: 6 docs missing from disk that validate-local.sh checks for and README.md links to — deployment-guide.md, backup-and-retention.md, restore-and-validation.md, operations-runbook.md, cleanup.md, assumptions.md. Lambert's history claims these were delivered but they are absent. Some may exist under different names (teardown.md instead of cleanup.md; operations-and-monitoring.md instead of operations-runbook.md). Artifact owner: Lambert. Per reviewer-protocol, Lambert is locked out; Scribe assigned to fix. Non-blocking: BCP334 suppress directive in infra/modules/container-host.bicep is misplaced (line 39 targets var decl; warning fires on line 43 resource name property) — Dallas to address; .gitignore missing *.key and *.pem; backup-restore-runbook.md missing anchors #ingestion-issues and #restore-failures that README links to.
- 2026-04-27T11:47:49.954-04:00 — Re-review gate run after Ripley remediation. VERDICT: APPROVED. All 6 original blockers resolved and verified by direct inspection + local execution. validate-local.sh: exit 0, 0 failures (all 34+ file/tool/Bicep/hygiene checks passed). Unit tests: 28/28 PASS across 3 suites. Bicep build: all modules compile (BCP334 warning on container-host.bicep is pre-existing and non-blocking — suppress directive on var decl does not suppress the downstream resource property warning; build still exits 0). Repo is cleared for Azure deployment validation (G3/G4/G5 gates require live Azure subscription). Decision recorded in .squad/decisions/inbox/bishop-re-review.md.
