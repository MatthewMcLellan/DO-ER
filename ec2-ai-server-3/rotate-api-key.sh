#!/usr/bin/env bash
# ============================================================
# FIX-R EC2 — Rotate API Key (ngrok edition)
# Generates a new key and reconfigures Ollama automatically.
# Run: sudo bash rotate-api-key.sh
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash rotate-api-key.sh"; exit 1; }

API_KEY_FILE="/etc/fixr/api.key"
OLLAMA_ENV_FILE="/etc/systemd/system/ollama.service.d/override.conf"

NEW_KEY="fixr-$(openssl rand -hex 24)"
echo "$NEW_KEY" > "$API_KEY_FILE"
chmod 600 "$API_KEY_FILE"

# Update Ollama service override
if [[ -f "$OLLAMA_ENV_FILE" ]]; then
  sed -i "s/OLLAMA_API_KEYS=.*/OLLAMA_API_KEYS=${NEW_KEY}/" "$OLLAMA_ENV_FILE"
  systemctl daemon-reload
  systemctl restart ollama
  sleep 2
  echo -e "${GREEN}✓ API key rotated and Ollama restarted.${NC}"
else
  echo "Warning: Ollama override file not found. Update OLLAMA_API_KEYS manually."
fi

echo ""
echo "New API Key: $NEW_KEY"
echo ""
echo "Update this in FIX-R: Admin → Servers → Edit → API Key"
