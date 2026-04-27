### 2026-04-27T13:26:02.906-04:00: Observability docs corrected to match implementation (issue #1)
**By:** Ash (Technical Writer)
**What:** Fixed three inaccuracies in `docs/observability-and-logging.md`:
1. Enablement status updated from "not wired" to "fully wired via Bicep" — `APPLICATIONINSIGHTS_CONNECTION_STRING` flows `monitoring.bicep` → `main.bicep` → `container-host.bicep` into both containers.
2. All KQL `parse-json()` replaced with valid `parse_json()` syntax.
3. Event name `documents_queried` replaced with actual code events `cosmos_query_start` and `cosmos_query_complete`.

**Why:** Reviewer blockers on issue #1. Stale enablement status would mislead operators; invalid KQL would fail at query time.

**Team impact:** Documentation now matches the Bicep and TypeScript implementation. No further Dallas or Parker changes needed for issue #1 scope.

**Recommended follow-up (out of scope for issue #1):**
- The TypeScript logger uses the legacy `applicationinsights` Node.js SDK (`new TelemetryClient(connStr)`). Consider migrating to `@azure/monitor-opentelemetry` for OpenTelemetry-native tracing. This is a Parker task and should be a separate issue.
