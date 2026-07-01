#!/usr/bin/env python3
"""Summarize Xray access logs for selective routing triage.

The parser is intentionally tolerant: Xray access log formats vary between
builds and config styles. This script extracts useful hints without treating
the result as a final routing decision.
"""

from __future__ import annotations

import argparse
import collections
import ipaddress
import re
from pathlib import Path


HOST_RE = re.compile(r"(?P<host>[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})(?::(?P<port>\d{1,5}))?")
IP_RE = re.compile(r"\b(?P<ip>(?:\d{1,3}\.){3}\d{1,3})(?::(?P<port>\d{1,5}))?\b")


def classify_line(line: str) -> str:
    lowered = line.lower()
    if "vless-reality" in lowered or "proxy" in lowered:
        return "proxy"
    if "direct" in lowered:
        return "direct"
    if "block" in lowered:
        return "block"
    return "unknown"


def redact_ip(value: str, redact: bool) -> str:
    if not redact:
        return value
    try:
        ip = ipaddress.ip_address(value)
    except ValueError:
        return value

    if ip.is_private or ip.is_loopback or ip.is_link_local:
        return "<private-ip>"
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize sanitized Xray access logs.")
    parser.add_argument("logfile", type=Path)
    parser.add_argument("--top", type=int, default=30)
    parser.add_argument("--no-redact", action="store_true", help="print private/local IP addresses")
    args = parser.parse_args()
    redact = not args.no_redact

    by_route: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)
    udp_443 = 0

    for raw_line in args.logfile.read_text(errors="replace").splitlines():
        line = raw_line.strip()
        if not line:
            continue

        route = classify_line(line)
        if "udp" in line.lower() and ":443" in line:
            udp_443 += 1

        seen: set[str] = set()
        for match in HOST_RE.finditer(line):
            host = match.group("host").lower().strip(".")
            if host not in seen:
                by_route[route][host] += 1
                seen.add(host)

        for match in IP_RE.finditer(line):
            ip = redact_ip(match.group("ip"), redact)
            if ip not in seen:
                by_route[route][ip] += 1
                seen.add(ip)

    print("# Xray Access Log Summary")
    print()
    print(f"UDP/443 hints: {udp_443}")
    print()

    for route in ("direct", "proxy", "block", "unknown"):
        if not by_route[route]:
            continue
        print(f"## {route}")
        for value, count in by_route[route].most_common(args.top):
            print(f"- {value}: {count}")
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
