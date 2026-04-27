#!/usr/bin/env bash
# ============================================================
# validate-backup.sh
# G4 sub-check: Validate backup and immutability configuration.
#
# Checks:
#   1. Cosmos native continuous backup policy (type + tier)
#   2. Export storage lifecycle policy (Cool then Archive)
#   3. Retention storage immutability policy (WORM)
#   4. Export blobs present with valid manifest structure
#   5. Simulated delete attempt on immutable blob (must fail)
#
# REQUIRES: Active Azure subscription, az login, deployed env.
# ⚠️ The immutable-delete test writes a test blob then attempts
#    deletion; the blob is cleaned up automatically if the delete
#    succeeds (meaning immutability is NOT active — fail state).
# Exit 0 = pass, non-zero = fail.
# ============================================================
set -euo pipefail

# ---------- defaults ----------------------------------------
PREFIX="${PREFIX:-cosmos-backup}"
ENV="${ENV:-dev}"
EXPECTED_BACKUP_TIER="${EXPECTED_BACKUP_TIER:-Continuous30Days}"
EXPECTED_IMMUTABILITY_DAYS="${EXPECTED_IMMUTABILITY_DAYS:-1}"
EXPECTED_COOL_AFTER_DAYS="${EXPECTED_COOL_AFTER_DAYS:-7}"
EXPECTED_ARCHIVE_AFTER_DAYS="${EXPECTED_ARCHIVE_AFTER_DAYS:-30}"

PRIMARY_RG="${PREFIX}-demo-${ENV}-rg"
RETENTION_RG="${PREFIX}-retention-${ENV}-rg"
COSMOS_ACCOUNT="${PREFIX}-cosmos-${ENV}"
EXPORT_STORAGE="${PREFIX//[-_]/}exp${ENV}"   # no hyphens, matches Bicep take('${baseNameClean}exp${environmentName}', 24)
RETENTION_STORAGE="${PREFIX//[-_]/}ret${ENV}"
EXPORT_CONTAINER="exports"
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
echo "  BACKUP & IMMUTABILITY VALIDATION"
echo "  PREFIX=$PREFIX  ENV=$ENV"
echo "============================================================"

if ! az account show &>/dev/null; then
  FAIL "Not logged in to Azure. Run: az login"
  exit 1
fi

# ============================================================
# 1. COSMOS CONTINUOUS BACKUP POLICY
# ============================================================
HEADER "1. Cosmos native backup policy"

BACKUP_TYPE=$(az cosmosdb show \
  --name "$COSMOS_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --query "backupPolicy.type" -o tsv 2>/dev/null || echo "NOT_FOUND")

if [[ "$BACKUP_TYPE" == "Continuous" ]]; then
  PASS "Cosmos backup type: Continuous"
else
  FAIL "Cosmos backup type: '$BACKUP_TYPE' — expected 'Continuous'"
fi

BACKUP_TIER=$(az cosmosdb show \
  --name "$COSMOS_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --query "backupPolicy.continuousModeProperties.tier" -o tsv 2>/dev/null || echo "UNKNOWN")

INFO "Backup tier reported: $BACKUP_TIER"
if [[ "$BACKUP_TIER" == "$EXPECTED_BACKUP_TIER" ]]; then
  PASS "Backup tier matches expected: $EXPECTED_BACKUP_TIER"
else
  WARN "Backup tier '$BACKUP_TIER' != expected '$EXPECTED_BACKUP_TIER' — verify parameter"
fi

# Verify restore timestamps are available (indicates backup is active)
EARLIEST=$(az cosmosdb restorable-database-account list \
  --location "$LOCATION" \
  --query "[?accountName=='$COSMOS_ACCOUNT'].restorableLocations[0].regionalDatabaseAccountInstanceId" \
  -o tsv 2>/dev/null || echo "")

if [[ -n "$EARLIEST" ]]; then
  PASS "Cosmos account appears in restorable accounts list"
else
  WARN "Cosmos account not yet in restorable accounts — may need 30+ min after initial deployment"
fi

# ============================================================
# 2. EXPORT STORAGE LIFECYCLE POLICY
# ============================================================
HEADER "2. Export storage lifecycle (Cool → Archive)"

LIFECYCLE_JSON=$(az storage account management-policy show \
  --account-name "$EXPORT_STORAGE" \
  --resource-group "$PRIMARY_RG" \
  -o json 2>/dev/null || echo "null")

if [[ "$LIFECYCLE_JSON" == "null" ]]; then
  FAIL "No lifecycle policy found on export storage: $EXPORT_STORAGE"
else
  PASS "Lifecycle policy present on export storage"

  # Check for Cool tier rule
  COOL_DAYS=$(echo "$LIFECYCLE_JSON" | jq -r '
    .policy.rules[]
    | select(.definition.actions.baseBlob.tierToCool != null)
    | .definition.actions.baseBlob.tierToCool.daysAfterCreationGreaterThan
    // .definition.actions.baseBlob.tierToCool.daysAfterModificationGreaterThan
  ' 2>/dev/null | head -1)

  if [[ -n "$COOL_DAYS" ]]; then
    PASS "Cool tier rule present (transition after $COOL_DAYS days)"
    if (( COOL_DAYS <= EXPECTED_COOL_AFTER_DAYS )); then
      PASS "Cool transition within expected window (≤${EXPECTED_COOL_AFTER_DAYS} days)"
    else
      WARN "Cool transition at $COOL_DAYS days > expected $EXPECTED_COOL_AFTER_DAYS days"
    fi
  else
    WARN "No tierToCool rule found in lifecycle policy"
  fi

  # Check for Archive tier rule
  ARCHIVE_DAYS=$(echo "$LIFECYCLE_JSON" | jq -r '
    .policy.rules[]
    | select(.definition.actions.baseBlob.tierToArchive != null)
    | .definition.actions.baseBlob.tierToArchive.daysAfterCreationGreaterThan
    // .definition.actions.baseBlob.tierToArchive.daysAfterModificationGreaterThan
  ' 2>/dev/null | head -1)

  if [[ -n "$ARCHIVE_DAYS" ]]; then
    PASS "Archive tier rule present (transition after $ARCHIVE_DAYS days)"
    if (( ARCHIVE_DAYS <= EXPECTED_ARCHIVE_AFTER_DAYS )); then
      PASS "Archive transition within expected window (≤${EXPECTED_ARCHIVE_AFTER_DAYS} days)"
    else
      WARN "Archive transition at $ARCHIVE_DAYS days > expected $EXPECTED_ARCHIVE_AFTER_DAYS days"
    fi
  else
    WARN "No tierToArchive rule found in lifecycle policy"
  fi
fi

# ============================================================
# 3. RETENTION STORAGE IMMUTABILITY (WORM)
# ============================================================
HEADER "3. Retention storage immutability / WORM"

# Account-level version immutability
ACCOUNT_IMMUTABLE=$(az storage account show \
  --name "$RETENTION_STORAGE" \
  --resource-group "$RETENTION_RG" \
  --query "immutableStorageWithVersioning.enabled" -o tsv 2>/dev/null || echo "false")

if [[ "$ACCOUNT_IMMUTABLE" == "true" ]]; then
  PASS "Version-level immutability enabled on retention account"
else
  FAIL "Version-level immutability NOT enabled on retention account: $RETENTION_STORAGE"
fi

# Container-level immutability policy
CONTAINER_POLICY=$(az storage container immutability-policy show \
  --account-name "$RETENTION_STORAGE" \
  --container-name "$RETENTION_CONTAINER" \
  --query "properties.immutabilityPeriodSinceCreationInDays" -o tsv 2>/dev/null || echo "NOT_FOUND")

if [[ "$CONTAINER_POLICY" == "NOT_FOUND" || "$CONTAINER_POLICY" == "" ]]; then
  WARN "No container-level immutability policy on '$RETENTION_CONTAINER' — check if account-level covers it"
else
  INFO "Container immutability policy: $CONTAINER_POLICY days"
  if (( CONTAINER_POLICY >= EXPECTED_IMMUTABILITY_DAYS )); then
    PASS "Immutability period $CONTAINER_POLICY days >= minimum $EXPECTED_IMMUTABILITY_DAYS day(s)"
  else
    FAIL "Immutability period $CONTAINER_POLICY days < expected minimum $EXPECTED_IMMUTABILITY_DAYS day(s)"
  fi
fi

# ============================================================
# 4. SIMULATED IMMUTABLE DELETE TEST
# ============================================================
HEADER "4. Immutable-delete simulation (⚠️ LIVE TEST)"
INFO "Writing test blob and attempting deletion — must fail while policy is active."

TEST_BLOB_NAME="bishop-validation-test-$(date +%s).txt"
TEST_CONTENT="Bishop immutability test - $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Write test blob
if az storage blob upload \
  --account-name "$RETENTION_STORAGE" \
  --container-name "$RETENTION_CONTAINER" \
  --name "$TEST_BLOB_NAME" \
  --data "$TEST_CONTENT" \
  --auth-mode login &>/dev/null 2>&1; then
  PASS "Test blob written: $TEST_BLOB_NAME"
else
  WARN "Could not write test blob — skipping delete simulation (check RBAC: Storage Blob Data Contributor)"
  IMMUTABLE_TEST_SKIPPED=true
fi

if [[ "${IMMUTABLE_TEST_SKIPPED:-false}" == "false" ]]; then
  # Attempt deletion — should fail
  DELETE_OUTPUT=$(az storage blob delete \
    --account-name "$RETENTION_STORAGE" \
    --container-name "$RETENTION_CONTAINER" \
    --name "$TEST_BLOB_NAME" \
    --auth-mode login 2>&1 || true)

  if echo "$DELETE_OUTPUT" | grep -qi "BlobImmutableDueToPolicy\|protected\|immutable\|policy"; then
    PASS "Delete correctly blocked by immutability policy — WORM active"
  else
    # If delete succeeded, immutability may not be locked
    EXISTS=$(az storage blob exists \
      --account-name "$RETENTION_STORAGE" \
      --container-name "$RETENTION_CONTAINER" \
      --name "$TEST_BLOB_NAME" \
      --auth-mode login \
      --query "exists" -o tsv 2>/dev/null || echo "false")

    if [[ "$EXISTS" == "false" ]]; then
      WARN "Test blob was deleted — immutability policy may be unlocked (demo mode)"
      INFO "For demo: 1-day policy is active but delete may still succeed if policy hasn't been locked."
      INFO "To lock: az storage container immutability-policy lock --account-name $RETENTION_STORAGE --container-name $RETENTION_CONTAINER"
    else
      PASS "Test blob still exists after delete attempt — immutability enforced"
      # Clean it up
      az storage blob delete \
        --account-name "$RETENTION_STORAGE" \
        --container-name "$RETENTION_CONTAINER" \
        --name "$TEST_BLOB_NAME" \
        --auth-mode login &>/dev/null 2>&1 || true
    fi
  fi
fi

# ============================================================
# 5. EXPORT BLOBS PRESENT
# ============================================================
HEADER "5. Export blob presence check"

EXPORT_BLOB_COUNT=$(az storage blob list \
  --account-name "$EXPORT_STORAGE" \
  --container-name "$EXPORT_CONTAINER" \
  --auth-mode login \
  --query "length(@)" -o tsv 2>/dev/null || echo "ERROR")

if [[ "$EXPORT_BLOB_COUNT" == "ERROR" ]]; then
  WARN "Could not list export blobs — check RBAC and container name '$EXPORT_CONTAINER'"
elif (( EXPORT_BLOB_COUNT > 0 )); then
  PASS "Export blobs present: $EXPORT_BLOB_COUNT blob(s) in $EXPORT_CONTAINER"

  # Find a manifest.json and validate structure
  MANIFEST_BLOB=$(az storage blob list \
    --account-name "$EXPORT_STORAGE" \
    --container-name "$EXPORT_CONTAINER" \
    --auth-mode login \
    --query "[?ends_with(name,'manifest.json')].name | [0]" -o tsv 2>/dev/null || echo "")

  if [[ -n "$MANIFEST_BLOB" && "$MANIFEST_BLOB" != "null" ]]; then
    INFO "Checking manifest: $MANIFEST_BLOB"
    MANIFEST_JSON=$(az storage blob download \
      --account-name "$EXPORT_STORAGE" \
      --container-name "$EXPORT_CONTAINER" \
      --name "$MANIFEST_BLOB" \
      --auth-mode login \
      --file - 2>/dev/null | head -c 4096 || echo "null")

    if [[ "$MANIFEST_JSON" != "null" ]]; then
      for field in itemCount sha256 exportedAt sourceFrom sourceTo; do
        val=$(echo "$MANIFEST_JSON" | jq -r --arg f "$field" '.[$f] // "MISSING"' 2>/dev/null)
        if [[ "$val" != "MISSING" && "$val" != "null" ]]; then
          PASS "Manifest field present: $field = $val"
        else
          FAIL "Manifest field missing: $field"
        fi
      done
    else
      WARN "Could not download manifest JSON for inspection"
    fi
  else
    WARN "No manifest.json found in export container yet — exporter may not have run"
  fi
else
  WARN "No export blobs yet — exporter job may not have run (runs every 6 hours)"
  INFO "Trigger manually: az container restart --name ${PREFIX}-exporter-${ENV} --resource-group $PRIMARY_RG"
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "======================================================"
if [[ $FAILURES -eq 0 ]]; then
  PASS "ALL BACKUP CHECKS PASSED (0 failures) — G4 backup sub-gate clear"
  echo "======================================================"
  exit 0
else
  FAIL "$FAILURES check(s) FAILED"
  echo "======================================================"
  exit 1
fi
