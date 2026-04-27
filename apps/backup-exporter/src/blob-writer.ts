import { BlobServiceClient, ContainerClient } from "@azure/storage-blob";
import { DefaultAzureCredential } from "@azure/identity";
import { ExportManifest } from "./manifest.js";

/**
 * Return the export storage client.
 * Azure: reads EXPORT_STORAGE_URL (full blob endpoint injected by Bicep) + managed identity.
 * Local dev: reads STORAGE_CONNECTION_STRING (Azurite / emulator).
 */
function getExportStorageClient(): BlobServiceClient {
  if (process.env.STORAGE_CONNECTION_STRING) {
    console.log("[blob] Using local storage connection string (dev mode)");
    return BlobServiceClient.fromConnectionString(
      process.env.STORAGE_CONNECTION_STRING
    );
  }

  const url = process.env.EXPORT_STORAGE_URL;
  if (!url) {
    throw new Error(
      "EXPORT_STORAGE_URL is required when STORAGE_CONNECTION_STRING is not set."
    );
  }

  console.log(`[blob] Export storage: ${url}`);
  return new BlobServiceClient(url, new DefaultAzureCredential());
}

/**
 * Return the WORM retention storage client, or null in local dev mode.
 * Azure: reads RETENTION_STORAGE_URL (full blob endpoint injected by Bicep).
 * Local dev: skipped — single Azurite instance does not model the two-account split.
 */
function getRetentionStorageClient(): BlobServiceClient | null {
  if (process.env.STORAGE_CONNECTION_STRING) return null;

  const url = process.env.RETENTION_STORAGE_URL;
  if (!url) {
    console.warn(
      "[blob] RETENTION_STORAGE_URL not set — retention (WORM) write skipped"
    );
    return null;
  }

  console.log(`[blob] Retention storage: ${url}`);
  return new BlobServiceClient(url, new DefaultAzureCredential());
}

/**
 * Derive the Blob prefix for a given export time window.
 * Format: exports/{yyyy}/{MM}/{dd}/{HH}-{mm}/
 */
export function buildBlobPrefix(windowStart: Date): string {
  const yyyy = windowStart.getUTCFullYear().toString();
  const MM = String(windowStart.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(windowStart.getUTCDate()).padStart(2, "0");
  const HH = String(windowStart.getUTCHours()).padStart(2, "0");
  const mm = String(windowStart.getUTCMinutes()).padStart(2, "0");
  return `exports/${yyyy}/${MM}/${dd}/${HH}-${mm}/`;
}

/**
 * Write JSONL + manifest to a single BlobServiceClient's container.
 * Returns the URLs of the uploaded data and manifest blobs.
 */
async function writeBundleToClient(
  serviceClient: BlobServiceClient,
  containerName: string,
  prefix: string,
  dataBuffer: Buffer,
  manifestBuffer: Buffer,
  manifest: ExportManifest
): Promise<{ dataUrl: string; manifestUrl: string }> {
  const containerClient: ContainerClient =
    serviceClient.getContainerClient(containerName);

  // Create container only for local dev / emulator
  if (process.env.STORAGE_CONNECTION_STRING) {
    await containerClient.createIfNotExists();
  }

  const dataBlob = containerClient.getBlockBlobClient(`${prefix}data.jsonl`);
  const manifestBlob = containerClient.getBlockBlobClient(
    `${prefix}manifest.json`
  );

  await dataBlob.upload(dataBuffer, dataBuffer.byteLength, {
    blobHTTPHeaders: { blobContentType: "application/x-ndjson" },
    metadata: {
      exportTimestamp: manifest.exportTimestamp,
      windowStart: manifest.windowStart,
      windowEnd: manifest.windowEnd,
      itemCount: String(manifest.itemCount),
    },
  });

  await manifestBlob.upload(manifestBuffer, manifestBuffer.byteLength, {
    blobHTTPHeaders: { blobContentType: "application/json" },
    metadata: {
      exportTimestamp: manifest.exportTimestamp,
      sha256: manifest.sha256,
    },
  });

  return { dataUrl: dataBlob.url, manifestUrl: manifestBlob.url };
}

/**
 * Write the JSONL data file and manifest.json to BOTH the export storage account
 * (primary, in the primary RG) and the WORM retention storage account (compliance archive).
 *
 * Container name defaults to "exports" — matches the Bicep-provisioned container in both
 * storage-exports.bicep and storage-retention.bicep.
 *
 * Idempotent: re-running with the same window overwrites existing blobs.
 */
export async function writeExportBundle(params: {
  jsonlContent: string;
  manifest: ExportManifest;
  windowStart: Date;
}): Promise<{
  dataUrl: string;
  manifestUrl: string;
  retentionDataUrl?: string;
  retentionManifestUrl?: string;
}> {
  const containerName = process.env.EXPORT_CONTAINER_NAME ?? "exports";
  const prefix = buildBlobPrefix(params.windowStart);

  const dataBuffer = Buffer.from(params.jsonlContent, "utf8");
  const manifestBuffer = Buffer.from(
    JSON.stringify(params.manifest, null, 2),
    "utf8"
  );

  // Write to primary export storage
  const exportClient = getExportStorageClient();
  const { dataUrl, manifestUrl } = await writeBundleToClient(
    exportClient,
    containerName,
    prefix,
    dataBuffer,
    manifestBuffer,
    params.manifest
  );

  // Write to WORM retention storage (compliance archive)
  let retentionDataUrl: string | undefined;
  let retentionManifestUrl: string | undefined;

  const retentionClient = getRetentionStorageClient();
  if (retentionClient) {
    const result = await writeBundleToClient(
      retentionClient,
      containerName,
      prefix,
      dataBuffer,
      manifestBuffer,
      params.manifest
    );
    retentionDataUrl = result.dataUrl;
    retentionManifestUrl = result.manifestUrl;
    console.log(
      JSON.stringify({
        level: "info",
        event: "retention_write_complete",
        retentionDataUrl,
        retentionManifestUrl,
      })
    );
  }

  return { dataUrl, manifestUrl, retentionDataUrl, retentionManifestUrl };
}
