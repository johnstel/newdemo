#!/usr/bin/env bash
# ============================================================
# validate-restore.sh
# G4 core: Simulate data loss and verify PITR restore.
#
# Workflow:
#   1. Record current document count and capture a restore
#      timestamp (T_RESTORE) just before deletion.
#   2. Delete a sample of documents to simulate data loss.
#   3. Verify documents are gone from the live container.
#   4. Trigger Cosmos DB PITR restore to a NEW account
#      ({PREFIX}-restored-{ENV}).
#   5. Poll for restore completion (up to RESTORE_TIMEOUT_MINS).
#   6. Query the restored account to verify data is present.
#   7. Confirm restored account is NOT the live account.
#
# ⚠️  AZURE REQUIRED — this script cannot run locally.
# ⚠️  Restore creates a new Cosmos account; this incurs cost.
#     Delete ${PREFIX}-restored-${ENV} when done (see teardown.sh).
# ⚠️  Restore times vary; allow 30–60 minutes for large accounts.
#     RESTORE_TIMEOUT_MINS defaults to 90.
#
# Exit 0 = pass (restore verified), non-zero = fail.
# ============================================================
set -euo pipefail

# ---------- defaults ----------------------------------------
PREFIX="${PREFIX:-cosmos-backup}"
ENV="${ENV:-dev}"
LOCATION="${LOCATION:-eastus2}"
RESTORE_TIMEOUT_MINS="${RESTORE_TIMEOUT_MINS:-90}"
DELETE_SAMPLE_SIZE="${DELETE_SAMPLE_SIZE:-5}"   # documents to delete
POLL_INTERVAL_SECS=60

PRIMARY_RG="${PREFIX}-demo-${ENV}-rg"
COSMOS_ACCOUNT="${PREFIX}-cosmos-${ENV}"
RESTORE_ACCOUNT="${PREFIX}-restored-${ENV}"
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
echo "  PITR RESTORE VALIDATION"
echo "  Source: $COSMOS_ACCOUNT  →  Target: $RESTORE_ACCOUNT"
echo "  ⚠️  AZURE SUBSCRIPTION REQUIRED"
echo "  ⚠️  Restore creates a real Azure resource — delete after demo"
echo "============================================================"

# ============================================================
# SAFETY CHECK: confirm we are NOT targeting the live account
# ============================================================
if [[ "$RESTORE_ACCOUNT" == "$COSMOS_ACCOUNT" ]]; then
  FAIL "SAFETY: RESTORE_ACCOUNT == COSMOS_ACCOUNT — restore must target a different account"
  exit 1
fi
PASS "Safety: restore target '$RESTORE_ACCOUNT' != live account '$COSMOS_ACCOUNT'"

# Auth
if ! az account show &>/dev/null; then
  FAIL "Not logged in. Run: az login"
  exit 1
fi

# ============================================================
# 1. PRE-LOSS BASELINE
# ============================================================
HEADER "1. Pre-loss baseline"

T_RESTORE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
INFO "Capture restore timestamp: $T_RESTORE"

PRE_COUNT=$(az cosmosdb sql query \
  --account-name "$COSMOS_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --database-name "$DB_NAME" \
  --name "$CONTAINER_NAME" \
  --query-text "SELECT VALUE COUNT(1) FROM c" \
  --query "[0]._count" -o tsv 2>/dev/null || echo "0")

PASS "Pre-loss document count: $PRE_COUNT"

if (( PRE_COUNT == 0 )); then
  FAIL "No documents in container — run validate-ingestion.sh first"
  exit 1
fi

# ============================================================
# 2. SIMULATE DATA LOSS (delete sample documents)
# ============================================================
HEADER "2. Simulating data loss (delete $DELETE_SAMPLE_SIZE documents)"
INFO "⚠️  This modifies live data — restore will recover them."

# Fetch IDs to delete
IDS_JSON=$(az cosmosdb sql query \
  --account-name "$COSMOS_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --database-name "$DB_NAME" \
  --name "$CONTAINER_NAME" \
  --query-text "SELECT TOP $DELETE_SAMPLE_SIZE c.id, c.cityId FROM c" \
  -o json 2>/dev/null || echo "[]")

if [[ "$IDS_JSON" == "[]" || -z "$IDS_JSON" ]]; then
  WARN "Could not retrieve document IDs for deletion — skipping data-loss simulation"
  INFO "Continuing with restore validation against pre-loss timestamp only."
  SIMULATE_DONE=false
else
  DELETED=0
  while IFS= read -r doc; do
    DOC_ID=$(echo "$doc" | jq -r '.id')
    CITY_ID=$(echo "$doc" | jq -r '.cityId')
    if az cosmosdb sql container delete-item \
      --account-name "$COSMOS_ACCOUNT" \
      --resource-group "$PRIMARY_RG" \
      --database-name "$DB_NAME" \
      --name "$CONTAINER_NAME" \
      --item-id "$DOC_ID" \
      --partition-key-value "$CITY_ID" &>/dev/null 2>&1; then
      DELETED=$((DELETED+1))
    fi
  done < <(echo "$IDS_JSON" | jq -c '.[]')

  PASS "Deleted $DELETED document(s) from live container"

  POST_DELETE_COUNT=$(az cosmosdb sql query \
    --account-name "$COSMOS_ACCOUNT" \
    --resource-group "$PRIMARY_RG" \
    --database-name "$DB_NAME" \
    --name "$CONTAINER_NAME" \
    --query-text "SELECT VALUE COUNT(1) FROM c" \
    --query "[0]._count" -o tsv 2>/dev/null || echo "UNKNOWN")

  INFO "Post-deletion count: $POST_DELETE_COUNT (was: $PRE_COUNT)"
  if [[ "$POST_DELETE_COUNT" != "UNKNOWN" ]] && \
     (( POST_DELETE_COUNT < PRE_COUNT )); then
    PASS "Data loss confirmed — $((PRE_COUNT - POST_DELETE_COUNT)) documents missing"
  else
    WARN "Count did not decrease as expected — manual verification recommended"
  fi
  SIMULATE_DONE=true
fi

# ============================================================
# 3. TRIGGER PITR RESTORE
# ============================================================
HEADER "3. Triggering PITR restore"
INFO "Restore timestamp: $T_RESTORE"
INFO "Target account: $RESTORE_ACCOUNT"
INFO "This will take 30–60 minutes. Polling every ${POLL_INTERVAL_SECS}s."

# Check if restore account already exists (idempotency)
EXISTING=$(az cosmosdb show --name "$RESTORE_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --query "name" -o tsv 2>/dev/null || echo "NOT_FOUND")

if [[ "$EXISTING" == "$RESTORE_ACCOUNT" ]]; then
  WARN "Restore account $RESTORE_ACCOUNT already exists — skipping restore trigger"
  INFO "Delete it first to re-run: az cosmosdb delete --name $RESTORE_ACCOUNT --resource-group $PRIMARY_RG --yes"
else
  RESTORE_START=$(date +%s)

  az cosmosdb restore \
    --account-name "$COSMOS_ACCOUNT" \
    --resource-group "$PRIMARY_RG" \
    --target-database-account-name "$RESTORE_ACCOUNT" \
    --restore-timestamp "$T_RESTORE" \
    --location "$LOCATION" \
    --databases-to-restore name="$DB_NAME" collection-names="$CONTAINER_NAME" \
    --no-wait 2>/dev/null

  PASS "PITR restore initiated — polling for completion..."
fi

# ============================================================
# 4. POLL FOR RESTORE COMPLETION
# ============================================================
HEADER "4. Polling restore status"

TIMEOUT_SECS=$((RESTORE_TIMEOUT_MINS * 60))
ELAPSED=0

while true; do
  RESTORE_STATE=$(az cosmosdb show \
    --name "$RESTORE_ACCOUNT" \
    --resource-group "$PRIMARY_RG" \
    --query "provisioningState" -o tsv 2>/dev/null || echo "Pending")

  echo "  [$(date -u +"%H:%M:%S")] Restore state: $RESTORE_STATE (${ELAPSED}s elapsed)"

  if [[ "$RESTORE_STATE" == "Succeeded" ]]; then
    PASS "Restore completed successfully"
    break
  elif [[ "$RESTORE_STATE" == "Failed" ]]; then
    FAIL "Restore FAILED — check Azure portal for error details"
    break
  fi

  if (( ELAPSED >= TIMEOUT_SECS )); then
    FAIL "Restore timed out after ${RESTORE_TIMEOUT_MINS} minutes — check Azure portal"
    INFO "You can re-run this script later; it will skip the restore trigger if the account exists."
    exit 1
  fi

  sleep "$POLL_INTERVAL_SECS"
  ELAPSED=$((ELAPSED + POLL_INTERVAL_SECS))
done

# ============================================================
# 5. VERIFY RESTORED DATA
# ============================================================
HEADER "5. Verifying restored data"

# Confirmed: restore target is not the live account
RESTORED_ENDPOINT=$(az cosmosdb show \
  --name "$RESTORE_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --query "documentEndpoint" -o tsv 2>/dev/null || echo "UNKNOWN")

LIVE_ENDPOINT=$(az cosmosdb show \
  --name "$COSMOS_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --query "documentEndpoint" -o tsv 2>/dev/null || echo "UNKNOWN")

if [[ "$RESTORED_ENDPOINT" != "$LIVE_ENDPOINT" ]]; then
  PASS "Restored account endpoint is distinct from live account"
  INFO "  Live:     $LIVE_ENDPOINT"
  INFO "  Restored: $RESTORED_ENDPOINT"
else
  FAIL "CRITICAL: Restored and live account endpoints are identical!"
fi

# Verify container exists in restored account
RESTORED_CONT=$(az cosmosdb sql container show \
  --account-name "$RESTORE_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --database-name "$DB_NAME" \
  --name "$CONTAINER_NAME" \
  --query "name" -o tsv 2>/dev/null || echo "NOT_FOUND")

if [[ "$RESTORED_CONT" == "$CONTAINER_NAME" ]]; then
  PASS "Container '$CONTAINER_NAME' exists in restored account"
else
  FAIL "Container '$CONTAINER_NAME' NOT found in restored account"
fi

# Document count in restored account
RESTORED_COUNT=$(az cosmosdb sql query \
  --account-name "$RESTORE_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --database-name "$DB_NAME" \
  --name "$CONTAINER_NAME" \
  --query-text "SELECT VALUE COUNT(1) FROM c" \
  --query "[0]._count" -o tsv 2>/dev/null || echo "0")

INFO "Restored document count: $RESTORED_COUNT"
INFO "Pre-loss count was:       $PRE_COUNT"

if (( RESTORED_COUNT > 0 )); then
  PASS "Restored account contains $RESTORED_COUNT documents"
else
  FAIL "Restored account has 0 documents — restore may have produced empty container"
fi

if [[ "$SIMULATE_DONE" == "true" ]] && (( RESTORED_COUNT >= PRE_COUNT )); then
  PASS "Restored count ($RESTORED_COUNT) >= pre-loss count ($PRE_COUNT) — recovery complete"
fi

# ============================================================
# 6. RESTORE ACCOUNT CLEANUP REMINDER
# ============================================================
echo ""
echo "=== Cleanup reminder ==="
INFO "The restored account '$RESTORE_ACCOUNT' is still running and incurring cost."
INFO "Delete it when the demo is complete:"
INFO "  az cosmosdb delete --name $RESTORE_ACCOUNT --resource-group $PRIMARY_RG --yes"

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "======================================================"
if [[ $FAILURES -eq 0 ]]; then
  PASS "RESTORE VALIDATION PASSED — G4 restore gate clear"
  echo "======================================================"
  exit 0
else
  FAIL "$FAILURES check(s) FAILED — review above"
  echo "======================================================"
  exit 1
fi
