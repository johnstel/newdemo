"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const strict_1 = __importDefault(require("node:assert/strict"));
const data_generator_js_1 = require("./data-generator.js");
(0, node_test_1.describe)("generateWeatherObservation", () => {
    (0, node_test_1.it)("returns a document with required top-level fields", () => {
        const doc = (0, data_generator_js_1.generateWeatherObservation)(0);
        strict_1.default.ok(doc.id, "id should be set");
        strict_1.default.ok(doc.cityId, "cityId (partition key) should be set");
        strict_1.default.strictEqual(doc.tenantId, "demo-tenant");
        strict_1.default.strictEqual(doc.workloadId, "weather-ingestor");
        strict_1.default.strictEqual(doc.schemaVersion, "1.0");
        strict_1.default.strictEqual(doc.documentType, "weather-observation");
        strict_1.default.strictEqual(doc.source, "synthetic");
        strict_1.default.strictEqual(doc.country, "US");
        strict_1.default.ok(doc.observedAt, "observedAt should be set");
        strict_1.default.ok(doc.ingestedAt, "ingestedAt should be set");
    });
    (0, node_test_1.it)("observedAt and ingestedAt are ISO 8601 strings", () => {
        const doc = (0, data_generator_js_1.generateWeatherObservation)(0);
        strict_1.default.doesNotThrow(() => new Date(doc.observedAt));
        strict_1.default.doesNotThrow(() => new Date(doc.ingestedAt));
        strict_1.default.ok(doc.observedAt.includes("T"), "observedAt should be ISO 8601");
    });
    (0, node_test_1.it)("partition key matches station cityId", () => {
        const doc = (0, data_generator_js_1.generateWeatherObservation)(0);
        strict_1.default.strictEqual(doc.cityId, data_generator_js_1.STATIONS[0].cityId);
    });
    (0, node_test_1.it)("rotates through stations by index", () => {
        const doc0 = (0, data_generator_js_1.generateWeatherObservation)(0);
        const doc1 = (0, data_generator_js_1.generateWeatherObservation)(1);
        strict_1.default.notStrictEqual(doc0.cityId, doc1.cityId);
    });
    (0, node_test_1.it)("wraps station index round-robin", () => {
        const count = data_generator_js_1.STATIONS.length;
        const doc = (0, data_generator_js_1.generateWeatherObservation)(count);
        strict_1.default.strictEqual(doc.cityId, data_generator_js_1.STATIONS[0].cityId);
    });
    (0, node_test_1.it)("metrics have numeric fields in expected ranges", () => {
        const { metrics } = (0, data_generator_js_1.generateWeatherObservation)(0);
        strict_1.default.ok(typeof metrics.temperatureCelsius === "number");
        strict_1.default.ok(metrics.humidityPercent >= 0 && metrics.humidityPercent <= 100);
        strict_1.default.ok(metrics.windSpeedKph >= 0);
        strict_1.default.ok(metrics.pressureHpa >= 900 && metrics.pressureHpa <= 1100);
        strict_1.default.ok(typeof metrics.condition === "string" && metrics.condition.length > 0);
    });
    (0, node_test_1.it)("each call produces a unique id", () => {
        const ids = new Set(Array.from({ length: 20 }, (_, i) => (0, data_generator_js_1.generateWeatherObservation)(i).id));
        strict_1.default.strictEqual(ids.size, 20, "ids should be unique");
    });
});
//# sourceMappingURL=index.test.js.map