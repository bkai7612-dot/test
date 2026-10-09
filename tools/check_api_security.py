#!/usr/bin/env python3
"""
Flags property writes that Roblox scripts are not allowed to make (e.g. Lighting.Technology),
which throw at runtime and are invisible to type checkers.
Usage: python3 tools/check_api_security.py path/to/API-Dump.json
API dump: https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json
"""
import glob, json, re, sys

dump = json.load(open(sys.argv[1]))
cls = {c["Name"]: c for c in dump["Classes"]}
src = "".join(open(f).read() for f in glob.glob("src/**/*.luau", recursive=True))
used = set(re.findall(r'Instance\.new\("(\w+)"', src)) | set(re.findall(r'GetService\("(\w+)"\)', src))
used |= {"Part", "Humanoid", "Model", "Player", "Workspace", "Terrain", "Camera", "Tool", "Lighting"}

def chain(c):
    while c and c in cls:
        yield c
        c = cls[c].get("Superclass")

# names restricted on some used class AND never freely writable on any used class
restricted, free = {}, set()
for c in used:
    for k in chain(c):
        for m in cls[k]["Members"]:
            if m["MemberType"] != "Property":
                continue
            sec = m.get("Security", {})
            w = sec.get("Write") if isinstance(sec, dict) else sec
            if (w and w != "None") or "ReadOnly" in (m.get("Tags") or []):
                restricted.setdefault(m["Name"], set()).add(k)
            else:
                free.add(m["Name"])
PLAIN_TABLES = {"opts", "def", "spec", "step", "payload", "config", "a", "q", "c", "out", "rewards", "result", "r", "e", "ai", "ctl", "run", "rt", "state", "session", "profile", "p", "GameConfig"}
problems = 0
for f in glob.glob("src/**/*.luau", recursive=True):
    for i, line in enumerate(open(f), 1):
        if line.strip().startswith("--"):
            continue
        for m in re.finditer(r"(\w+)\.([A-Z]\w*)\s*=[^=]", line):
            # plain Lua config tables, not Instances
            if m.group(1) in PLAIN_TABLES:
                continue
            n = m.group(2)
            if n in restricted and n not in free:
                problems += 1
                print(f"{f}:{i}: {n} is not script-writable on {sorted(restricted[n])}")
print("OK" if problems == 0 else f"{problems} problem(s)")
sys.exit(1 if problems else 0)
