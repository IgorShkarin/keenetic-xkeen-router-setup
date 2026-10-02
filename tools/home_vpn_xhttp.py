#!/usr/bin/env python3
"""Convert private Xray JSON on stdin; output must stay private (contains UUIDs)."""
import json
import sys

PATH = "/home-vpn-xhttp/"


def convert(config, role):
    if role == "server":
        inbound = next(i for i in config["inbounds"] if i.get("tag") == "home-vpn")
        config["inbounds"] = [inbound]
        inbound.update(listen="127.0.0.1", port=18444)
        inbound["streamSettings"] = {
            "network": "xhttp", "xhttpSettings": {"path": PATH, "mode": "packet-up"}
        }
        for client in inbound["settings"]["clients"]:
            client.pop("flow", None)
        config["log"] = {"loglevel": "warning"}
    elif role == "client":
        candidates = [o for o in config["outbounds"] if o.get("protocol") == "vless"
                      and o.get("tag") == "vless-reality"]
        if len(candidates) != 1:
            raise ValueError("Expected exactly one personal VPS outbound")
        outbound = candidates[0]
        outbound["settings"]["vnext"][0]["port"] = 443
        for user in outbound["settings"]["vnext"][0]["users"]:
            user.pop("flow", None)
        outbound["streamSettings"] = {
            "network": "xhttp", "security": "tls",
            "tlsSettings": {"serverName": outbound["settings"]["vnext"][0]["address"], "allowInsecure": False,
                            "alpn": ["http/1.1"]},
            "xhttpSettings": {"path": PATH, "mode": "packet-up"}
        }
    else:
        raise ValueError("Role must be server or client")
    return config


if __name__ == "__main__":
    json.dump(convert(json.load(sys.stdin), sys.argv[1]), sys.stdout, indent=2)
    sys.stdout.write("\n")
