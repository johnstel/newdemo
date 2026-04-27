# Ash — History

## Seed Context

- **Project:** newdemo
- **User:** John Stelmaszek
- **Stack:** Azure Cosmos DB, Bicep, Azure Container Apps, TypeScript workloads, Azure Monitor/Application Insights, Blob Storage lifecycle and immutable WORM retention.
- **Purpose:** Enterprise Azure demonstration environment for Cosmos DB backup and recovery, including native continuous backup/PITR and custom long-term retention up to 7 years through exported data in Blob Storage.
- **Standing directive:** Ash owns technical writing and GitHub issue body drafting. Any document or issue writing must use `claude-opus-4.6`.

## Learnings

- 2026-04-27T13:20:55.799-04:00 — Added as dedicated Technical Writer so all technical writing routes to a specialist using `claude-opus-4.6`.
- 2026-04-27T13:26:02.906-04:00 — Fixed issue #1 in `docs/observability-and-logging.md`: (1) Updated stale App Insights enablement status — Bicep now wires `APPLICATIONINSIGHTS_CONNECTION_STRING` to both containers via `monitoring.bicep` → `main.bicep` → `container-host.bicep`; docs previously claimed it was not wired. (2) Replaced all 9 instances of invalid KQL `parse-json()` with correct `parse_json()`. (3) Corrected event name `documents_queried` to actual code events `cosmos_query_start` and `cosmos_query_complete` per `apps/backup-exporter/src/cosmos-reader.ts`. Added bash and PowerShell operator verification commands. Always verify implementation before documenting claims.
