"""Benennt die von `xcresulttool export attachments` exportierten Dateien
anhand der manifest.json in lesbare Namen um (z. B. 01-heute-hell.png)."""
import json
import os
import re
import sys

folder = sys.argv[1]
manifest_path = os.path.join(folder, "manifest.json")
if not os.path.exists(manifest_path):
    sys.exit(0)

with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)


def walk(node):
    if isinstance(node, dict):
        if "exportedFileName" in node:
            yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


for attachment in walk(manifest):
    source = os.path.join(folder, attachment["exportedFileName"])
    readable = attachment.get("suggestedHumanReadableName") or attachment["exportedFileName"]
    # Xcode hängt „_0_<UUID>“ an; das schneiden wir ab.
    stem, extension = os.path.splitext(readable)
    stem = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", stem)
    stem = re.sub(r"[^\w\-äöüÄÖÜß]+", "-", stem).strip("-")
    target = os.path.join(folder, f"{stem}{extension or '.png'}")
    if os.path.exists(source) and not os.path.exists(target):
        os.rename(source, target)
        print(f"{attachment['exportedFileName']} -> {os.path.basename(target)}")
