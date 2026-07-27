#!/usr/bin/env bash
# =============================================================================
# install-mac.sh – One-shot macOS setup for the OTel AI Telemetry pipeline
#
# What this script does:
#   1. Checks for Homebrew and installs it if missing
#   2. Installs opentelemetry-collector-contrib via Homebrew (otelcol-contrib)
#   3. Creates the config directory and copies otel-config.yaml
#   4. Creates the log directory
#   5. Customises and installs the launchd plist
#   6. Loads the launchd agent
#   7. Waits for the health-check endpoint to respond
#
# Usage:
#   cd observability
#   ./scripts/install-mac.sh
#
# Required environment variables (export before running, or you will be prompted):
#   ADX_CLUSTER_URI      ADX_DATABASE
#   ADX_CLIENT_ID        ADX_CLIENT_SECRET     ADX_TENANT_ID
#   AMP_REMOTE_WRITE_URL
#   AMP_CLIENT_ID        AMP_CLIENT_SECRET     AMP_TENANT_ID
#   OTEL_SERVICE_NAME    (default: ai-demo-agent)
#   OTEL_ENV             (default: dev)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBSERVABILITY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Colour helpers ─────────────────────────────────────────────────────────
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; RESET="\033[0m"
info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

# ── Prompt for missing env vars ────────────────────────────────────────────
prompt_if_missing() {
  local var_name="$1"
  local prompt_text="$2"
  local default_val="${3:-}"
  if [[ -z "${!var_name:-}" ]]; then
    if [[ -n "${default_val}" ]]; then
      read -rp "  ${prompt_text} [${default_val}]: " val
      val="${val:-${default_val}}"
    else
      read -rsp "  ${prompt_text}: " val
      echo
    fi
    export "${var_name}=${val}"
  fi
}

echo ""
echo "=== OTel AI Telemetry – macOS Installer ==="
echo ""

# ── Collect configuration ──────────────────────────────────────────────────
info "Collecting configuration…"

prompt_if_missing OTEL_SERVICE_NAME "Service name"          "ai-demo-agent"
prompt_if_missing OTEL_ENV          "Deployment environment" "dev"

echo ""
echo "── Azure Data Explorer ────────────────────────────────"
prompt_if_missing ADX_CLUSTER_URI   "ADX cluster URI (e.g. https://mycluster.eastus2.kusto.windows.net)"
prompt_if_missing ADX_DATABASE      "ADX database name" "telemetry"
prompt_if_missing ADX_CLIENT_ID     "ADX app-registration client ID"
prompt_if_missing ADX_CLIENT_SECRET "ADX app-registration client secret"
prompt_if_missing ADX_TENANT_ID     "ADX Entra tenant ID"

echo ""
echo "── Azure Managed Prometheus ───────────────────────────"
prompt_if_missing AMP_REMOTE_WRITE_URL "AMP remote-write URL"
prompt_if_missing AMP_CLIENT_ID        "AMP app-registration client ID"
prompt_if_missing AMP_CLIENT_SECRET    "AMP app-registration client secret"
prompt_if_missing AMP_TENANT_ID        "AMP Entra tenant ID"

# ── 1. Homebrew ────────────────────────────────────────────────────────────
info "Checking Homebrew…"
if ! command -v brew &>/dev/null; then
  warn "Homebrew not found – installing…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  info "Homebrew found at $(which brew)"
fi

# ── 2. Install otelcol-contrib ─────────────────────────────────────────────
info "Installing opentelemetry-collector-contrib…"
# The Homebrew formula is opentelemetry-collector; the contrib binary is otelcol-contrib
if brew list opentelemetry-collector &>/dev/null; then
  info "opentelemetry-collector already installed – checking for upgrades…"
  brew upgrade opentelemetry-collector 2>/dev/null || true
else
  brew install opentelemetry-collector
fi

OTELCOL_BIN="$(brew --prefix)/bin/otelcol-contrib"
if [[ ! -x "${OTELCOL_BIN}" ]]; then
  # Some Homebrew versions install the binary as 'otelcol'; handle both
  OTELCOL_BIN="$(brew --prefix)/bin/otelcol"
  [[ -x "${OTELCOL_BIN}" ]] || error "Could not find otelcol-contrib binary after install."
fi
info "Collector binary: ${OTELCOL_BIN}"

# ── 3. Create config directory and copy otel-config.yaml ──────────────────
CONFIG_DIR="${HOME}/.config/otelcol"
CONFIG_FILE="${CONFIG_DIR}/otel-config.yaml"

info "Creating config directory: ${CONFIG_DIR}"
mkdir -p "${CONFIG_DIR}"

info "Copying otel-config.yaml → ${CONFIG_FILE}"
cp "${OBSERVABILITY_DIR}/otel-config.yaml" "${CONFIG_FILE}"
chmod 600 "${CONFIG_FILE}"   # restrict access (contains env var references to secrets)

# ── 4. Create log directory ────────────────────────────────────────────────
LOG_DIR="${HOME}/Library/Logs/otelcol"
info "Creating log directory: ${LOG_DIR}"
mkdir -p "${LOG_DIR}"

# ── 5. Install launchd plist ───────────────────────────────────────────────
PLIST_SRC="${OBSERVABILITY_DIR}/launchd/com.otelcol.agent.plist"
PLIST_DEST="${HOME}/Library/LaunchAgents/com.otelcol.agent.plist"

info "Generating launchd plist → ${PLIST_DEST}"

# Substitute placeholder tokens in the plist template
sed \
  -e "s|/opt/homebrew/bin/otelcol-contrib|${OTELCOL_BIN}|g" \
  -e "s|/Users/YOUR_USERNAME/.config/otelcol/otel-config.yaml|${CONFIG_FILE}|g" \
  -e "s|/Users/YOUR_USERNAME/Library/Logs/otelcol/otelcol.log|${LOG_DIR}/otelcol.log|g" \
  -e "s|<string>/Users/YOUR_USERNAME</string>|<string>${HOME}</string>|g" \
  -e "s|<string>ai-demo-agent</string>|<string>${OTEL_SERVICE_NAME}</string>|" \
  -e "s|<string>dev</string>|<string>${OTEL_ENV}</string>|" \
  -e "s|<string>https://REPLACE_ME.eastus2.kusto.windows.net</string>|<string>${ADX_CLUSTER_URI}</string>|" \
  -e "s|<key>ADX_DATABASE</key>.*$||; /ADX_DATABASE/{n; s|.*|        <string>${ADX_DATABASE}</string>|;}" \
  "${PLIST_SRC}" > "${PLIST_DEST}"

# Inject the remaining secrets via a Python one-liner for reliable XML manipulation
python3 - <<PYEOF
import plistlib, os

path = os.path.expanduser("${PLIST_DEST}")
with open(path, "rb") as f:
    pl = plistlib.load(f)

env = pl.setdefault("EnvironmentVariables", {})
env["ADX_CLUSTER_URI"]       = "${ADX_CLUSTER_URI}"
env["ADX_DATABASE"]          = "${ADX_DATABASE}"
env["ADX_CLIENT_ID"]         = "${ADX_CLIENT_ID}"
env["ADX_CLIENT_SECRET"]     = "${ADX_CLIENT_SECRET}"
env["ADX_TENANT_ID"]         = "${ADX_TENANT_ID}"
env["AMP_REMOTE_WRITE_URL"]  = "${AMP_REMOTE_WRITE_URL}"
env["AMP_CLIENT_ID"]         = "${AMP_CLIENT_ID}"
env["AMP_CLIENT_SECRET"]     = "${AMP_CLIENT_SECRET}"
env["AMP_TENANT_ID"]         = "${AMP_TENANT_ID}"
env["OTEL_SERVICE_NAME"]     = "${OTEL_SERVICE_NAME}"
env["OTEL_ENV"]              = "${OTEL_ENV}"

with open(path, "wb") as f:
    plistlib.dump(pl, f, fmt=plistlib.FMT_XML)
print("  plist secrets written.")
PYEOF

chmod 600 "${PLIST_DEST}"   # restrict access (contains secrets)

# ── 6. Load the launchd agent ─────────────────────────────────────────────
info "Loading launchd agent…"
# Unload first in case a previous version is running
launchctl unload "${PLIST_DEST}" 2>/dev/null || true
launchctl load "${PLIST_DEST}"

# ── 7. Verify the collector is running ────────────────────────────────────
info "Waiting for health-check endpoint (http://localhost:13133)…"
for i in $(seq 1 15); do
  if curl -sf http://localhost:13133/ &>/dev/null; then
    echo ""
    info "✅  OTel Collector is running!"
    break
  fi
  echo -n "."
  sleep 2
done

if ! curl -sf http://localhost:13133/ &>/dev/null; then
  warn "Health check did not respond within 30 seconds."
  warn "Check logs: tail -f ${LOG_DIR}/otelcol.log"
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "  Config file : ${CONFIG_FILE}"
echo "  Plist file  : ${PLIST_DEST}"
echo "  Logs        : ${LOG_DIR}/otelcol.log"
echo "  Health check: http://localhost:13133"
echo "  Metrics     : http://localhost:8888/metrics"
echo ""
echo "  Manage the agent:"
echo "    Start : launchctl load   ${PLIST_DEST}"
echo "    Stop  : launchctl unload ${PLIST_DEST}"
echo "    Status: launchctl list | grep otelcol"
echo ""
echo "  Send test spans to your agent code:"
echo "    export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318"
echo ""
