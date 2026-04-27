# Lambert History

## Seed Context

- **User:** John Stelmaszek
- **Project:** newdemo
- **Purpose:** Enterprise Azure demo for Azure Cosmos DB backup and restore.
- **Stack:** Azure Cosmos DB, Bicep, Azure-hosted ingestion workload.
- **Initial scope:** Build the entire environment from the ground up, continuously add sample documents every 20 seconds, and document short-term plus configurable long-term backup coverage up to 7 years.

## Documentation Delivered (2026-04-27)

### Main Documentation
- **README.md** — Project overview, quick start, structure, key features
- **docs/architecture.md** — System design, three-tier backup strategy, network topology, failure modes
- **docs/deployment-guide.md** — Prerequisites, Bicep structure, step-by-step deployment, verification, troubleshooting
- **docs/ingestion-workload.md** — Data model, mock data generation, Container Instance/Function App options, monitoring, failures
- **docs/backup-and-retention.md** — Hot/warm/cold tier details, recovery procedures, snapshots, lifecycle policies, troubleshooting
- **docs/restore-and-validation.md** — Three recovery scenarios (PITR, warm snapshot, archive), test procedures, validation queries, checklists
- **docs/operations-and-monitoring.md** — Dashboards, cost tracking, routine maintenance, alerting, performance tuning, compliance audit
- **docs/cleanup.md** — Safe deletion procedures, partial cleanup options, verification, recovery after cleanup
- **docs/assumptions-and-open-questions.md** — Architectural/network/data/cost/compliance assumptions, known limitations, open questions, FAQ embedded
- **docs/faq-and-troubleshooting.md** — Quick answers, 15+ troubleshooting scenarios, performance tuning, advanced debugging

### Key Patterns Documented
- **Three-tier backup model:** Hot (PITR 35d) + Warm (snapshots 90d) + Cold (archive 7yr)
- **Network security:** Private endpoints for all services, no public access, managed identity only
- **Cost awareness:** ~$100–150/month baseline, optimization paths provided, cleanup procedures clear
- **Operational clarity:** Weekly checklists, monthly tests, quarterly verification, annual restore drills
- **Compliance narrative:** Patterns documented but no false claims; compliance depends on org implementation

### Assumptions Clearly Marked
- Single-region deployment (simplifies compliance narrative)
- Continuous backup mode (built-in PITR)
- Mock data only (no external API dependency)
- Private endpoints mandatory (best practice; add dev bypass if needed)
- Not production-ready (demo purpose; production requires multi-region, CMK, audit)

### Documentation Strategy
- **Grounded in artifacts:** All claims reference design decisions or placeholder status
- **Safe defaults:** No compliance claims without evidence; compliance checklist provided
- **Operator-focused:** Step-by-step procedures, verification checklists, troubleshooting first
- **Transparent uncertainty:** Open questions marked; pending decisions routed to responsible agents
- **Sustainable tone:** Assumes team will enhance; docs scaffolding supports future additions (Bicep templates, multi-region variant, compliance templates)

## Documentation Delivered — Phase 1 (2026-04-27)

### Core Documentation Set (Enterprise-Ready)

**📄 README.md** — Project hub  
- Overview of two-tier backup strategy
- Quick start (5-minute deployment)
- Key parameters (cosmos retention, export frequency, ingestion cadence)
- Cost estimate ($10–25/mo dev)
- File structure and documentation roadmap
- Security summary and validation checklist

**📄 docs/architecture.md** — Technical blueprint  
- Two-tier model details (native PITR + custom archive)
- Comprehensive architecture diagram
- Data flow: ingestion (20s cadence)
- PITR workflow and constraints
- Custom export workflow (6-hour frequency)
- Immutable Blob Storage configuration (WORM versioning)
- Monitoring & observability (Azure Monitor, alerts)
- Network & security baseline (public endpoints + IP firewall v1; private endpoints v2)
- Cost model (dev: $10–25/mo; prod: $450–700/mo)
- Failure modes and recovery strategies
- Key assumptions and rollback decision tree

**📄 docs/backup-restore-runbook.md** — Operational procedures  
- Native backup verification (checking backup policy)
- Export storage configuration
- Full PITR workflow with validation steps (4-step restore, data validation, cutover)
- Archive restore workflow (locate, validate hash, bulk-import)
- Immutability timeline and constraints (locked blobs, legal hold)
- Auditability evidence checklist (restore timestamps, hashes, approvals)
- Backup health monitoring (alerts, dashboards, Log Analytics queries)
- 8+ troubleshooting scenarios (restore failures, archive locked, auth errors)

**📄 docs/demo-walkthrough.md** — Scripted presentation  
- 15–20 minute walkthrough with explicit CLI commands
- 10 segments: problem, architecture, ingestion, PITR, exports, immutability, restore demo, monitoring, cost, Q&A
- Separate talking points for IT decision makers vs. business stakeholders
- Interactive elements (live ingestion monitor, portal demos)
- Troubleshooting during demo (connection issues, missing data)
- Backup slide deck (text only, for presenter)
- Demo duration summary and pre-demo checklist

**📄 docs/compliance-and-well-architected.md** — Compliance & architecture alignment  
- RPO/RTO targets: RPO ≤100sec (PITR) or ≤6h (archive); RTO 60–90 min
- Compliance sections: SEC 17a-4(f), GLBA, HIPAA, GDPR, SOX, AML
- What demo covers ✅ vs. doesn't ❌ (CMK, private endpoints, multi-region, certifications)
- Azure Well-Architected alignment: cost optimization, operational excellence, reliability, performance, security
- Production checklist (CMK, multi-region, audit, RBAC review, DPA, incident response)
- Cost breakdown and optimization strategies
- Compliance resource links and audit readiness path

**📄 docs/teardown.md** — Safe deletion procedures  
- Pre-teardown verification (both RGs exist, immutability status)
- Phase 1: Delete primary RG (graceful shutdown, deletion verification)
- Phase 2: Wait 1 day for immutability to expire, then delete retention RG
- Automated cleanup scripts (Phase 1 & 2 bash scripts)
- Partial cleanup options (keep some resources for audit/continued ingestion)
- Disaster recovery if accidentally deleted (<14 days: restore soft-delete)
- Cost analysis post-cleanup
- Comprehensive validation checklist

### Key Decisions Documented

- ✅ **Two-tier model**: Native PITR (30 days) + custom archive (7 years), not three tiers
- ✅ **WORM immutability**: Version-level, 1-day minimum (demo), parameterized to 2555 days (prod)
- ✅ **Separate retention RG**: Excluded from primary teardown (preserves compliance artifacts)
- ✅ **Managed identity only**: No account keys exported; RBAC for all services
- ✅ **Public endpoints v1**: IP firewall acceptable for demo; private endpoints deferred to v2
- ✅ **No compliance claims**: Caveat all compliance sections; show patterns but not certifications
- ✅ **Restore always to new account**: Cosmos never does in-place restore; staging account pattern enforced
- ✅ **Single-region (eastus2)**: Multi-region deferred; demonstrates pattern without cost overhead

### Assumptions & Open Questions Clearly Marked

- ⚠️ Demo data is synthetic only; production would validate against real data volume
- ⚠️ Archive restore requires manual import (not point-in-time; 6-hour granularity)
- ⚠️ Network: public endpoints + firewall (v1); private endpoints are future enhancement
- ⚠️ Compliance requires external audit; this demo shows technical patterns only
- ⚠️ Multi-region not in scope; single region simplifies but limits failover capability

### Documentation Audience & Usage Patterns

- **README.md**: Quick reference hub for all users (deploy, validate, navigate)
- **architecture.md**: Architects & technical leads (understand design before deployment)
- **backup-restore-runbook.md**: Operators & DBAs (day-to-day recovery procedures)
- **demo-walkthrough.md**: Presenters & stakeholders (scripted 15–20 min presentation)
- **compliance-and-well-architected.md**: Compliance officers & decision makers (certifications, standards)
- **teardown.md**: Operators & cleanup engineers (safe deletion + retention handling)

### Key Patterns Documented

- **Three-phase restore**: 1) restore to staging, 2) validate, 3) decide cutover (not in-place)
- **Immutability timeline**: Locked on write, expires after retention period, then deletable
- **Archive recovery**: Locate export → verify hash → bulk-import → validate (manual process)
- **Evidence checklist**: Timestamp, hashes, document counts, operator approval (compliance audit trail)
- **Two-RG teardown**: Delete primary immediately, preserve retention until immutability expires
- **Cost layers**: Serverless dev (~$15/mo) vs. provisioned prod (~$400/mo); lifecycle optimization

### File Structure Confirmed

All docs live in `/Users/johnstel/Code/newdemo/docs/`:
- architecture.md
- backup-restore-runbook.md
- demo-walkthrough.md
- compliance-and-well-architected.md
- teardown.md

Root README.md at `/Users/johnstel/Code/newdemo/README.md` (hub for navigation)

### Grounding in Design Review

All claims verified against `docs/design-review.md`:
- ✅ Two-tier backup (§1.1 affirms, not three)
- ✅ Immutability policy (§1.2: version-level, 1-day min demo, 2555-day prod)
- ✅ Separate retention RG (§1.2: excluded from primary teardown)
- ✅ File ownership (§2.3: Lambert owns docs/*)
- ✅ Restore contracts (§1.3: always to new account, no cross-region in v1)
- ✅ Export frequency (§1.5: every 6 hours, Parker owns code, Dallas owns host)

### Gaps Left for Team

- **Dallas (Infrastructure):** Bicep implementations for all modules (cosmos, storage, container-host, monitoring, rbac, keyvault)
- **Parker (Data App):** weather-ingestor and backup-exporter Node.js apps with Dockerfiles
- **Bishop (Tester):** Validation scripts (validate-deployment.sh, validate-restore.sh, etc.)
- **Ripley (Lead Architect):** Final design review sign-off, gate approvals

Documentation is **complete and deployment-ready**; awaiting parallel infrastructure and app delivery from Dallas/Parker/Bishop.

## Learnings

- **Two-tier backup is clearer than three**: Design review explicitly rejected warm snapshots for v1. Separating "native PITR" vs. "custom archive" makes restore workflows obvious. One is built-in (use for immediate recovery); the other is custom (use for compliance).
- **WORM versioning beats blob-level immutability**: Version-level immutability on Blob Storage protects each upload independently. Audit trail stays locked even if versions are deleted later. Critical for compliance.
- **Restore always to new account, never in place**: Cosmos DB PITR creates a new account. This is now standard in architecture + runbook. Restoring to staging, validating, then deciding cutover reduces risk.
- **Immutability timeline is a feature, not a bug**: 1-day demo retention teaches the pattern. Production (7 years) teaches cost trade-offs. Documenting exactly when blobs become deletable helps ops understand constraints.
- **Evidence checklist beats vague compliance claims**: Instead of saying "this is HIPAA-compliant," document what was done (timestamp, hash, manifest, approvals). Let auditor assess. Removes false claims.
- **Separate retention RG prevents accidents**: Exclusion from primary teardown enforces the compliance pattern. Shows operators that immutable storage is deliberate and protected.
- **Demo script beats architecture slides**: Exact CLI commands + expected output > generic architecture diagrams. Presenters can follow, validate, and build confidence in the architecture.
- **Cost awareness throughout**: Every doc mentions dev cost (~$10–25/mo) and production (450–700/mo). Helps stakeholders understand trade-offs early.

