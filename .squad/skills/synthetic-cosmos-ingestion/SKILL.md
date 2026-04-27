---
name: "synthetic-cosmos-ingestion"
description: "Build simple Cosmos DB demo ingestion workloads with non-sensitive generated data"
domain: "azure, cosmos-db, ingestion, demo-data"
confidence: "medium"
source: "observed"
---

## Context

Use this pattern when a demo needs recurring Cosmos DB writes but must avoid proprietary datasets, public API dependencies, and credentials in source control.

## Patterns

- Generate public-style synthetic records locally instead of depending on live third-party APIs.
- Keep the Cosmos DB schema easy to explain: stable document type, schema version, partition key field, measurement payload, source classification, and ingestion metadata.
- Use a non-overlapping async loop for timed writes so slow Cosmos DB calls do not pile up concurrent work.
- Default to managed identity in Azure and reserve connection strings for uncommitted local development only.
- Document the exact infrastructure contract as environment variables and Bicep output placeholders.
- Handle `SIGINT` and `SIGTERM` so container hosts can stop the workload cleanly.

## Examples

- `apps/weather-ingestor` writes one synthetic weather observation every `INGEST_INTERVAL_MS`, defaulting to 20 seconds.
- The default partition key is `/cityId`, with database/container defaults of `demo` and `weather`.
- `apps/backup-exporter` reads Cosmos DB via time-window query and writes JSONL + manifest to Blob Storage under `exports/{yyyy}/{MM}/{dd}/{HH}-{mm}/`.
- Eight US cities (Seattle, Chicago, Miami, Denver, Boston, Phoenix, Portland, Atlanta) provide partition distribution without any live API dependencies.
- Use `buildBlobPrefix(windowStart)` from `blob-writer.ts` to derive the deterministic Blob path — Dallas's lifecycle policy targets the `exports/` prefix.

## Anti-Patterns

- Calling public weather APIs in the demo loop when synthetic data is enough.
- Committing connection strings, account keys, or local env files.
- Creating overlapping timer callbacks that continue writing after shutdown starts.
- Hiding partition key assumptions inside code without documenting the Bicep handoff.
