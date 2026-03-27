# Runbook — Diagnostics and Recovery

Step-by-step instructions for common issues.

---

## Known Architectural Limitations

### TSPU and "Internal Traffic"

A Russian IP for the server **reduces** the probability of TSPU detection, but does not eliminate it entirely.
TSPU is installed at the junctions of backbone providers — even traffic within Russia (RU→RU) can pass
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
make ssh

# Check status
sudo systemctl status xray

# View detailed log
sudo journalctl -u xray -n 50 --no-pager

# Validate config for syntax errors
sudo xray run -test -c /usr/local/etc/xray/config.json
```

Common causes:
- Syntax error in config → check the output of `xray run -test`
- Port 443 is occupied by another process → `sudo ss -tlnp | grep 443`

---

## Client Cannot Connect

```bash
# 1. Get the server IP
cd terraform && terraform output server_ip

# 2. Verify that port 443 is open from outside (run locally, not on the server)
nc -zv <IP> 443

# 3. Check xray on the server
make status

# 4. View access log
make ssh
sudo tail -f /var/log/xray/access.log

# 5. Check the security group in YC
# console.yandex.cloud → VPC → Security Groups
# There should be rules for TCP 443 and TCP 8443
```

---

## User Does Not Receive Config (Link Does Not Work)

```bash
make ssh

# Check nginx
sudo systemctl status nginx
sudo nginx -t

# Check that the config file exists
ls -la /var/www/sub/

# Check the subscription token
sudo cat /etc/xray-manager/sub_token

# Check port 8443
sudo ss -tlnp | grep 8443

# Show current links (with token)
make show-users

# Recreate configs for all users
make sync-users
```

> Subscription URL now contains a random token: `https://IP:8443/sub/<token>/name`.
> Without the token, nginx will return 404.

---

## Full Server Recovery

### VM is Broken, but the Same IP is Needed

```bash
# Delete only the VM (IP is preserved, deletion_protection = true)
make destroy

# Recreate the VM with the same IP
make apply

# Set up again (Reality keys will be new)
make install

# Users press Update in their client
```

### Deploy to a New IP from Scratch

```bash
# Delete everything including the IP
make destroy-all

# Bring up again (new IP)
make deploy

# Users need to re-import the subscription URL
make show-users
```

> **Important:** `make destroy` preserves the IP (user links remain valid).
> `make destroy-all` deletes everything — links will need to be redistributed.
>
> Terraform state is stored in YC Object Storage (S3) — it will not be lost
> even if the local machine breaks.

---

## ChatGPT / Claude Does Not Open

Traffic to AI services goes through a **chain proxy** (VPS in Sweden, SOCKS5). If it is not working:

```bash
# 1. Check routing in logs
ssh -i ~/.ssh/xray-infra ubuntu@51.250.x.x \
  "sudo tail -50 /var/log/xray/access.log | grep -E 'chatgpt|claude|openai'"
# Should show: [chain] — meaning traffic goes through VPS

# 2. Check that microsocks is running on the VPS
ssh -i ~/.ssh/xray-infra <USER>@<CHAIN_PROXY_IP> \
  "systemctl status microsocks --no-pager | head -5"

# 3. Check that the YC server can reach the VPS
ssh -i ~/.ssh/xray-infra ubuntu@51.250.x.x \
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

# Check the server config — routing rules
make ssh
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
2. As a workaround: `chrome://flags/#enable-quic` → Disabled

---

## Checking Traffic by User

```bash
ssh -i ~/.ssh/xray-infra ubuntu@51.250.x.x \
  "sudo /usr/local/bin/xray api statsquery --server=127.0.0.1:10085 -pattern ''"
```

The output shows upload/download in bytes for each user since the last Xray restart.

---

## Checking Whitelists

```bash
make check-whitelist      # check our IP against operator lists
make update-whitelist     # update lists from GitHub
```

---

## Chain Proxy (VPS Sweden) is Not Working

```bash
# Check microsocks on the VPS
ssh -i ~/.ssh/xray-infra <USER>@<CHAIN_PROXY_IP> "systemctl status microsocks --no-pager | head -5"

# Restart
ssh -i ~/.ssh/xray-infra <USER>@<CHAIN_PROXY_IP> "sudo systemctl restart microsocks"

# Check iptables (access only from YC IP)
ssh -i ~/.ssh/xray-infra <USER>@<CHAIN_PROXY_IP> "sudo iptables -L INPUT -n | grep 1080"
# Should show: ACCEPT tcp -- 51.250.x.x  0.0.0.0/0  tcp dpt:1080
```

> **Important:** port 1080 on the VPS is closed to everyone except the YC server (iptables).
> If the YC IP has changed — update the iptables rule.

---

## Emergency Key Rotation

If you suspect that keys have been compromised:

```bash
make rotate-keys
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

# Apply
make sync-users
```

---

## Xray Auto-Update

Xray is updated automatically via cron every Sunday at 3:00 AM.
The script `/usr/local/sbin/xray-update.sh`:
- downloads install-release.sh to a temporary file (not `curl | bash`)
- compares versions before/after
- restarts Xray only if the version has changed
- verifies that Xray has started after the update

```bash
# View update log
sudo cat /var/log/xray-update.log

# Run update manually
sudo /usr/local/sbin/xray-update.sh
```

---

## Useful Commands on the Server

```bash
# Status of all required services
sudo systemctl status xray nginx fail2ban

# Xray logs in real time
sudo journalctl -u xray -f

# Who is currently connected (from access log)
sudo tail -f /var/log/xray/access.log

# User state (JSON)
sudo cat /etc/xray-manager/users.json | python3 -m json.tool

# Reality secrets (publicKey for verification)
sudo cat /etc/xray-manager/secrets.json | python3 -m json.tool

# WARP credentials (WireGuard)
sudo cat /etc/xray-manager/warp.json | python3 -m json.tool

# Subscription token (part of the URL)
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
