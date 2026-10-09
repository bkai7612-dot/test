# Tower of the Fallen

An original dark-fantasy, Soulslike action RPG for Roblox. You explore the Wildlands, gather gear and embers, level up, and climb a central tower guarded by twenty bosses. You can play the whole game solo, or bring up to three friends.

This repository is a [Rojo](https://rojo.space) project written in Luau. It has no external asset dependencies: the world, characters, bosses, weapons and interface are all built from code using parts, terrain, lighting and particles.

> **Status (honest summary):** the code is complete for all 12 roadmap milestones. It passes 127 offline automated tests and a clean `luau-lsp` type analysis against the Roblox API definitions, and it builds into a place file with Rojo. It has **not yet been run in Roblox Studio**, because the development environment had no Studio access. See [docs/QA_REPORT.md](docs/QA_REPORT.md) for what was verified and [docs/CHECKLIST.md](docs/CHECKLIST.md) for the manual playtests still required.

## Quick start

```bash
# build a place file
rojo build default.project.json -o TowerOfTheFallen.rbxlx
# or live-sync into an open Studio place
rojo serve
# offline tests (needs the luau CLI)
LUAU=/path/to/luau tools/run_tests.sh
```

Full Studio setup (enabling API services, publishing, product IDs, audio) is in [docs/INSTALL.md](docs/INSTALL.md).

## What's in the game

| Area | Content |
|---|---|
| Classes | Warrior, Knight, Mage, Wizard, Assassin, Paladin. Each has its own attributes, loadout and two abilities. No class is locked out of any gear. |
| Combat | Light combos, charged heavies, dodge rolls with i-frames, blocking with stability, timed parries, ripostes, backstabs, poise and stagger, stamina and mana, status build-up (bleed, poison, burn), lock-on |
| Progression | XP and levels (cap 120) and seven attributes with soft caps. Weapon scaling grades, a blacksmith with +10/+5 upgrade paths, six rarities, and 2 ability slots |
| World | Fallen Sanctuary hub, Training Grounds, Ashen Pit (PvP, opt-in), Mistveil Forest, Ruins of Ashford, Hallowed Rest Cemetery, The Hollow Deep caves, Broken Gate Fortress, and the hidden Hollow Vale |
| Tower | 20 bosses, each with its own mechanic and its own instanced arena. Solo and party play, replays, and first-clear rewards |
| Souls systems | Ember Shrines (rest, respawn, fast travel), currency drop on death with one-chance recovery, and Ember Flask charges |
| Social | Parties (invite, kick, promote), co-op boss scaling, global leaderboards and titles |
| Meta | 16 quests, 24 achievements, cosmetics (auras, weapon finishes, dyes, titles) and build presets |
| Monetisation | Cosmetic and convenience purchases only. Server-validated, idempotent receipts. Every product is disabled until you configure a real ID |

## Repository layout

```
default.project.json   Rojo mapping
src/shared/            ReplicatedStorage.Shared - Config (all data), Logic (formulas), Util, Net
src/server/            ServerScriptService.Server - Bootstrap, Core (pure logic), Services (Roblox)
src/client/            StarterPlayerScripts.Client - Main + Controllers (input, camera, HUD, menus)
src/character/         StarterCharacterScripts.Health (disables default regen)
tests/                 ServerStorage.Tests - TestKit + *.spec modules (run offline or in Studio)
tools/                 offline test bundler / runner
docs/                  architecture, design, install, bosses, checklist, QA report
```

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) – services, data flow, remotes and security model
- [docs/DESIGN.md](docs/DESIGN.md) – formulas, rules, balance and fairness decisions
- [docs/BOSSES.md](docs/BOSSES.md) – the twenty guardians
- [docs/INSTALL.md](docs/INSTALL.md) – Studio setup, publishing and configuration
- [docs/CHECKLIST.md](docs/CHECKLIST.md) – milestone checklist with verification status
- [docs/QA_REPORT.md](docs/QA_REPORT.md) – tests run, defects found and fixed, known limitations
