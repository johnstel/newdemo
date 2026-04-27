"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
const cosmos_client_js_1 = require("./cosmos-client.js");
const data_generator_js_1 = require("./data-generator.js");
const INTERVAL_MS = parseInt(process.env.INGEST_INTERVAL_MS ?? "20000", 10);
let running = true;
let stationIndex = 0;
async function writeObservation(container) {
    const doc = (0, data_generator_js_1.generateWeatherObservation)(stationIndex++);
    try {
        const { resource, statusCode, requestCharge } = await container.items.upsert(doc);
        console.log(JSON.stringify({
            level: "info",
            event: "document_written",
            id: resource?.id,
            cityId: doc.cityId,
            observedAt: doc.observedAt,
            statusCode,
            requestChargeRU: requestCharge,
        }));
    }
    catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        console.error(JSON.stringify({
            level: "error",
            event: "write_failed",
            cityId: doc.cityId,
            error: message,
        }));
        // Re-throw so the caller can decide retry strategy
        throw err;
    }
}
async function ingestLoop(container) {
    console.log(JSON.stringify({
        level: "info",
        event: "ingestor_started",
        intervalMs: INTERVAL_MS,
    }));
    while (running) {
        const loopStart = Date.now();
        try {
            await writeObservation(container);
        }
        catch {
            // Error already logged in writeObservation; continue loop
        }
        // Sleep for the remainder of the interval, clamped to 0
        const elapsed = Date.now() - loopStart;
        const sleep = Math.max(0, INTERVAL_MS - elapsed);
        if (sleep > 0 && running) {
            await new Promise((resolve) => setTimeout(resolve, sleep));
        }
    }
    console.log(JSON.stringify({
        level: "info",
        event: "ingestor_stopped",
    }));
}
async function main() {
    const container = await (0, cosmos_client_js_1.getCosmosContainer)();
    await ingestLoop(container);
}
// Graceful shutdown on SIGINT (Ctrl-C) and SIGTERM (container stop)
function handleShutdown(signal) {
    console.log(JSON.stringify({
        level: "info",
        event: "shutdown_requested",
        signal,
    }));
    running = false;
}
process.on("SIGINT", () => handleShutdown("SIGINT"));
process.on("SIGTERM", () => handleShutdown("SIGTERM"));
main().catch((err) => {
    console.error(JSON.stringify({
        level: "fatal",
        event: "startup_failed",
        error: err instanceof Error ? err.message : String(err),
    }));
    process.exit(1);
});
//# sourceMappingURL=index.js.map