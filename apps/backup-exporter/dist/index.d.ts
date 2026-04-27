/**
 * backup-exporter — entry point
 *
 * Queries Cosmos DB for documents in a configurable time window and writes
 * a JSONL bundle + manifest to Azure Blob Storage for long-term retention.
 *
 * By default runs once and exits (suitable for a scheduled container job).
 * Set EXPORT_LOOP_INTERVAL_MS to run on a repeating schedule in-process.
 *
 * Environment variables:
 *   COSMOS_ENDPOINT                — Cosmos DB account endpoint (Azure managed identity)
 *   COSMOS_CONNECTION_STRING       — Local dev only; never commit with a value
 *   COSMOS_DATABASE_NAME           — Default: "demo"
 *   COSMOS_CONTAINER_NAME          — Default: "weather"
 *   EXPORT_STORAGE_ACCOUNT_NAME    — Target storage account name (Azure managed identity)
 *   STORAGE_CONNECTION_STRING      — Local dev only (Azurite / emulator)
 *   EXPORT_CONTAINER_NAME          — Blob container name. Default: "cosmos-exports"
 *   EXPORT_WINDOW_HOURS            — Hours of data per export. Default: 6
 *   EXPORT_LOOP_INTERVAL_MS        — If set, repeat exports on this interval; else run once
 *   AZURE_CLIENT_ID                — Optional user-assigned managed identity client ID
 */
export {};
//# sourceMappingURL=index.d.ts.map