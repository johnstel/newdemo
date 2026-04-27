#!/usr/bin/env bash
# ============================================================
# validate-deployment.sh
# G3: Post-deployment smoke check.
# Verifies that all expected Azure resources exist, Cosmos
# backup policy is correct, storage accounts are configured,
# managed identities are present, and container host is running.
#
# REQUIRES: Active Azure subscription, az login, deployed env.
# Exit 0 = pass, non-zero = fail.
# ============================================================
set -euo pipefail

# ---------- defaults (override via env vars or flags) -------
PREFIX="${PREFIX:-cosmos-backup}"
ENV="${ENV:-dev}"
LOCATION="${LOCATION:-eastus2}"

PRIMARY_RG="${PREFIX}-demo-${ENV}-rg"
RETENTION_RG="${PREFIX}-retention-${ENV}-rg"
COSMOS_ACCOUNT="${PREFIX}-cosmos-${ENV}"
EXPORT_STORAGE="${PREFIX//[-_]/}exp${ENV}"   # no hyphens, matches Bicep take('${baseNameClean}exp${environmentName}', 24)
RETENTION_STORAGE="${PREFIX//[-_]/}ret${ENV}"   # no hyphens, 24-char max
INGESTOR_APP="${PREFIX}-ingestor-${ENV}"
EXPECTED_BACKUP_POLICY="${EXPECTED_BACKUP_POLICY:-Continuous30Days}"
DB_NAME="demo"
CONTAINER_NAME="weather"

# ---------- colour helpers ----------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS()  { echo -e "${GREEN}[PASS]${NC} $*"; }
FAIL()  { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES+1)); }
WARN()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
INFO()  { echo "       $*"; }
HEADER(){ echo ""; echo "=== $* ==="; }

FAILURES=0

echo "============================================================"
echo "  POST-DEPLOYMENT SMOKE CHECK"
echo "  PREFIX=$PREFIX  ENV=$ENV  LOCATION=$LOCATION"
echo "  PRIMARY_RG=$PRIMARY_RG"
echo "  RETENTION_RG=$RETENTION_RG"
echo "============================================================"

# ============================================================
# 1. AZURE AUTH
# ============================================================
HEADER "1. Azure authentication"
if az account show &>/dev/null; then
  CURRENT_SUB=$(az account show --query "name" -o tsv 2>/dev/null)
  PASS "Authenticated — subscription: $CURRENT_SUB"
else
  FAIL "Not logged in to Azure. Run: az login"
  exit 1
fi

# ============================================================
# 2. RESOURCE GROUPS
# ============================================================
HEADER "2. Resource groups"

check_rg() {
  local rg="$1"
  local state
  state=$(az group show --name "$rg" --query "properties.provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")
  if [[ "$state" == "Succeeded" ]]; then
    PASS "Resource group exists: $rg"
  else
    FAIL "Resource group missing or not Succeeded: $rg (state=$state)"
  fi
}

check_rg "$PRIMARY_RG"
check_rg "$RETENTION_RG"

# ============================================================
# 3. COSMOS DB ACCOUNT
# ============================================================
HEADER "3. Cosmos DB account"

COSMOS_STATE=$(az cosmosdb show \
  --name "$COSMOS_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --query "documentEndpoint" -o tsv 2>/dev/null || echo "NOT_FOUND")

if [[ "$COSMOS_STATE" == "NOT_FOUND" ]]; then
  FAIL "Cosmos account not found: $COSMOS_ACCOUNT in $PRIMARY_RG"
else
  PASS "Cosmos account exists: $COSMOS_ACCOUNT"
  INFO "Endpoint: $COSMOS_STATE"
fi

# Backup policy
BACKUP_POLICY=$(az cosmosdb show \
  --name "$COSMOS_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --query "backupPolicy.type" -o tsv 2>/dev/null || echo "UNKNOWN")

if [[ "$BACKUP_POLICY" == "Continuous" ]]; then
  RETENTION_DAYS=$(az cosmosdb show \
    --name "$COSMOS_ACCOUNT" \
    --resource-group "$PRIMARY_RG" \
    --query "backupPolicy.continuousModeProperties.tier" -o tsv 2>/dev/null || echo "UNKNOWN")
  PASS "Continuous backup enabled (tier: $RETENTION_DAYS)"
  INFO "Expected: $EXPECTED_BACKUP_POLICY"
  if [[ "$RETENTION_DAYS" != "$EXPECTED_BACKUP_POLICY" ]]; then
    WARN "Backup tier '$RETENTION_DAYS' != expected '$EXPECTED_BACKUP_POLICY'"
  fi
else
  FAIL "Cosmos backup policy is '$BACKUP_POLICY' — expected Continuous"
fi

# Database and container
DB_EXISTS=$(az cosmosdb sql database show \
  --account-name "$COSMOS_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --name "$DB_NAME" \
  --query "name" -o tsv 2>/dev/null || echo "NOT_FOUND")

if [[ "$DB_EXISTS" == "$DB_NAME" ]]; then
  PASS "Cosmos database '$DB_NAME' exists"
else
  FAIL "Cosmos database '$DB_NAME' not found"
fi

CONT_EXISTS=$(az cosmosdb sql container show \
  --account-name "$COSMOS_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --database-name "$DB_NAME" \
  --name "$CONTAINER_NAME" \
  --query "name" -o tsv 2>/dev/null || echo "NOT_FOUND")

if [[ "$CONT_EXISTS" == "$CONTAINER_NAME" ]]; then
  PASS "Cosmos container '$CONTAINER_NAME' exists"
  # Check partition key
  PARTITION_KEY=$(az cosmosdb sql container show \
    --account-name "$COSMOS_ACCOUNT" \
    --resource-group "$PRIMARY_RG" \
    --database-name "$DB_NAME" \
    --name "$CONTAINER_NAME" \
    --query "resource.partitionKey.paths[0]" -o tsv 2>/dev/null || echo "UNKNOWN")
  if [[ "$PARTITION_KEY" == "/cityId" ]]; then
    PASS "Partition key is /cityId"
  else
    FAIL "Partition key is '$PARTITION_KEY' — expected /cityId"
  fi
else
  FAIL "Cosmos container '$CONTAINER_NAME' not found"
fi

# Key check — no account keys should be needed, but verify no public key access enabled
KEY_DISABLED=$(az cosmosdb show \
  --name "$COSMOS_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --query "disableLocalAuth" -o tsv 2>/dev/null || echo "false")
if [[ "$KEY_DISABLED" == "true" ]]; then
  PASS "Local auth (account keys) disabled on Cosmos account"
else
  WARN "Local auth not explicitly disabled — acceptable for demo, but verify no keys in app config"
fi

# ============================================================
# 4. STORAGE ACCOUNTS
# ============================================================
HEADER "4. Storage accounts"

check_storage() {
  local sa_name="$1"
  local rg="$2"
  local label="$3"

  local state
  state=$(az storage account show \
    --name "$sa_name" \
    --resource-group "$rg" \
    --query "provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")

  if [[ "$state" == "Succeeded" ]]; then
    PASS "Storage account exists ($label): $sa_name"
    return 0
  else
    FAIL "Storage account missing ($label): $sa_name in $rg (state=$state)"
    return 1
  fi
}

check_storage "$EXPORT_STORAGE"    "$PRIMARY_RG"   "export"    && EXPORT_OK=true || EXPORT_OK=false
check_storage "$RETENTION_STORAGE" "$RETENTION_RG" "retention" && RETENTION_OK=true || RETENTION_OK=false

# Immutability on retention storage
if [[ "$RETENTION_OK" == "true" ]]; then
  IMMUTABLE=$(az storage account show \
    --name "$RETENTION_STORAGE" \
    --resource-group "$RETENTION_RG" \
    --query "immutableStorageWithVersioning.enabled" -o tsv 2>/dev/null || echo "false")
  if [[ "$IMMUTABLE" == "true" ]]; then
    PASS "Version-level immutability enabled on retention storage"
  else
    FAIL "Version-level immutability NOT enabled on retention storage — WORM not active"
  fi

  # Blob versioning
  VERSIONING=$(az storage account blob-service-properties show \
    --account-name "$RETENTION_STORAGE" \
    --resource-group "$RETENTION_RG" \
    --query "isVersioningEnabled" -o tsv 2>/dev/null || echo "false")
  if [[ "$VERSIONING" == "true" ]]; then
    PASS "Blob versioning enabled on retention storage"
  else
    FAIL "Blob versioning NOT enabled on retention storage"
  fi
fi

# Lifecycle policy on export storage
if [[ "$EXPORT_OK" == "true" ]]; then
  LIFECYCLE=$(az storage account management-policy show \
    --account-name "$EXPORT_STORAGE" \
    --resource-group "$PRIMARY_RG" \
    --query "policy.rules[0].name" -o tsv 2>/dev/null || echo "NOT_FOUND")
  if [[ "$LIFECYCLE" != "NOT_FOUND" ]]; then
    PASS "Lifecycle policy present on export storage (first rule: $LIFECYCLE)"
  else
    WARN "No lifecycle policy found on export storage — Cool/Archive tiering not configured"
  fi
fi

# ============================================================
# 5. MANAGED IDENTITIES
# ============================================================
HEADER "5. Managed identities"

check_identity() {
  local name="$1"
  local rg="$2"
  local label="$3"
  local state
  state=$(az identity show --name "$name" --resource-group "$rg" \
    --query "provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")
  if [[ "$state" == "Succeeded" ]]; then
    PASS "Managed identity present ($label): $name"
  else
    FAIL "Managed identity missing ($label): $name in $rg"
  fi
}

check_identity "${PREFIX}-ingestor-id-${ENV}"  "$PRIMARY_RG" "ingestor"
check_identity "${PREFIX}-exporter-id-${ENV}"  "$PRIMARY_RG" "exporter"

# ============================================================
# 6. CONTAINER HOST
# ============================================================
HEADER "6. Container host (ingestor)"

INGESTOR_STATE=$(az containerapp show \
  --name "$INGESTOR_APP" \
  --resource-group "$PRIMARY_RG" \
  --query "properties.provisioningState" -o tsv 2>/dev/null || \
  az container show \
    --name "$INGESTOR_APP" \
    --resource-group "$PRIMARY_RG" \
    --query "provisioningState" -o tsv 2>/dev/null || \
  echo "NOT_FOUND")

if [[ "$INGESTOR_STATE" == "Succeeded" ]]; then
  PASS "Container host running: $INGESTOR_APP"
elif [[ "$INGESTOR_STATE" == "NOT_FOUND" ]]; then
  FAIL "Container host not found: $INGESTOR_APP"
else
  WARN "Container host state: $INGESTOR_STATE (expected Succeeded)"
fi

# ============================================================
# 7. TAGGING SPOT CHECK
# ============================================================
HEADER "7. Required tags"

TAGS=$(az group show --name "$PRIMARY_RG" --query "tags" -o json 2>/dev/null || echo "{}")

for tag_key in project environment owner costCenter createdBy; do
  val=$(echo "$TAGS" | jq -r --arg k "$tag_key" '.[$k] // "MISSING"')
  if [[ "$val" != "MISSING" && "$val" != "null" ]]; then
    PASS "Tag present on primary RG: $tag_key=$val"
  else
    WARN "Tag missing on primary RG: $tag_key"
  fi
done

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "======================================================"
if [[ $FAILURES -eq 0 ]]; then
  PASS "ALL DEPLOYMENT CHECKS PASSED (0 failures) — G3 eligible"
  echo "======================================================"
  exit 0
else
  FAIL "$FAILURES check(s) FAILED — resolve before G3 approval"
  echo "======================================================"
  exit 1
fi
