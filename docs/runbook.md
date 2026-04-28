# Runbook — Diagnostics and Recovery

Step-by-step instructions for common issues.

---

## Multi-Server Architecture

The infrastructure supports multiple VPN servers (e.g., `edge-01`, `edge-02`).
Each server is an independent VM in Yandex Cloud with its own:

- **Static IP address** (reserved separately, survives VM recreation)
- **Reality key pair** (`/etc/xray-manager/secrets.json`)
- **WARP credentials** (`/etc/xray-manager/warp.json`)
- **Subscription token** (`/etc/xray-manager/sub_token`)
- **Masquerade host** (configured in `terraform.tfvars` via the `servers` map)
- **Client config files** (`/var/www/sub/`)

Servers are defined in `terraform.tfvars` under the `servers` variable. Adding a new
server means adding one entry to that map and running `make deploy`.

### Targeting a Specific Server

Most Makefile commands accept the `SERVER=` parameter to target a single server:

```bash
make install SERVER=edge-02      # install only edge-02
make sync-users SERVER=edge-02   # sync users on edge-02 only
make status SERVER=edge-01       # check status of edge-01 only
make destroy SERVER=edge-02      # destroy only edge-02 VM
make ssh SERVER=edge-02          # SSH into edge-02
make rotate-keys SERVER=edge-01  # rotate keys on edge-01 only
```

Without `SERVER=`, commands run against **all servers**.

### Getting Server IPs

```bash
# Show all server IPs
make output

# Or directly from Terraform
cd terraform && terraform output server_ips
```

### SSH Access

```bash
# SSH into the default server (edge-01)
make ssh

# SSH into a specific server
make ssh SERVER=edge-02

# Manual SSH (replace <SERVER_IP> with the actual IP)
ssh -i ~/.ssh/xray-infra ubuntu@<SERVER_IP>
```

---

## Known Architectural Limitations

### TSPU and "Internal Traffic"

A Russian IP for the server **reduces** the probability of TSPU detection, but does not eliminate it entirely.
TSPU is installed at the junctions of backbone providers — even traffic within Russia (RU->RU) can pass
through filtering nodes (e.g., client on Rostelecom, server in YC).
Reality masks the protocol, but with heuristic behavioral analysis (long sessions,
traffic volume) it is theoretically possible to attract attention.

**Mitigation:** Reality + Vision + masquerade to apple.com makes the traffic indistinguishable from
regular HTTPS. In practice, this is the best available level of obfuscation.

### DNS Leaks

DNS requests to blocked domains can leak to the system DNS (Yandex, ISP).
In the Xray server config, DNS-over-HTTPS (1.1.1.1, 8.8.8.8) is configured for WARP domains,
and sniffing intercepts and redirects DNS at the protocol level.

Verify that DNS works via DoH:
```bash
make status
# In the report, look for the line "DNS (DoH): ✓"

# Check a specific server
make status SERVER=edge-02
```

### Port 8443 for subscription

Nginx on port 8443 serves client configs. This port may attract attention
during active scanning. The token in the URL protects the data but does not hide the existence of the service.

**Mitigation:** nginx responds with 404 to any request without a token. If needed,
config distribution can be moved to port 443 via path-based routing in Xray.

### S3 Backend Secrets

`backend.conf` contains a static access key for Object Storage. It is stored locally and in `.gitignore`.
For team collaboration, it is better to use environment variables (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`)
or VM IAM metadata if Terraform is run from the cloud.

### Traffic Limits

Connection timeouts are configured in the policy (`connIdle`, `uplinkOnly`, `downlinkOnly`),
but hard limits on traffic volume per user are not implemented —
Xray core does not support quotas natively. For quotas, external monitoring is needed
(e.g., parsing the stats API via cron).

---

## Xray Does Not Start

```bash
# SSH into the affected server
make ssh SERVER=edge-01

# Check status
sudo systemctl status xray

# View detailed log
sudo journalctl -u xray -n 50 --no-pager

# Validate config for syntax errors
sudo xray run -test -c /usr/local/etc/xray/config.json
```

Common causes:
- Syntax error in config -> check the output of `xray run -test`
- Port 443 is occupied by another process -> `sudo ss -tlnp | grep 443`

---

## Client Cannot Connect

```bash
# 1. Get the server IPs
cd terraform && terraform output server_ips

# 2. Verify that port 443 is open from outside (run locally, not on the server)
nc -zv <SERVER_IP> 443

# 3. Check xray on the server (all servers or a specific one)
make status
make status SERVER=edge-02

# 4. View access log on the affected server
make ssh SERVER=edge-01
sudo tail -f /var/log/xray/access.log

# 5. Check the security group in YC
# console.yandex.cloud → VPC → Security Groups
# There should be rules for TCP 443 and TCP 8443
```

---

## User Does Not Receive Config (Link Does Not Work)

```bash
# SSH into the affected server
make ssh SERVER=edge-01

# Check nginx
sudo systemctl status nginx
sudo nginx -t

# Check that the config file exists
ls -la /var/www/sub/

# Check the subscription token (unique per server)
sudo cat /etc/xray-manager/sub_token

# Check port 8443
sudo ss -tlnp | grep 8443

# Show current links (with token) — all servers
make show-users

# Show links for a specific server
make show-users SERVER=edge-02

# Recreate configs for all users (all servers or specific)
make sync-users
make sync-users SERVER=edge-01
```

> Subscription URL now contains a random token: `https://<SERVER_IP>:8443/sub/<token>/name`.
> Without the token, nginx will return 404.
> Each server has its own `sub_token`, so subscription URLs differ between servers.

---

## Full Server Recovery

### Single Server is Broken, but the Same IP is Needed

**If a backup exists** (run `make backup-server` beforehand or secrets are in `data/backups/`):

```bash
# Delete only the VM (IP preserved)
make destroy SERVER=edge-02

# Recreate VM with same IP, restore secrets, full install
# All user links remain unchanged
make resume-server SERVER=edge-02
```

**If no backup exists** (keys will be regenerated — users need to press Update):

```bash
# Delete only the VM for the affected server (IP is preserved, deletion_protection = true)
make destroy SERVER=edge-02

# Recreate the VM with the same IP
make apply SERVER=edge-02

# Set up again (Reality keys and WARP credentials will be regenerated)
make install SERVER=edge-02

# Users press Update in their client — subscription URL stays the same
```

### Recover All Servers

```bash
# Delete all VMs (IPs are preserved)
make destroy

# Recreate
make apply

# Set up again
make install
```

### Deploy a Server to a New IP from Scratch

```bash
# Delete everything including the IP for the specific server
make destroy-all SERVER=edge-02

# Bring up again (new IP)
make apply SERVER=edge-02
make install SERVER=edge-02

# Users need to re-import the subscription URL
make show-users SERVER=edge-02
```

### Deploy Everything from Scratch

```bash
# Delete everything for all servers
make destroy-all

# Full deploy (new IPs)
make deploy

# Users need to re-import subscription URLs
make show-users
```

> **Important:** `make destroy` preserves the IP (user links remain valid).
> `make destroy-all` deletes everything — links will need to be redistributed.
> Use `SERVER=` to scope destruction to a single server.
>
> Terraform state is stored in YC Object Storage (S3) — it will not be lost
> even if the local machine breaks.
>
> After recovery, each server gets new Reality keys and WARP credentials.
> The masquerade_host is preserved since it comes from `terraform.tfvars`.

---

## ChatGPT / Claude Does Not Open

Traffic to AI services goes through a **chain proxy** (VPS in Sweden, SOCKS5). If it is not working:

```bash
# 1. Check routing in logs (replace <SERVER_IP> with the actual server IP)
ssh -i ~/.ssh/xray-infra ubuntu@<SERVER_IP> \
  "sudo tail -50 /var/log/xray/access.log | grep -E 'chatgpt|claude|openai'"
# Should show: [chain] — meaning traffic goes through VPS

# 2. Check that microsocks is running on the VPS
ssh -i ~/.ssh/xray-infra <USER>@<CHAIN_PROXY_IP> \
  "systemctl status microsocks --no-pager | head -5"

# 3. Check that the edge server can reach the VPS
ssh -i ~/.ssh/xray-infra ubuntu@<SERVER_IP> \
  "curl -s --socks5-hostname <CHAIN_PROXY_IP>:1080 --max-time 5 https://ifconfig.me"
# Should return: <CHAIN_PROXY_IP>

# 4. If microsocks is down — restart it
ssh -i ~/.ssh/xray-infra <USER>@<CHAIN_PROXY_IP> "sudo systemctl restart microsocks"
```

If the VPS is unreachable — AI domains can be temporarily switched to WARP in `group_vars/all.yml`
(move from `chain_domains` to `warp_domains`) and run `make sync-users`.

---

## Google Meet / Zoom is Slow or Does Not Connect

Meet and Zoom go through WARP (WireGuard/UDP). If there are issues:

```bash
# Check that Meet domains are in warp_domains
grep -i meet ansible/inventory/group_vars/all.yml

# Check the server config — routing rules (on a specific server)
make ssh SERVER=edge-01
sudo cat /usr/local/etc/xray/config.json | python3 -c "
import sys,json
c=json.load(sys.stdin)
for r in c['routing']['rules']:
    if r.get('outboundTag') == 'warp':
        print('WARP domains:', r.get('domain', [])[:5], '...')
"

# If domains are missing — update the config
make sync-users
```

---

## ERR_QUIC_PROTOCOL_ERROR in Browser

QUIC (UDP 443) is blocked on the client — this is normal. The browser should automatically fall back to TCP HTTPS.

If the error persists:
1. Make sure the client has downloaded the updated config (Update in V2Box/Hiddify)
2. As a workaround: `chrome://flags/#enable-quic` -> Disabled

---

## Checking Traffic by User

```bash
# Check traffic on a specific server
make ssh SERVER=edge-01
sudo /usr/local/bin/xray api statsquery --server=127.0.0.1:10085 -pattern ''

# Or via direct SSH (replace <SERVER_IP> with the actual IP)
ssh -i ~/.ssh/xray-infra ubuntu@<SERVER_IP> \
  "sudo /usr/local/bin/xray api statsquery --server=127.0.0.1:10085 -pattern ''"
```

The output shows upload/download in bytes for each user since the last Xray restart
(cumulative, not daily). Run this on each server separately to see per-server traffic.

**Daily traffic** is tracked by the monitoring script using a baseline snapshot
(`/var/lib/xray-traffic-baseline.json`). Daily = current counters minus baseline.
The baseline is updated once per day at 09:00 MSK when the daily report is sent.

If Xray was restarted (counters reset to zero), the script detects this and uses
the current value as the daily amount.

---

## Checking Whitelists

```bash
make check-whitelist              # check all server IPs against operator lists
make check-whitelist SERVER=edge-01  # check a specific server
make update-whitelist             # update lists from GitHub
```

---

## Chain Proxy (VPS Sweden) is Not Working

```bash
# SSH to the chain VPS (address and credentials in ansible/vars/chain.yml)
# Use -o IdentitiesOnly=yes to avoid "Too many authentication failures"
ssh -o IdentitiesOnly=yes -i <KEY> <USER>@<CHAIN_PROXY_IP>

# Check microsocks
sudo systemctl status microsocks --no-pager | head -5

# Restart
sudo systemctl restart microsocks

# Check iptables (access should be allowed from ALL edge server IPs)
sudo iptables -L INPUT -n | grep 1080
# Should show ACCEPT rules for each edge server IP

# Check resources
free -h
uptime
sudo journalctl -u microsocks --since "1 hour ago" --no-pager
```

> **Important:** port 1080 on the VPS is closed to everyone except the edge servers (iptables).
> If a server IP has changed (after `make destroy-all`) — update the iptables rules on the VPS
> to include the new IP.

---

## Troubleshooting Per-Server User Files

Each server maintains its own set of user config files. If a user's config is missing
or incorrect on one server but works on another:

```bash
# Check user files on a specific server
make ssh SERVER=edge-01
ls -la /var/www/sub/
sudo cat /etc/xray-manager/users.json | python3 -m json.tool

# Compare with another server
make ssh SERVER=edge-02
ls -la /var/www/sub/
sudo cat /etc/xray-manager/users.json | python3 -m json.tool

# Re-sync users on the affected server
make sync-users SERVER=edge-01
```

Each server has its own:
- `/etc/xray-manager/secrets.json` — Reality key pair (unique per server)
- `/etc/xray-manager/warp.json` — WARP registration (unique per server)
- `/etc/xray-manager/sub_token` — subscription URL token (unique per server)
- `/var/www/sub/` — generated client config files (contain server-specific IP, keys, etc.)

If user configs look wrong, verify that the server's secrets are intact:

```bash
make ssh SERVER=edge-01

# Reality keys
sudo cat /etc/xray-manager/secrets.json | python3 -m json.tool

# WARP credentials
sudo cat /etc/xray-manager/warp.json | python3 -m json.tool

# Subscription token
sudo cat /etc/xray-manager/sub_token
```

If secrets are missing or corrupted, re-run installation for that server:

```bash
make install SERVER=edge-01
make sync-users SERVER=edge-01
```

---

## Pausing a Server to Save Costs

Destroys the VM (compute + disk charges stop) while keeping the static IP reserved (~130 RUB/mo).
All user subscription links remain valid after resume.

```bash
# Pause (backs up secrets automatically, then destroys VM)
make pause-server SERVER=edge-01

# Resume (recreates VM, restores secrets, runs full install)
make resume-server SERVER=edge-01
```

Backup files are stored in `data/backups/edge-01/` — they are in `.gitignore`, keep them safe.
To back up without pausing (while the server is running):

```bash
make backup-server SERVER=edge-01
```

---

## Emergency Key Rotation

If you suspect that keys have been compromised:

```bash
# Rotate keys on all servers
make rotate-keys

# Or rotate on a specific server only
make rotate-keys SERVER=edge-02
```

Ansible automatically:
1. Generates a new key pair
2. Updates the server config
3. Updates all client configs and subscription files
4. Restarts Xray
5. Verifies that Xray has started

Users press **Update** in their client — everything continues to work.

---

## Rollback to Previous Configuration

```bash
# View history
git log --oneline ansible/vars/users.yml

# Revert the users file
git checkout HEAD~1 ansible/vars/users.yml

# Apply to all servers
make sync-users

# Or apply to a specific server
make sync-users SERVER=edge-01
```

---

## Xray Auto-Update

Xray is updated automatically via cron every Sunday at 3:00 AM on each server independently.
The script `/usr/local/sbin/xray-update.sh`:
- downloads install-release.sh to a temporary file (not `curl | bash`)
- compares versions before/after
- restarts Xray only if the version has changed
- verifies that Xray has started after the update

```bash
# View update log (on a specific server)
make ssh SERVER=edge-01
sudo cat /var/log/xray-update.log

# Run update manually
sudo /usr/local/sbin/xray-update.sh
```

---

## Useful Commands on the Server

First, SSH into the desired server:
```bash
make ssh                    # default (edge-01)
make ssh SERVER=edge-02     # specific server
```

Then run any of the following:

```bash
# Status of all required services
sudo systemctl status xray nginx fail2ban

# Xray logs in real time
sudo journalctl -u xray -f

# Who is currently connected (from access log)
sudo tail -f /var/log/xray/access.log

# User state (JSON)
sudo cat /etc/xray-manager/users.json | python3 -m json.tool

# Reality secrets (publicKey for verification) — unique per server
sudo cat /etc/xray-manager/secrets.json | python3 -m json.tool

# WARP credentials (WireGuard) — unique per server
sudo cat /etc/xray-manager/warp.json | python3 -m json.tool

# Subscription token (part of the URL) — unique per server
sudo cat /etc/xray-manager/sub_token

# Xray auto-update log
sudo tail -20 /var/log/xray-update.log

# Verify that all outbounds are working
sudo cat /usr/local/etc/xray/config.json | python3 -c "
import sys,json
c=json.load(sys.stdin)
for o in c['outbounds']:
    print(f\"  {o['tag']}: {o['protocol']}\")
"

# Check routing (which outbound is used)
sudo tail -50 /var/log/xray/access.log
# [direct] = directly, [warp] = Cloudflare, [chain] = VPS Sweden

# Traffic by user
sudo /usr/local/bin/xray api statsquery --server=127.0.0.1:10085 -pattern ''

# Restart everything
sudo systemctl restart xray nginx
```
