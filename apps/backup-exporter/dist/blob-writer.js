"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildBlobPrefix = buildBlobPrefix;
exports.writeExportBundle = writeExportBundle;
const storage_blob_1 = require("@azure/storage-blob");
const identity_1 = require("@azure/identity");
/**
 * Build a BlobServiceClient using managed identity (Azure) or
 * a connection string for local development.
 */
function getBlobServiceClient() {
    if (process.env.STORAGE_CONNECTION_STRING) {
        console.log("[blob] Using local storage connection string (dev mode)");
        return storage_blob_1.BlobServiceClient.fromConnectionString(process.env.STORAGE_CONNECTION_STRING);
    }
    const accountName = process.env.EXPORT_STORAGE_ACCOUNT_NAME;
    if (!accountName) {
        throw new Error("EXPORT_STORAGE_ACCOUNT_NAME is required when STORAGE_CONNECTION_STRING is not set.");
    }
    const url = `https://${accountName}.blob.core.windows.net`;
    console.log(`[blob] Using managed identity auth against ${url}`);
    return new storage_blob_1.BlobServiceClient(url, new identity_1.DefaultAzureCredential());
}
/**
 * Derive the Blob prefix for a given export time window.
 * Format: exports/{yyyy}/{MM}/{dd}/{HH}-{mm}/
 */
function buildBlobPrefix(windowStart) {
    const yyyy = windowStart.getUTCFullYear().toString();
    const MM = String(windowStart.getUTCMonth() + 1).padStart(2, "0");
    const dd = String(windowStart.getUTCDate()).padStart(2, "0");
    const HH = String(windowStart.getUTCHours()).padStart(2, "0");
    const mm = String(windowStart.getUTCMinutes()).padStart(2, "0");
    return `exports/${yyyy}/${MM}/${dd}/${HH}-${mm}/`;
}
/**
 * Write the JSONL data file and manifest.json to the export container.
 * Both blobs are tagged with Content-Type and custom metadata for the lifecycle policy.
 * Idempotent: re-running with the same window overwrites existing blobs.
 */
async function writeExportBundle(params) {
    const containerName = process.env.EXPORT_CONTAINER_NAME ?? "cosmos-exports";
    const prefix = buildBlobPrefix(params.windowStart);
    const serviceClient = getBlobServiceClient();
    const containerClient = serviceClient.getContainerClient(containerName);
    // Create the container if missing (only relevant for local dev / emulator)
    if (process.env.STORAGE_CONNECTION_STRING) {
        await containerClient.createIfNotExists();
    }
    const dataBlob = containerClient.getBlockBlobClient(`${prefix}data.jsonl`);
    const manifestBlob = containerClient.getBlockBlobClient(`${prefix}manifest.json`);
    const dataBuffer = Buffer.from(params.jsonlContent, "utf8");
    const manifestBuffer = Buffer.from(JSON.stringify(params.manifest, null, 2), "utf8");
    await dataBlob.upload(dataBuffer, dataBuffer.byteLength, {
        blobHTTPHeaders: { blobContentType: "application/x-ndjson" },
        metadata: {
            exportTimestamp: params.manifest.exportTimestamp,
            windowStart: params.manifest.windowStart,
            windowEnd: params.manifest.windowEnd,
            itemCount: String(params.manifest.itemCount),
        },
    });
    await manifestBlob.upload(manifestBuffer, manifestBuffer.byteLength, {
        blobHTTPHeaders: { blobContentType: "application/json" },
        metadata: {
            exportTimestamp: params.manifest.exportTimestamp,
            sha256: params.manifest.sha256,
        },
    });
    return { dataUrl: dataBlob.url, manifestUrl: manifestBlob.url };
}
//# sourceMappingURL=blob-writer.js.map