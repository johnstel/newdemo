---
name: "cosmos-enterprise-backup"
description: "Design Cosmos DB backup demos with native PITR plus immutable long-term archive"
domain: "azure-infrastructure, backup, cosmos-db"
confidence: "medium"
source: "earned from Cosmos DB enterprise backup demo infrastructure design"
---

## Context

Use this pattern when a project needs to demonstrate enterprise backup for Azure Cosmos DB, especially when requirements combine short-term point-in-time restore with multi-year retention.

## Patterns

- Use Cosmos DB native continuous backup for operational point-in-time restore windows (`Continuous7Days` or `Continuous30Days`).
- Do not model seven-year retention as Cosmos native backup; create a separate archival path to immutable, versioned Blob Storage.
- Make long-term retention a parameter in days, with 2555 days representing seven years.
- Keep restore runbooks explicit: Cosmos restore handles data PITR, while Bicep redeploys networking, RBAC, diagnostics, and app configuration around restored accounts.
- Prefer managed identity and data-plane RBAC over account keys for ingestion workloads.
- Isolate WORM/immutable retention storage in a separate resource group excluded from primary teardown.
- Use version-level immutability with short minimum retention (1 day) for demos; parameterize for production.
- Start with two tiers (native PITR + custom archive); add warm snapshots only when demo value justifies the complexity.
- Prefer container workloads (Container Apps/ACI) over Azure Functions for v1 when Dockerfile simplicity matters more than sub-minute triggers.
- Use periodic time-window exports (e.g., every 6 hours) before investing in real-time change feed export.

## Examples

- `infra/modules/cosmos.bicep` configures Cosmos native backup policy.
- `infra/modules/storage-retention.bicep` configures immutable Blob archive in a separate retention RG.
- `infra/modules/storage-exports.bicep` configures export target with Cool/Archive lifecycle in the primary RG.
- `infra/modules/rbac.bicep` grants the ingestion identity Cosmos SQL data-plane and storage data-plane permissions.
- `docs/design-review.md` serves as the alignment contract with file/module ownership and reviewer gates.

## Anti-Patterns

- Claiming Cosmos DB native backup supports seven-year retention.
- Hard-coding tenant IDs, subscription IDs, or secrets in templates.
- Relying on Cosmos account keys when managed identity and RBAC can be used.
- Tearing down the retention resource group during demo cleanup.
- Building warm snapshot tier in v1 when two tiers cover the demo narrative.
- Using private endpoints in v1 demo when public endpoints with IP firewall are simpler and cheaper.
