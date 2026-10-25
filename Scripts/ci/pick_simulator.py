"""Gibt die UDID des passendsten iPhone-Simulators aus.

Bevorzugt die neueste iOS-Version und darin das iPhone 15 (dein Gerät),
sonst ein normales iPhone (kein Pro/Max/Plus), sonst irgendein iPhone.
"""
import json
import subprocess
import sys

raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
devices_by_runtime = json.loads(raw)["devices"]


def runtime_version(runtime_id: str) -> tuple:
    # z. B. com.apple.CoreSimulator.SimRuntime.iOS-26-1
    if ".iOS-" not in runtime_id:
        return ()
    return tuple(int(part) for part in runtime_id.split(".iOS-")[-1].split("-") if part.isdigit())


def preference(name: str) -> int:
    if name == "iPhone 15":
        return 3
    if not any(word in name for word in ("Pro", "Max", "Plus", "mini", "Air", "SE")):
        return 2
    return 1


candidates = []
for runtime_id, devices in devices_by_runtime.items():
    version = runtime_version(runtime_id)
    if not version:
        continue
    for device in devices:
        if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
            candidates.append((version, preference(device["name"]), device["name"], device["udid"]))

if not candidates:
    sys.exit("Kein iPhone-Simulator gefunden.")

candidates.sort()
version, _, name, udid = candidates[-1]
print(f"Simulator: {name} (iOS {'.'.join(map(str, version))})", file=sys.stderr)
print(udid)
