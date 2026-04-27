"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const strict_1 = __importDefault(require("node:assert/strict"));
const manifest_js_1 = require("./manifest.js");
const blob_writer_js_1 = require("./blob-writer.js");
(0, node_test_1.describe)("computeSha256", () => {
    (0, node_test_1.it)("returns a 64-char hex string", () => {
        const hash = (0, manifest_js_1.computeSha256)("hello world");
        strict_1.default.strictEqual(typeof hash, "string");
        strict_1.default.strictEqual(hash.length, 64);
        strict_1.default.match(hash, /^[0-9a-f]+$/);
    });
    (0, node_test_1.it)("is deterministic", () => {
        strict_1.default.strictEqual((0, manifest_js_1.computeSha256)("test"), (0, manifest_js_1.computeSha256)("test"));
    });
    (0, node_test_1.it)("differs for different inputs", () => {
        strict_1.default.notStrictEqual((0, manifest_js_1.computeSha256)("a"), (0, manifest_js_1.computeSha256)("b"));
    });
});
(0, node_test_1.describe)("buildManifest", () => {
    const windowStart = new Date("2025-01-01T08:00:00.000Z");
    const windowEnd = new Date("2025-01-01T14:00:00.000Z");
    const jsonlContent = '{"id":"1"}\n{"id":"2"}';
    (0, node_test_1.it)("returns a manifest with expected shape", () => {
        const m = (0, manifest_js_1.buildManifest)({
            windowStart,
            windowEnd,
            itemCount: 2,
            jsonlContent,
            cosmosDatabase: "demo",
            cosmosContainer: "weather",
        });
        strict_1.default.strictEqual(m.windowStart, windowStart.toISOString());
        strict_1.default.strictEqual(m.windowEnd, windowEnd.toISOString());
        strict_1.default.strictEqual(m.itemCount, 2);
        strict_1.default.strictEqual(m.dataFile, "data.jsonl");
        strict_1.default.strictEqual(m.source.cosmosDatabase, "demo");
        strict_1.default.strictEqual(m.source.cosmosContainer, "weather");
        strict_1.default.ok(m.exportTimestamp, "exportTimestamp should be set");
        strict_1.default.strictEqual(m.sha256.length, 64);
    });
    (0, node_test_1.it)("sha256 matches content hash", () => {
        const m = (0, manifest_js_1.buildManifest)({
            windowStart,
            windowEnd,
            itemCount: 1,
            jsonlContent: "content",
            cosmosDatabase: "demo",
            cosmosContainer: "weather",
        });
        strict_1.default.strictEqual(m.sha256, (0, manifest_js_1.computeSha256)("content"));
    });
});
(0, node_test_1.describe)("buildBlobPrefix", () => {
    (0, node_test_1.it)("formats the path correctly", () => {
        const d = new Date("2025-03-07T14:30:00.000Z");
        const prefix = (0, blob_writer_js_1.buildBlobPrefix)(d);
        strict_1.default.strictEqual(prefix, "exports/2025/03/07/14-30/");
    });
    (0, node_test_1.it)("pads single-digit month and day", () => {
        const d = new Date("2025-01-05T06:00:00.000Z");
        const prefix = (0, blob_writer_js_1.buildBlobPrefix)(d);
        strict_1.default.strictEqual(prefix, "exports/2025/01/05/06-00/");
    });
    (0, node_test_1.it)("ends with a trailing slash", () => {
        const prefix = (0, blob_writer_js_1.buildBlobPrefix)(new Date());
        strict_1.default.ok(prefix.endsWith("/"));
    });
});
//# sourceMappingURL=index.test.js.map