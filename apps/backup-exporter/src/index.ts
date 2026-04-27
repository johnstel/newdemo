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

import { getCosmosContainer, readDocumentsInWindow } from "./cosmos-reader.js";
import { writeExportBundle, buildBlobPrefix } from "./blob-writer.js";
import { buildManifest } from "./manifest.js";

const WINDOW_HOURS = parseInt(process.env.EXPORT_WINDOW_HOURS ?? "6", 10);
const LOOP_INTERVAL_MS = process.env.EXPORT_LOOP_INTERVAL_MS
  ? parseInt(process.env.EXPORT_LOOP_INTERVAL_MS, 10)
  : undefined;

let running = true;

/**
 * Compute the most recent aligned time window.
 * e.g. WINDOW_HOURS=6 and now=14:37 → windowStart=08:00, windowEnd=14:00
 */
function computeWindow(windowHours: number): { windowStart: Date; windowEnd: Date } {
  const now = new Date();
  const windowMs = windowHours * 60 * 60 * 1000;
  const windowEnd = new Date(Math.floor(now.getTime() / windowMs) * windowMs);
  const windowStart = new Date(windowEnd.getTime() - windowMs);
  return { windowStart, windowEnd };
}

async function runExport(): Promise<void> {
  const { windowStart, windowEnd } = computeWindow(WINDOW_HOURS);
  const databaseName = process.env.COSMOS_DATABASE_NAME ?? "demo";
  const containerName = process.env.COSMOS_CONTAINER_NAME ?? "weather";

  console.log(
    JSON.stringify({
      level: "info",
      event: "export_started",
      windowStart: windowStart.toISOString(),
      windowEnd: windowEnd.toISOString(),
      targetPrefix: buildBlobPrefix(windowStart),
    })
  );

  const container = await getCosmosContainer();
  const documents = await readDocumentsInWindow(container, windowStart, windowEnd);

  console.log(
    JSON.stringify({
      level: "info",
      event: "documents_queried",
      itemCount: documents.length,
      windowStart: windowStart.toISOString(),
      windowEnd: windowEnd.toISOString(),
    })
  );

  // Serialize as JSONL — one document per line, no trailing newline
  const jsonlContent = documents.map((d) => JSON.stringify(d)).join("\n");

  const manifest = buildManifest({
    windowStart,
    windowEnd,
    itemCount: documents.length,
    jsonlContent,
    cosmosDatabase: databaseName,
    cosmosContainer: containerName,
  });

  const { dataUrl, manifestUrl } = await writeExportBundle({
    jsonlContent,
    manifest,
    windowStart,
  });

  console.log(
    JSON.stringify({
      level: "info",
      event: "export_complete",
      itemCount: documents.length,
      sha256: manifest.sha256,
      dataUrl,
      manifestUrl,
      windowStart: windowStart.toISOString(),
      windowEnd: windowEnd.toISOString(),
    })
  );
}

async function main(): Promise<void> {
  console.log(
    JSON.stringify({
      level: "info",
      event: "exporter_started",
      windowHours: WINDOW_HOURS,
      mode: LOOP_INTERVAL_MS ? "loop" : "once",
      loopIntervalMs: LOOP_INTERVAL_MS ?? null,
    })
  );

  if (!LOOP_INTERVAL_MS) {
    // Single-run mode — Dallas's container job scheduler controls recurrence
    await runExport();
    return;
  }

  // Loop mode — for simple in-process scheduling without a container scheduler
  while (running) {
    const loopStart = Date.now();
    try {
      await runExport();
    } catch (err: unknown) {
      console.error(
        JSON.stringify({
          level: "error",
          event: "export_failed",
          error: err instanceof Error ? err.message : String(err),
        })
      );
    }

    const elapsed = Date.now() - loopStart;
    const sleep = Math.max(0, LOOP_INTERVAL_MS - elapsed);
    if (sleep > 0 && running) {
      await new Promise<void>((resolve) => setTimeout(resolve, sleep));
    }
  }

  console.log(JSON.stringify({ level: "info", event: "exporter_stopped" }));
}

function handleShutdown(signal: string): void {
  console.log(
    JSON.stringify({ level: "info", event: "shutdown_requested", signal })
  );
  running = false;
}

process.on("SIGINT", () => handleShutdown("SIGINT"));
process.on("SIGTERM", () => handleShutdown("SIGTERM"));

main().catch((err) => {
  console.error(
    JSON.stringify({
      level: "fatal",
      event: "startup_failed",
      error: err instanceof Error ? err.message : String(err),
    })
  );
  process.exit(1);
});
