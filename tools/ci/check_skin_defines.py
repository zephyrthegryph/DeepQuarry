#!/usr/bin/env python3
"""Every SKIN_* define must name a window or control that exists in interface/skin.dmf."""
import re
import sys

windows, controls = set(), set()
current = None
for line in open("interface/skin.dmf", encoding="utf-8", errors="ignore"):
    m = re.match(r'^window "([^"]+)"', line)
    if m:
        current = m.group(1)
        windows.add(current)
        continue
    m = re.match(r'^\s+elem "([^"]+)"', line)
    if m and current:
        controls.add(f"{current}.{m.group(1)}")
        controls.add(m.group(1))

bad = []
for number, line in enumerate(open("code/__defines/skin.dm", encoding="utf-8"), 1):
    m = re.match(r'^#define (SKIN_\w+) "([^"]+)"', line)
    if not m:
        continue
    value = m.group(2)
    if value not in windows and value not in controls:
        bad.append(f"code/__defines/skin.dm:{number}: {m.group(1)} = \"{value}\" is not in interface/skin.dmf")

for b in bad:
    print(b)
sys.exit(1 if bad else 0)
