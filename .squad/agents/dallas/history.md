# Dallas History

## Seed Context

- **User:** John Stelmaszek
- **Project:** newdemo
- **Purpose:** Enterprise Azure demo for Azure Cosmos DB backup and restore.
- **Stack:** Azure Cosmos DB, Bicep, Azure-hosted ingestion workload.
- **Initial scope:** Build the entire environment from the ground up, continuously add sample documents every 20 seconds, and document short-term plus configurable long-term backup coverage up to 7 years.

## Learnings


- **2026-04-27T11:22:37.720-04:00:** Created initial `infra/` Bicep layout for the Cosmos DB enterprise backup demo. Pattern: Cosmos DB native continuous backup covers short-term PITR (`Continuous7Days`/`Continuous30Days`), while seven-year retention is modeled through immutable, versioned Blob archive storage (`longTermArchiveRetentionDays`, max 2555 days).
- **2026-04-27T11:22:37.720-04:00:** Added secure-by-default deployment modules: VNet with delegated Function subnet and private endpoint subnet, Cosmos DB account/database/container, archive/runtime storage, Key Vault, Log Analytics/Application Insights, Function App host, private endpoints/private DNS, RBAC, and Cosmos diagnostics.
- **2026-04-27T11:22:37.720-04:00:** Key paths: `infra/main.bicep`, `infra/main.bicepparam`, `infra/modules/*.bicep`, and `infra/README.md`. Defaults prefer managed identity and disabled data-plane public access; app public ingress remains configurable for demo deployment convenience.
- **2026-04-27T11:47:49.954-04:00:** Completed full modular Bicep implementation. 10 modules + subscription-scope orchestrator. `az bicep build` exits clean (0). Key paths: `infra/main.bicep`, `infra/modules/{resource-groups,identity,monitoring,cosmos,storage-exports,storage-retention,container-host,keyvault,rbac,alerts}.bicep`, `infra/parameters/{dev,test,prod}.bicepparam`, `scripts/deploy/deploy.sh`.
- **2026-04-27T11:47:49.954-04:00:** Monitoring split into `monitoring.bicep` (LAW + AppInsights, no deps) + `alerts.bicep` (3 alert rules, deployed last). This breaks the circular dep: Cosmos needs LAW ID first; alerts need Cosmos ID after.
- **2026-04-27T11:47:49.954-04:00:** Container Apps `resources.cpu` must use `json('0.25')` in Bicep — type def says `int | null` but the API accepts JSON decimals; `json()` is the correct workaround.
- **2026-04-27T11:47:49.954-04:00:** WORM storage diagnostic settings in retention RG can cross-reference a Log Analytics workspace in the primary RG by resource ID — cross-RG diagnostic target is fully supported.
- **2026-04-27T11:47:49.954-04:00:** Design-review D4 (single-region) vs. task requirement (multi-region): resolved with optional `secondaryLocation` parameter. Empty string = single-region (dev/test default); `westus2` in prod.bicepparam. `enableAutomaticFailover` is conditionally set.
- **2026-04-27T11:47:49.954-04:00:** Cosmos data-plane RBAC: `sqlRoleAssignments` resource type, NOT Azure ARM `roleAssignments`. Role def ID `00000000-0000-0000-0000-000000000002` = Built-in Data Contributor, referenced as `{cosmosAccount.id}/sqlRoleDefinitions/...`.
