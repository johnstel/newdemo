/**
 * Unit tests for apps/backup-exporter/src/manifest.ts
 *
 * Validates the export manifest contract defined in
 * docs/design-review.md §1.5:
 *   - itemCount: non-negative integer
 *   - sha256: 64-char hex string
 *   - exportedAt: ISO 8601 UTC
 *   - sourceFrom / sourceTo: ISO 8601 UTC range
 *   - Export path format: exports/{yyyy}/{MM}/{dd}/{HH}-{mm}/data.json
 *
 * STATUS: Scaffold — will pass once Parker implements manifest.ts.
 */

import { createHash } from 'crypto';

// Temporary stub interfaces mirroring Parker's expected contract.
// Replace with actual import once apps/backup-exporter/src/manifest.ts exists:
// import { buildManifest, ExportManifest, buildExportPath } from '../../apps/backup-exporter/src/manifest';

interface ExportManifest {
  itemCount: number;
  sha256: string;
  exportedAt: string;
  sourceFrom: string;
  sourceTo: string;
}

// Stub implementations matching Parker's expected behaviour:
function buildManifest(
  items: unknown[],
  serialised: string,
  sourceFrom: string,
  sourceTo: string,
): ExportManifest {
  return {
    itemCount: items.length,
    sha256: createHash('sha256').update(serialised).digest('hex'),
    exportedAt: new Date().toISOString(),
    sourceFrom,
    sourceTo,
  };
}

function buildExportPath(now: Date): string {
  const yyyy = now.getUTCFullYear().toString().padStart(4, '0');
  const MM = (now.getUTCMonth() + 1).toString().padStart(2, '0');
  const dd = now.getUTCDate().toString().padStart(2, '0');
  const HH = now.getUTCHours().toString().padStart(2, '0');
  const mm = now.getUTCMinutes().toString().padStart(2, '0');
  return `exports/${yyyy}/${MM}/${dd}/${HH}-${mm}/data.json`;
}

// ============================================================
// MANIFEST TESTS
// ============================================================

describe('manifest: buildManifest', () => {
  const SAMPLE_ITEMS = [{ id: 'a', cityId: 'seattle' }, { id: 'b', cityId: 'boston' }];
  const SERIALISED = JSON.stringify(SAMPLE_ITEMS);
  const SOURCE_FROM = '2026-04-27T00:00:00.000Z';
  const SOURCE_TO = '2026-04-27T06:00:00.000Z';

  let manifest: ExportManifest;

  beforeEach(() => {
    manifest = buildManifest(SAMPLE_ITEMS, SERIALISED, SOURCE_FROM, SOURCE_TO);
  });

  it('sets itemCount to the number of items', () => {
    expect(manifest.itemCount).toBe(SAMPLE_ITEMS.length);
  });

  it('sets sha256 to a 64-character lowercase hex string', () => {
    expect(manifest.sha256).toMatch(/^[0-9a-f]{64}$/);
  });

  it('sha256 is deterministic for the same input', () => {
    const m2 = buildManifest(SAMPLE_ITEMS, SERIALISED, SOURCE_FROM, SOURCE_TO);
    expect(manifest.sha256).toBe(m2.sha256);
  });

  it('sha256 changes when content changes', () => {
    const m2 = buildManifest(
      [...SAMPLE_ITEMS, { id: 'c', cityId: 'denver' }],
      JSON.stringify([...SAMPLE_ITEMS, { id: 'c', cityId: 'denver' }]),
      SOURCE_FROM,
      SOURCE_TO,
    );
    expect(manifest.sha256).not.toBe(m2.sha256);
  });

  it('exportedAt is an ISO 8601 UTC string', () => {
    expect(manifest.exportedAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/);
  });

  it('sourceFrom and sourceTo are preserved', () => {
    expect(manifest.sourceFrom).toBe(SOURCE_FROM);
    expect(manifest.sourceTo).toBe(SOURCE_TO);
  });

  it('sourceFrom is before sourceTo', () => {
    const from = new Date(manifest.sourceFrom).getTime();
    const to = new Date(manifest.sourceTo).getTime();
    expect(from).toBeLessThan(to);
  });

  it('itemCount is 0 for an empty batch', () => {
    const emptyManifest = buildManifest([], '[]', SOURCE_FROM, SOURCE_TO);
    expect(emptyManifest.itemCount).toBe(0);
  });
});

// ============================================================
// EXPORT PATH TESTS
// ============================================================

describe('manifest: buildExportPath', () => {
  it('produces correct path format: exports/yyyy/MM/dd/HH-mm/data.json', () => {
    const now = new Date('2026-04-27T14:30:00.000Z');
    const path = buildExportPath(now);
    expect(path).toBe('exports/2026/04/27/14-30/data.json');
  });

  it('zero-pads month, day, hour, minute', () => {
    const now = new Date('2026-01-05T03:05:00.000Z');
    const path = buildExportPath(now);
    expect(path).toBe('exports/2026/01/05/03-05/data.json');
  });

  it('always ends with data.json', () => {
    const path = buildExportPath(new Date());
    expect(path).toMatch(/data\.json$/);
  });

  it('starts with exports/', () => {
    const path = buildExportPath(new Date());
    expect(path).toMatch(/^exports\//);
  });
});
