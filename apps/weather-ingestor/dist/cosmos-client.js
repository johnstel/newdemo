"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getCosmosContainer = getCosmosContainer;
const cosmos_1 = require("@azure/cosmos");
const identity_1 = require("@azure/identity");
/**
 * Builds a Cosmos DB Container reference using managed identity in Azure
 * and a connection string fallback for local development only.
 *
 * Auth hierarchy (first match wins):
 *   1. COSMOS_CONNECTION_STRING — local dev only; never committed
 *   2. COSMOS_ENDPOINT + DefaultAzureCredential — Azure managed identity path
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
            throw new Error("COSMOS_ENDPOINT is required when COSMOS_CONNECTION_STRING is not set. " +
                "Set COSMOS_ENDPOINT for Azure managed-identity auth, or " +
                "COSMOS_CONNECTION_STRING for local development.");
        }
        console.log(`[cosmos] Using managed identity auth against ${endpoint}`);
        const credential = new identity_1.DefaultAzureCredential();
        client = new cosmos_1.CosmosClient({ endpoint, aadCredentials: credential });
    }
    const database = client.database(databaseName);
    const container = database.container(containerName);
    return container;
}
//# sourceMappingURL=cosmos-client.js.map