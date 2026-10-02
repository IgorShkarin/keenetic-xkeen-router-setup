#!/usr/bin/env python3
"""Refresh a private Premium VLESS export using the installed client's identity.

Input/output stay outside Git. The existing installation UUID is reused; this
does not create a new client identity. Gateway wire format follows Amnezia's
gatewayController.cpp and gatewayPayloadBuilder.cpp.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import urllib.error
import urllib.request
import uuid
import zlib

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes


def unpack(value):
    text = value.removeprefix("vpn://").strip()
    raw = base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))
    if raw[:4] == b"\x00\x00\x00\xff":
        raw = zlib.decompress(raw[4:])
    return json.loads(raw)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("key_file", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--country", default="pt")
    args = parser.parse_args()
    os.umask(0o077)
    key = unpack(args.key_file.read_text())
    prefs = plistlib.loads((Path.home() / "Library/Preferences/org.amneziavpn.AmneziaVPN.plist").read_bytes())
    app = Path("/Applications/AmneziaVPN.app/Contents")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    identity = prefs["Conf.installationUuid"]
    payload = {
        "os_version": "osx", "app_version": str(info.get("CFBundleShortVersionString") or info["CFBundleVersion"]),
        "cli_name": "AmneziaVPN", "distribution": "appstore", "app_language": "ru",
        "installation_uuid": identity, "public_key": identity,
        "user_country_code": key["api_config"]["user_country_code"],
        "server_country_code": args.country, "service_type": key["api_config"]["service_type"],
        "service_protocol": "vless", "auth_data": key["auth_data"],
    }
    public_keys = re.findall(rb"-----BEGIN PUBLIC KEY-----.*?-----END PUBLIC KEY-----",
                             (app / "MacOS/AmneziaVPN").read_bytes(), re.S)
    public_key = serialization.load_pem_public_key(public_keys[1])
    aes_key, iv, salt = os.urandom(32), os.urandom(32), os.urandom(8)
    plain = json.dumps(payload, separators=(",", ":")).encode()
    n = 16 - len(plain) % 16
    encryptor = Cipher(algorithms.AES(aes_key), modes.CBC(iv[:16])).encryptor()
    encrypted = encryptor.update(plain + bytes([n]) * n) + encryptor.finalize()
    key_payload = json.dumps({name: base64.b64encode(value).decode() for name, value in
                             [("aes_key", aes_key), ("aes_iv", iv), ("aes_salt", salt)]}).encode()
    body = json.dumps({"key_payload": base64.b64encode(public_key.encrypt(key_payload, padding.PKCS1v15())).decode(),
                       "api_payload": base64.b64encode(encrypted).decode()}).encode()
    request = urllib.request.Request("https://gw.amnezia.org/v1/config", data=body,
                                    headers={"Content-Type": "application/json", "X-Client-Request-ID": str(uuid.uuid4())})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        raise SystemExit("Gateway HTTP failure: " + str(error.code)) from None
    decryptor = Cipher(algorithms.AES(aes_key), modes.CBC(iv[:16])).decryptor()
    plain = decryptor.update(raw) + decryptor.finalize()
    n = plain[-1]
    if not 1 <= n <= 16 or plain[-n:] != bytes([n]) * n:
        raise SystemExit("Gateway response could not be decrypted")
    result = json.loads(plain[:-n])
    if not result.get("config"):
        raise SystemExit("Gateway did not return a configuration")
    config = unpack(result["config"])
    outbounds = []
    for container in config.get("containers", []):
        stored = container.get("xray", {}).get("last_config")
        if not stored:
            continue
        xray = json.loads(stored) if isinstance(stored, str) else stored
        outbounds.extend(o for o in xray.get("outbounds", []) if o.get("tag") in ("proxy", "proxy-relay"))
    if not any(o.get("tag") == "proxy" for o in outbounds):
        raise SystemExit("Gateway export has no VLESS primary")
    for outbound in outbounds:
        if outbound["tag"] == "proxy":
            outbound["tag"] = "vless-reality"
    outbounds += [{"tag": "direct", "protocol": "freedom"}, {"tag": "block", "protocol": "blackhole"}]
    args.output.write_text(json.dumps({"outbounds": outbounds}, indent=2) + "\n")
    args.output.chmod(0o600)
    print("Private VLESS profile refreshed; country=" + args.country)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, IndexError, OSError, urllib.error.URLError) as error:
        raise SystemExit("Profile refresh failed: " + type(error).__name__) from None
