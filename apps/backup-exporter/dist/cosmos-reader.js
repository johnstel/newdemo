"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getCosmosContainer = getCosmosContainer;
exports.readDocumentsInWindow = readDocumentsInWindow;
const cosmos_1 = require("@azure/cosmos");
const identity_1 = require("@azure/identity");
/**
 * Build a Cosmos DB Container reference for the export job.
 * Mirrors the auth strategy in weather-ingestor/cosmos-client.ts.
 */
async function getCosmosContainer() {
    const databaseName = process.env.COSMOS_DATABASE_NAME ?? "demo";
    const containerName = process.env.COSMOS_CONTAINER_NAME ?? "weather";
    let client;
    if (process.env.COSMOS_CONNECTION_STRING) {
        console.log("[cosmos] Using local connection string (dev mode)");
        client = new cosmos_1.CosmosClient(process.env.COSMOS_CONNECTION_STRING);
    }
    else {
        const endpoint = process.env.COSMOS_ENDPOINT;
        if (!endpoint) {
            throw new Error("COSMOS_ENDPOINT is required when COSMOS_CONNECTION_STRING is not set.");
        }
        console.log(`[cosmos] Using managed identity auth against ${endpoint}`);
        const credential = new identity_1.DefaultAzureCredential();
        client = new cosmos_1.CosmosClient({ endpoint, aadCredentials: credential });
    }
    return client.database(databaseName).container(containerName);
}
/**
 * Read all documents with observedAt in [windowStart, windowEnd).
 * Returns an array of plain objects (raw Cosmos items).
 */
async function readDocumentsInWindow(container, windowStart, windowEnd) {
    const query = {
        query: "SELECT * FROM c WHERE c.observedAt >= @windowStart AND c.observedAt < @windowEnd ORDER BY c.observedAt ASC",
        parameters: [
            { name: "@windowStart", value: windowStart.toISOString() },
            { name: "@windowEnd", value: windowEnd.toISOString() },
        ],
    };
    const { resources } = await container.items
        .query(query, { maxItemCount: 10000 })
        .fetchAll();
    return resources;
}
//# sourceMappingURL=cosmos-reader.js.map