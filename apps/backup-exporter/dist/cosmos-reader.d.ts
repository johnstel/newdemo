import { Container } from "@azure/cosmos";
/**
 * Build a Cosmos DB Container reference for the export job.
 * Mirrors the auth strategy in weather-ingestor/cosmos-client.ts.
 */
export declare function getCosmosContainer(): Promise<Container>;
/**
 * Read all documents with observedAt in [windowStart, windowEnd).
 * Returns an array of plain objects (raw Cosmos items).
 */
export declare function readDocumentsInWindow(container: Container, windowStart: Date, windowEnd: Date): Promise<Record<string, unknown>[]>;
//# sourceMappingURL=cosmos-reader.d.ts.map