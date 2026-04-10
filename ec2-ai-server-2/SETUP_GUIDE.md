# FIX-R EC2 AI Server — Setup Guide (ngrok)

This guide sets up an EC2 instance running Ollama (the AI inference engine),
exposed publicly via an ngrok tunnel. No Nginx, no SSL certificates, no firewall
config required — ngrok handles all of that.

---

## What You'll End Up With

```
FIX-R  ──HTTPS──▶  ngrok tunnel  ──▶  EC2 (Ollama on port 11434)
```

- Your EC2 runs Ollama locally on port 11434
- ngrok creates a secure `https://your-name.ngrok-free.app` public URL
- FIX-R sends chat requests to that URL with your API key

---

## 1. Create a Free ngrok Account

Go to **[https://dashboard.ngrok.com](https://dashboard.ngrok.com)** and sign up.

You'll need two things from the dashboard:
- **Auth Token** — Dashboard → Your Authtoken → Copy
- **Static Domain** — Dashboard → Domains → Create Domain (one free domain per account)

The static domain keeps your URL the same across restarts.
Without it, the URL changes every time ngrok restarts.

---

## 2. Launch an EC2 Instance

### Recommended Instance Types

| Use Case | Instance | RAM | Est. Cost |
|---|---|---|---|
| Light testing | `t3.large` | 8 GB | ~$0.08/hr |
| General chat | `t3.xlarge` | 16 GB | ~$0.17/hr |
| Better quality models | `m5.2xlarge` | 32 GB | ~$0.38/hr |
| GPU (fastest) | `g4dn.xlarge` | 16 GB + T4 GPU | ~$0.53/hr |

**AMI:** Ubuntu Server 22.04 LTS (x86_64)

**Storage:** At least 30 GB root volume. Models are 2–7 GB each, so 50 GB is comfortable.

### Security Group — Inbound Rules

You only need **one rule**:

| Port | Protocol | Source |
|---|---|---|
| 22 | TCP | Your IP only (for SSH) |

That's it. ngrok creates the public-facing tunnel — no other ports need to be open.

---

## 3. Connect via SSH

```bash
ssh -i your-key.pem ubuntu@<EC2-PUBLIC-IP>
```

---

## 4. Copy and Run the Setup Script

From your local machine, copy the files to EC2:

```bash
scp -i your-key.pem setup.sh add-model.sh status.sh rotate-api-key.sh \
  ubuntu@<EC2-PUBLIC-IP>:~/
```

On the EC2 instance, run the setup:

```bash
sudo bash setup.sh
```

The script will:
1. Install **Ollama** and start it on `localhost:11434`
2. Generate a random **API key** and configure Ollama to require it
3. Install **ngrok** and connect your auth token
4. Create a **systemd service** so ngrok restarts automatically on reboot
5. Optionally pull the `llama3.2` model (~2 GB)
6. Print your **public URL** and **API key**

When prompted, paste your ngrok auth token and static domain.

---

## 5. Verify It's Working

After setup, run:

```bash
bash status.sh
```

Or test the endpoint manually:

```bash
# Replace with your actual URL and API key
curl https://your-name.ngrok-free.app/v1/chat/completions \
  -H "Authorization: Bearer fixr-yourkeyhere" \
  -H "Content-Type: application/json" \
  -d '{"model":"llama3.2","messages":[{"role":"user","content":"Hello!"}]}'
```

You should get a JSON response with the AI's reply.

---

## 6. Add to FIX-R

1. Log in to your FIX-R app as admin
2. Go to **Admin → Servers**
3. Click **Add Server** and fill in:

| Field | Value |
|---|---|
| Name | `EC2 AI Server` |
| Base URL | `https://your-name.ngrok-free.app` |
| Model | `llama3.2` |
| API Key | (printed at end of setup.sh) |

4. Optionally set as **default server**, then save.

FIX-R will now route chat requests through your EC2 instance.

---

## 7. Ongoing Management

### Check status
```bash
bash status.sh
```

### Pull a different model
```bash
sudo bash add-model.sh
# or directly:
sudo ollama pull llama3.1:8b
```

### Rotate your API key
```bash
sudo bash rotate-api-key.sh
```
Then update the API Key in FIX-R Admin → Servers.

### View logs
```bash
# Ollama logs
journalctl -u ollama -f

# ngrok tunnel logs
journalctl -u fixr-ngrok -f

# Get current public URL (if not using static domain)
curl -s http://localhost:4040/api/tunnels | grep -o '"public_url":"[^"]*' | head -1
```

### Restart services
```bash
sudo systemctl restart ollama
sudo systemctl restart fixr-ngrok
```

---

## Model Recommendations

| Instance RAM | Model | Size | Notes |
|---|---|---|---|
| 8 GB | `phi3`, `gemma2:2b` | ~2 GB | Very fast |
| 16 GB | `llama3.2`, `mistral` | 2–4 GB | Good quality |
| 32 GB | `llama3.1:8b`, `qwen2.5:7b` | ~5 GB | High quality |
| GPU | `llama3.1:8b`, `mistral-nemo` | ~5–7 GB | Fast + quality |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| ngrok URL not showing | `curl http://localhost:4040/api/tunnels` |
| `401 Unauthorized` | Check API key matches `/etc/fixr/api.key` |
| Ollama not running | `sudo systemctl restart ollama` |
| ngrok disconnected | `sudo systemctl restart fixr-ngrok` |
| Model not found | Run `ollama list` to see installed models |
| Slow responses | Try a smaller model or upgrade to a GPU instance |
| URL changes on restart | Set up a free static domain on ngrok dashboard |
