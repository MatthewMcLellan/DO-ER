#!/usr/bin/env bash
# ============================================================
# FIX-R EC2 — Model Management Helper
# Usage: sudo bash add-model.sh [model-name]
# Example: sudo bash add-model.sh llama3.1:8b
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

POPULAR_MODELS=(
  "llama3.2          ~2GB   Fast, good for general chat"
  "llama3.1:8b       ~5GB   High quality, needs >=8GB RAM"
  "mistral           ~4GB   Strong reasoning"
  "mistral-nemo      ~7GB   Better reasoning"
  "phi3              ~2GB   Fast, Microsoft model"
  "gemma2:2b         ~2GB   Google, very fast"
  "qwen2.5:7b        ~5GB   Excellent coding + chat"
  "deepseek-r1:7b    ~5GB   Strong reasoning chains"
)

if [[ "${1:-}" == "" ]]; then
  echo -e "${YELLOW}Available popular models:${NC}"
  echo ""
  for m in "${POPULAR_MODELS[@]}"; do
    echo "  $m"
  done
  echo ""
  read -r -p "Enter model name to pull: " MODEL_NAME
else
  MODEL_NAME="$1"
fi

echo -e "${GREEN}Pulling $MODEL_NAME...${NC}"
ollama pull "$MODEL_NAME"

echo ""
echo -e "${GREEN}Done! Model '$MODEL_NAME' is ready.${NC}"
echo ""
echo "Update your FIX-R server config Model field to: $MODEL_NAME"
echo ""
echo "Currently installed models:"
ollama list
