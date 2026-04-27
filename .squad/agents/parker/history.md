# Parker History

## Seed Context

- **User:** John Stelmaszek
- **Project:** newdemo
- **Purpose:** Enterprise Azure demo for Azure Cosmos DB backup and restore.
- **Stack:** Azure Cosmos DB, Bicep, Azure-hosted ingestion workload.
- **Initial scope:** Build the entire environment from the ground up, continuously add sample documents every 20 seconds, and document short-term plus configurable long-term backup coverage up to 7 years.

## Learnings

- **2026-04-27T11:47:49.954-04:00:** Implemented full data workload layer. `apps/weather-ingestor` (Node.js 20, TypeScript) writes one synthetic weather observation per 20 s using a non-overlapping async loop, managed identity via `DefaultAzureCredential`, and `/cityId` partition key. `apps/backup-exporter` reads Cosmos DB via time-window query and writes JSONL + SHA-256 manifest to Blob Storage under `exports/{yyyy}/{MM}/{dd}/{HH}-{mm}/`. Both apps build clean (`npm run build`) and pass their unit tests (`npm test`) using Node.js built-in test runner. Both apps handle SIGINT/SIGTERM. All env vars are documented in `.env.example`; no secrets in source.
- **2026-04-27T11:47:49.954-04:00:** Key file paths: `apps/weather-ingestor/src/data-generator.ts` (schema + station catalog), `apps/weather-ingestor/src/cosmos-client.ts`, `apps/weather-ingestor/src/index.ts`, `apps/backup-exporter/src/manifest.ts` (SHA-256 + manifest builder), `apps/backup-exporter/src/blob-writer.ts` (Blob path + upload), `apps/backup-exporter/src/cosmos-reader.ts`, `apps/backup-exporter/src/index.ts`. Both apps ship a multi-stage Dockerfile on node:20-alpine.
- **2026-04-27T11:47:49.954-04:00:** Partition key contract confirmed as `/cityId` matching design-review §1.4. Export blob path format: `exports/{yyyy}/{MM}/{dd}/{HH}-{mm}/data.jsonl` + `manifest.json`. Dallas wires `COSMOS_ENDPOINT`, `COSMOS_DATABASE_NAME`, `COSMOS_CONTAINER_NAME`, `EXPORT_STORAGE_ACCOUNT_NAME`, `AZURE_CLIENT_ID` from Bicep outputs. `EXPORT_CONTAINER_NAME` defaults to `cosmos-exports`.

- **2026-04-27T11:22:37.720-04:00:** Added `apps/weather-ingestor`, a Node.js container workload that writes synthetic weather observations to Cosmos DB every 20 seconds by default. It uses managed identity through `COSMOS_ENDPOINT` in Azure, a local-only `COSMOS_CONNECTION_STRING` fallback, graceful shutdown, retrying writes, and a `/cityId` partition-friendly schema.
- **2026-04-27T11:22:37.720-04:00:** Documented the ingestion contract in `apps/weather-ingestor/README.md` and `docs/ingestion-workload.md`; Dallas can wire Bicep outputs such as `cosmosAccountEndpoint`, `cosmosDatabaseName`, `cosmosContainerName`, and optional `ingestionManagedIdentityClientId`.
