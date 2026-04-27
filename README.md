# Azure Cosmos DB Backup & Recovery Demo

**Version:** 1.0 (Demo)  
**Date:** 2026-04-27  
**Purpose:** Enterprise-ready demonstration of Azure Cosmos DB point-in-time restore (PITR) and custom long-term archival backup strategies.

---

## Quick Links

- **Getting Started:** See [Deployment Guide](docs/deployment-guide.md)
- **Architecture Overview:** See [Architecture](docs/architecture.md)
- **Operations & Runbook:** See [Operations Runbook](docs/operations-runbook.md)
- **Demo Script (15–20 min):** See [Demo Walkthrough](docs/demo-walkthrough.md)
- **Backup & Retention Details:** See [Backup & Retention](docs/backup-and-retention.md)
- **Restore Procedures:** See [Restore & Validation](docs/restore-and-validation.md)
- **Compliance & Cost:** See [Compliance & Well-Architected](docs/compliance-and-well-architected.md)
- **Backup & Restore Runbook:** See [Backup & Restore Runbook](docs/backup-restore-runbook.md)
- **Cleanup:** See [Cleanup Guide](docs/cleanup.md)
- **Assumptions & Scope:** See [Assumptions](docs/assumptions.md)
- **Teardown:** See [Teardown](docs/teardown.md)

---

## What This Demo Does

This demo deploys a **two-tier backup strategy** for Azure Cosmos DB:

1. **Native PITR (Hot Tier, 7–30 days)**  
   - Cosmos DB continuous backup for point-in-time recovery
   - Restore to a new Cosmos account on demand
   - Managed by Azure, included in Cosmos pricing

2. **Custom Archive (Cold Tier, up to 7 years)**  
   - Scheduled exports of Cosmos DB documents to immutable Blob Storage
   - Versioned, WORM-protected retention with configurable lifecycle
   - Manual export job every 6 hours

The demo also runs **continuous synthetic data ingestion** (one weather document every 20 seconds) to provide a realistic dataset for testing restore workflows.

---

## Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────┐
│  Primary Demo Resource Group (deleted on teardown)          │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐         ┌──────────────┐                 │
│  │ Cosmos DB    │ ◄───────│ Ingestion    │                 │
│  │ (native PITR)│         │ Container    │                 │
│  │ Continuous30 │         │ (20s cadence)│                 │
│  │ Days         │         └──────────────┘                 │
│  └──────────────┘                │                          │
│        │                         │                          │
│        │ PITR restore            │ Scheduled export         │
│        │ creates new account     │ (6 hourly)              │
│        │                         └──────────►               │
│        │                                      │             │
│        │                                      ▼             │
│        │                          ┌────────────────────┐    │
│        │                          │ Export Storage     │    │
│        │                          │ (Cool/Archive      │    │
│        │                          │  lifecycle)        │    │
│        │                          └────────────────────┘    │
│        │                                      │              │
│        │  Copy to retention RG               │              │
│        │                                      │              │
└────────┼──────────────────────────────────────┼──────────────┘
         │                                      │
         └──────────────┬───────────────────────┘
                        │
         ┌──────────────▼──────────────┐
         │ Retention Resource Group     │
         │ (NOT deleted on teardown)    │
         │                              │
         │ ┌──────────────────────┐    │
         │ │ Immutable Storage     │    │
         │ │ (WORM: 1-day min,    │    │
         │ │  versioned, 7yr cap) │    │
         │ └──────────────────────┘    │
         └──────────────────────────────┘
```

---

## Prerequisites

- **Azure subscription** with Contributor access
- **Azure CLI** (v2.50+)
- **Bicep CLI** (v0.25+)
- **Node.js** (v18+) — for local testing (optional)
- **Docker** (optional, for building apps locally)

---

## Quick Start (5 minutes)

### 1. Set environment variables

```bash
export AZURE_SUBSCRIPTION_ID="<your-subscription-id>"
export PREFIX="cosmos-backup"        # Resource naming prefix
export ENV="dev"                      # dev, test, prod
export LOCATION="eastus2"             # Azure region
```

### 2. Login to Azure

```bash
az login
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
```

### 3. Deploy infrastructure and apps

```bash
cd infra
az deployment sub create \
  --template-file main.bicep \
  --parameters \
    prefix="$PREFIX" \
    environmentName="$ENV" \
    location="$LOCATION" \
  --location "$LOCATION"
```

### 4. Verify deployment

```bash
bash scripts/validate-deployment.sh
```

### 5. Watch ingestion and backup

```bash
# Monitor ingestion (documents written per minute)
bash scripts/validate-ingestion.sh

# Monitor backup policy and storage
bash scripts/validate-backup.sh
```

### 6. (Optional) Trigger a restore

```bash
# Restore to a new account
bash scripts/validate-restore.sh

# Verify restored data
az cosmosdb list --resource-group "${PREFIX}-demo-${ENV}-rg" -o table
```

### 7. Cleanup

```bash
# Delete primary demo RG (retention RG preserved)
bash scripts/teardown.sh

# Wait 1 day, then manually delete retention storage if needed
# (see Teardown docs for safe procedures)
```

---

## Key Parameters

All deployments are controlled by a single **Bicep parameter file** (`infra/main.bicepparam` or environment-specific variants).

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `prefix` | `cosmos-backup` | Resource naming prefix |
| `environmentName` | `dev` | Environment (dev/test/prod); controls SKU and retention |
| `location` | `eastus2` | Azure region for all resources |
| `cosmosContinuousBackupTier` | `Continuous30Days` | PITR retention window |
| `longTermRetentionDays` | `2555` | Custom archive retention (≈7 years) |
| `exportIntervalMinutes` | `360` | Backup export frequency (6 hours) |
| `ingestIntervalMs` | `20000` | Ingestion cadence (20 seconds) |

---

## Key Features

✅ **Enterprise-Ready**  
- Two-tier backup (native PITR + custom archive)  
- Immutable Blob Storage with WORM versioning  
- Managed identity and RBAC (no account keys)  
- Full audit trail via Azure Monitor  
- Cost-optimized for dev (~$10–35/month)  

✅ **Demo-Repeatable**  
- Continuous synthetic data ingestion  
- Scripted validation for each layer  
- Safe teardown preserves retention storage  

✅ **Compliance-Aware**  
- RPO/RTO targets documented  
- Immutability enforced for long-term storage  
- Audit logging enabled; compliance patterns shown but not claimed  

---

## Cost Estimate (Development)

| Resource | Monthly (Dev) |
|----------|---------------|
| Cosmos DB (serverless) | $0–15 |
| Container Apps (consumption) | $0–5 |
| Storage (Cool + Archive) | <$1 |
| Log Analytics | $0–5 |
| Key Vault | <$1 |
| **Total** | **~$10–25** |

Costs vary by usage. See [Compliance & Well-Architected](docs/compliance-and-well-architected.md) for cost optimization strategies.

---

## File Structure

```
.
├── README.md                               ← You are here
├── docs/
│   ├── architecture.md                     # System design & data flow
│   ├── deployment-guide.md                 # Step-by-step setup
│   ├── backup-restore-runbook.md           # Operational procedures
│   ├── demo-walkthrough.md                 # Scripted 15–20 min demo
│   ├── compliance-and-well-architected.md  # RPO/RTO, compliance, cost
│   └── teardown.md                         # Safe deletion procedures
├── infra/
│   ├── main.bicep                          # Orchestrator
│   ├── main.bicepparam                     # Default parameters
│   ├── parameters/
│   │   ├── dev.bicepparam
│   │   ├── test.bicepparam
│   │   └── prod.bicepparam
│   └── modules/
│       ├── cosmos.bicep
│       ├── storage-retention.bicep
│       ├── storage-exports.bicep
│       ├── container-host.bicep
│       ├── monitoring.bicep
│       ├── identity.bicep
│       ├── rbac.bicep
│       ├── keyvault.bicep
│       └── resource-groups.bicep
├── apps/
│   ├── weather-ingestor/
│   │   ├── src/
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   └── .env.example
│   └── backup-exporter/
│       ├── src/
│       ├── Dockerfile
│       ├── package.json
│       └── .env.example
└── scripts/
    ├── validate-local.sh
    ├── validate-deployment.sh
    ├── validate-ingestion.sh
    ├── validate-backup.sh
    ├── validate-restore.sh
    ├── validate-cleanup.sh
    └── teardown.sh
```

---

## Documentation Roadmap

| Document | Audience | When to Read |
|----------|----------|-------------|
| **[Architecture](docs/architecture.md)** | Technical leads, architects | Before deployment; understand data flow and tier separation |
| **[Deployment Guide](docs/deployment-guide.md)** | DevOps, cloud engineers | First deployment; step-by-step setup with verification |
| **[Backup & Retention](docs/backup-and-retention.md)** | Operators, DBAs | Understand how each backup tier is configured |
| **[Restore & Validation](docs/restore-and-validation.md)** | Operators, DBAs | During restore events; PITR and archive restore procedures |
| **[Backup & Restore Runbook](docs/backup-restore-runbook.md)** | Operators, DBAs | Full operational procedures; restore, immutability constraints |
| **[Operations Runbook](docs/operations-runbook.md)** | Operators, on-call engineers | Day-to-day operations; alert responses, maintenance |
| **[Demo Walkthrough](docs/demo-walkthrough.md)** | Presenters, stakeholders | Before demo; scripted 15–20 min presentation with talking points |
| **[Compliance & Well-Architected](docs/compliance-and-well-architected.md)** | Architects, compliance officers | Planning phase; RPO/RTO, compliance caveats, cost optimization |
| **[Assumptions](docs/assumptions.md)** | Evaluators, architects | Before evaluating; scope boundaries and design decisions |
| **[Cleanup Guide](docs/cleanup.md)** | Operators | End of demo; safe deletion with retention preservation |
| **[Teardown](docs/teardown.md)** | Operators | Teardown script reference |

---

## Validation Checklist

After deployment, verify:

- [ ] Cosmos DB account created and accepting writes  
- [ ] Ingestion container running (one document per 20 seconds)  
- [ ] Continuous backup policy set to 30 days  
- [ ] Export storage account created with immutability versioning  
- [ ] First export completed and manifest present  
- [ ] Log Analytics receiving diagnostic data  
- [ ] Alert rules configured for throttling and ingestion gaps  
- [ ] Restore to separate account succeeds  
- [ ] Teardown script leaves retention RG intact  

See [Deployment Guide](docs/deployment-guide.md) for detailed checks.

---

## Security

- **Managed Identity** everywhere; no account keys exported  
- **RBAC assignments** scoped to data-plane roles (`Cosmos DB Built-in Data Contributor`, `Storage Blob Data Contributor`)  
- **Network security** baseline allows public endpoints with IP firewall; private endpoints documented as enhancement  
- **Key Vault** provisioned for future secret storage  
- **Audit logging** via Azure Monitor (all Cosmos, storage, and compute logs)  

See [Architecture](docs/architecture.md) for full security model.

---

## Support & Troubleshooting

- **Deployment fails:** See [Deployment Guide — Troubleshooting](docs/deployment-guide.md#troubleshooting)  
- **Ingestion not writing:** See [Backup & Restore Runbook — Ingestion Issues](docs/backup-restore-runbook.md#ingestion-issues)  
- **Restore fails:** See [Backup & Restore Runbook — Restore Failures](docs/backup-restore-runbook.md#restore-failures)  
- **Compliance questions:** See [Compliance & Well-Architected](docs/compliance-and-well-architected.md)  

---

## License & Attribution

This demo is provided as-is for educational and demonstration purposes.

---

## Next Steps

1. **Read** [Architecture](docs/architecture.md) to understand the design.  
2. **Deploy** using [Deployment Guide](docs/deployment-guide.md).  
3. **Verify** with [Validation Checklist](#validation-checklist).  
4. **Demo** using [Demo Walkthrough](docs/demo-walkthrough.md).  
5. **Operate** using [Backup & Restore Runbook](docs/backup-restore-runbook.md).  
6. **Clean up** using [Teardown](docs/teardown.md).

---

**Questions? Refer to the linked documentation or raise an issue.**
