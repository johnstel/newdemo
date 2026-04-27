#!/usr/bin/env bash
# ============================================================
# teardown.sh
# Remove the PRIMARY demo resource group only.
# The retention resource group is explicitly preserved.
#
# REQUIRES: Active Azure subscription, az login.
# ⚠️  This is irreversible. A confirmation prompt is shown.
# ============================================================
set -euo pipefail

# ---------- defaults ----------------------------------------
PREFIX="${PREFIX:-cosmos-backup}"
ENV="${ENV:-dev}"
SKIP_CONFIRM="${SKIP_CONFIRM:-false}"   # set to 'true' in CI

PRIMARY_RG="${PREFIX}-demo-${ENV}-rg"
RETENTION_RG="${PREFIX}-retention-${ENV}-rg"
COSMOS_ACCOUNT="${PREFIX}-cosmos-${ENV}"
RESTORE_ACCOUNT="${PREFIX}-restored-${ENV}"

# ---------- colour helpers ----------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS()  { echo -e "${GREEN}[OK]${NC} $*"; }
FAIL()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
WARN()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
INFO()  { echo "       $*"; }

echo "============================================================"
echo "  DEMO TEARDOWN"
echo "  Will DELETE:  $PRIMARY_RG"
echo "  Will PRESERVE: $RETENTION_RG  ← WORM archive, never deleted"
echo "============================================================"

if ! az account show &>/dev/null; then
  FAIL "Not logged in. Run: az login"
fi

# ============================================================
# SAFETY: confirm retention RG will NOT be touched
# ============================================================
RETENTION_STATE=$(az group show --name "$RETENTION_RG" \
  --query "properties.provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")

if [[ "$RETENTION_STATE" == "Succeeded" ]]; then
  PASS "Retention RG exists and will be preserved: $RETENTION_RG"
elif [[ "$RETENTION_STATE" == "NOT_FOUND" ]]; then
  WARN "Retention RG '$RETENTION_RG' not found — it may not have been deployed yet."
fi

# ============================================================
# CONFIRM
# ============================================================
if [[ "$SKIP_CONFIRM" != "true" ]]; then
  echo ""
  echo -e "${YELLOW}⚠️  You are about to delete: $PRIMARY_RG${NC}"
  echo "This will permanently remove:"
  echo "  - Cosmos DB account ($COSMOS_ACCOUNT)"
  echo "  - Container host"
  echo "  - Monitoring resources"
  echo "  - Export storage"
  echo "  - Managed identities"
  echo "  - Key Vault"
  echo ""
  echo "The retention resource group ($RETENTION_RG) will NOT be deleted."
  echo ""
  read -r -p "Type the resource group name to confirm deletion: " CONFIRM_RG

  if [[ "$CONFIRM_RG" != "$PRIMARY_RG" ]]; then
    WARN "Confirmation mismatch — aborting teardown"
    exit 0
  fi
fi

# ============================================================
# OPTIONAL: clean up restored account first (if it's in primary RG)
# ============================================================
RESTORE_STATE=$(az cosmosdb show \
  --name "$RESTORE_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --query "provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")

if [[ "$RESTORE_STATE" != "NOT_FOUND" ]]; then
  echo "Deleting restored account $RESTORE_ACCOUNT..."
  az cosmosdb delete \
    --name "$RESTORE_ACCOUNT" \
    --resource-group "$PRIMARY_RG" \
    --yes &>/dev/null || true
  PASS "Restored account removed"
fi

# ============================================================
# DELETE PRIMARY RG
# ============================================================
echo ""
echo "Deleting resource group: $PRIMARY_RG ..."
az group delete \
  --name "$PRIMARY_RG" \
  --yes \
  --no-wait

PASS "Delete request submitted for: $PRIMARY_RG"
echo ""
echo "Deletion runs asynchronously. Track status:"
echo "  az group show --name $PRIMARY_RG --query 'properties.provisioningState'"
echo ""
echo "Run cleanup validation after deletion completes:"
echo "  PREFIX=$PREFIX ENV=$ENV bash scripts/validate-cleanup.sh"
echo ""
PASS "Retention RG '$RETENTION_RG' untouched — WORM archive preserved"
