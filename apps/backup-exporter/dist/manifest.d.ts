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
export declare function computeSha256(data: string | Buffer): string;
/**
 * Build the manifest object from export metadata.
 */
export declare function buildManifest(params: {
    windowStart: Date;
    windowEnd: Date;
    itemCount: number;
    jsonlContent: string;
    cosmosDatabase: string;
    cosmosContainer: string;
}): ExportManifest;
//# sourceMappingURL=manifest.d.ts.map