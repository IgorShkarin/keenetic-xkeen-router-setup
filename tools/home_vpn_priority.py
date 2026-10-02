#!/usr/bin/env python3
"""Build private Xray fragments for explicit priority switching via local API."""
import copy
import json
import sys


def build(home, blanc, amnezia, routing, home_h1=None):
    outbounds = copy.deepcopy(home["outbounds"])
    if home_h1 is not None:
        fallback = copy.deepcopy(next(o for o in home_h1['outbounds'] if o['tag'] == 'vless-reality'))
        fallback['tag'] = 'home-h1-reserve'
        outbounds.append(fallback)
    for name, profile in [("blanc", blanc), ("amnezia", amnezia)]:
        mapping = {o["tag"]: "reserve-" + name + ("" if o["tag"] == "vless-reality"
                   else "-" + o["tag"]) for o in profile["outbounds"]
                   if o["protocol"] == "vless" or o["tag"] == "vless-reality"}
        for original in profile["outbounds"]:
            if original["protocol"] != "vless" and original["tag"] != "vless-reality":
                continue
            outbound = copy.deepcopy(original)
            outbound["tag"] = mapping[original["tag"]]
            sockopt = outbound.get("streamSettings", {}).get("sockopt", {})
            if sockopt.get("dialerProxy") in mapping:
                sockopt["dialerProxy"] = mapping[sockopt["dialerProxy"]]
            if outbound.get("proxySettings", {}).get("tag") in mapping:
                outbound["proxySettings"]["tag"] = mapping[outbound["proxySettings"]["tag"]]
            outbounds.append(outbound)
    route = copy.deepcopy(routing["routing"])
    for rule in route["rules"]:
        if rule.get("outboundTag") == "vless-reality":
            del rule["outboundTag"]
            rule["balancerTag"] = "home-priority"
    route["balancers"] = [{"tag": "home-priority", "selector": ["vless-reality"],
                           "strategy": {"type": "random"}}]
    probes = []
    rules = [{"type": "field", "inboundTag": ["home-api"], "outboundTag": "home-api"}]
    probe_targets = [(10821, "vless-reality"), (10822, "reserve-blanc"), (10823, "reserve-amnezia")]
    if home_h1 is not None:
        probe_targets.append((10824, 'home-h1-reserve'))
    for port, tag in probe_targets:
        inbound_tag = "health-" + tag
        probes.append({"tag": inbound_tag, "listen": "127.0.0.1", "port": port,
                       "protocol": "socks", "settings": {"auth": "noauth", "udp": False}})
        rules.append({"type": "field", "inboundTag": [inbound_tag], "outboundTag": tag})
    probes.append({"tag": "home-api", "listen": "127.0.0.1", "port": 10085,
                   "protocol": "dokodemo-door", "settings": {"address": "127.0.0.1"}})
    route["rules"] = rules + route["rules"]
    return {"04_outbounds.json": {"outbounds": outbounds}, "05_routing.json": {"routing": route},
            "07_home_api.json": {"api": {"tag": "home-api", "services": ["RoutingService"]}, "stats": {},
                                 "inbounds": probes}}


if __name__ == "__main__":
    bundle = json.load(sys.stdin)
    json.dump(build(**bundle), sys.stdout)
