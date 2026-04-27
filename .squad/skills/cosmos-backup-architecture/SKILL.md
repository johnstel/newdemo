---
name: "cosmos-backup-architecture"
description: "Design Azure Cosmos DB demo backup architectures with native PITR plus immutable long-term archive retention"
domain: "azure-architecture, backup-restore, cosmos-db"
confidence: "medium"
source: "extracted from Cosmos DB enterprise backup demo architecture work"
---

## Context

Use this skill when designing a Cosmos DB backup demo or implementation plan that must show both short-term operational recovery and long-term enterprise retention.

## Patterns

- Separate native Cosmos DB backup capabilities from application-managed archive retention.
- Use Cosmos DB continuous backup for short-term point-in-time recovery; verify current tier names, retention, region support, and restore paths before implementation.
- Use immutable Blob Storage for multi-year retention such as 7 years; do not describe this as native Cosmos DB backup retention.
- Generate or ingest non-sensitive sample data on a schedule so restore demos operate against a changing dataset.
- Restore into isolated accounts or staging containers before any live cutover.
- Capture evidence artifacts: snapshot manifests, hashes, item counts, restore target, restore timestamp, validation result, and operator approval.
- Treat Azure API versions, SKU names, feature availability, and pricing as dynamic facts that require Microsoft Learn verification before Bicep generation.

## Examples

- Short-term tier: Cosmos DB continuous backup configured by Bicep parameter, then restore to an isolated account for accidental delete/update validation.
- Long-term tier: scheduled exports from Cosmos DB to immutable Blob Storage with lifecycle transition and a 7-year retention parameter.
- Demo ingestion: timer-triggered Azure Function writes synthetic weather documents every 20 seconds using managed identity.

## Anti-Patterns

- Claiming Cosmos DB native backup supports 7-year retention without current documentation.
- Treating archive blobs as valid backups without restore validation and evidence manifests.
- Restoring directly into the live database without staging and approval.
- Using external public APIs that require secrets before secret handling is designed.
- Hardcoding stale API versions, SKU names, or region assumptions in architecture documentation.
