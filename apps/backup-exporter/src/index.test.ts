import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { buildManifest, computeSha256 } from "./manifest.js";
import { buildBlobPrefix } from "./blob-writer.js";

describe("computeSha256", () => {
  it("returns a 64-char hex string", () => {
    const hash = computeSha256("hello world");
    assert.strictEqual(typeof hash, "string");
    assert.strictEqual(hash.length, 64);
    assert.match(hash, /^[0-9a-f]+$/);
  });

  it("is deterministic", () => {
    assert.strictEqual(computeSha256("test"), computeSha256("test"));
  });

  it("differs for different inputs", () => {
    assert.notStrictEqual(computeSha256("a"), computeSha256("b"));
  });
});

describe("buildManifest", () => {
  const windowStart = new Date("2025-01-01T08:00:00.000Z");
  const windowEnd = new Date("2025-01-01T14:00:00.000Z");
  const jsonlContent = '{"id":"1"}\n{"id":"2"}';

  it("returns a manifest with expected shape", () => {
    const m = buildManifest({
      windowStart,
      windowEnd,
      itemCount: 2,
      jsonlContent,
      cosmosDatabase: "demo",
      cosmosContainer: "weather",
    });

    assert.strictEqual(m.windowStart, windowStart.toISOString());
    assert.strictEqual(m.windowEnd, windowEnd.toISOString());
    assert.strictEqual(m.itemCount, 2);
    assert.strictEqual(m.dataFile, "data.jsonl");
    assert.strictEqual(m.source.cosmosDatabase, "demo");
    assert.strictEqual(m.source.cosmosContainer, "weather");
    assert.ok(m.exportTimestamp, "exportTimestamp should be set");
    assert.strictEqual(m.sha256.length, 64);
  });

  it("sha256 matches content hash", () => {
    const m = buildManifest({
      windowStart,
      windowEnd,
      itemCount: 1,
      jsonlContent: "content",
      cosmosDatabase: "demo",
      cosmosContainer: "weather",
    });
    assert.strictEqual(m.sha256, computeSha256("content"));
  });
});

describe("buildBlobPrefix", () => {
  it("formats the path correctly", () => {
    const d = new Date("2025-03-07T14:30:00.000Z");
    const prefix = buildBlobPrefix(d);
    assert.strictEqual(prefix, "exports/2025/03/07/14-30/");
  });

  it("pads single-digit month and day", () => {
    const d = new Date("2025-01-05T06:00:00.000Z");
    const prefix = buildBlobPrefix(d);
    assert.strictEqual(prefix, "exports/2025/01/05/06-00/");
  });

  it("ends with a trailing slash", () => {
    const prefix = buildBlobPrefix(new Date());
    assert.ok(prefix.endsWith("/"));
  });
});
