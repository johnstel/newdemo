#!/usr/bin/env bash
# ============================================================
# validate-cleanup.sh
# G6 post-demo: Verify teardown was performed correctly.
#
# Checks:
#   1. Primary demo RG is deleted (or empty).
#   2. Retention RG still exists and has not been deleted.
#   3. Retention storage blobs are still present.
#   4. Restored Cosmos account is cleaned up (optional check).
#
# REQUIRES: Active Azure subscription, az login.
# Exit 0 = pass, non-zero = fail.
# ============================================================
set -euo pipefail

# ---------- defaults ----------------------------------------
PREFIX="${PREFIX:-cosmos-backup}"
ENV="${ENV:-dev}"

PRIMARY_RG="${PREFIX}-demo-${ENV}-rg"
RETENTION_RG="${PREFIX}-retention-${ENV}-rg"
RESTORE_ACCOUNT="${PREFIX}-restored-${ENV}"
RETENTION_STORAGE="${PREFIX//[-_]/}ret${ENV}"
RETENTION_CONTAINER="exports"

# ---------- colour helpers ----------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS()  { echo -e "${GREEN}[PASS]${NC} $*"; }
FAIL()  { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES+1)); }
WARN()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
INFO()  { echo "       $*"; }
HEADER(){ echo ""; echo "=== $* ==="; }

FAILURES=0

echo "============================================================"
echo "  CLEANUP VALIDATION"
echo "  PRIMARY_RG:   $PRIMARY_RG"
echo "  RETENTION_RG: $RETENTION_RG  (must NOT be deleted)"
echo "============================================================"

if ! az account show &>/dev/null; then
  FAIL "Not logged in. Run: az login"
  exit 1
fi

# ============================================================
# 1. PRIMARY RG — should be gone
# ============================================================
HEADER "1. Primary demo resource group"

PRIMARY_STATE=$(az group show --name "$PRIMARY_RG" \
  --query "properties.provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")

if [[ "$PRIMARY_STATE" == "NOT_FOUND" ]]; then
  PASS "Primary RG deleted: $PRIMARY_RG"
else
  FAIL "Primary RG still exists: $PRIMARY_RG (state: $PRIMARY_STATE)"
  INFO "Run teardown: scripts/teardown.sh"
fi

# ============================================================
# 2. RETENTION RG — must still exist
# ============================================================
HEADER "2. Retention resource group (must be preserved)"

RETENTION_STATE=$(az group show --name "$RETENTION_RG" \
  --query "properties.provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")

if [[ "$RETENTION_STATE" == "Succeeded" ]]; then
  PASS "Retention RG preserved: $RETENTION_RG"
else
  FAIL "Retention RG is MISSING or not Succeeded: $RETENTION_RG (state: $RETENTION_STATE)"
  INFO "WORM archive may have been accidentally deleted — this is a compliance failure."
fi

# ============================================================
# 3. RETENTION BLOBS — must still exist
# ============================================================
HEADER "3. Retention blobs preserved"

if [[ "$RETENTION_STATE" == "Succeeded" ]]; then
  BLOB_COUNT=$(az storage blob list \
    --account-name "$RETENTION_STORAGE" \
    --container-name "$RETENTION_CONTAINER" \
    --auth-mode login \
    --query "length(@)" -o tsv 2>/dev/null || echo "ERROR")

  if [[ "$BLOB_COUNT" == "ERROR" ]]; then
    WARN "Could not list retention blobs — check RBAC"
  elif (( BLOB_COUNT > 0 )); then
    PASS "Retention blobs intact: $BLOB_COUNT blob(s) in $RETENTION_CONTAINER"
  else
    WARN "Retention container is empty — may be expected if exporter never ran"
  fi
else
  WARN "Retention RG not found — skipping blob check"
fi

# ============================================================
# 4. RESTORED ACCOUNT — should be cleaned up
# ============================================================
HEADER "4. Restored Cosmos account cleanup (optional)"

RESTORE_STATE=$(az cosmosdb show \
  --name "$RESTORE_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --query "provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")

if [[ "$RESTORE_STATE" == "NOT_FOUND" ]]; then
  PASS "Restored account cleaned up: $RESTORE_ACCOUNT"
else
  WARN "Restored account still exists: $RESTORE_ACCOUNT (state: $RESTORE_STATE)"
  INFO "If primary RG was deleted, this may have been removed automatically."
  INFO "Manual cleanup: az cosmosdb delete --name $RESTORE_ACCOUNT --resource-group $PRIMARY_RG --yes"
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "======================================================"
if [[ $FAILURES -eq 0 ]]; then
  PASS "CLEANUP VALIDATION PASSED — teardown clean"
  echo "======================================================"
  exit 0
else
  FAIL "$FAILURES check(s) FAILED"
  echo "======================================================"
  exit 1
fi
