# infra/ — Azure Infrastructure

Bicep templates for the Cosmos DB Enterprise Backup & Recovery demo.

## Module Map

| Module | Scope | Purpose |
|--------|-------|---------|
| `modules/resource-groups.bicep` | Subscription | Creates primary demo RG + retention RG |
| `modules/identity.bicep` | Primary RG | User-assigned managed identities (ingest + export) |
| `modules/monitoring.bicep` | Primary RG | Log Analytics workspace + Application Insights |
| `modules/cosmos.bicep` | Primary RG | Cosmos DB account, SQL database, container, diagnostics |
| `modules/storage-exports.bicep` | Primary RG | Working export storage with lifecycle management |
| `modules/storage-retention.bicep` | Retention RG | WORM immutable archive storage |
| `modules/container-host.bicep` | Primary RG | ACR + Container Apps environment + ingestor app + exporter job |
| `modules/keyvault.bicep` | Primary RG | Key Vault (pre-authorized; empty in v1) |
| `modules/rbac.bicep` | Primary RG | Cosmos data-plane RBAC + export storage RBAC + AcrPull |
| `modules/alerts.bicep` | Primary RG | Cosmos 429 throttle + ingestion gap + export failure alerts |

## Resource Groups

| Group | Pattern | Teardown? |
|-------|---------|-----------|
| Primary | `{workloadName}-demo-{env}-rg` | ✅ Safe to delete |
| Retention | `{workloadName}-retention-{env}-rg` | ❌ **Excluded from teardown** — holds WORM archive data |

## Backup Tiers

| Tier | Mechanism | Retention | Notes |
|------|-----------|-----------|-------|
| Short-term (PITR) | Cosmos DB native continuous backup | 7 or 30 days | Restore creates a NEW account — no in-place restore |
| Long-term (Archive) | Custom export → immutable Blob Storage | Up to 2555 days (≈7 years) | **Not native Cosmos DB** — application-managed |

## Quick Deploy

```bash
# Install Bicep CLI
az bicep install

# Deploy dev environment (creates resource groups automatically)
az deployment sub create \
  --location eastus2 \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam

# Or use the helper script (includes what-if preview + output display):
./scripts/deploy/deploy.sh dev
./scripts/deploy/deploy.sh test
./scripts/deploy/deploy.sh prod
```

## Idempotency

All modules use deterministic resource names and `guid()` for role assignment names.
Re-running a deployment updates changed properties and leaves unchanged resources alone.

## Outputs

All outputs are consumed by Parker's app config and Lambert's runbooks.

| Output | Used by |
|--------|---------|
| `cosmosAccountEndpoint` | Parker (`COSMOS_ENDPOINT`) |
| `cosmosDatabaseName` | Parker (`COSMOS_DATABASE_NAME`) |
| `cosmosContainerName` | Parker (`COSMOS_CONTAINER_NAME`) |
| `ingestionIdentityClientId` | Parker (`AZURE_CLIENT_ID` in ingestor) |
| `exportIdentityClientId` | Parker (`AZURE_CLIENT_ID` in exporter) |
| `exportStorageAccountName` | Lambert runbooks |
| `retentionStorageAccountName` | Lambert runbooks |
| `containerHostName` | Lambert runbooks |
| `acrLoginServer` | Image build commands |
| `primaryResourceGroupName` | Bishop validation scripts |
| `retentionResourceGroupName` | Bishop validation scripts |
| `keyVaultUri` | Future secrets integration |
| `logAnalyticsWorkspaceId` | Dashboard queries |
| `appInsightsConnectionString` | Application telemetry |

## Parameters Reference

| Parameter | Default | Dev | Test | Prod | Notes |
|-----------|---------|-----|------|------|-------|
| `workloadName` | `cosmos-backup` | same | same | same | Prefix for all resource names |
| `environmentName` | `dev` | `dev` | `test` | `prod` | Controls naming and SKU selection |
| `location` | `eastus2` | same | same | same | |
| `secondaryLocation` | `""` | `""` | `""` | `westus2` | Cosmos DB read replica |
| `cosmosPitrTier` | `Continuous30Days` | `Continuous7Days` | `Continuous30Days` | `Continuous30Days` | Native backup window |
| `cosmosMaxThroughput` | `1000` | `1000` | `4000` | `10000` | Autoscale RU/s max |
| `longTermRetentionDays` | `2555` | same | same | same | ≈7 years |
| `immutabilityRetentionDays` | `1` | `1` | `1` | `7` | WORM lock window |
| `coolAfterDays` | `7` | same | same | same | Lifecycle transition |
| `archiveAfterDays` | `30` | same | same | same | Lifecycle transition |
| `exportCronSchedule` | `0 */6 * * *` | same | same | same | Every 6 hours |
| `ingestIntervalMs` | `20000` | same | same | same | 20 seconds |

## Naming Conventions

`{workloadName}-{service}-{env}` for most resources.
Storage accounts use `{workloadNameNoHyphens}exp{env}` / `{workloadNameNoHyphens}ret{env}` (max 24 chars, no hyphens).

**Example (dev):**
- RG: `cosmos-backup-demo-dev-rg`
- Cosmos: `cosmos-backup-cosmos-dev`
- Export storage: `cosmosbackupexpdev`
- Retention storage: `cosmosbackupretdev`
- ACR: `cosmosbackupacrdev`
- Key Vault: `cosmos-backup-kv-dev`

## Security Baseline

- **No account keys.** `disableLocalAuth: true` on Cosmos DB; `allowSharedKeyAccess: false` on all storage accounts.
- **Managed identity everywhere.** Container Apps use user-assigned identities; `DefaultAzureCredential` handles auth.
- **Least-privilege RBAC.** Ingestor: Cosmos Built-in Data Contributor only. Exporter: Cosmos + export storage + retention storage.
- **Private endpoints:** Documented enhancement, not in v1. Public endpoints with default ACL are acceptable for demo.

## Building & Pushing Container Images

After deploy, images must be pushed to ACR before the Container Apps will function:

```bash
ACR_SERVER=$(az deployment sub show --name <deployment-name> --query properties.outputs.acrLoginServer.value -o tsv)
ACR_NAME="${ACR_SERVER%%.*}"

az acr build --registry "${ACR_NAME}" --image weather-ingestor:latest apps/weather-ingestor
az acr build --registry "${ACR_NAME}" --image backup-exporter:latest  apps/backup-exporter
```

Then redeploy with updated `ingestorImageRef` / `exporterImageRef` parameters pointing to the ACR images.

## Validation Notes (G1 Gate)

Bicep validation requires Azure CLI and an active subscription:

```bash
# Syntax/compilation check (no Azure required)
az bicep build --file infra/main.bicep

# What-if (dry run — requires Azure subscription)
az deployment sub what-if \
  --location eastus2 \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam
```

If `az bicep` is not available, the deploy script auto-installs it (`az bicep install`).
