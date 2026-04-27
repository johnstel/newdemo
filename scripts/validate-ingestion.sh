#!/usr/bin/env bash
# ============================================================
# validate-ingestion.sh
# G3 sub-check: Verify the weather ingestor is writing
# documents to Cosmos DB at the expected cadence.
#
# Method: query document count, wait WAIT_SECS, query again,
# confirm delta >= MIN_DELTA.  Optionally dump one document
# to verify schema correctness.
#
# REQUIRES: Active Azure subscription, az login, deployed env.
# Exit 0 = pass, non-zero = fail.
# ============================================================
set -euo pipefail

# ---------- defaults ----------------------------------------
PREFIX="${PREFIX:-cosmos-backup}"
ENV="${ENV:-dev}"
WAIT_SECS="${WAIT_SECS:-25}"    # one cycle (20s) + 5s buffer
MIN_DELTA="${MIN_DELTA:-1}"     # at least one document per interval

PRIMARY_RG="${PREFIX}-demo-${ENV}-rg"
COSMOS_ACCOUNT="${PREFIX}-cosmos-${ENV}"
DB_NAME="demo"
CONTAINER_NAME="weather"

# ---------- colour helpers ----------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS()  { echo -e "${GREEN}[PASS]${NC} $*"; }
FAIL()  { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES+1)); }
WARN()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
INFO()  { echo "       $*"; }

FAILURES=0

echo "============================================================"
echo "  INGESTION VALIDATION"
echo "  Cosmos: $COSMOS_ACCOUNT  DB: $DB_NAME  Container: $CONTAINER_NAME"
echo "  Waiting ${WAIT_SECS}s between counts (cadence: 20s + buffer)"
echo "============================================================"

# ============================================================
# AUTH CHECK
# ============================================================
if ! az account show &>/dev/null; then
  FAIL "Not logged in to Azure. Run: az login"
  exit 1
fi

# ============================================================
# HELPER: run a Cosmos SQL query and return plain count
# Uses az cosmosdb sql query if available, else REST via token
# ============================================================
query_count() {
  local query="$1"
  az cosmosdb sql query \
    --account-name "$COSMOS_ACCOUNT" \
    --resource-group "$PRIMARY_RG" \
    --database-name "$DB_NAME" \
    --name "$CONTAINER_NAME" \
    --query-text "$query" \
    --query "[0]._count" \
    -o tsv 2>/dev/null || echo "ERROR"
}

# Fallback using data-plane REST (if az cosmosdb sql query isn't available)
query_count_rest() {
  # Acquire token for Cosmos data plane
  TOKEN=$(az account get-access-token \
    --resource "https://cosmos.azure.com" \
    --query "accessToken" -o tsv 2>/dev/null)
  ENDPOINT=$(az cosmosdb show \
    --name "$COSMOS_ACCOUNT" \
    --resource-group "$PRIMARY_RG" \
    --query "documentEndpoint" -o tsv 2>/dev/null)

  # Using REST API — count query
  RESULT=$(curl -s -X POST \
    "${ENDPOINT}dbs/${DB_NAME}/colls/${CONTAINER_NAME}/docs" \
    -H "Authorization: type=aad,ver=1.0,sig=${TOKEN}" \
    -H "Content-Type: application/query+json" \
    -H "x-ms-documentdb-isquery: true" \
    -H "x-ms-documentdb-query-enablecrosspartition: true" \
    -H "x-ms-version: 2018-12-31" \
    -d '{"query":"SELECT VALUE COUNT(1) FROM c","parameters":[]}' 2>/dev/null)

  echo "$RESULT" | jq -r '._count // .Documents[0] // "ERROR"' 2>/dev/null || echo "ERROR"
}

# ============================================================
# T0: INITIAL DOCUMENT COUNT
# ============================================================
echo ""
echo "--- T0: querying initial document count ---"
T0_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
T0_COUNT=$(query_count "SELECT VALUE COUNT(1) FROM c" 2>/dev/null || echo "ERROR")

if [[ "$T0_COUNT" == "ERROR" || -z "$T0_COUNT" ]]; then
  WARN "az cosmosdb sql query unavailable; attempting REST fallback..."
  T0_COUNT=$(query_count_rest 2>/dev/null || echo "ERROR")
fi

if [[ "$T0_COUNT" == "ERROR" || -z "$T0_COUNT" ]]; then
  FAIL "Unable to query document count — check RBAC assignment and connectivity"
  exit 1
fi

PASS "T0 count at $T0_TIME: $T0_COUNT documents"

# ============================================================
# WAIT
# ============================================================
echo ""
echo "--- Waiting ${WAIT_SECS}s for ingestor to write new documents ---"
sleep "$WAIT_SECS"

# ============================================================
# T1: FINAL DOCUMENT COUNT
# ============================================================
echo ""
echo "--- T1: querying final document count ---"
T1_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
T1_COUNT=$(query_count "SELECT VALUE COUNT(1) FROM c" 2>/dev/null || \
           query_count_rest 2>/dev/null || echo "ERROR")

if [[ "$T1_COUNT" == "ERROR" || -z "$T1_COUNT" ]]; then
  FAIL "Unable to query document count at T1"
  exit 1
fi

PASS "T1 count at $T1_TIME: $T1_COUNT documents"

DELTA=$((T1_COUNT - T0_COUNT))
INFO "Delta: $DELTA documents in ${WAIT_SECS}s"

if (( DELTA >= MIN_DELTA )); then
  PASS "Ingestion active — delta $DELTA >= required $MIN_DELTA"
else
  FAIL "Ingestion stalled — delta $DELTA < required $MIN_DELTA"
  INFO "Check container host logs: az containerapp logs show --name ${PREFIX}-ingestor-${ENV} --resource-group $PRIMARY_RG"
fi

# ============================================================
# SCHEMA SPOT CHECK — one recent document
# ============================================================
echo ""
echo "--- Schema spot check (most recent document) ---"

SAMPLE_DOC=$(az cosmosdb sql query \
  --account-name "$COSMOS_ACCOUNT" \
  --resource-group "$PRIMARY_RG" \
  --database-name "$DB_NAME" \
  --name "$CONTAINER_NAME" \
  --query-text "SELECT TOP 1 * FROM c ORDER BY c._ts DESC" \
  -o json 2>/dev/null | jq '.[0]' 2>/dev/null || echo "null")

if [[ "$SAMPLE_DOC" == "null" || -z "$SAMPLE_DOC" ]]; then
  WARN "Schema check skipped — could not retrieve a sample document."
else
  INFO "Sample document (truncated):"
  echo "$SAMPLE_DOC" | jq '{id, cityId, timestamp, temperature, humidity, _ts}' 2>/dev/null || \
    echo "$SAMPLE_DOC" | head -20

  # Required fields
  for field in id cityId timestamp; do
    val=$(echo "$SAMPLE_DOC" | jq -r --arg f "$field" '.[$f] // "MISSING"' 2>/dev/null)
    if [[ "$val" != "MISSING" && "$val" != "null" ]]; then
      PASS "Document field present: $field = $val"
    else
      FAIL "Document missing required field: $field"
    fi
  done

  # Timestamp should be ISO 8601
  TIMESTAMP=$(echo "$SAMPLE_DOC" | jq -r '.timestamp // ""' 2>/dev/null)
  if [[ "$TIMESTAMP" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
    PASS "Timestamp is ISO 8601 format: $TIMESTAMP"
  else
    WARN "Timestamp format may not be ISO 8601: '$TIMESTAMP'"
  fi

  # Partition key value should exist
  CITY_ID=$(echo "$SAMPLE_DOC" | jq -r '.cityId // ""' 2>/dev/null)
  if [[ -n "$CITY_ID" && "$CITY_ID" != "null" ]]; then
    PASS "Partition key /cityId is populated: $CITY_ID"
  else
    FAIL "Partition key /cityId is empty or missing"
  fi
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "======================================================"
if [[ $FAILURES -eq 0 ]]; then
  PASS "INGESTION VALIDATION PASSED — G3 ingestion sub-gate clear"
  echo "======================================================"
  exit 0
else
  FAIL "$FAILURES check(s) FAILED"
  echo "======================================================"
  exit 1
fi
