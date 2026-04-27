import { createHash } from "node:crypto";

/**
 * Manifest written alongside each export bundle.
 * Stored as manifest.json in the same Blob prefix as data.jsonl.
 */
export interface ExportManifest {
  exportTimestamp: string;
  windowStart: string;
  windowEnd: string;
  itemCount: number;
  dataFile: string;
  sha256: string;
  source: {
    cosmosDatabase: string;
    cosmosContainer: string;
  };
}

/**
 * Compute the SHA-256 hex digest of a UTF-8 string or Buffer.
 */
export function computeSha256(data: string | Buffer): string {
  return createHash("sha256").update(data).digest("hex");
}

/**
 * Build the manifest object from export metadata.
 */
export function buildManifest(params: {
  windowStart: Date;
  windowEnd: Date;
  itemCount: number;
  jsonlContent: string;
  cosmosDatabase: string;
  cosmosContainer: string;
}): ExportManifest {
  return {
    exportTimestamp: new Date().toISOString(),
    windowStart: params.windowStart.toISOString(),
    windowEnd: params.windowEnd.toISOString(),
    itemCount: params.itemCount,
    dataFile: "data.jsonl",
    sha256: computeSha256(params.jsonlContent),
    source: {
      cosmosDatabase: params.cosmosDatabase,
      cosmosContainer: params.cosmosContainer,
    },
  };
}
