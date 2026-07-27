# OTel AI Telemetry Pipeline – macOS → Azure

This directory contains everything needed to run an **OpenTelemetry Collector** on your macOS development machine that captures all AI agent prompts, sub-agent calls, and token utilization, and ships that data to **Azure Data Explorer (ADX)** and/or **Azure Managed Prometheus**.

---

## Directory Layout

```
observability/
├── otel-config.yaml                    # OTel Collector configuration (ADX + Prometheus)
├── launchd/
│   └── com.otelcol.agent.plist         # macOS launchd service policy (auto-start)
├── adx/
│   └── schema.kql                      # ADX table DDL + demo queries
├── grafana/
│   └── dashboard.json                  # Pre-built Grafana dashboard (token usage + latency)
├── scripts/
│   └── install-mac.sh                  # One-shot macOS installer
└── README.md                           # This file
```

---

## Quick Start (< 10 minutes)

### 1. Azure prerequisites

#### Azure Data Explorer (ADX)

1. Create an ADX cluster and a database (e.g. `telemetry`) in the [Azure portal](https://portal.azure.com).
2. In **Entra ID → App registrations**, create an app registration (e.g. `otelcol-adx`).
   - Note the **Client ID** and **Tenant ID**.
   - Under **Certificates & secrets**, create a client secret and note its value.
3. In your ADX database, grant the app the `ingestor` role:
   ```kusto
   .add database telemetry ingestors ('aadapp=<CLIENT_ID>;<TENANT_ID>') 'OTel Collector'
   ```
4. Create the OTel tables by running `adx/schema.kql` in the [ADX Web UI](https://dataexplorer.azure.com) or via Azure CLI:
   ```bash
   az kusto script execute \
     --cluster-name <cluster-name> \
     --database-name telemetry \
     --resource-group <rg> \
     --script-path observability/adx/schema.kql
   ```

#### Azure Managed Prometheus

1. In the Azure portal, create an **Azure Monitor Workspace**.
2. In **Entra ID → App registrations**, create an app registration (e.g. `otelcol-amp`).
   - Note the **Client ID**, **Tenant ID**, and create a **Client Secret**.
3. On the Monitor Workspace, assign the app the **Monitoring Metrics Publisher** role:
   ```bash
   az role assignment create \
     --assignee <AMP_CLIENT_ID> \
     --role "Monitoring Metrics Publisher" \
     --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/microsoft.monitor/accounts/<workspace>
   ```
4. Note the **remote write endpoint** from the workspace overview (Metrics ingestion endpoint), e.g.:
   ```
   https://<workspace>.prometheus.monitor.azure.com/api/v1/write
   ```

---

### 2. One-shot macOS install

Export the required environment variables, then run the installer:

```bash
# Azure Data Explorer
export ADX_CLUSTER_URI="https://mycluster.eastus2.kusto.windows.net"
export ADX_DATABASE="telemetry"
export ADX_CLIENT_ID="<adx-app-registration-client-id>"
export ADX_CLIENT_SECRET="<adx-app-registration-secret>"
export ADX_TENANT_ID="<your-entra-tenant-id>"

# Azure Managed Prometheus
export AMP_REMOTE_WRITE_URL="https://<workspace>.prometheus.monitor.azure.com/api/v1/write"
export AMP_CLIENT_ID="<amp-app-registration-client-id>"
export AMP_CLIENT_SECRET="<amp-app-registration-secret>"
export AMP_TENANT_ID="<your-entra-tenant-id>"

# Agent identity
export OTEL_SERVICE_NAME="ai-demo-agent"
export OTEL_ENV="dev"

# Run the installer from the repo root
bash observability/scripts/install-mac.sh
```

The installer will:
- Install `otelcol-contrib` via Homebrew
- Write the config to `~/.config/otelcol/otel-config.yaml`
- Install and load the launchd plist so the collector starts at login
- Verify the health-check endpoint (`http://localhost:13133`) is responding

---

### 3. Instrument your agent code

Point your agent application at the local collector using the standard OTel environment variables:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318"   # HTTP
# or
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4317"   # gRPC
export OTEL_SERVICE_NAME="ai-demo-agent"
```

#### Required span attributes (gen_ai semantic conventions)

Every LLM call should emit a span with these attributes:

| Attribute | Type | Description |
|-----------|------|-------------|
| `gen_ai.system` | string | e.g. `openai`, `azure_openai` |
| `gen_ai.model` | string | e.g. `gpt-4o`, `gpt-4o-mini` |
| `gen_ai.operation.name` | string | e.g. `chat`, `embeddings` |
| `gen_ai.usage.prompt_tokens` | int | Input token count |
| `gen_ai.usage.completion_tokens` | int | Output token count |
| `gen_ai.usage.total_tokens` | int | Total token count |
| `gen_ai.prompt` | string | Full prompt text (omit if PII-sensitive) |
| `gen_ai.completion` | string | Full completion text (omit if PII-sensitive) |
| `agent.name` | string | Identifies which agent made the call (e.g. `orchestrator`, `planner`, `executor`) |
| `agent.parent` | string | Parent agent's span ID, enabling call-tree reconstruction |

#### Python example (opentelemetry-sdk)

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

provider = TracerProvider()
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(provider)

tracer = trace.get_tracer("ai-demo-agent")

def call_llm(prompt: str, agent_name: str, parent_span=None) -> str:
    ctx = trace.set_span_in_context(parent_span) if parent_span else None
    with tracer.start_as_current_span("gen_ai.chat", context=ctx) as span:
        span.set_attribute("gen_ai.system", "azure_openai")
        span.set_attribute("gen_ai.model", "gpt-4o")
        span.set_attribute("gen_ai.operation.name", "chat")
        span.set_attribute("agent.name", agent_name)
        span.set_attribute("gen_ai.prompt", prompt)

        # --- make your actual LLM call here ---
        response = your_openai_client.chat(prompt)

        span.set_attribute("gen_ai.usage.prompt_tokens",     response.usage.prompt_tokens)
        span.set_attribute("gen_ai.usage.completion_tokens", response.usage.completion_tokens)
        span.set_attribute("gen_ai.usage.total_tokens",      response.usage.total_tokens)
        span.set_attribute("gen_ai.completion",              response.choices[0].message.content)
        return response.choices[0].message.content
```

#### Semantic Kernel (C#)

Semantic Kernel 1.x has built-in OTel support. Enable it via:

```csharp
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddSource("Microsoft.SemanticKernel*")
        .AddOtlpExporter(o => o.Endpoint = new Uri("http://localhost:4317")));
```

All kernel function calls, planner steps, and connector calls are automatically instrumented with `gen_ai.*` attributes.

#### LangChain (Python)

```python
from opentelemetry.instrumentation.langchain import LangchainInstrumentor
LangchainInstrumentor().instrument()
```

---

## Viewing the data

### Azure Data Explorer (ADX)

Open the [ADX Web UI](https://dataexplorer.azure.com) and run these sample queries:

```kusto
// Full agent call tree for a specific trace
OTelTraces
| where TraceId == "<your-trace-id>"
| project SpanId, ParentId, SpanName, AgentName, GenAiModel,
          GenAiPromptTokens, GenAiCompletionTokens, DurationMs
| order by StartTime asc

// Token utilization by agent – last hour
OTelTraces
| where StartTime > ago(1h)
| summarize
    PromptTokens     = sum(GenAiPromptTokens),
    CompletionTokens = sum(GenAiCompletionTokens),
    Calls            = count()
  by AgentName, GenAiModel
| order by CompletionTokens desc

// p95 latency by model – last hour
OTelTraces
| where StartTime > ago(1h) and isnotempty(GenAiModel)
| summarize avg(DurationMs), percentiles(DurationMs, 50, 95, 99) by GenAiModel
```

### Grafana (Azure Managed Prometheus)

1. In Grafana, add your Azure Monitor Workspace as a **Prometheus** data source.
   - URL: `https://<workspace>.prometheus.monitor.azure.com`
   - Authentication: Azure Active Directory (client credentials)
2. Import `observability/grafana/dashboard.json`:
   - Grafana → Dashboards → Import → Upload JSON file
3. Select your Prometheus data source when prompted.

The dashboard provides:
- **Prompt/completion token rate** over time, broken down by model and agent
- **Total token stat panels** for the selected time window
- **p50/p95/p99 LLM latency** by model
- **Agent call duration** p95 by agent name
- **Token usage table and bar chart** per agent

---

## Managing the collector

```bash
# Check collector status
launchctl list | grep otelcol

# View logs
tail -f ~/Library/Logs/otelcol/otelcol.log

# Restart
launchctl unload  ~/Library/LaunchAgents/com.otelcol.agent.plist
launchctl load    ~/Library/LaunchAgents/com.otelcol.agent.plist

# Test health check
curl http://localhost:13133/

# View internal collector metrics
curl http://localhost:8888/metrics
```

---

## Security notes

- The launchd plist and `otel-config.yaml` are written with `chmod 600` by the installer.
- For production use, store `ADX_CLIENT_SECRET` and `AMP_CLIENT_SECRET` in the macOS Keychain instead of the plist, and source them in a wrapper launch script:
  ```bash
  export ADX_CLIENT_SECRET=$(security find-generic-password -a otelcol -s ADX_CLIENT_SECRET -w)
  exec otelcol-contrib --config ~/.config/otelcol/otel-config.yaml
  ```
- To use a managed identity instead of a service principal (when running on an Azure VM), remove the `application_id`/`application_key` fields from the `azuredataexplorer` exporter and set `use_managed_identity: true`.

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Collector not starting | `tail -f ~/Library/Logs/otelcol/otelcol.log` |
| Health check not responding | Verify port 13133 is free: `lsof -i :13133` |
| No data in ADX | Check ingestion failures in the ADX portal → Diagnostics; verify the app has `ingestor` role |
| No data in Prometheus | Check the remote write endpoint URL and AMP app role assignment |
| `gen_ai.*` metrics missing | Ensure your agent code sets the span attributes listed above |
| Spans not appearing | Verify `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318` is set in your agent process |

---

## Environment variables reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OTEL_SERVICE_NAME` | No | `ai-demo-agent` | Service name tagged on all telemetry |
| `OTEL_ENV` | No | `dev` | `deployment.environment` resource attribute |
| `ADX_CLUSTER_URI` | Yes | – | ADX cluster URI |
| `ADX_DATABASE` | Yes | – | ADX database name |
| `ADX_CLIENT_ID` | Yes | – | Entra app registration client ID |
| `ADX_CLIENT_SECRET` | Yes | – | Entra app registration client secret |
| `ADX_TENANT_ID` | Yes | – | Entra tenant ID |
| `AMP_REMOTE_WRITE_URL` | Yes | – | Azure Monitor Workspace remote write URL |
| `AMP_CLIENT_ID` | Yes | – | Entra app registration client ID |
| `AMP_CLIENT_SECRET` | Yes | – | Entra app registration client secret |
| `AMP_TENANT_ID` | Yes | – | Entra tenant ID |
