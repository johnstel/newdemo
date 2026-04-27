import { Container } from "@azure/cosmos";
/**
 * Builds a Cosmos DB Container reference using managed identity in Azure
 * and a connection string fallback for local development only.
 *
 * Auth hierarchy (first match wins):
 *   1. COSMOS_CONNECTION_STRING — local dev only; never committed
 *   2. COSMOS_ENDPOINT + DefaultAzureCredential — Azure managed identity path
 */
export declare function getCosmosContainer(): Promise<Container>;
//# sourceMappingURL=cosmos-client.d.ts.map