#!/usr/bin/env python3
import json, sys
from urllib.parse import parse_qs, unquote, urlsplit

src, dst, wanted = sys.argv[1:]
aliases = {
    "ee": "эстония", "estonia": "эстония", "эстония": "эстония",
    "se": "швеция", "sweden": "швеция", "швеция": "швеция",
    "fi": "финляндия", "finland": "финляндия", "финляндия": "финляндия",
    "pl": "польша", "poland": "польша", "польша": "польша",
    "lt": "литва", "lithuania": "литва", "литва": "литва",
    "ch": "цюрих", "switzerland": "цюрих", "швейцария": "цюрих", "цюрих": "цюрих",
    "nl": "нидерланды", "netherlands": "нидерланды", "нидерланды": "нидерланды",
}
needle = aliases.get(wanted.lower(), wanted.lower())
line = next((x.strip() for x in open(src, encoding="utf-8")
             if x.strip().startswith("vless://") and needle in unquote(x).lower()), None)
if not line:
    raise SystemExit("Узел для страны не найден: " + wanted)
u = urlsplit(line)
q = {k: v[0] for k, v in parse_qs(u.query).items()}
if u.scheme != "vless" or not u.username or not u.hostname or not u.port:
    raise SystemExit("Неполная VLESS-запись")
reality = {
    "fingerprint": q.get("fp", "chrome"),
    "publicKey": q.get("pbk", ""),
    "serverName": q.get("sni", ""),
    "shortId": q.get("sid", ""),
    "spiderX": q.get("spx", "/"),
}
if not reality["publicKey"] or not reality["serverName"]:
    raise SystemExit("Нет Reality-параметров")
obj = {"outbounds": [
    {"tag": "vless-reality", "protocol": "vless",
     "settings": {"vnext": [{"address": u.hostname, "port": u.port,
       "users": [{"id": unquote(u.username), "encryption": "none",
                  "flow": q.get("flow", ""), "level": 0}]}]},
     "streamSettings": {"network": q.get("type", "tcp"),
       "security": q.get("security", "reality"), "realitySettings": reality}},
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"},
]}
open(dst, "w", encoding="utf-8").write(json.dumps(obj, ensure_ascii=False, indent=2) + "\n")
print("selected=" + unquote(u.fragment))
