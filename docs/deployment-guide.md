# Deployment Guide — Azure Cosmos DB Backup Demo

**Date:** 2026-04-27  
**Status:** Demo-ready  
**Audience:** DevOps engineers, cloud engineers

---

## Prerequisites

| Tool | Minimum Version | Install |
|------|----------------|---------|
| Azure CLI | 2.50+ | `brew install azure-cli` |
| Bicep CLI | 0.25+ | `az bicep install` |
| Node.js | 18+ | https://nodejs.org |
| Docker | 24+ | https://docker.com (optional for local build) |

An Azure subscription with **Contributor** access is required.

---

## Step 1 — Clone and Configure

```bash
git clone <repo-url>
cd newdemo

export AZURE_SUBSCRIPTION_ID="<your-subscription-id>"
export PREFIX="cosmos-backup"   # resource naming prefix
export ENV="dev"                 # dev | test | prod
export LOCATION="eastus2"
```

---

## Step 2 — Login to Azure

```bash
az login
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
```

---

## Step 3 — Run Local Validation (pre-deploy)

Before deploying, verify the repo is well-formed:

```bash
bash scripts/validate-local.sh
```

Expected: all checks **PASS** (Bicep build, file presence, .env hygiene, .gitignore).

---

## Step 4 — Deploy Infrastructure

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

Deployment creates two resource groups:

| Resource Group | Contents | Teardown |
|----------------|----------|---------|
| `{prefix}-demo-{env}-rg` | Cosmos DB, Container Apps, monitoring, export storage | Deleted by `teardown.sh` |
| `{prefix}-retention-{env}-rg` | WORM immutable storage | **Preserved** — never deleted by scripts |

---

## Step 5 — Build and Push Container Images

> **Note:** The ingestor and exporter start with hello-world placeholder images. Replace them with real images after building.

```bash
# Get ACR login server from deployment outputs
ACR=$(az acr list --resource-group "${PREFIX}-demo-${ENV}-rg" --query "[0].loginServer" -o tsv)

az acr login --name "${ACR%%.*}"

# Build and push ingestor
docker build -t "$ACR/weather-ingestor:latest" apps/weather-ingestor/
docker push "$ACR/weather-ingestor:latest"

# Build and push exporter
docker build -t "$ACR/backup-exporter:latest" apps/backup-exporter/
docker push "$ACR/backup-exporter:latest"
```

Then redeploy with the real image refs:

```bash
az deployment sub create \
  --template-file infra/main.bicep \
  --parameters \
    prefix="$PREFIX" \
    environmentName="$ENV" \
    location="$LOCATION" \
    ingestorImageRef="$ACR/weather-ingestor:latest" \
    exporterImageRef="$ACR/backup-exporter:latest" \
  --location "$LOCATION"
```

---

## Step 6 — Post-Deploy Smoke Check

```bash
PREFIX=$PREFIX ENV=$ENV bash scripts/validate-deployment.sh
```

Expected: all checks PASS — resource groups, Cosmos account, continuous backup policy, storage accounts, managed identities, Container Apps environment.

---

## Step 7 — Verify Ingestion and Backup

```bash
# Confirm documents are being written every 20 seconds
bash scripts/validate-ingestion.sh

# Confirm backup policy and WORM immutability
PREFIX=$PREFIX ENV=$ENV bash scripts/validate-backup.sh
```

---

## Environment-Specific Parameters

| Environment | Parameter File | Notes |
|-------------|---------------|-------|
| dev | `infra/parameters/dev.bicepparam` | LRS storage, single-region, `Continuous30Days` |
| test | `infra/parameters/test.bicepparam` | LRS storage, single-region, `Continuous30Days` |
| prod | `infra/parameters/prod.bicepparam` | GRS storage, multi-region (`westus2`), `Continuous7Days` (PITR) |

Pass environment-specific params:

```bash
az deployment sub create \
  --template-file infra/main.bicep \
  --parameters infra/parameters/prod.bicepparam \
  --location eastus2
```

---

## Teardown

See [Cleanup Guide](cleanup.md) for safe deletion procedures that preserve the WORM retention archive.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Container App shows hello-world | Images not pushed to ACR | Complete Step 5 |
| `validate-deployment.sh` fails on export storage name | Wrong `PREFIX`/`ENV` vars | Ensure env vars match deployment |
| Bicep build errors | Outdated Bicep CLI | `az bicep upgrade` |
| `az login` fails | MFA / conditional access | Use `az login --use-device-code` |
