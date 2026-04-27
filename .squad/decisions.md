# Squad Decisions

## Archived Decisions
- ripley-cosmos-backup-architecture.md — Cosmos DB continuous backup architecture with PITR multi-region support
- ripley-design-review.md — Lead architecture review; design completed with decision inbox entries
- ripley-review.md — Initial G6 architecture review; identified 6 blockers
- ripley-remediation.md — Ripley independent lockout remediation; fixed all 6 blockers
- dallas-bicep-environment.md — Bicep environment parameter strategy and multi-region resource groups
- dallas-infra.md — Modular Bicep orchestrator, subscription scope, identities, monitoring, lifecycle policies, WORM retention RG
- parker-ingestion-workload.md — 20-second ingestion cycle with structured container logs
- parker-data-workload.md — JSONL export with SHA-256 manifests; Dockerfiles; managed identity; safe env examples
- lambert-docs.md — README.md, architecture, runbook, demo walkthrough, compliance, well-architected, teardown docs
- bishop-validation-strategy.md — Validation suite design: local static checks + unit tests + live Azure validation (G3-G6)
- bishop-validation.md — 28/28 unit tests pass; validate-local.sh exit 0; az bicep build pass; env hygiene clean
- bishop-re-review.md — **APPROVED** — All 6 blockers resolved; Bishop validates Ripley remediation; repo ready for Azure

## Final Status
- **Architecture:** Complete and approved by Bishop (final validator)
- **Implementation:** All agents (Dallas, Parker, Lambert) delivered modular Bicep, TypeScript containers, documentation
- **Compliance:** Ready for live Azure deployment; gates G3-G6 require subscription
- **Quality Gates:** Static validation (34+ checks), bicep build pass, unit tests 28/28, env hygiene pass

## Governance
- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
