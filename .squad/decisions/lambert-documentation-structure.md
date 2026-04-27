---
date: 2026-04-27T11:22:37.720-04:00
author: Lambert (Documentation Lead)
status: Accepted
---

# Documentation Structure: Azure Cosmos DB Backup Demo

## Decision

**Document the enterprise Cosmos DB backup demo via modular, operator-focused guides organized as:**
1. **Main README.md** — Overview, quick start, high-level architecture, team routing
2. **docs/architecture.md** — System design, three-tier backup model, network patterns, cost model
3. **docs/deployment-guide.md** — Prerequisites, Bicep template structure, step-by-step deployment, verification
4. **docs/ingestion-workload.md** — Sample data model, Container Instance/Function App options, monitoring, failures
5. **docs/backup-and-retention.md** — Hot/warm/cold tier operations, snapshots, lifecycle policies, recovery procedures
6. **docs/restore-and-validation.md** — PITR restore, snapshot recovery, archive rehydration, test procedures, checklists
7. **docs/operations-and-monitoring.md** — Dashboards, cost tracking, routine maintenance, alerts, compliance audit
8. **docs/cleanup.md** — Safe deletion, partial cleanup, verification, recovery options
9. **docs/assumptions-and-open-questions.md** — Architectural decisions, known limitations, compliance caveats, FAQ
10. **docs/faq-and-troubleshooting.md** — Quick reference, 15+ troubleshooting scenarios, performance tuning

## Rationale

### Why This Structure

- **README as hub** — Operators see overview, navigation, team contacts immediately
- **Separate architecture doc** — Architects and reviewers can see design patterns without operational noise
- **Modular guides** — Operators navigate by task (deploy, backup, restore, operate, clean up) not by service
- **Transparent uncertainty** — Pending decisions clearly marked; routed to responsible agents (Ripley, Dallas, Parker, Ralph)
- **Compliance clarity** — Patterns documented; compliance claims avoided; checklist provided for org verification
- **Sustainable** — Scaffolding supports future additions (multi-region variant, Terraform, compliance templates)

### Grounding Principle: "No False Claims"

**We do not claim:**
- ✗ "This demo is HIPAA-compliant" (depends on org implementation)
- ✗ "Data residency is enforced" (Azure SKU-dependent; org must verify)
- ✗ "This is production-ready" (it's not; we say so explicitly)

**We do document:**
- ✓ "This shows patterns for compliance; compliance depends on org policy"
- ✓ "Data stays in one region; verify with your org's data residency requirements"
- ✓ "This is a demo; production requires multi-region, CMK, audit logging, etc."

### Why Three Backup Tiers

- **Hot (PITR, 0–35d):** Built-in, no extra cost, covers most accidents
- **Warm (snapshots, 30–90d):** Shows enterprise pattern; extends hot window
- **Cold (archive, 1–7yr):** Demonstrates compliance/audit retention; cost-effective; not for emergency recovery

This is **educational** — many orgs skip warm tier for cost. Docs provide variant.

### Why Private Endpoints + Managed Identity

- **Private endpoints:** Azure Well-Architected Framework best practice; demo shows enterprise pattern
- **Managed identity only:** No shared keys; RBAC-enforced; aligns with zero-trust principles
- **Cost:** ~$4–5/month; justified by security pattern
- **Development caveat:** Noted that "dev bypass" (public endpoints) may be needed; docs scaffold for that

### Why Single-Region Only

- **Simplifies compliance narrative:** "Data stays in eastus2" is clear and auditable
- **Lower cost:** No geo-redundancy; appropriate for demo
- **Scalability path:** Docs note multi-region is "not in scope"; Ripley owns that decision
- **Real use case:** Many orgs start single-region; can be added later

## Decisions Made (in service of documentation)

1. **No "quick-start" misleads** — Quick Start redirects to full deployment guide (not "3-click deploy")
2. **Assumptions section prominent** — Reader can't miss it; compliance caveats up-front
3. **Troubleshooting mirrors real experience** — 15+ scenarios cover 80% of operational pain points
4. **Checklists over prose** — Pre-flight, post-restore, weekly maintenance → checkboxes; operators can verify completion
5. **Cost visible everywhere** — Every guide includes cost implications; cleanup guide emphasizes "$0/month if deleted"
6. **Team routing clear** — Every doc includes "Support / Escalation" table; no ambiguity about who owns what

## Trade-offs

| Benefit | Cost | Mitigation |
|---------|------|-----------|
| Transparent about limitations | May deter some users | Compliance checklist shows path forward |
| Detailed troubleshooting | Long FAQ section | Searchable; organized by symptom |
| No "magic" claims | Less attractive for marketers | README emphasizes "enterprise patterns" instead |
| Modular structure | More files to navigate | README is central hub; cross-links present |
| Operational focus | Light on architecture deep-dives | Architecture guide exists; separate from ops |

## Next Steps

1. **Ripley:** Review architecture decisions; provide feedback on multi-region path, compliance variants
2. **Dallas:** Validate Bicep template structure assumptions; confirm parameter approach aligns with infrastructure team
3. **Parker:** Review operations & cleanup procedures; identify missing monitoring/alerting
4. **Ralph:** Review ingestion workload documentation; provide engineering feedback on mock data, API integration options

## Related Decisions

- **Architectural decision:** Three-tier backup model (owned by Ripley; documented in architecture.md)
- **Infrastructure decision:** Bicep templates (owned by Dallas; deployment guide scaffolds for pending templates)
- **Operational decision:** Retention policies up to 7 years (owned by Parker/compliance; documented as configurable)

## Document Maintenance

- **Owner:** Lambert (Documentation Lead)
- **Review cycle:** Quarterly (2026-07-27)
- **Change triggers:** Architecture change, infrastructure decision, operational learning, customer feedback
- **Version tracking:** Git history + .squad/agents/lambert/history.md

---

**Status:** Accepted  
**Implementation date:** 2026-04-27  
**Last updated:** 2026-04-27
