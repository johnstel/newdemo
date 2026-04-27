import { CosmosClient, Container } from "@azure/cosmos";
import { DefaultAzureCredential } from "@azure/identity";

/**
 * Build a Cosmos DB Container reference for the export job.
 * Mirrors the auth strategy in weather-ingestor/cosmos-client.ts.
 */
export async function getCosmosContainer(): Promise<Container> {
  const databaseName = process.env.COSMOS_DATABASE_NAME ?? "demo";
  const containerName = process.env.COSMOS_CONTAINER_NAME ?? "weather";

  let client: CosmosClient;

  if (process.env.COSMOS_CONNECTION_STRING) {
    console.log("[cosmos] Using local connection string (dev mode)");
    client = new CosmosClient(process.env.COSMOS_CONNECTION_STRING);
  } else {
    const endpoint = process.env.COSMOS_ENDPOINT;
    if (!endpoint) {
      throw new Error(
        "COSMOS_ENDPOINT is required when COSMOS_CONNECTION_STRING is not set."
      );
    }
    console.log(`[cosmos] Using managed identity auth against ${endpoint}`);
    const credential = new DefaultAzureCredential();
    client = new CosmosClient({ endpoint, aadCredentials: credential });
  }

  return client.database(databaseName).container(containerName);
}

/**
 * Read all documents with observedAt in [windowStart, windowEnd).
 * Returns an array of plain objects (raw Cosmos items).
 */
export async function readDocumentsInWindow(
  container: Container,
  windowStart: Date,
  windowEnd: Date
): Promise<Record<string, unknown>[]> {
  const query = {
    query:
      "SELECT * FROM c WHERE c.observedAt >= @windowStart AND c.observedAt < @windowEnd ORDER BY c.observedAt ASC",
    parameters: [
      { name: "@windowStart", value: windowStart.toISOString() },
      { name: "@windowEnd", value: windowEnd.toISOString() },
    ],
  };

  const { resources } = await container.items
    .query<Record<string, unknown>>(query, { maxItemCount: 10000 })
    .fetchAll();

  return resources;
}
