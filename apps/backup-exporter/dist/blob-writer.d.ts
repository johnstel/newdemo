import { ExportManifest } from "./manifest.js";
/**
 * Derive the Blob prefix for a given export time window.
 * Format: exports/{yyyy}/{MM}/{dd}/{HH}-{mm}/
 */
export declare function buildBlobPrefix(windowStart: Date): string;
/**
 * Write the JSONL data file and manifest.json to the export container.
 * Both blobs are tagged with Content-Type and custom metadata for the lifecycle policy.
 * Idempotent: re-running with the same window overwrites existing blobs.
 */
export declare function writeExportBundle(params: {
    jsonlContent: string;
    manifest: ExportManifest;
    windowStart: Date;
}): Promise<{
    dataUrl: string;
    manifestUrl: string;
}>;
//# sourceMappingURL=blob-writer.d.ts.map