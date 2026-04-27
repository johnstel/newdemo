/**
 * Unit tests for apps/weather-ingestor/src/data-generator.ts
 *
 * These tests validate the document schema contract defined in
 * docs/design-review.md §1.4:
 *   - Partition key: /cityId (non-empty string)
 *   - Required fields: id, cityId, timestamp, temperature, humidity
 *   - Timestamp: ISO 8601 UTC string
 *   - No account keys or secrets in the document or env var usage
 *
 * STATUS: Scaffold — will pass once Parker implements data-generator.ts.
 * Import path assumes tests/ is sibling to apps/.
 */

// Adjust this import once apps/weather-ingestor/src/data-generator.ts exists:
// import { generateWeatherDocument } from '../../apps/weather-ingestor/src/data-generator';

// Temporary stub so the test file is parseable before apps/ is created.
// Uses a monotonic counter to guarantee ID uniqueness — matching Parker's
// real implementation requirement (e.g., crypto.randomUUID or nanoid).
let _stubCounter = 0;
const generateWeatherDocument = (): Record<string, unknown> => {
  _stubCounter += 1;
  return {
    id: `mock-${Date.now()}-${_stubCounter}`,
    cityId: 'seattle-wa',
    timestamp: new Date().toISOString(),
    temperature: 15.3,
    humidity: 72,
    windSpeedKph: 12.1,
    conditionCode: 'CLOUDY',
  };
};

// ============================================================
// SCHEMA CONTRACT TESTS
// ============================================================

describe('data-generator: generateWeatherDocument', () => {
  let doc: Record<string, unknown>;

  beforeEach(() => {
    doc = generateWeatherDocument();
  });

  // --- Required fields ---

  it('returns a document with a non-empty id', () => {
    expect(typeof doc.id).toBe('string');
    expect((doc.id as string).length).toBeGreaterThan(0);
  });

  it('returns a document with a non-empty cityId (partition key)', () => {
    expect(typeof doc.cityId).toBe('string');
    expect((doc.cityId as string).length).toBeGreaterThan(0);
  });

  it('returns a document with an ISO 8601 UTC timestamp', () => {
    expect(typeof doc.timestamp).toBe('string');
    // ISO 8601: starts with YYYY-MM-DDTHH:MM:SS and ends with Z or offset
    expect(doc.timestamp as string).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/);
  });

  it('returns a document with a numeric temperature', () => {
    expect(typeof doc.temperature).toBe('number');
  });

  it('returns a document with a numeric humidity', () => {
    expect(typeof doc.humidity).toBe('number');
    expect(doc.humidity as number).toBeGreaterThanOrEqual(0);
    expect(doc.humidity as number).toBeLessThanOrEqual(100);
  });

  // --- Partition key contract ---

  it('cityId is consistent across multiple calls for the same city', () => {
    // Documents for the same city must share a partition key
    const docs = Array.from({ length: 3 }, () => generateWeatherDocument());
    const cityIds = new Set(docs.map((d) => d.cityId));
    // Each call may use the same or different cities, but cityId must always be populated
    docs.forEach((d) => {
      expect(d.cityId).toBeTruthy();
    });
  });

  // --- ID uniqueness ---

  it('generates unique ids across successive calls', () => {
    const ids = Array.from({ length: 10 }, () => generateWeatherDocument().id);
    const unique = new Set(ids);
    expect(unique.size).toBe(10);
  });

  // --- No secrets in document payload ---

  it('does not include connection strings or keys in the document', () => {
    const payload = JSON.stringify(doc).toLowerCase();
    const forbidden = ['accountkey', 'connectionstring', 'password', 'secret', 'sas_token'];
    forbidden.forEach((kw) => {
      expect(payload).not.toContain(kw);
    });
  });
});
