#!/usr/bin/env bash
# ============================================================
# deploy.sh — Deploy the Cosmos DB backup demo to Azure
# ============================================================
# Usage:
#   ./scripts/deploy/deploy.sh [dev|test|prod]
#
# Prerequisites:
#   - az CLI installed and signed in (az login)
#   - Bicep CLI installed (az bicep install)
#   - Sufficient permissions: Subscription Contributor or Owner
#     (required to create resource groups and assign RBAC roles)
#
# The script deploys at subscription scope. Resource groups are
# created automatically — they do NOT need to exist beforehand.
# ============================================================

set -euo pipefail

ENVIRONMENT="${1:-dev}"
LOCATION="eastus2"
DEPLOYMENT_NAME="cosmos-backup-demo-${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PARAMS_FILE="${REPO_ROOT}/infra/parameters/${ENVIRONMENT}.bicepparam"
TEMPLATE_FILE="${REPO_ROOT}/infra/main.bicep"

echo "========================================"
echo " Cosmos DB Backup Demo — Deploy"
echo " Environment : ${ENVIRONMENT}"
echo " Location    : ${LOCATION}"
echo " Deployment  : ${DEPLOYMENT_NAME}"
echo "========================================"

# ── Validate environment argument ────────────────────────────────────────────

if [[ ! "${ENVIRONMENT}" =~ ^(dev|test|prod)$ ]]; then
  echo "ERROR: environment must be dev, test, or prod" >&2
  exit 1
fi

# ── Check prerequisites ───────────────────────────────────────────────────────

command -v az >/dev/null 2>&1 || { echo "ERROR: az CLI not found" >&2; exit 1; }

az bicep install --only-show-errors 2>/dev/null || true

echo ""
echo "── Checking az CLI login ────────────────────────────────────────────────"
SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null) || {
  echo "ERROR: Not logged in. Run: az login" >&2
  exit 1
}
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo "  Subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"

# ── What-if preview (optional but informative) ────────────────────────────────

echo ""
echo "── Running what-if preview ──────────────────────────────────────────────"
az deployment sub what-if \
  --location "${LOCATION}" \
  --template-file "${TEMPLATE_FILE}" \
  --parameters "${PARAMS_FILE}" \
  --name "${DEPLOYMENT_NAME}-whatif" \
  --no-pretty-print 2>/dev/null || echo "  [what-if skipped or returned warnings — proceeding]"

# ── Deploy ────────────────────────────────────────────────────────────────────

echo ""
echo "── Deploying ────────────────────────────────────────────────────────────"
az deployment sub create \
  --location "${LOCATION}" \
  --template-file "${TEMPLATE_FILE}" \
  --parameters "${PARAMS_FILE}" \
  --name "${DEPLOYMENT_NAME}" \
  --output json > /dev/null

echo "  Deployment complete."

# ── Extract and display outputs ───────────────────────────────────────────────

echo ""
echo "── Deployment Outputs ───────────────────────────────────────────────────"

get_output() {
  az deployment sub show \
    --name "${DEPLOYMENT_NAME}" \
    --query "properties.outputs.${1}.value" \
    -o tsv 2>/dev/null || echo "(not found)"
}

PRIMARY_RG=$(get_output "primaryResourceGroupName")
RETENTION_RG=$(get_output "retentionResourceGroupName")
COSMOS_ENDPOINT=$(get_output "cosmosAccountEndpoint")
COSMOS_DB=$(get_output "cosmosDatabaseName")
COSMOS_CONTAINER=$(get_output "cosmosContainerName")
EXPORT_STORAGE=$(get_output "exportStorageAccountName")
RETENTION_STORAGE=$(get_output "retentionStorageAccountName")
ACR_SERVER=$(get_output "acrLoginServer")
INGESTOR_APP=$(get_output "ingestorAppName")
EXPORTER_JOB=$(get_output "exporterJobName")
INGEST_CLIENT_ID=$(get_output "ingestionIdentityClientId")
EXPORT_CLIENT_ID=$(get_output "exportIdentityClientId")
KV_URI=$(get_output "keyVaultUri")

cat <<EOF

  Primary RG          : ${PRIMARY_RG}
  Retention RG        : ${RETENTION_RG}  ← DO NOT DELETE during teardown

  Cosmos Endpoint     : ${COSMOS_ENDPOINT}
  Database            : ${COSMOS_DB}
  Container           : ${COSMOS_CONTAINER}

  Export Storage      : ${EXPORT_STORAGE}
  Retention Storage   : ${RETENTION_STORAGE}

  ACR Login Server    : ${ACR_SERVER}
  Ingestor App        : ${INGESTOR_APP}
  Exporter Job        : ${EXPORTER_JOB}

  Ingest Identity CID : ${INGEST_CLIENT_ID}
  Export Identity CID : ${EXPORT_CLIENT_ID}

  Key Vault URI       : ${KV_URI}

========================================"
 Next steps:
   1. Build and push images:
      az acr build --registry ${ACR_SERVER%%.*} --image weather-ingestor:latest apps/weather-ingestor
      az acr build --registry ${ACR_SERVER%%.*} --image backup-exporter:latest apps/backup-exporter
   2. Update ingestorImageRef / exporterImageRef params and redeploy (idempotent).
   3. Verify ingestion: az containerapp logs show -n ${INGESTOR_APP} -g ${PRIMARY_RG}
   4. Run Bishop's validation scripts: ./scripts/validate-local.sh
========================================
EOF
