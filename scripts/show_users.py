#!/usr/bin/env python3
"""
scripts/show_users.py

Shows subscription URL and VLESS links for all active users on a server.

Usage:
  SERVER_IP=1.2.3.4 SERVER_NAME=edge-01 python3 scripts/show_users.py
  SERVER_IP=1.2.3.4 SERVER_NAME=edge-01 python3 scripts/show_users.py --qr
"""

import json
import subprocess
import base64
import os
import sys

try:
    import qrcode
    import qrcode.image.svg
    HAS_QR = True
except ImportError:
    HAS_QR = False


def ansible_slurp(path: str, host: str = "xray_servers") -> str:
    """Reads a file from the server via ansible slurp and returns its contents."""
    result = subprocess.run(
        ["ansible", host, "-b", "-m", "slurp", "-a", f"src={path}"],
        capture_output=True, text=True, cwd=os.path.join(os.path.dirname(__file__), "..", "ansible")
    )
    if result.returncode != 0:
        print(f"Error reading {path}: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    output = result.stdout
    json_start = output.index("{")
    json_str = output[json_start:]
    data = json.loads(json_str)
    return base64.b64decode(data["content"]).decode().strip()


def get_masquerade_host(server_name: str) -> str:
    """Read masquerade_host from inventory for a specific server."""
    inventory_path = os.path.join(os.path.dirname(__file__), "..", "ansible", "inventory", "hosts.yml")
    try:
        import yaml
        with open(inventory_path) as f:
            inv = yaml.safe_load(f)
        hosts = inv["all"]["children"]["xray_servers"]["hosts"]
        if server_name in hosts:
            return hosts[server_name].get("masquerade_host", "www.apple.com")
    except Exception:
        pass

    # Fallback: try reading from inventory via grep
    try:
        with open(inventory_path) as f:
            content = f.read()
        # Find the server block and extract masquerade_host
        in_server = False
        for line in content.split("\n"):
            stripped = line.strip()
            if stripped.startswith(f"{server_name}:"):
                in_server = True
                continue
            if in_server and "masquerade_host:" in stripped:
                return stripped.split(":", 1)[1].strip()
            if in_server and not stripped.startswith("ansible_") and not stripped.startswith("sub_port") and not stripped.startswith("masquerade") and stripped and not stripped.startswith("#"):
                in_server = False
    except Exception:
        pass

    return "www.apple.com"


def main():
    server_ip = os.environ.get("SERVER_IP")
    server_name = os.environ.get("SERVER_NAME", "")

    if not server_ip:
        print("SERVER_IP is not set", file=sys.stderr)
        sys.exit(1)

    # Determine which host to query
    host = server_name if server_name else "xray_servers"
    masquerade_host = get_masquerade_host(server_name) if server_name else "www.apple.com"

    sub_token = ansible_slurp("/etc/xray-manager/sub_token", host)
    users = json.loads(ansible_slurp("/etc/xray-manager/users.json", host))
    secrets = json.loads(ansible_slurp("/etc/xray-manager/secrets.json", host))

    show_qr = "--qr" in sys.argv or "-q" in sys.argv
    active_users = [u for u in users if u.get("active", False)]

    if server_name:
        print(f"\033[1;36m  === {server_name} ({server_ip}) — SNI: {masquerade_host} ===\033[0m")
        print()

    if not active_users:
        print("  No active users")
        return

    for u in active_users:
        name = u["name"]
        uuid = u["uuid"]
        pub_key = secrets["public_key"]
        short_id = secrets["short_id"]

        sub_url = f"https://{server_ip}:8443/sub/{sub_token}/{name}"
        vless = (
            f"vless://{uuid}@{server_ip}:443"
            f"?encryption=none"
            f"&flow=xtls-rprx-vision"
            f"&security=reality"
            f"&sni={masquerade_host}"
            f"&fp=chrome"
            f"&pbk={pub_key}"
            f"&sid={short_id}"
            f"&type=tcp"
            f"#YC-{name}"
        )

        print(f"\033[1m  {name}\033[0m")
        print(f"\033[0;32m  Subscription URL\033[0m (for V2Box/Hiddify -> Add Subscription):")
        print(f"\033[0;36m  {sub_url}\033[0m")
        print()
        print(f"\033[0;32m  VLESS link\033[0m (for manual addition):")
        print(f"\033[0;36m  {vless}\033[0m")
        print()

        if show_qr and HAS_QR:
            qr_dir = os.path.join(os.path.dirname(__file__), "..", "qr-codes")
            if server_name:
                qr_dir = os.path.join(qr_dir, server_name)
            os.makedirs(qr_dir, exist_ok=True)
            qr_path = os.path.join(qr_dir, f"{name}.png")

            qr = qrcode.QRCode(border=2, box_size=10)
            qr.add_data(vless)
            qr.make(fit=True)
            img = qr.make_image(fill_color="black", back_color="white")
            img.save(qr_path)

            print(f"\033[0;32m  QR code saved:\033[0m {qr_path}")
            print()
        elif show_qr and not HAS_QR:
            print(f"\033[0;33m  QR: pip3 install qrcode Pillow to generate\033[0m")
            print()

        print(f"\033[1;33m  ────────────────────────────────\033[0m")
        print()


if __name__ == "__main__":
    main()
