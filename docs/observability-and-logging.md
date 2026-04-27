# Observability and Logging — Azure Monitor Integration

**Date:** 2026-04-27  
**Status:** Documentation-ready  
**Audience:** Operators, on-call engineers, compliance auditors  

---

## Overview

This demo integrates **Azure Monitor** and **Application Insights** to provide visibility into ingestion and export operations. All application logs flow to a **Log Analytics workspace** where they can be queried, visualized, and alerted on.

### Telemetry Architecture

```
┌─────────────────────────┐
│ weather-ingestor        │
│ (Container App)         │
│ JSON stdout logs        │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Container Apps          │
│ managed environment     │
│ (stdout capture)        │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Log Analytics Workspace │
│ (ContainerAppConsoleLogs_CL) │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Application Insights    │
│ (workspace-based)       │
│ AppTraces, AppMetrics   │
└─────────────────────────┘


┌─────────────────────────┐
│ backup-exporter         │
│ (Container App Job)     │
│ JSON stdout logs        │
└────────────┬────────────┘
             │
             ▼
     [Same path as above]
```

### What Gets Logged

Application-level telemetry (best-effort):

| Event | Source | Fields | Purpose |
|-------|--------|--------|---------|
| `ingestor_started` | weather-ingestor entry | level, event, intervalMs | Lifecycle marker |
| `document_written` | writeObservation() | level, event, id, cityId, observedAt, statusCode, requestChargeRU | Track successful writes; RU consumption |
| `write_failed` | writeObservation() error | level, event, cityId, error | Capture transient failures |
| `shutdown_requested` | SIGTERM/SIGINT handler | level, event, signal | Graceful termination |
| `startup_failed` | main() error handler | level, event, fatal, error | Catastrophic failures |
| `exporter_started` | backup-exporter entry | level, event, windowHours, mode, loopIntervalMs | Lifecycle marker |
| `export_started` | runExport() | level, event, windowStart, windowEnd, targetPrefix | Export window context |
| `cosmos_query_start` | readDocumentsInWindow() | level, event, component, windowStart, windowEnd | Query initiation marker |
| `cosmos_query_complete` | readDocumentsInWindow() | level, event, component, itemCount, windowStart, windowEnd | Query success + cardinality |
| `export_complete` | writeExportBundle() | level, event, itemCount, sha256, dataUrl, manifestUrl, retention URLs, window times | Success confirmation with manifest |
| `export_failed` | runExport() error handler | level, event, error | Job failure reason |
| `exporter_stopped` | main() after loop | level, event | Lifecycle marker |

**Platform-level telemetry (best-effort):**
- Container App instance metrics (CPU, memory, restart count)
- Container App request latency (if HTTP ingress enabled)
- Azure Cosmos DB request metrics (separate from Container App logs)
- Storage account access logs (if diagnostic settings configured)

### Important Caveats

1. **Application logs are best-effort**: If the container crashes before stdout is flushed, logs may be lost.
2. **Connection string wired via Bicep**: The `APPLICATIONINSIGHTS_CONNECTION_STRING` environment variable is injected into both Container Apps by `infra/modules/container-host.bicep`. After deploying (or redeploying) the Bicep environment, the env var will be present in live containers. See **Enablement** section for verification commands.
3. **Log Analytics ingestion delay**: Console logs typically appear in Log Analytics within 30–60 seconds; real-time alerting depends on alert rules configured separately.
4. **Sampling**: If App Insights sampling is enabled (default: off for demo), some events may not appear in queries.
5. **Azure control-plane actions** (e.g., "deployment started", "RBAC role assigned") appear in **Azure Activity Log**, not in Application Insights. See **Querying Activity Logs** section.

---

## Enablement — Connection String Wiring

**Status:** ✅ Fully wired in Bicep. Deploy (or redeploy) the environment to activate.

### Current State (2026-04-27)

- ✅ **Log Analytics workspace** provisioned by `infra/modules/monitoring.bicep`
- ✅ **Application Insights** created with workspace-based configuration
- ✅ **Container Apps managed environment** configured to send console logs to Log Analytics
- ✅ **`APPLICATIONINSIGHTS_CONNECTION_STRING`** injected into both containers by `infra/modules/container-host.bicep` (param wired from `monitoring.bicep` → `main.bicep` → `container-host.bicep`)

### How It Works

1. `infra/modules/monitoring.bicep` outputs `appInsightsConnectionString` from the Application Insights resource.
2. `infra/main.bicep` passes it to the `container-host` module.
3. `infra/modules/container-host.bicep` sets `APPLICATIONINSIGHTS_CONNECTION_STRING` as an env var on both the **ingestor Container App** and the **exporter Container App Job**.
4. Both TypeScript workloads use a shared `logger.ts` that lazily initializes the Application Insights SDK when the connection string is present. No separate SDK setup step is required.

### Operator Action Required

After initial deployment or any Bicep redeploy, verify the env var is present in the live containers:

**Bash:**

```bash
PREFIX=cosmos-backup
ENV=dev

# Ingestor
az containerapp show \
  --name "${PREFIX}-ingestor-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --query "properties.template.containers[0].env[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].value" \
  -o tsv

# Exporter
az containerapp job show \
  --name "${PREFIX}-exporter-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --query "properties.template.containers[0].env[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].value" \
  -o tsv
```

**PowerShell:**

```powershell
$prefix = "cosmos-backup"
$env = "dev"

# Ingestor
az containerapp show `
  --name "$prefix-ingestor-$env" `
  --resource-group "$prefix-demo-$env-rg" `
  --query "properties.template.containers[0].env[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].value" `
  -o tsv

# Exporter
az containerapp job show `
  --name "$prefix-exporter-$env" `
  --resource-group "$prefix-demo-$env-rg" `
  --query "properties.template.containers[0].env[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].value" `
  -o tsv
```

If the result is empty, the environment has not been deployed (or redeployed) since the Bicep wiring was added. Run `az deployment sub create` with the Bicep orchestrator and wait 2–3 minutes for the new revision to activate.

> **Note:** Console logs flow to Log Analytics regardless of the connection string. The connection string adds Application Insights custom events, exceptions, and metrics on top of console-log capture.

---

## Querying Logs and Metrics

### Via Azure Portal

1. Navigate to **Log Analytics workspace** → `cosmos-backup-law-{env}`
2. Click **Logs**
3. Use KQL queries below

### Via Azure CLI

```bash
PREFIX=cosmos-backup
ENV=dev
LAW=$(az monitor log-analytics workspace list \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --query "[0].name" -o tsv)

az monitor log-analytics query \
  --workspace "$LAW" \
  --analytics-query "ContainerAppConsoleLogs_CL | limit 10"
```

### Sample KQL Queries

#### All Events (Last 1 Hour)

```kusto
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(1h)
| project TimeGenerated, ContainerAppName_s, Log_s
| sort by TimeGenerated desc
```

#### Ingestion Events Only

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s contains "ingestor"
| where TimeGenerated > ago(1h)
| parse_json(Log_s) as event
| where event.event in ("document_written", "write_failed", "ingestor_started")
| project TimeGenerated, Event=event.event, CityId=event.cityId, Error=event.error
| sort by TimeGenerated desc
```

#### Successful Writes with RU Consumption

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s contains "ingestor"
| where TimeGenerated > ago(6h)
| parse_json(Log_s) as event
| where event.event == "document_written"
| project TimeGenerated, Id=event.id, StatusCode=event.statusCode, RU=event.requestChargeRU
| summarize TotalRU=sum(todouble(RU)), Count=count() by bin(TimeGenerated, 5m)
| sort by TimeGenerated desc
```

#### Write Failures (Last 24 Hours)

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s contains "ingestor"
| where TimeGenerated > ago(24h)
| parse_json(Log_s) as event
| where event.event == "write_failed"
| project TimeGenerated, CityId=event.cityId, Error=event.error
| summarize Failures=count() by Error
| sort by Failures desc
```

#### Export Events (Last 7 Days)

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s contains "exporter"
| where TimeGenerated > ago(7d)
| parse_json(Log_s) as event
| where event.event in ("export_started", "export_complete", "export_failed")
| project TimeGenerated, Event=event.event, ItemCount=event.itemCount, Error=event.error, Sha256=event.sha256
| sort by TimeGenerated desc
```

#### Export Success Rate (Last 7 Days)

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s contains "exporter"
| where TimeGenerated > ago(7d)
| parse_json(Log_s) as event
| where event.event in ("export_complete", "export_failed")
| summarize 
    Successes=countif(event.event == "export_complete"),
    Failures=countif(event.event == "export_failed")
| project SuccessRate=round(100.0 * Successes / (Successes + Failures), 2)
```

#### Hourly Event Summary

```kusto
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(24h)
| parse_json(Log_s) as event
| summarize 
    Ingestor_Writes=countif(event.event == "document_written"),
    Ingestor_Errors=countif(event.event == "write_failed"),
    Exporter_Starts=countif(event.event == "export_started"),
    Exporter_Completes=countif(event.event == "export_complete")
    by bin(TimeGenerated, 1h), ContainerAppName_s
| sort by TimeGenerated desc
```

#### Correlation ID Tracing (When Enabled)

Once `APPLICATIONINSIGHTS_CONNECTION_STRING` is deployed to containers, custom events can include correlation IDs:

```kusto
AppEvents
| where Name == "export_complete" 
| where operation_Id == "3fa85f64-5717-4562-b3fc-2c963f66afa6"  // Replace with real ID
| project TimeGenerated, Name, CustomDimensions
```

### Via Kusto Explorer (Advanced)

Download [Kusto.Explorer](https://kusto.azurewebsites.net/) and connect to your Log Analytics workspace for interactive, low-latency queries.

---

## Troubleshooting Missing Telemetry

### Symptoms: No Logs Appearing

**Check 1: Container App is running**

```bash
az containerapp show \
  --name "${PREFIX}-ingestor-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --query "properties.runningStatus"
```

If `Provisioning` or `Stopped`, check deployment logs:

```bash
az containerapp revision list \
  --name "${PREFIX}-ingestor-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --query "[0].properties.provisioningState"
```

**Check 2: Container App has container image**

```bash
az containerapp show \
  --name "${PREFIX}-ingestor-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --query "properties.template.containers[0].image"
```

If it shows `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`, the actual weather-ingestor image has not been pushed. See [Deployment Guide](deployment-guide.md) **Pushing Container Images to ACR**.

**Check 3: Log Analytics workspace is receiving any logs**

```bash
az monitor log-analytics query \
  --workspace "$LAW" \
  --analytics-query "ContainerAppConsoleLogs_CL | where TimeGenerated > ago(5m)"
```

If empty, the managed environment logs configuration may not be active. Wait 2–3 minutes after deployment; Container Apps managed environment startup can be slow.

**Check 4: JSON parsing in Container App logs**

If logs appear but don't parse as JSON (parse_json() fails in KQL), the container may be writing mixed output. Check for non-JSON debug prints:

```bash
az containerapp logs show \
  --name "${PREFIX}-ingestor-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --tail 20 --format json
```

All output should be valid JSON on each line. Remove any `console.log()` calls that don't output JSON.

### Symptoms: Logs Appear but APPLICATIONINSIGHTS_CONNECTION_STRING Not Found

**Status:** The env var is wired in Bicep. If missing at runtime, the environment has not been deployed (or redeployed) since the wiring was added.

**Workaround:** Query `ContainerAppConsoleLogs_CL` directly (sufficient for this demo).

**To verify it's actually set:**

```bash
az containerapp show \
  --name "${PREFIX}-ingestor-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --query "properties.template.containers[0].env[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING']"
```

If the result is empty, the env var was not injected. Redeploy the Bicep environment and wait 2–3 minutes for the new revision to activate.

### Symptoms: 429 Throttling / Ingestion Lag

**In Application Insights:**

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s contains "ingestor"
| parse_json(Log_s) as event
| where event.event == "write_failed" and event.error contains "429"
| summarize Count=count() by bin(TimeGenerated, 5m)
```

**Root cause:** Request Unit (RU) exhaustion on Cosmos DB.

**Action:**
1. Check current RU configuration in `infra/modules/cosmos.bicep`.
2. Increase `cosmosMaxThroughput` parameter in `infra/main.bicep` and redeploy.
3. Or reduce `INGEST_INTERVAL_MS` in container env vars.

### Symptoms: Export Job Not Appearing in Logs

**Check container job execution status:**

```bash
az containerapp job execution list \
  --name "${PREFIX}-exporter-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --output table | head -20
```

If status is `Succeeded` but no logs appear, the job ran but output was lost before Log Analytics ingested it. Re-run the job manually:

```bash
az containerapp job start \
  --name "${PREFIX}-exporter-${ENV}" \
  --resource-group "${PREFIX}-demo-${ENV}-rg"
```

Then query immediately:

```bash
az monitor log-analytics query \
  --workspace "$LAW" \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s contains 'exporter' | sort by TimeGenerated desc | limit 10"
```

---

## Dashboards and Alerts

### Creating a Custom Dashboard

1. **Portal → Monitor → Dashboards → Create dashboard**
2. **Add Tiles:**
   - **Ingestion Rate:** KQL query for `document_written` count per 5 minutes
   - **Write Failures:** KQL query for `write_failed` count per hour
   - **Export Success:** KQL query for export completion rate (7 days)
   - **RU Consumption:** Cosmos DB Metrics → Total Request Units

3. **Save** as `cosmos-backup-demo-{env}`

### Alert Rule: Ingestion Stopped

Set up an alert if no `document_written` event appears for 5 minutes:

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s contains "ingestor"
| where TimeGenerated > ago(5m)
| where parse_json(Log_s).event == "document_written"
| summarize Writes=count()
| where Writes == 0
```

**Action group:** Email ops team, trigger runbook to restart container.

### Alert Rule: Export Failure

Set up an alert if an export job ends with `export_failed`:

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s contains "exporter"
| where TimeGenerated > ago(30m)
| where parse_json(Log_s).event == "export_failed"
| summarize Failures=count()
| where Failures > 0
```

**Action group:** Create incident, notify on-call.

---

## Platform Logging (Azure Activity Log)

Container App deployments, RBAC changes, and resource lifecycle events are logged in **Azure Activity Log**, not in Application Insights.

### Query Activity Log for Recent Changes

```bash
az monitor activity-log list \
  --resource-group "${PREFIX}-demo-${ENV}-rg" \
  --start-time "$(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%SZ)" \
  --output table | head -20
```

### Common Activity Log Events

| Event | Operation Name | What It Means |
|-------|---|---|
| Container App revision update | `Microsoft.App/containerApps/write` | New container image deployed |
| Container App Job execution | `Microsoft.App/jobs/start` | Scheduled export job started |
| Role assignment | `Microsoft.Authorization/roleAssignments/write` | Managed identity granted permission (RBAC) |
| Diagnostic settings changed | `Microsoft.Insights/diagnosticSettings/write` | Log routing configured |

### Querying via Log Analytics (Optional)

If you have Azure Activity Log forwarded to Log Analytics, query it:

```kusto
AzureActivity
| where TimeGenerated > ago(24h)
| where ResourceGroup == "{PREFIX}-demo-{ENV}-rg"
| where OperationName in (
    "Microsoft.App/containerApps/write",
    "Microsoft.App/jobs/start",
    "Microsoft.Authorization/roleAssignments/write"
)
| project TimeGenerated, OperationName, Caller, Status
| sort by TimeGenerated desc
```

---

## Data Retention and Compliance

- **Log Analytics:** 30-day retention (set in `infra/modules/monitoring.bicep` as `retentionInDays`)
- **Application Insights:** Inherits workspace retention (30 days)
- **Azure Activity Log:** 90-day retention (default; longer retention available through Azure Archive Log)
- **Export Blobs (WORM):** Configurable 1–7 years per `longTermRetentionDays` param

### For Longer-Term Compliance

To retain logs beyond 30 days:
1. Export Log Analytics data to **Archive Storage** (managed by lifecycle policies)
2. Or increase `retentionInDays` in `infra/modules/monitoring.bicep` and redeploy

For examples, see [Backup & Retention](backup-and-retention.md).

---

## Glossary

- **Container App (continuous)**: Long-running ingestor replica
- **Container App Job (scheduled)**: Cron-triggered exporter; runs once per schedule window
- **Log Analytics workspace**: Central data sink for logs from multiple sources
- **Application Insights**: Analytics engine; workspace-based = data routed through Log Analytics
- **ContainerAppConsoleLogs_CL**: KQL table name for Container App stdout/stderr logs (suffix `_CL` = custom log)
- **KQL**: Kusto Query Language; used in Log Analytics and Application Insights
- **RU**: Request Unit; Cosmos DB throughput metric
- **WORM**: Write-Once-Read-Many; immutable blob storage with minimum retention lock
- **Correlation ID**: Trace identifier linking related events across systems (enabled via SDK)

---

## Related Documentation

- [Deployment Guide](deployment-guide.md) — Infrastructure setup
- [Operations Runbook](operations-runbook.md) — Day-to-day tasks and alerts
- [Backup & Retention](backup-and-retention.md) — Storage and export procedures
- [Assumptions](assumptions.md) — Compliance and retention assumptions
