#!/usr/bin/env python3
"""Wait for SSH readiness on server(s)."""

import json
import os
import subprocess
import sys
import time


def main():
    ips = json.load(sys.stdin)
    server = os.environ.get("SERVER", "")

    if server and server in ips:
        targets = {server: ips[server]}
    else:
        targets = ips

    # Remove old host keys
    for ip in targets.values():
        subprocess.run(["ssh-keygen", "-R", ip], capture_output=True)

    # Wait for SSH
    for name, ip in targets.items():
        ok = False
        for i in range(30):
            r = subprocess.run(["nc", "-z", "-w2", ip, "22"], capture_output=True)
            if r.returncode == 0:
                print(f"  ✓ {name} ({ip}) SSH available")
                ok = True
                break
            print(f"  {name}: SSH not ready ({i+1}/30)...")
            time.sleep(5)
        if not ok:
            print(f"  ✗ {name}: SSH timeout")
            sys.exit(1)


if __name__ == "__main__":
    main()
