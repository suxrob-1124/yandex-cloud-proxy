#!/usr/bin/env python3
"""
scripts/gen_inventory.py

Reads JSON from Terraform output ansible_inventory_json
and generates an Ansible inventory in YAML format.

Usage:
  terraform output -json ansible_inventory_json | python3 gen_inventory.py
"""

import json
import sys


def main():
    raw = sys.stdin.read().strip()

    # Terraform output -json wraps the value in a string
    data = json.loads(json.loads(raw))

    lines = [
        "# This file is generated automatically by: make inventory",
        "# Do not edit manually — changes will be overwritten",
        "",
        "all:",
        "  children:",
        "    xray_servers:",
        "      hosts:",
    ]

    for srv in data["servers"]:
        lines.append(f"        {srv['name']}:")
        lines.append(f"          ansible_host: {srv['ip']}")
        lines.append(f"          ansible_user: {srv['ssh_user']}")
        lines.append(f"          sub_port: {srv['sub_port']}")
        lines.append(f"          masquerade_host: {srv['masquerade_host']}")
        lines.append("")

    print("\n".join(lines))


if __name__ == "__main__":
    main()
