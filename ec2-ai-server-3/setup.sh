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

# ── Load config.env if present ────────────────────────────────
CONFIG_FILE="$(dirname "$0")/config.env"
if [[ -f "$CONFIG_FILE" ]]; then
  info "Loading config.env..."
  set -o allexport
  source "$CONFIG_FILE"
  set +o allexport
fi

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

# ── 3. API key ────────────────────────────────────────────────
mkdir -p /etc/fixr
API_KEY_FILE="/etc/fixr/api.key"

if [[ -n "${API_KEY:-}" ]]; then
  # Use key from config.env
  echo "$API_KEY" > "$API_KEY_FILE"
  chmod 600 "$API_KEY_FILE"
  info "Using API key from config.env."
elif [[ -f "$API_KEY_FILE" ]]; then
  API_KEY=$(cat "$API_KEY_FILE")
  warn "Existing API key found, reusing."
else
  API_KEY="fixr-$(openssl rand -hex 24)"
  echo "$API_KEY" > "$API_KEY_FILE"
  chmod 600 "$API_KEY_FILE"
  info "Generated new API key."
fi

API_KEY=$(cat "$API_KEY_FILE")

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

# ── 5. ngrok auth token ───────────────────────────────────────
if [[ -z "${NGROK_AUTH_TOKEN:-}" ]]; then
  echo ""
  echo -e "${YELLOW}============================================================"
  echo " ngrok Auth Token Required"
  echo " Sign up free at: https://dashboard.ngrok.com"
  echo " Then: Dashboard → Your Authtoken → Copy"
  echo " (Or add it to config.env and re-run)"
  echo "============================================================${NC}"
  read -r -p "Paste your ngrok authtoken: " NGROK_AUTH_TOKEN
fi

ngrok config add-authtoken "$NGROK_AUTH_TOKEN"
info "ngrok auth token configured."

# ── 6. Static domain ──────────────────────────────────────────
if [[ -z "${NGROK_STATIC_DOMAIN:-}" ]]; then
  echo ""
  echo -e "${YELLOW}============================================================"
  echo " Static Domain (optional — one free domain per ngrok account)"
  echo " Dashboard → Domains → Create Domain"
  echo " Keeps your URL stable across restarts."
  echo " Leave blank for a random URL (changes on restart)."
  echo " (Or add NGROK_STATIC_DOMAIN to config.env and re-run)"
  echo "============================================================${NC}"
  read -r -p "Enter static domain or press Enter to skip: " NGROK_STATIC_DOMAIN
fi

# ── 7. ngrok systemd service ──────────────────────────────────
NGROK_CMD="ngrok http 11434 --log=stdout"
if [[ -n "${NGROK_STATIC_DOMAIN:-}" ]]; then
  NGROK_CMD="ngrok http 11434 --domain=${NGROK_STATIC_DOMAIN} --log=stdout"
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
if [[ -n "${NGROK_STATIC_DOMAIN:-}" ]]; then
  PUBLIC_URL="https://${NGROK_STATIC_DOMAIN}"
else
  sleep 3
  PUBLIC_URL=$(curl -sf http://localhost:4040/api/tunnels \
    | grep -oP '"public_url":"https://[^"]+' \
    | head -1 \
    | sed 's/"public_url":"//') \
    || PUBLIC_URL="(run: curl http://localhost:4040/api/tunnels)"
fi

# ── 9. Model pull ─────────────────────────────────────────────
PULL="${DEFAULT_MODEL:-}"
if [[ -z "$PULL" ]]; then
  echo ""
  echo -e "${YELLOW}============================================================"
  echo " Pull a model now? (leave blank to skip)"
  echo " Options: llama3.2, phi3, mistral, llama3.1:8b, qwen2.5:7b"
  echo " (Or set DEFAULT_MODEL in config.env and re-run)"
  echo "============================================================${NC}"
  read -r -p "Model to pull [llama3.2]: " PULL
  PULL="${PULL:-llama3.2}"
fi

if [[ "$PULL" != "none" && "$PULL" != "skip" && -n "$PULL" ]]; then
  info "Pulling $PULL..."
  OLLAMA_API_KEY="$API_KEY" ollama pull "$PULL"
  info "Model ready: $PULL"
fi

# ── 10. Summary ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}============================================================"
echo " ✓  FIX-R EC2 AI Server setup complete!"
echo "============================================================${NC}"
echo ""
echo "  Public URL : ${PUBLIC_URL}"
echo "  API Key    : ${API_KEY}"
echo "  Model      : ${PULL:-llama3.2}"
echo ""
echo "  Quick test:"
echo "    curl ${PUBLIC_URL}/v1/chat/completions \\"
echo "      -H 'Authorization: Bearer ${API_KEY}' \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"model\":\"${PULL:-llama3.2}\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}'"
echo ""
echo "  Add to FIX-R → Admin → Servers:"
echo "    Base URL : ${PUBLIC_URL}"
echo "    Model    : ${PULL:-llama3.2}"
echo "    API Key  : ${API_KEY}"
echo ""
echo "  API key saved at: /etc/fixr/api.key"
echo ""
