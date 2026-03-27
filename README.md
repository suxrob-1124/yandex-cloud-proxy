# Xray VLESS+Reality Infrastructure

Infrastructure as code for deploying a private proxy server.

**Stack:** Terraform (YC infrastructure) + Ansible (configuration) + Makefile (DX)

---

## How It Works

```
Client (Russia)
    │
    │ VLESS + Reality (TCP, disguised as HTTPS to apple.com)
    │ TSPU cannot detect this is a proxy
    ▼
Xray Server (YC, Russian IP — in carrier whitelist)
    │
    ├── ChatGPT, Claude, Gemini → Chain proxy → VPS Sweden → Internet
    │     ✓ Clean dedicated IP (AI services don't ban it)
    │
    ├── YouTube, Instagram, Meet, Zoom, Discord → WARP → Cloudflare → Internet
    │     ✓ Non-Russian IP (bypasses geo-blocks)
    │     ✓ UDP works (video calls without lag)
    │
    ├── Russian websites (if ru_direct: true) → Direct
    │
    └── Everything else → Direct
```

**Tested:** works on LTE (mobile carrier whitelists) — the server IP is whitelisted (`158.160.106.0/23`).

Users are added via `ansible/vars/users.yml` → `make sync-users`.
Client config is imported into V2Box / Hiddify with a single tap or QR code (`make show-qr`).

---

## Yandex Cloud Pricing

| Resource | Price |
|----------|-------|
| VM 2 vCPU + 2GB RAM (standard-v3) | ~₽1,390/mo |
| Disk 20GB SSD | included in VM cost |
| Static IP (attached to running VM) | ₽0.26/hr (~₽190/mo) |
| Static IP (without VM — after `make destroy`) | ₽0.60/hr (~₽435/mo) |
| Inbound traffic | free |
| Outbound traffic up to 100 GB/mo | free |
| Outbound above 100 GB/mo | ₽1.68/GB |
| Object Storage (Terraform state) | < ₽1/mo |

**Example by number of users (~100 GB/mo each):**

```
3 users (~300 GB/mo):
  VM + IP:   ₽1,580
  Traffic:   (300 - 100) × ₽1.68 = ₽336
  Total:     ~₽1,916/mo (~$20)

10 users (~1 TB/mo):
  VM + IP:   ₽1,580
  Traffic:   (1000 - 100) × ₽1.68 = ₽1,512
  Total:     ~₽3,092/mo (~$32)

30 users (~3 TB/mo):
  VM + IP:   ₽1,580
  Traffic:   (3000 - 100) × ₽1.68 = ₽4,872
  Total:     ~₽6,452/mo (~$66)
```

> Current prices: [cloud.yandex.ru/ru/docs/vpc/pricing](https://cloud.yandex.ru/ru/docs/vpc/pricing)

---

## Quick Start (deploy from scratch)

### 1. Install dependencies

```bash
# macOS
brew install terraform ansible

# Verify everything is installed
make check-deps
```

### 2. Install YC CLI

```bash
curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh -o /tmp/yc-install.sh
bash /tmp/yc-install.sh
source ~/.bashrc   # or restart the terminal

yc init            # authenticate via browser
```

### 3. Create a service account

```bash
# Get the folder ID
yc resource-manager folder list
#   → note the ID (e.g. b1gp6bumbc5prb8mpch2)

# Create a service account
yc iam service-account create --name xray-terraform

# Grant editor role
yc resource-manager folder add-access-binding \
  --id <FOLDER_ID> \
  --role editor \
  --service-account-name xray-terraform

# Create a key for Terraform (does not expire)
yc iam key create \
  --service-account-name xray-terraform \
  --output terraform/key.json

# Create a static access key for S3 backend (state)
yc iam access-key create --service-account-name xray-terraform
#   → note the key_id and secret (secret is shown ONCE!)
```

### 4. Create a bucket for Terraform state

```bash
yc storage bucket create --name xray-tfstate
```

### 5. Create an SSH key (if you don't have one)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/xray-infra -C "xray-infra"
```

### 6. Fill in the configs

```bash
# Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
nano terraform/terraform.tfvars
```

```hcl
yc_service_account_key_file = "key.json"
yc_cloud_id  = "your_cloud_id"       # yc resource-manager cloud list
yc_folder_id = "your_folder_id"      # yc resource-manager folder list
```

```bash
# S3 backend secrets
cp terraform/backend.conf.example terraform/backend.conf
nano terraform/backend.conf
```

```hcl
access_key = "key_id from step 3"
secret_key = "secret from step 3"
```

### 7. Add users

```bash
nano ansible/vars/users.yml
```

```yaml
users:
  - name:      sukhrob
    ru_direct: true
    created:   "2026-03-25"
    active:    true
```

### 8. Deploy

```bash
make deploy
```

Done. The output will contain subscription links. To view them later: `make show-users`

---

## User Management

All users are stored in a single file:

```bash
nano ansible/vars/users.yml
```

```yaml
users:
  - name:      ivan        # Latin characters, no spaces
    ru_direct: true        # true = Russian sites accessed directly
    created:   "2025-01-15"
    active:    true        # false = disable without deleting

  - name:      maria
    ru_direct: false       # false = all traffic goes through the proxy
    created:   "2025-01-16"
    active:    true
```

Apply changes:

```bash
git add ansible/vars/users.yml
git commit -m "add user ivan"
make sync-users
```

The Ansible output will contain links for all active users:

```
ivan:  https://51.250.x.x:8443/sub/<token>/ivan.json
maria: https://51.250.x.x:8443/sub/<token>/maria.json
```

> The token is generated once during installation and protects the endpoint from brute-force attacks.
> View links: `make show-users`

---

## Commands

```bash
make deploy        # Full deploy from scratch (Terraform + Ansible)
make sync-users    # Synchronize users
make show-users    # Show subscription and VLESS links
make status        # Status of all servers
make logs          # Xray logs
make rotate-keys   # Rotate Reality keys
make rotate-warp   # Re-register WARP credentials
make ssh           # SSH connection
make plan          # View Terraform change plan
make destroy       # Delete VM and network (IP is preserved)
make destroy-all   # ⚠️ Delete EVERYTHING including IP
make help          # All commands
```

---

## How a Client Adds a Config

**V2Box (iOS / macOS):**
```
+ → Import from URL → paste the link from make show-users
```

**Hiddify (all platforms):**
```
+ → Import from clipboard → paste subscription URL
```

**Update config** (after routing changes or key rotation):
```
V2Box → long tap on config → Update
```

---

## Project Structure

```
xray-infra/
├── Makefile                         ← single entry point
├── .gitignore
│
├── terraform/                       ← infrastructure layer
│   ├── versions.tf                  # Terraform and provider versions
│   ├── variables.tf                 # all parameters with descriptions
│   ├── main.tf                      # network, IP, VM, firewall
│   ├── outputs.tf                   # IP and parameters for Ansible
│   ├── terraform.tfvars.example     # variables template
│   └── backend.conf.example        # S3 backend secrets template
│
├── ansible/                         ← configuration layer
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── hosts.yml                # generated from Terraform
│   │   └── group_vars/
│   │       └── all.yml              # global variables
│   ├── vars/
│   │   └── users.yml                # ← USER LIST
│   ├── roles/
│   │   ├── common/                  # basic Ubuntu setup, fail2ban, auto-updates
│   │   ├── firewall/                # ufw rules
│   │   ├── warp/                    # Cloudflare WARP registration (WireGuard credentials)
│   │   ├── xray/                    # Xray: installation, keys, config
│   │   │   └── tasks/
│   │   │       ├── main.yml         # installation and initial setup
│   │   │       ├── sync-users.yml   # user UUID synchronization (shared logic)
│   │   │       └── gen-client-configs.yml  # config generation (shared logic)
│   │   └── nginx/                   # serving client configs
│   └── playbooks/
│       ├── install.yml              # full installation
│       ├── users.yml                # user synchronization
│       ├── status.yml               # health check
│       ├── rotate_keys.yml          # Reality key rotation
│       └── rotate_warp.yml          # WARP credentials rotation
│
├── scripts/
│   └── gen_inventory.py             # Terraform output → Ansible inventory
│
└── docs/
    └── runbook.md                   # what to do if something breaks
```

---

## Scaling

Adding a second server is a one-liner in `terraform/variables.tf`:

```hcl
# Currently
vm_name = "edge-01"

# For multiple servers — add count to main.tf
# and a parameter to variables.tf
```

The same `vars/users.yml` is applied to all servers with a single `make sync-users` command.

---

## Traffic Routing

### Why the server is in Russia, not abroad

TSPU (Technical Countermeasures Against Threats) inspects traffic at the ISP level.
Key principle: **the client always connects to a Russian IP** — TSPU sees
internal traffic and does not apply deep inspection. Reality disguises the connection
as regular HTTPS to apple.com — to TSPU it looks like an ordinary website visit.

If the server were abroad — TSPU would inspect international traffic much
more aggressively, and the probability of detection/blocking would be higher.

### Three routing levels

```
Client (Russia)
    │
    │ VLESS + Reality (internal traffic RU→RU, TSPU doesn't interfere)
    ▼
Xray Server (YC, Russian IP — whitelisted 158.160.106.0/23)
    │
    │  ┌─ 1. Chain proxy ─→ VPS Sweden → Internet
    ├──┤  2. WARP ────────→ Cloudflare → Internet
    │  └─ 3. Direct ──────→ Internet directly
    │
```

| Level | Services | How it works | Status |
|-------|----------|--------------|--------|
| **Chain proxy** | ChatGPT, Claude, Gemini, Perplexity, Midjourney | Via VPS in Sweden (SOCKS5), clean dedicated IP | Working ✓ |
| **WARP** | YouTube, Instagram, Facebook, Twitter, Discord, Meet, Zoom, Spotify, Netflix | Via Cloudflare WireGuard, non-Russian IP | Working ✓ |
| **Direct** | Russian websites (`ru_direct: true`), everything else | Directly with Russian IP | Working ✓ |

### Whitelist testing

Tested on LTE (mobile carrier, Moscow):
- Server IP `51.250.x.x` falls within the whitelist (`51.250.x.x/23`)
- ChatGPT, YouTube, Instagram — **work on LTE** via VPN
- Reality masquerading as `apple.com` — TSPU allows it through

Check whitelist: `make check-whitelist`

### Why three levels instead of one

| Problem | Solution |
|---------|----------|
| AI services ban shared IPs (WARP) | Chain proxy via dedicated VPS |
| YouTube/Instagram throttled by TSPU | WARP — non-Russian IP via Cloudflare |
| Russian websites don't need proxying | Direct — fast direct access |

### Domain list

Domains for WARP and (in the future) chain proxy are configured in `ansible/inventory/group_vars/all.yml` → `warp_domains`.
Apply changes: `make sync-users`.

---

## Security

| What | Where | Protection |
|------|-------|------------|
| `privateKey` Reality | `/etc/xray-manager/secrets.json` on server | `0600 root`, root-only access |
| `publicKey` | client configs | public by nature |
| User `UUID` | `users.json` on server | `0600 root`, root-only access |
| WARP credentials | `/etc/xray-manager/warp.json` on server | `0600 root`, registered via Cloudflare API |
| Subscription endpoint | `/sub/<token>/` on nginx | random 32-character token in URL |
| Static IP | Terraform | `deletion_protection = true` |
| Service Account Key | `terraform/key.json` | in `.gitignore`, does not expire |
| S3 backend secrets | `terraform/backend.conf` | in `.gitignore` |
| SSH | fail2ban + UFW | max 5 attempts, 1 hour ban |
| Xray auto-update | `/usr/local/sbin/xray-update.sh` | script with version check and health check |
| Xray config | `/usr/local/etc/xray/config.json` | `0640 root:nogroup` (Xray reads via group) |

**Never commit `terraform.tfvars`, `key.json`, `backend.conf`, `telegram.yml` to git.**

### destroy vs destroy-all

- `make destroy` — deletes VM and network, **IP is preserved** (user links work after recreation)
- `make destroy-all` — deletes everything including IP (removes `deletion_protection` automatically)

---

## Monitoring (optional)

A Telegram bot sends alerts to a private channel. It is installed **only if configured** — everything works without it.

### Alerts

| Alert | When | Severity |
|-------|------|----------|
| Xray is down | `systemctl status xray != active` | Critical |
| Nginx is down | `systemctl status nginx != active` | Critical |
| Port 443 not listening | Clients cannot connect | Critical |
| Chain proxy unreachable | AI services not working | Warning |
| Disk > 80% | Logs filled the disk | Warning |

Checks run every 5 minutes. Alerts are deduplicated — the same alert is not sent more than once per hour. Upon recovery, a `✅ working again` message is sent.

### Setup

```bash
# 1. Create a bot: @BotFather → /newbot → copy the token
# 2. Create a private channel, add the bot as admin
# 3. Configure:
cp ansible/vars/telegram.yml.example ansible/vars/telegram.yml
nano ansible/vars/telegram.yml

# 4. Apply:
make install
```

If `telegram.yml` is not created — monitoring is simply skipped, nothing breaks.
