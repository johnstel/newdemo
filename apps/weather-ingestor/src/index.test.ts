import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { generateWeatherObservation, STATIONS } from "./data-generator.js";

describe("generateWeatherObservation", () => {
  it("returns a document with required top-level fields", () => {
    const doc = generateWeatherObservation(0);

    assert.ok(doc.id, "id should be set");
    assert.ok(doc.cityId, "cityId (partition key) should be set");
    assert.strictEqual(doc.tenantId, "demo-tenant");
    assert.strictEqual(doc.workloadId, "weather-ingestor");
    assert.strictEqual(doc.schemaVersion, "1.0");
    assert.strictEqual(doc.documentType, "weather-observation");
    assert.strictEqual(doc.source, "synthetic");
    assert.strictEqual(doc.country, "US");
    assert.ok(doc.observedAt, "observedAt should be set");
    assert.ok(doc.ingestedAt, "ingestedAt should be set");
  });

  it("observedAt and ingestedAt are ISO 8601 strings", () => {
    const doc = generateWeatherObservation(0);
    assert.doesNotThrow(() => new Date(doc.observedAt));
    assert.doesNotThrow(() => new Date(doc.ingestedAt));
    assert.ok(doc.observedAt.includes("T"), "observedAt should be ISO 8601");
  });

  it("partition key matches station cityId", () => {
    const doc = generateWeatherObservation(0);
    assert.strictEqual(doc.cityId, STATIONS[0].cityId);
  });

  it("rotates through stations by index", () => {
    const doc0 = generateWeatherObservation(0);
    const doc1 = generateWeatherObservation(1);
    assert.notStrictEqual(doc0.cityId, doc1.cityId);
  });

  it("wraps station index round-robin", () => {
    const count = STATIONS.length;
    const doc = generateWeatherObservation(count);
    assert.strictEqual(doc.cityId, STATIONS[0].cityId);
  });

  it("metrics have numeric fields in expected ranges", () => {
    const { metrics } = generateWeatherObservation(0);
    assert.ok(typeof metrics.temperatureCelsius === "number");
    assert.ok(metrics.humidityPercent >= 0 && metrics.humidityPercent <= 100);
    assert.ok(metrics.windSpeedKph >= 0);
    assert.ok(metrics.pressureHpa >= 900 && metrics.pressureHpa <= 1100);
    assert.ok(typeof metrics.condition === "string" && metrics.condition.length > 0);
  });

  it("each call produces a unique id", () => {
    const ids = new Set(
      Array.from({ length: 20 }, (_, i) => generateWeatherObservation(i).id)
    );
    assert.strictEqual(ids.size, 20, "ids should be unique");
  });
});
