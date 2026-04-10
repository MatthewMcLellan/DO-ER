#!/usr/bin/env bash
# ============================================================
# FIX-R EC2 AI Server — Setup (ngrok edition)
# Ubuntu 22.04 LTS
# Run as root or with sudo: sudo bash setup.sh
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Run as root: sudo bash setup.sh"

info "FIX-R EC2 AI Server (ngrok) setup starting..."

# ── 1. System packages ────────────────────────────────────────
info "Updating system packages..."
apt-get update -qq
apt-get install -y -qq curl wget openssl

# ── 2. Install Ollama ─────────────────────────────────────────
if command -v ollama &>/dev/null; then
  warn "Ollama already installed, skipping."
else
  info "Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
fi

systemctl enable ollama
systemctl start ollama
sleep 3
info "Ollama is running."

# ── 3. Generate API key ───────────────────────────────────────
mkdir -p /etc/fixr
API_KEY_FILE="/etc/fixr/api.key"

if [[ -f "$API_KEY_FILE" ]]; then
  API_KEY=$(cat "$API_KEY_FILE")
  warn "Existing API key found, reusing."
else
  API_KEY="fixr-$(openssl rand -hex 24)"
  echo "$API_KEY" > "$API_KEY_FILE"
  chmod 600 "$API_KEY_FILE"
  info "Generated new API key."
fi

# Configure Ollama to require this API key
OLLAMA_ENV_FILE="/etc/systemd/system/ollama.service.d/override.conf"
mkdir -p "$(dirname "$OLLAMA_ENV_FILE")"
cat > "$OLLAMA_ENV_FILE" << EOF
[Service]
Environment="OLLAMA_API_KEYS=${API_KEY}"
Environment="OLLAMA_HOST=127.0.0.1:11434"
EOF

systemctl daemon-reload
systemctl restart ollama
sleep 3
info "Ollama configured with API key auth."

# ── 4. Install ngrok ──────────────────────────────────────────
if command -v ngrok &>/dev/null; then
  warn "ngrok already installed, skipping."
else
  info "Installing ngrok..."
  curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
    | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
  echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
    | tee /etc/apt/sources.list.d/ngrok.list
  apt-get update -qq
  apt-get install -y -qq ngrok
fi

# ── 5. Configure ngrok auth token ─────────────────────────────
echo ""
echo -e "${YELLOW}============================================================"
echo " ngrok Auth Token Required"
echo " Sign up free at: https://dashboard.ngrok.com"
echo " Then go to: Dashboard → Your Authtoken"
echo "============================================================${NC}"
read -r -p "Paste your ngrok authtoken: " NGROK_TOKEN

ngrok config add-authtoken "$NGROK_TOKEN"
info "ngrok auth token configured."

# ── 6. Static domain (optional) ───────────────────────────────
echo ""
echo -e "${YELLOW}============================================================"
echo " Static Domain (recommended — free on ngrok)"
echo " Go to: Dashboard → Domains → Create Domain"
echo " This keeps your URL the same across restarts."
echo " Leave blank to use a random URL (changes on restart)."
echo "============================================================${NC}"
read -r -p "Enter your static domain (e.g. abc-xyz.ngrok-free.app) or press Enter to skip: " STATIC_DOMAIN

# ── 7. Create ngrok systemd service ──────────────────────────
NGROK_CMD="ngrok http 11434 --log=stdout"
if [[ -n "${STATIC_DOMAIN:-}" ]]; then
  NGROK_CMD="ngrok http 11434 --domain=${STATIC_DOMAIN} --log=stdout"
fi

cat > /etc/systemd/system/fixr-ngrok.service << EOF
[Unit]
Description=FIX-R ngrok tunnel for Ollama
After=network.target ollama.service
Wants=ollama.service

[Service]
ExecStart=${NGROK_CMD}
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable fixr-ngrok
systemctl start fixr-ngrok
sleep 5

# ── 8. Get public URL ──────────────────────────────────────────
if [[ -n "${STATIC_DOMAIN:-}" ]]; then
  PUBLIC_URL="https://${STATIC_DOMAIN}"
else
  # Pull URL from ngrok local API
  sleep 3
  PUBLIC_URL=$(curl -sf http://localhost:4040/api/tunnels \
    | grep -oP '"public_url":"https://[^"]+' \
    | head -1 \
    | sed 's/"public_url":"//') || PUBLIC_URL="<run: curl http://localhost:4040/api/tunnels to get URL>"
fi

# ── 9. Optional model pull ─────────────────────────────────────
echo ""
echo -e "${YELLOW}============================================================"
echo " Pull a model now?"
echo " Recommended: llama3.2 (2GB), phi3 (2GB), mistral (4GB)"
echo "============================================================${NC}"
read -r -p "Pull llama3.2 now? [Y/n]: " PULL_MODEL
if [[ "${PULL_MODEL:-Y}" =~ ^[Yy]$ ]]; then
  info "Pulling llama3.2..."
  OLLAMA_API_KEY="$API_KEY" ollama pull llama3.2
  info "Model ready."
fi

# ── 10. Summary ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}============================================================"
echo " ✓  FIX-R EC2 AI Server setup complete!"
echo "============================================================${NC}"
echo ""
echo "  Public URL : ${PUBLIC_URL}"
echo "  API Key    : ${API_KEY}"
echo "  Model      : llama3.2  (or whichever you pulled)"
echo ""
echo "  Test:"
echo "    curl ${PUBLIC_URL}/v1/chat/completions \\"
echo "      -H 'Authorization: Bearer ${API_KEY}' \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"model\":\"llama3.2\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}'"
echo ""
echo "  Add to FIX-R Admin → Servers:"
echo "    Base URL : ${PUBLIC_URL}"
echo "    Model    : llama3.2"
echo "    API Key  : ${API_KEY}"
echo ""
echo "  API key saved at: /etc/fixr/api.key"
echo ""
