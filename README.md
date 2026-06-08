# Gaming PC — Alternative Inference Boot Mode

Installs a minimal Ubuntu Server OS onto a **second NVMe drive** in your gaming PC. When booted into this mode the PC runs a GPU-accelerated AI inference server accessible to any device on your local network. Your gaming OS on the primary drive is untouched.

```
 ┌─────────────────────────────────────────────┐
 │             Gaming PC                       │
 │  NVMe 0: Windows / Linux gaming OS  ──────► gaming as normal
 │  NVMe 1: Inference Boot OS          ──────► LAN inference API
 │           └─ Ollama (GPU-accelerated)       │
 │           └─ OpenAI-compatible API          │
 └──────────────────────┬──────────────────────┘
                        │ LAN (mDNS / .local)
          ┌─────────────▼──────────┐
          │  Client PC / device    │
          │  http://inference-pc.local:8080/v1  │
          └────────────────────────┘
```

## What you get

| Feature | Detail |
|---|---|
| OS | Ubuntu Server 24.04 LTS (headless, ~2 GB) |
| Inference | [Ollama](https://ollama.com) — GPU-accelerated, runs locally |
| API | OpenAI-compatible (`/v1/chat/completions`, `/v1/models`) |
| GPU support | NVIDIA (CUDA) and AMD (ROCm) |
| Discovery | mDNS — access as `inference-pc.local` from any LAN device |
| Remote access | SSH + optional Wake-on-LAN |
| Security | UFW firewall, SSH hardening, no root login |

---

## Prerequisites

- A PC with a **second NVMe slot** (or USB 3 NVMe enclosure)
- An NVIDIA (GTX 900+/RTX) or AMD (RX 5000+/RX 6000+/RX 7000+) GPU
- A Ubuntu 22.04 or 24.04 **live USB** to run the installer
- The second NVMe drive (minimum recommended: 256 GB)

---

## Quick start

### 1. Edit configuration

```bash
nano install/install.conf
```

Key settings:

| Setting | Default | Description |
|---|---|---|
| `TARGET_DRIVE` | `/dev/nvme1n1` | **Check this carefully** — this drive will be wiped |
| `HOSTNAME` | `inference-pc` | Resolves as `inference-pc.local` on LAN |
| `GPU_BACKEND` | `nvidia` | `nvidia`, `amd`, or `cpu` |
| `MODELS_TO_PULL` | `llama3.2` | Models downloaded on first boot |
| `SSH_PUBLIC_KEY` | _(empty)_ | Paste your public key for passwordless SSH |

Generate a password hash for `INFERENCE_PASSWORD_HASH`:

```bash
openssl passwd -6 'your-password-here'
```

### 2. Boot the live USB

Insert your Ubuntu live USB, boot from it, and choose **"Try Ubuntu"**.

### 3. Clone this repo onto the live system

```bash
# In the live USB terminal:
sudo apt-get install -y git
git clone https://github.com/Smithm231/Pc-alt-ai-mode /tmp/inference-boot
cd /tmp/inference-boot
```

### 4. Identify your second NVMe

```bash
lsblk -d -o NAME,SIZE,MODEL
```

Make sure `TARGET_DRIVE` in `install.conf` matches the correct drive (e.g. `/dev/nvme1n1`).

### 5. Run the bootstrap installer

```bash
sudo bash install/00-bootstrap.sh /dev/nvme1n1
```

This will:
- Partition and format the target NVMe
- Bootstrap Ubuntu 24.04 onto it
- Install GRUB with an **"InferenceBoot"** entry
- Schedule GPU + inference setup for first boot

The process takes **~5–10 minutes** depending on your internet connection.

### 6. Reboot into Inference Boot

Power off, then:

1. Press your BIOS one-time-boot key at POST (usually **F8**, **F11**, **F12**, or **Del**)
2. Select **"InferenceBoot"** from the boot menu
   - Or set it permanently in BIOS boot order when you want to use inference mode

First boot will automatically install GPU drivers, Ollama, and pull your configured models. This takes **~10–20 minutes**. You can monitor progress:

```bash
# From your gaming PC / another machine on the LAN:
ssh inference@inference-pc.local
sudo journalctl -fu inference-firstboot
```

---

## Using the inference API

Once the server is running, it's accessible from **any device on your LAN**:

### Check what's available

```bash
./scripts/health-check.sh
```

### List loaded models

```bash
./client/list-models.sh
```

### Query the API (curl)

```bash
# OpenAI-compatible (via nginx proxy, port 8080):
curl http://inference-pc.local:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.2",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# Native Ollama API (port 11434):
curl http://inference-pc.local:11434/api/generate \
  -d '{"model": "llama3.2", "prompt": "Hello!"}'
```

### Query the API (Python — OpenAI SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://inference-pc.local:8080/v1",
    api_key="not-needed",
)

response = client.chat.completions.create(
    model="llama3.2",
    messages=[{"role": "user", "content": "Hello!"}],
)
print(response.choices[0].message.content)
```

See `client/examples/` for more.

### Pull additional models

```bash
# On the inference PC:
ollama pull mistral
ollama pull deepseek-r1:14b
ollama pull gemma2:9b

# Or remotely via the pull script:
./scripts/pull-model.sh mistral
```

Popular model sizes as a guide:

| Model | VRAM needed | Quality |
|---|---|---|
| `llama3.2` (3B) | ~3 GB | Fast, lightweight |
| `llama3.1:8b` | ~6 GB | Good balance |
| `mistral` (7B) | ~5 GB | Good balance |
| `gemma2:9b` | ~7 GB | Strong reasoning |
| `deepseek-r1:14b` | ~10 GB | Strong reasoning |
| `llama3.1:70b` | ~48 GB | Near-GPT-4 quality |

---

## Switching between gaming and inference mode

| Method | How |
|---|---|
| **One-time boot** | Press F8/F11/F12/Del at POST → select the OS |
| **BIOS boot order** | Change which drive boots by default in BIOS settings |
| **Wake-on-LAN** | Power on the inference PC remotely from your gaming OS |

### Wake-on-LAN (power on remotely)

Your inference PC's MAC address is saved at `/opt/inference-boot/.mac-address` during first boot.

```bash
# From your gaming OS:
./scripts/wol-wake.sh aa:bb:cc:dd:ee:ff

# Wait ~30 seconds then check:
./scripts/health-check.sh
```

---

## SSH access

```bash
# Interactive shell
./client/connect.sh

# Or directly:
ssh inference@inference-pc.local

# Default credentials (change immediately in install.conf):
# user: inference
# pass: inferenceboot
```

---

## Project structure

```
.
├── install/
│   ├── install.conf          ← EDIT THIS FIRST
│   ├── 00-bootstrap.sh       ← Run from live USB
│   ├── 01-base-system.sh     ← Base OS setup (auto)
│   ├── 02-gpu-drivers.sh     ← GPU driver install (auto, first boot)
│   ├── 03-inference-stack.sh ← Ollama install (auto, first boot)
│   ├── 04-network.sh         ← Firewall + WoL (auto, first boot)
│   └── firstboot-run.sh      ← Orchestrates 02–04 on first boot
├── config/
│   ├── sshd_config           ← SSH hardening
│   ├── avahi-daemon.conf     ← mDNS config
│   ├── nginx-inference.conf  ← OpenAI-compatible reverse proxy
│   ├── inference-firstboot.service ← Systemd first-boot unit
│   └── network/
│       └── 10-inference.yaml ← Netplan (DHCP)
├── client/
│   ├── connect.sh            ← SSH helper
│   ├── list-models.sh        ← List loaded models
│   └── examples/
│       ├── curl-example.sh
│       └── python-example.py
└── scripts/
    ├── health-check.sh       ← Full status check
    ├── pull-model.sh         ← Pull a model remotely
    └── wol-wake.sh           ← Wake-on-LAN sender
```

---

## Troubleshooting

**"Host unreachable" after first boot**
- Wait a full 30 minutes — GPU drivers and model download take time
- Check the host's IP with your router's DHCP table if mDNS isn't working
- Try `ssh inference@<IP-address>` instead of `inference-pc.local`

**mDNS not resolving on Windows**
- Install [Bonjour](https://support.apple.com/downloads/bonjour) or use the PC's IP address directly

**NVIDIA: `nvidia-smi` not found after reboot**
- First reboot after driver install: `sudo reboot` from the inference PC
- Check: `lsmod | grep nvidia`

**AMD: GPU not detected by Ollama**
- Verify ROCm: `rocm-smi --showid`
- Check group membership: `groups inference` (should include `render` and `video`)

**Ollama not starting**
- `sudo systemctl status ollama`
- `sudo journalctl -u ollama -n 50`

**Out of VRAM**
- Use a smaller model (e.g. `llama3.2` instead of `llama3.1:70b`)
- Close other GPU-using applications

---

## Security notes

- The inference API has **no authentication** by default — it's intended for trusted LAN use
- Restrict `ALLOWED_CIDR` in `install.conf` to your subnet (e.g. `192.168.1.0/24`)
- Change the default SSH password or use key-based auth
- Do not expose ports 11434 or 8080 to the internet without adding auth
