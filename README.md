# Gaming PC — Alternative Inference Boot Mode

Installs a minimal Ubuntu Server OS onto a **second NVMe drive** in a gaming PC
(Ryzen 9 9800X3D + Sapphire Nitro+ RX 7900 XTX 24 GB).  When booted into this
mode the PC runs a GPU-accelerated inference server — the **Herald** node —
accessible to the work PC on the same local network.  The gaming OS on the
primary drive is untouched.

```
 ┌──────────────────────────────────────────────────┐
 │                  Gaming PC                       │
 │  NVMe  (500GB): Inference Boot OS                │
 │   └─ llama-server (llama.cpp, ROCm, gfx1100)     │
 │   └─ OpenAI-compatible API (:8081, :8080/v1)     │
 │  SATA SSD (500GB): model library, sandbox, backups│
 └─────────────────────┬────────────────────────────┘
                       │ LAN
          ┌────────────▼───────────────────┐
          │  Work PC (Herald / archivist)  │
          │  POST http://inference-pc.local:8080/v1/chat/completions
          └────────────────────────────────┘
```

## Architecture

This node is the **Herald inference endpoint only**.  Secretary, the archivist,
ChromaDB, and the canonical Digital Brain vault live on the work PC and are out
of scope for this repo.

The data-flow is asymmetric:
- The work PC's scaffold **calls in** to the Herald's API.
- The Herald **never reaches out** to the work PC.
- The Herald's one outbound voice is the **Discord bot** — everything else is
  blocked by default-deny egress rules.

---

## What you get

| Feature | Detail |
|---|---|
| OS | Ubuntu Server 24.04 LTS (headless) |
| Inference engine | [llama.cpp](https://github.com/ggml-org/llama.cpp) — built from source |
| GPU backend | AMD ROCm (HIP, gfx1100) + Vulkan side-build for benchmarking |
| API | OpenAI-compatible `/v1/chat/completions`, `/v1/models` |
| Model format | GGUF (downloaded via `huggingface-cli`) |
| Discovery | mDNS — `inference-pc.local` |
| Remote access | SSH |
| Network | Default-deny egress; Discord API allowlisted; inbound restricted to LAN |
| Scratch vault | Disposable session memory on NVMe (not backed up, not canonical) |
| Sandbox | Ring-fenced write/execute dir for model-generated code (SATA SSD) |
| Wake-on-LAN | Power on remotely from gaming OS |

---

## Hardware targets

| Component | Spec |
|---|---|
| CPU | Ryzen 9 9800X3D |
| GPU | Sapphire Nitro+ RX 7900 XTX 24 GB (gfx1100, RDNA3) |
| NVMe | 500 GB — inference OS + active model |
| SATA SSD | 500 GB — model library, sandbox, backups |

---

## Prerequisites

- A **second NVMe slot** (for the inference OS drive)
- A Ubuntu 22.04 or 24.04 **live USB** to run the installer from
- Both drives must already be physically installed

---

## Single-file install (one file on a USB)

If you want the whole project as **one file** — to drop on a USB stick or hand
to a local Claude Code session — build the self-extracting installer:

```bash
./install/build-installer.sh        # -> ./inference-boot-installer.sh
```

`inference-boot-installer.sh` embeds the entire repo (all install scripts,
configs, and client/scripts) as a compressed payload. Copy that single file
anywhere — no git clone or other files required.

```bash
./inference-boot-installer.sh --help               # show usage
./inference-boot-installer.sh --verify             # check the embedded payload checksum
./inference-boot-installer.sh --extract            # unpack to /tmp/inference-boot
sudo ./inference-boot-installer.sh --install /dev/nvme1n1   # unpack + run bootstrap (WIPES that drive)
```

### Pointing local Claude Code at it

On the Ubuntu live USB, hand the single file to a local Claude Code session and
say **"run this installer."** The brief at the top of the file tells Claude to:

1. `--extract` the project to `/tmp/inference-boot`.
2. Help you edit `install/install.conf` (drives, password/SSH key, LAN CIDR, model).
3. `--install /dev/nvmeXnX` to partition, debootstrap, and install GRUB.
4. Reboot into the **InferenceBoot** entry; first boot finishes automatically.

Re-run `build-installer.sh` after changing any file to keep the single file in sync.

---

## Quick start

### 1. Edit configuration

```bash
nano install/install.conf
```

Critical settings to change before running:

| Setting | Action |
|---|---|
| `TARGET_DRIVE` | Verify this is the 500 GB NVMe — **this drive is wiped** |
| `SATA_SSD_DEVICE` | Verify this is the 500 GB SATA SSD |
| `INFERENCE_PASSWORD_HASH` | Generate with `openssl passwd -6 'yourpassword'` |
| `SSH_PUBLIC_KEY` | Paste your public key (recommended over password) |
| `ALLOWED_CIDR` | Set to your actual LAN subnet, e.g. `192.168.1.0/24` |
| `MODEL_REPO` / `MODEL_FILE` | HuggingFace repo + GGUF filename to pre-download |

`GPU_BACKEND` is already set to `amd` and `AMDGPU_TARGETS` to `gfx1100`.

### 2. Boot the live USB

Insert your Ubuntu live USB, boot from it, choose **"Try Ubuntu"**.

### 3. Clone this repo onto the live system

```bash
sudo apt-get install -y git
git clone https://github.com/Smithm231/Pc-alt-ai-mode /tmp/inference-boot
cd /tmp/inference-boot
```

### 4. Identify your drives

```bash
lsblk -d -o NAME,SIZE,MODEL,TRAN
```

Confirm `TARGET_DRIVE` (NVMe) and `SATA_SSD_DEVICE` (SATA) in `install.conf`.

### 5. Run the bootstrap installer

```bash
sudo bash install/00-bootstrap.sh /dev/nvme1n1
```

This partitions and formats the NVMe, bootstraps Ubuntu 24.04, installs GRUB
with an **"InferenceBoot"** entry, and schedules the rest for first boot.
Takes ~5–10 minutes.

### 6. Reboot into Inference Boot

1. Press your BIOS one-time-boot key at POST (**F8**, **F11**, **F12**, or **Del**)
2. Select **"InferenceBoot"**

First boot completes automatically in roughly 20–40 minutes (GPU drivers,
llama.cpp build, model download).  Monitor progress:

```bash
ssh inference@inference-pc.local
sudo journalctl -fu inference-firstboot
```

---

## Using the inference API

```bash
# Check everything is healthy
./scripts/health-check.sh

# List loaded models
./client/list-models.sh

# Chat via curl (OpenAI format, through nginx proxy)
curl http://inference-pc.local:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Llama-3.2-3B-Instruct-Q8_0","messages":[{"role":"user","content":"Hello"}]}'

# Python (OpenAI SDK)
python3 client/examples/python-example.py
```

The API endpoint for the work-PC Herald caller:

```
base_url: http://inference-pc.local:8080/v1
api_key:  not-needed
```

**Caller note:** the current Herald hits the Anthropic API, which is not
OpenAI-shaped.  Repointing it at this endpoint is a real (if small) caller
change — not a pure base-URL swap.  Plan for that on the work-PC side when
migrating Herald.

---

## Model management

Models live on the **SATA SSD** (`/media/sata-ssd/models/`).
The active model is a symlink on the NVMe (`/opt/inference-boot/models/active.gguf`).

```bash
# Download a model to the library
./scripts/pull-model.sh bartowski/Llama-3.1-8B-Instruct-GGUF \
  Llama-3.1-8B-Instruct-Q8_0.gguf

# Download and activate immediately
./scripts/pull-model.sh bartowski/Mistral-7B-Instruct-v0.3-GGUF \
  Mistral-7B-Instruct-v0.3-Q8_0.gguf --activate

# Swap to a model already in the library
./scripts/swap-model.sh Llama-3.1-8B-Instruct-Q8_0.gguf
```

### GPU VRAM guide (7900 XTX, 24 GB)

| Model | Quant | VRAM (approx) |
|---|---|---|
| Llama 3.2 3B | Q8 | ~4 GB |
| Llama 3.1 8B | Q8 | ~9 GB |
| Mistral 7B | Q8 | ~8 GB |
| Gemma 2 9B | Q8 | ~10 GB |
| DeepSeek R1 14B | Q8 | ~16 GB |
| Llama 3.1 70B | Q4 | ~40 GB (exceeds VRAM — split across GPU+CPU) |

---

## Boot behaviour (dual boot)

Both OSes live on separate drives in the one PC. The installer makes the
**inference OS the default boot target** and adds the gaming OS (Windows) to the
GRUB menu:

- **Power on / Wake-on-LAN →** GRUB shows a menu for `GRUB_TIMEOUT_SECONDS`
  (default 10s), then boots **InferenceBoot** automatically. This is what makes
  remote wake land in inference mode with nothing running in Windows.
- **To game →** sit down, power on, and pick **Windows** in the GRUB menu (or
  use your BIOS one-time boot key). It's one keypress.

Don't want inference as the default? Set the gaming drive first in your BIOS
boot order instead — but then remote wake-into-inference won't work.

---

## Remote wake from the Digital Brain

Goal: starting the Digital Brain on the work PC powers the gaming PC on **into
inference mode** and waits until the Herald API is live.

```bash
# Run this from the work PC as part of the Digital Brain startup.
# MAC is printed at first boot and saved at /opt/inference-boot/.mac-address
./client/wake-herald.sh aa:bb:cc:dd:ee:ff
# or via env, for wiring into a startup script:
HERALD_MAC=aa:bb:cc:dd:ee:ff ./client/wake-herald.sh
```

`wake-herald.sh` sends the WoL magic packet, then polls
`http://inference-pc.local:8080/v1/models` until it answers (or times out with
diagnostics). For a bare packet with no wait, use `./scripts/wol-wake.sh <mac>`.

### Prerequisites for waking from *fully off* (one-time setup)

Wake-on-LAN can power the box on, but the firmware and the **last OS that ran**
must leave the NIC armed. Because you normally power off from Windows after
gaming, do all of these once:

**In the BIOS/UEFI:**
- Enable **"Power On By PCIE/PCI"** (a.k.a. *Wake on LAN* / *Resume by PCI-E*).
- Disable **"ErP Ready"** / deep-sleep (it cuts standby power to the NIC).

**In Windows (so a wake works after a gaming session):**
- Disable **Fast Startup** (Control Panel → Power Options → *Choose what the
  power buttons do* → uncheck *Turn on fast startup*). Fast Startup makes
  "shut down" a hybrid state that usually breaks WoL.
- Device Manager → your network adapter → **Power Management**: check *Allow
  this device to wake the computer* and *Only allow a magic packet…*.
- Device Manager → adapter → **Advanced**: set *Wake on Magic Packet* = Enabled.

The inference OS already arms WoL on every boot (`wol.service`, via `ethtool`),
so waking after an inference session works out of the box.

> Note: WoL is layer-2 — the work PC and gaming PC must share the same LAN
> subnet. Across subnets/VLANs you'd need a directed broadcast or a forwarder.

---

## Network and security

### Inbound (allowed)
- SSH from `ALLOWED_CIDR` (default `192.168.1.0/24`)
- llama-server API port from `ALLOWED_CIDR`
- nginx proxy port from `ALLOWED_CIDR`

### Outbound (default deny)
- **Discord API only** (resolved daily by `discord-ips-refresh.timer`)
- DNS (for hostname resolution)
- NTP (time sync)
- Everything else: **blocked**, including the work PC and the internet

### Discord bot token
Stored at `/etc/inference-boot/discord-token` on the inference OS (mode 0600,
root:root).  **Not** in this repo.  Set it after first boot:

```bash
ssh inference@inference-pc.local
sudo bash -c 'echo "your-bot-token" > /etc/inference-boot/discord-token'
sudo chmod 600 /etc/inference-boot/discord-token
sudo chown root:root /etc/inference-boot/discord-token
```

### Sandbox (write/execute ring-fence)
The Herald can write and execute code.  All execution is confined to
`/media/sata-ssd/sandbox/` via a dedicated unprivileged user, systemd
sandboxing directives, and `PrivateNetwork=true`.

```bash
# Run a model-generated script inside the sandbox
./scripts/run-sandbox.sh /media/sata-ssd/sandbox/my-script.py
```

**Honest risk statement:** a model that can write and run arbitrary code can
attempt to escape its sandbox.  The layers in place (confined user, systemd
`ProtectSystem=strict / PrivateNetwork / NoNewPrivileges / ReadWritePaths`,
default-deny egress) make this safe enough for a LAN box under direct human
control.  They are not and cannot be described as total isolation.

---

## Project structure

```
.
├── install/
│   ├── install.conf           ← EDIT THIS FIRST
│   ├── 00-bootstrap.sh        ← Run from live USB
│   ├── 01-base-system.sh      ← Base OS (auto, chroot)
│   ├── 02-gpu-drivers.sh      ← AMD ROCm, gfx1100 verify (auto, first boot)
│   ├── 03-inference-stack.sh  ← Build llama.cpp HIP+Vulkan (auto, first boot)
│   ├── 04-network.sh          ← Firewall, default-deny egress (auto, first boot)
│   ├── 05-storage.sh          ← SATA SSD mount + workspace dirs (auto, first boot)
│   ├── 06-scratch-vault.sh    ← Disposable scratch vault (auto, first boot)
│   ├── 07-sandbox.sh          ← Ring-fenced exec sandbox (auto, first boot)
│   ├── firstboot-run.sh       ← Orchestrates 02–07
│   └── build-installer.sh     ← Pack the whole repo into one self-extracting file
├── config/
│   ├── llama-server.service        ← systemd unit for llama-server
│   ├── sandbox-exec.service        ← systemd sandbox template
│   ├── discord-ips-refresh.service ← Discord IP rule refresh
│   ├── discord-ips-refresh.timer   ← Daily timer
│   ├── nginx-inference.conf        ← OpenAI-compatible proxy
│   ├── sshd_config                 ← SSH hardening
│   ├── avahi-daemon.conf           ← mDNS
│   ├── inference-firstboot.service ← First-boot trigger
│   └── network/
│       └── 10-inference.yaml       ← Netplan DHCP
├── client/
│   ├── connect.sh
│   ├── list-models.sh
│   ├── wake-herald.sh         ← Wake gaming PC into inference + wait for API
│   └── examples/
│       ├── curl-example.sh
│       └── python-example.py
└── scripts/
    ├── health-check.sh
    ├── pull-model.sh           ← HuggingFace GGUF download
    ├── swap-model.sh           ← Switch active model + restart server
    ├── wol-wake.sh
    ├── run-sandbox.sh          ← Execute code in ring-fenced sandbox
    └── update-discord-ips.sh   ← Refresh Discord IP firewall rules
```

---

## Troubleshooting

**gfx1100 not detected after first boot**
```bash
ssh inference@inference-pc.local
rocminfo | grep -i gfx
# If empty: verify HSA_OVERRIDE_GFX_VERSION in install.conf
# Check: journalctl -u llama-server | grep -i gpu
```

**llama.cpp build failed**
```bash
# The CMake flag names can change between releases.
# Check the current flags in the source:
grep -r "GGML_HIP\|GGML_VULKAN\|LLAMA_HIPBLAS" /opt/llama.cpp/CMakeLists.txt
# Then edit 03-inference-stack.sh or rerun with corrected flags.
```

**llama-server not starting**
```bash
systemctl status llama-server
journalctl -u llama-server -n 50
# Common cause: ACTIVE_MODEL_LINK symlink target doesn't exist
ls -la /opt/inference-boot/models/active.gguf
```

**mDNS not resolving on Windows**
Install [Bonjour](https://support.apple.com/downloads/bonjour) or use the
PC's IP address directly (`192.168.x.x`).

**Discord outbound not working**
```bash
# Refresh Discord IP rules manually
sudo /opt/inference-boot/scripts/update-discord-ips.sh
sudo ufw status | grep discord
```
