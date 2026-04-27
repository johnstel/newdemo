/**
 * weather-ingestor — entry point
 *
 * Writes one synthetic weather observation to Cosmos DB every INGEST_INTERVAL_MS
 * (default: 20 000 ms = 20 seconds). Uses a non-overlapping async loop so slow
 * Cosmos DB calls do not pile up concurrent writes.
 *
 * Environment variables:
 *   COSMOS_ENDPOINT            — Cosmos DB account endpoint (Azure managed identity path)
 *   COSMOS_CONNECTION_STRING   — Local dev only; never commit with a value
 *   COSMOS_DATABASE_NAME       — Default: "demo"
 *   COSMOS_CONTAINER_NAME      — Default: "weather"
 *   INGEST_INTERVAL_MS         — Default: 20000
 *   AZURE_CLIENT_ID            — Optional: user-assigned managed identity client ID
 */
export {};
//# sourceMappingURL=index.d.ts.map