#!/usr/bin/env python3
"""
scripts/check_whitelist.py

Checks the server IP address against Russian mobile operator whitelists.
Source: https://github.com/hxehex/russia-mobile-internet-whitelist

Usage:
  SERVER_IP=x.x.x.x python3 scripts/check_whitelist.py
  # or
  python3 scripts/check_whitelist.py x.x.x.x
"""

import ipaddress
import os
import sys

WHITELIST_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "whitelist")


def check_ip_in_cidrs(ip: str, cidr_file: str) -> list:
    """Checks the IP against a list of CIDR subnets."""
    matches = []
    addr = ipaddress.ip_address(ip)
    with open(cidr_file) as f:
        for line in f:
            cidr = line.strip()
            if not cidr or cidr.startswith("#"):
                continue
            try:
                if addr in ipaddress.ip_network(cidr, strict=False):
                    matches.append(cidr)
            except ValueError:
                continue
    return matches


def check_ip_in_list(ip: str, ip_file: str) -> bool:
    """Checks the IP against a list of individual addresses."""
    with open(ip_file) as f:
        for line in f:
            if line.strip() == ip:
                return True
    return False


def check_sni_in_whitelist(sni: str, whitelist_file: str) -> bool:
    """Checks the SNI (masquerade domain) against the whitelist."""
    with open(whitelist_file) as f:
        for line in f:
            domain = line.strip()
            if not domain or domain.startswith("#"):
                continue
            if sni == domain or sni.endswith("." + domain):
                return True
    return False


def main():
    ip = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("SERVER_IP")
    if not ip:
        print("Usage: SERVER_IP=x.x.x.x python3 check_whitelist.py", file=sys.stderr)
        sys.exit(1)

    sni = os.environ.get("MASQUERADE_HOST", "www.apple.com")

    cidr_file = os.path.join(WHITELIST_DIR, "cidrwhitelist.txt")
    ip_file = os.path.join(WHITELIST_DIR, "ipwhitelist.txt")
    sni_file = os.path.join(WHITELIST_DIR, "whitelist.txt")

    print(f"\033[1m  Checking Russian mobile operator whitelists\033[0m")
    print(f"  IP:  {ip}")
    print(f"  SNI: {sni}")
    print()

    # Check IP against CIDR
    cidr_matches = check_ip_in_cidrs(ip, cidr_file)
    if cidr_matches:
        print(f"\033[0;32m  ✓ IP is in the whitelist (CIDR)\033[0m")
        for cidr in cidr_matches:
            print(f"    → {cidr}")
    else:
        print(f"\033[0;31m  ✗ IP not found in the CIDR whitelist\033[0m")

        # Search for nearby YC subnets
        prefix = ".".join(ip.split(".")[:2])  # e.g. "158.160"
        nearby = []
        with open(cidr_file) as f:
            for line in f:
                if line.strip().startswith(prefix):
                    nearby.append(line.strip())
        if nearby:
            print(f"    Nearby subnets from the same range ({prefix}.x.x):")
            for n in nearby[:10]:
                print(f"    → {n}")
            if len(nearby) > 10:
                print(f"    ... and {len(nearby) - 10} more")

    print()

    # Check IP against individual address list
    if check_ip_in_list(ip, ip_file):
        print(f"\033[0;32m  ✓ IP is in the whitelist (individual addresses)\033[0m")
    else:
        print(f"\033[0;31m  ✗ IP not found in the individual address list\033[0m")

    print()

    # Check SNI
    if check_sni_in_whitelist(sni, sni_file):
        print(f"\033[0;32m  ✓ SNI '{sni}' is in the domain whitelist\033[0m")
    else:
        print(f"\033[0;31m  ✗ SNI '{sni}' not found in the domain whitelist\033[0m")

    print()


if __name__ == "__main__":
    main()
