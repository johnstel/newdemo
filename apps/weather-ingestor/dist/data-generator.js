"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.STATIONS = void 0;
exports.generateWeatherObservation = generateWeatherObservation;
const node_crypto_1 = require("node:crypto");
/** Station catalog — public US cities used for demo variety */
const STATIONS = [
    {
        cityId: "city-seattle-wa",
        city: "Seattle",
        state: "WA",
        region: "westus2",
        deviceId: "station-sea-01",
    },
    {
        cityId: "city-chicago-il",
        city: "Chicago",
        state: "IL",
        region: "northcentralus",
        deviceId: "station-chi-01",
    },
    {
        cityId: "city-miami-fl",
        city: "Miami",
        state: "FL",
        region: "eastus",
        deviceId: "station-mia-01",
    },
    {
        cityId: "city-denver-co",
        city: "Denver",
        state: "CO",
        region: "westcentralus",
        deviceId: "station-den-01",
    },
    {
        cityId: "city-boston-ma",
        city: "Boston",
        state: "MA",
        region: "eastus2",
        deviceId: "station-bos-01",
    },
    {
        cityId: "city-phoenix-az",
        city: "Phoenix",
        state: "AZ",
        region: "westus",
        deviceId: "station-phx-01",
    },
    {
        cityId: "city-portland-or",
        city: "Portland",
        state: "OR",
        region: "westus2",
        deviceId: "station-pdx-01",
    },
    {
        cityId: "city-atlanta-ga",
        city: "Atlanta",
        state: "GA",
        region: "eastus",
        deviceId: "station-atl-01",
    },
];
exports.STATIONS = STATIONS;
const CONDITIONS = [
    "Clear",
    "Partly Cloudy",
    "Mostly Cloudy",
    "Overcast",
    "Light Rain",
    "Moderate Rain",
    "Heavy Rain",
    "Thunderstorm",
    "Light Snow",
    "Fog",
    "Drizzle",
    "Windy",
];
function rand(min, max, decimals = 1) {
    const value = Math.random() * (max - min) + min;
    const factor = Math.pow(10, decimals);
    return Math.round(value * factor) / factor;
}
function randInt(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
}
function pickRandom(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
}
/**
 * Generate one synthetic weather observation record.
 * The station is chosen round-robin by index to distribute partition load evenly.
 */
function generateWeatherObservation(stationIndex) {
    const station = STATIONS[stationIndex % STATIONS.length];
    const now = new Date();
    return {
        id: (0, node_crypto_1.randomUUID)(),
        cityId: station.cityId,
        tenantId: "demo-tenant",
        workloadId: "weather-ingestor",
        schemaVersion: "1.0",
        documentType: "weather-observation",
        region: station.region,
        city: station.city,
        state: station.state,
        country: "US",
        deviceId: station.deviceId,
        source: "synthetic",
        observedAt: now.toISOString(),
        ingestedAt: now.toISOString(),
        metrics: {
            temperatureCelsius: rand(-10, 40, 1),
            humidityPercent: rand(10, 100, 0),
            windSpeedKph: rand(0, 120, 1),
            windDirectionDeg: randInt(0, 359),
            pressureHpa: rand(970, 1040, 1),
            precipitationMm: rand(0, 30, 2),
            cloudCoverPercent: rand(0, 100, 0),
            visibilityKm: rand(0.5, 50, 1),
            uvIndex: rand(0, 11, 1),
            condition: pickRandom(CONDITIONS),
        },
    };
}
//# sourceMappingURL=data-generator.js.map