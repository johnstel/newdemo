#!/usr/bin/env bash
# ============================================================
# validate-local.sh
# G1 prerequisite: Azure-free static validation.
# Checks tool availability, required file structure, Bicep
# build success, and .env.example hygiene.
# Exit 0 = pass, non-zero = fail.
# ============================================================
set -euo pipefail

# ---------- colour helpers ----------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS() { echo -e "${GREEN}[PASS]${NC} $*"; }
FAIL() { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES+1)); }
WARN() { echo -e "${YELLOW}[WARN]${NC} $*"; }
INFO() { echo "       $*"; }

FAILURES=0
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ============================================================
# 1. TOOL AVAILABILITY
# ============================================================
echo ""
echo "=== 1. Required tools ==="

for tool in az jq; do
  if command -v "$tool" &>/dev/null; then
    PASS "Tool present: $tool ($(command -v "$tool"))"
  else
    FAIL "Tool missing: $tool"
  fi
done

if az bicep version &>/dev/null 2>&1; then
  PASS "az bicep extension installed: $(az bicep version 2>/dev/null | head -1)"
else
  WARN "az bicep not installed; 'az bicep install' will be needed before G1 gate."
fi

if command -v docker &>/dev/null; then
  PASS "docker present"
else
  WARN "docker not found; G2 (app build) gate will need it."
fi

if command -v node &>/dev/null; then
  PASS "node present: $(node --version)"
else
  WARN "node not found; test suite will not run locally."
fi

# ============================================================
# 2. REQUIRED FILE STRUCTURE
# ============================================================
echo ""
echo "=== 2. Required file presence ==="

check_file() {
  local path="$REPO_ROOT/$1"
  if [[ -f "$path" ]]; then
    PASS "File present: $1"
  else
    FAIL "File missing: $1"
  fi
}

check_dir() {
  local path="$REPO_ROOT/$1"
  if [[ -d "$path" ]]; then
    PASS "Directory present: $1"
  else
    WARN "Directory not yet created: $1  (expected before G1/G2)"
  fi
}

# Infrastructure
check_dir "infra"
check_file "infra/main.bicep"
check_file "infra/main.bicepparam"
check_file "infra/parameters/dev.bicepparam"
check_file "infra/parameters/test.bicepparam"
check_file "infra/parameters/prod.bicepparam"
check_file "infra/modules/cosmos.bicep"
check_file "infra/modules/storage-retention.bicep"
check_file "infra/modules/storage-exports.bicep"
check_file "infra/modules/container-host.bicep"
check_file "infra/modules/monitoring.bicep"
check_file "infra/modules/identity.bicep"
check_file "infra/modules/rbac.bicep"
check_file "infra/modules/keyvault.bicep"
check_file "infra/modules/resource-groups.bicep"

# Applications
check_dir "apps"
check_dir "apps/weather-ingestor"
check_file "apps/weather-ingestor/package.json"
check_file "apps/weather-ingestor/Dockerfile"
check_file "apps/weather-ingestor/.env.example"
check_file "apps/weather-ingestor/src/index.ts"
check_file "apps/weather-ingestor/src/cosmos-client.ts"
check_file "apps/weather-ingestor/src/data-generator.ts"
check_dir "apps/backup-exporter"
check_file "apps/backup-exporter/package.json"
check_file "apps/backup-exporter/Dockerfile"
check_file "apps/backup-exporter/.env.example"
check_file "apps/backup-exporter/src/index.ts"
check_file "apps/backup-exporter/src/cosmos-reader.ts"
check_file "apps/backup-exporter/src/blob-writer.ts"
check_file "apps/backup-exporter/src/manifest.ts"

# Documentation
check_file "docs/design-review.md"
check_file "docs/architecture.md"
check_file "docs/deployment-guide.md"
check_file "docs/backup-and-retention.md"
check_file "docs/restore-and-validation.md"
check_file "docs/demo-walkthrough.md"
check_file "docs/operations-runbook.md"
check_file "docs/cleanup.md"
check_file "docs/assumptions.md"
check_file "README.md"

# ============================================================
# 3. BICEP BUILD (requires az bicep)
# ============================================================
echo ""
echo "=== 3. Bicep build ==="

MAIN_BICEP="$REPO_ROOT/infra/main.bicep"
if [[ ! -f "$MAIN_BICEP" ]]; then
  WARN "infra/main.bicep not found; skipping build check."
else
  if az bicep version &>/dev/null 2>&1; then
    BUILD_OUT="$REPO_ROOT/infra/main.json"
    if az bicep build --file "$MAIN_BICEP" --outfile "$BUILD_OUT" 2>&1; then
      PASS "az bicep build succeeded: infra/main.bicep"
      rm -f "$BUILD_OUT"
    else
      FAIL "az bicep build FAILED on infra/main.bicep"
    fi

    # Validate each module compiles independently
    for mod in "$REPO_ROOT"/infra/modules/*.bicep; do
      MOD_NAME="${mod##*/}"
      if az bicep build --file "$mod" --outfile "${mod%.bicep}.json" 2>&1; then
        PASS "  Module build OK: $MOD_NAME"
        rm -f "${mod%.bicep}.json"
      else
        FAIL "  Module build FAILED: $MOD_NAME"
      fi
    done
  else
    WARN "Bicep build skipped (az bicep not installed)."
  fi
fi

# ============================================================
# 4. .ENV.EXAMPLE HYGIENE — no real secrets
# ============================================================
echo ""
echo "=== 4. .env.example hygiene ==="

# Check only non-comment, non-empty lines for actual secret values.
# Pattern: an env var name that implies a secret, assigned a value that
# is not a placeholder (<...> or ...) and not an empty/template string.
SECRET_PATTERN="^(AZURE_CLIENT_SECRET|COSMOS_KEY|STORAGE_KEY|SAS_TOKEN|PASSWORD|PASSWD)[[:space:]]*=[[:space:]]*[^<\"\$[:space:]]"

for env_file in \
  "apps/weather-ingestor/.env.example" \
  "apps/backup-exporter/.env.example"; do
  full="$REPO_ROOT/$env_file"
  if [[ ! -f "$full" ]]; then
    continue  # already caught in file presence check
  fi
  # Strip comment lines before scanning
  if grep -v '^\s*#' "$full" | grep -qiE "$SECRET_PATTERN" 2>/dev/null; then
    FAIL ".env.example may contain a real secret: $env_file"
    INFO "Review non-comment lines matching secret var names with real values"
  else
    PASS "No embedded secrets detected: $env_file"
  fi
done

# ============================================================
# 5. GITIGNORE / GITATTRIBUTES
# ============================================================
echo ""
echo "=== 5. .gitignore / .gitattributes ==="

GITIGNORE="$REPO_ROOT/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  for pattern in ".env" "*.key" "*.pem" "node_modules"; do
    if grep -qF "$pattern" "$GITIGNORE"; then
      PASS ".gitignore covers: $pattern"
    else
      WARN ".gitignore missing pattern: $pattern"
    fi
  done
else
  FAIL ".gitignore not found at repo root"
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "====================================="
if [[ $FAILURES -eq 0 ]]; then
  PASS "ALL LOCAL CHECKS PASSED (0 failures)"
  echo "====================================="
  exit 0
else
  FAIL "$FAILURES check(s) FAILED — resolve before G1/G2 review"
  echo "====================================="
  exit 1
fi
