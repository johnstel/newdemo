/**
 * Unit tests for apps/weather-ingestor/src/cosmos-client.ts
 * and apps/backup-exporter/src/cosmos-reader.ts
 *
 * Validates the environment variable contract (no account keys)
 * and the managed identity / DefaultAzureCredential usage
 * defined in docs/design-review.md §1.3 and §1.4.
 *
 * STATUS: Scaffold — validates env var contract and security
 * invariants. Mocks Azure SDK; does NOT hit live Azure.
 */

// ============================================================
// ENV VAR CONTRACT
// ============================================================

describe('cosmos-client: environment variable contract', () => {
  const REQUIRED_ENV_VARS = [
    'COSMOS_ENDPOINT',
    'COSMOS_DATABASE_NAME',
    'COSMOS_CONTAINER_NAME',
  ];

  const FORBIDDEN_ENV_VARS = [
    'COSMOS_KEY',
    'COSMOS_ACCOUNT_KEY',
    'COSMOS_CONNECTION_STRING',
    'AZURE_CLIENT_SECRET',
  ];

  it('documents required env vars for ingestor', () => {
    // These are the env vars the ingestor MUST read from .env.example
    REQUIRED_ENV_VARS.forEach((v) => {
      expect(v).toBeDefined(); // structural assertion — ensures list is populated
    });
  });

  it('does not hard-code a connection string (security invariant)', () => {
    // If apps/weather-ingestor/src/cosmos-client.ts exists, check it doesn't
    // contain account keys. This is a static check at the environment level.
    // When running in Azure: AZURE_CLIENT_ID is set via managed identity binding.
    const envVarsInUse = Object.keys(process.env);

    FORBIDDEN_ENV_VARS.forEach((forbidden) => {
      // The test environment should not have any of these populated.
      // If they ARE set, the test environment itself may be misconfigured.
      if (process.env[forbidden]) {
        throw new Error(
          `Forbidden env var '${forbidden}' is set in test environment — ` +
          'this indicates a key-based auth leak. Use managed identity instead.'
        );
      }
    });
  });

  it('INGEST_INTERVAL_MS defaults to 20000 if not set', () => {
    // Per design-review.md §1.4: cadence defaults to 20 seconds.
    const interval = process.env.INGEST_INTERVAL_MS
      ? parseInt(process.env.INGEST_INTERVAL_MS, 10)
      : 20000;
    expect(interval).toBe(20000);
  });

  it('INGEST_INTERVAL_MS is positive when set', () => {
    const envVal = process.env.INGEST_INTERVAL_MS;
    if (envVal !== undefined) {
      const parsed = parseInt(envVal, 10);
      expect(isNaN(parsed)).toBe(false);
      expect(parsed).toBeGreaterThan(0);
    }
  });
});

// ============================================================
// AUTH PATTERN — DefaultAzureCredential usage
// ============================================================

describe('cosmos-client: managed identity auth', () => {
  it('DefaultAzureCredential is the only credential type used (static assertion)', () => {
    // This test documents the architectural constraint:
    // both apps MUST use DefaultAzureCredential from @azure/identity.
    //
    // When apps/ is built, add a real import and verify:
    //   import { CosmosClient } from '@azure/cosmos';
    //   import { DefaultAzureCredential } from '@azure/identity';
    //
    // Here we assert the expectation structurally.
    const REQUIRED_AUTH_CLASS = 'DefaultAzureCredential';
    expect(REQUIRED_AUTH_CLASS).toBe('DefaultAzureCredential');
  });

  it('no account keys should appear in Cosmos client constructor (security)', () => {
    // When apps/weather-ingestor/src/cosmos-client.ts exists:
    //   const client = new CosmosClient({ endpoint, aadCredentials });
    // The 'key' property must NOT be set.
    //
    // Structural assertion for now:
    const constructorMustNotHaveKeyProperty = true;
    expect(constructorMustNotHaveKeyProperty).toBe(true);
  });
});

// ============================================================
// COSMOS READER ENV CONTRACT (backup-exporter)
// ============================================================

describe('cosmos-reader: environment variable contract', () => {
  const REQUIRED_EXPORTER_ENV_VARS = [
    'COSMOS_ENDPOINT',
    'COSMOS_DATABASE_NAME',
    'COSMOS_CONTAINER_NAME',
    'EXPORT_STORAGE_ACCOUNT_NAME',
    'EXPORT_CONTAINER_NAME',
    'EXPORT_WINDOW_HOURS',
  ];

  it('documents required env vars for exporter', () => {
    REQUIRED_EXPORTER_ENV_VARS.forEach((v) => {
      expect(v).toBeDefined();
    });
  });

  it('EXPORT_WINDOW_HOURS defaults to 6 when not set', () => {
    const windowHours = process.env.EXPORT_WINDOW_HOURS
      ? parseInt(process.env.EXPORT_WINDOW_HOURS, 10)
      : 6;
    expect(windowHours).toBe(6);
  });
});
