#!/usr/bin/env bash
# ============================================================
# FIX-R EC2 — Server Status Check
# Run: bash status.sh
# ============================================================

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

check() {
  local name="$1"; local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC}  $name"
  else
    echo -e "  ${RED}✗${NC}  $name"
  fi
}

echo ""
echo "FIX-R EC2 AI Server — Status"
echo "=============================="
check "Ollama service"      "systemctl is-active --quiet ollama"
check "ngrok tunnel"        "systemctl is-active --quiet fixr-ngrok"
check "Ollama reachable"    "curl -sf http://localhost:11434/api/tags -H 'Authorization: Bearer $(cat /etc/fixr/api.key 2>/dev/null)'"
check "ngrok local API"     "curl -sf http://localhost:4040/api/tunnels"

echo ""
echo "Installed models:"
ollama list 2>/dev/null || echo "  (ollama not reachable)"

echo ""
API_KEY_FILE="/etc/fixr/api.key"
if [[ -f "$API_KEY_FILE" ]]; then
  API_KEY=$(cat "$API_KEY_FILE")
  # Try to get current URL from ngrok
  PUBLIC_URL=$(curl -sf http://localhost:4040/api/tunnels \
    | grep -oP '"public_url":"https://[^"]+' \
    | head -1 \
    | sed 's/"public_url":"//') || PUBLIC_URL="(ngrok not running)"
  echo "Public URL : $PUBLIC_URL"
  echo "API Key    : $API_KEY"
else
  echo -e "${YELLOW}No API key found — run setup.sh first.${NC}"
fi
echo ""
