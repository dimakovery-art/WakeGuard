"""Print the UDID of an available iPhone on the requested iOS major."""
import json
import re
import subprocess
import sys

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
choices = []
for runtime, group in devices.items():
    version = re.search(r"\.iOS-(\d+(?:-\d+)*)$", runtime)
    if not version:
        continue
    numbers = tuple(map(int, version[1].split("-")))
    if numbers[0] != int(sys.argv[1]):
        continue
    for device in group:
        if device["isAvailable"] and device["name"].startswith("iPhone"):
            choices.append((numbers, device["name"], device["udid"]))
if not choices:
    sys.exit(f"Не найден симулятор iPhone на iOS {sys.argv[1]}. Проверьте образ runner.")
print(max(choices)[2])

