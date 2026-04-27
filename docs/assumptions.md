# Assumptions & Scope — Azure Cosmos DB Backup Demo

**Date:** 2026-04-27  
**Status:** Demo-ready  
**Audience:** Technical leads, evaluators, architects

---

## Purpose

This document records the assumptions, design choices, and explicit non-goals for the demo. It is intended to set evaluator expectations accurately and prevent misinterpretation of what is demonstrated.

---

## In Scope

| Capability | Notes |
|------------|-------|
| Cosmos DB Continuous Backup (PITR) | Native, managed by Azure. 7-day tier (prod) or 30-day tier (dev/test). |
| Custom scheduled export to Blob Storage | Container App Job every 6 hours; JSONL + SHA-256 manifest |
| WORM immutable retention storage | Version-level immutability, 1-day minimum (unlocked for demo; lock for production) |
| Two-tier separation | Primary RG (short-term) and retention RG (long-term) are isolated |
| Managed identity and RBAC | No account keys or secrets in code or config |
| Synthetic data ingestion | Weather readings every 20 seconds across multiple virtual stations |
| Azure Monitor alerts | 429 throttling, ingestion gap, export failure |
| Cost-optimized dev environment | ~$10–35/month; serverless Cosmos DB, Container Apps consumption plan |
| Scripted validation | Gates G1–G6 covering local, deployment, backup, ingestion, restore, cleanup |

---

## Out of Scope

| Item | Reason |
|------|--------|
| **True 7-year native Cosmos DB retention** | Azure Cosmos DB continuous backup does not support 7-year retention natively. The custom export path *demonstrates the architecture* for long-term retention; it is not a certified compliance solution. |
| **Private networking / VNet integration** | Deferred for v1; public endpoints with IP firewall are used. Enable private endpoints for production. |
| **Automated restore testing** | `validate-restore.sh` exercises the restore path manually. Automated DR drills are not configured. |
| **Key Vault secret rotation** | Key Vault is provisioned but secret lifecycle management is not automated in this demo. |
| **Production container image pipeline** | Images are placeholders (MCR hello-world) until built and pushed to ACR. A CI/CD pipeline for image builds is not included. |
| **Multi-tenant / subscription isolation** | Single subscription, two resource groups. Multi-subscription patterns are not demonstrated. |
| **Regulatory compliance certification** | The WORM pattern is architecturally aligned with immutable storage requirements but does not constitute a certified HIPAA, PCI-DSS, SEC 17a-4, or equivalent solution. |
| **Change feed-based export** | Export uses a cross-partition time-range query. Change feed would be more efficient at scale but is deferred for v1. |

---

## Naming Assumptions

All resource names follow `{prefix}-{service}-{env}` (e.g., `cosmos-backup-cosmos-dev`). Storage accounts use alphanumeric-only shortened names (`{prefix-no-hyphens}{suffix}{env}`):

| Resource | Suffix | Example |
|----------|--------|---------|
| Export storage | `exp` | `cosmosbackupexpdev` |
| Retention storage | `ret` | `cosmosbackupretdev` |
| ACR | `acr` | `cosmosbackupacrdev` |

---

## Cost Assumptions

Dev environment cost estimates are based on:
- Cosmos DB serverless: ~1M RUs/month at demo ingestion rate
- Container Apps: consumption plan, minimal compute hours
- Storage: LRS, Cool/Archive tiering, <1 GB
- Log Analytics: minimal ingestion

Actual costs vary by region, usage, and Azure pricing changes. See [Compliance & Well-Architected](compliance-and-well-architected.md) for detailed estimates.

---

## PITR Restore Assumptions

- PITR creates a **new Cosmos account**; the source account is not modified.
- The restore target must be in the **same subscription** as the source.
- Restore time for demo-sized datasets: 15–60 minutes.
- After restore, connection strings and RBAC must be updated manually.

---

## WORM Retention Assumptions

- The retention period minimum is set to **1 day** in demo configuration (not locked).
- In production, increase the immutability period and **lock the policy** before any data is written.
- Once locked, immutability policy cannot be reduced or removed until the period expires.
- Lifecycle deletion in the export storage (primary RG) is separate from WORM policy in the retention RG.

---

## Related Documents

- [Architecture](architecture.md) — Full system design
- [Backup & Retention](backup-and-retention.md) — How each tier works
- [Compliance & Well-Architected](compliance-and-well-architected.md) — RPO/RTO targets, cost optimization
