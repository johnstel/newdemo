"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.computeSha256 = computeSha256;
exports.buildManifest = buildManifest;
const node_crypto_1 = require("node:crypto");
/**
 * Compute the SHA-256 hex digest of a UTF-8 string or Buffer.
 */
function computeSha256(data) {
    return (0, node_crypto_1.createHash)("sha256").update(data).digest("hex");
}
/**
 * Build the manifest object from export metadata.
 */
function buildManifest(params) {
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
//# sourceMappingURL=manifest.js.map