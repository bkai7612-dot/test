# Development Checklist

Legend:
- **Code**: implemented in this repository.
- **Auto**: covered by the automated tests (offline `luau` and in Studio via `RunTests`).
- **Static**: passes `luau-lsp` type analysis against the Roblox API definitions.
- **Studio**: verified by a manual Studio playtest. **No item is marked Studio yet**, because Studio was not available in the development environment.

| # | Milestone | Code | Auto | Static | Studio | Notes |
|---|---|---|---|---|---|---|
| 1 | Project structure, movement, camera, basic combat, health, stamina, death, respawn | ✅ | ✅ (Combat, Death) | ✅ | ⬜ | Rojo layout. Lock-on camera, dodge/block/parry/stamina, respawn at a shrine |
| 2 | Classes, XP, attributes, inventory, equipment, persistence | ✅ | ✅ (Progression, Inventory, Profile) | ✅ | ⬜ | Session-locked DataStore; Studio memory fallback with a HUD warning |
| 3 | Fallen Sanctuary, shops, checkpoints, training grounds | ✅ | ✅ (Economy, Training) | ✅ | ⬜ | 13 NPCs, 4 shops, blacksmith, 8 shrines with fast travel, 6 training challenges |
| 4 | Wildlands, enemy AI, loot, quests, exploration | ✅ | ✅ (Loot, Quest, DataIntegrity) | ✅ | ⬜ | 8 regions, 22 spawn zones, 3 mini-bosses, 11 chests, 16 quests |
| 5 | Boss framework + bosses 1–3 | ✅ | ✅ (Encounter, BossFairness) | ✅ | ⬜ | Instanced arenas, phases, telegraphs, rewards |
| 6 | Bosses 4–10 + balance | ✅ | ✅ (Balance) | ✅ | ⬜ | Counter stances, twins, ambient hazards, teleports, armour |
| 7 | Bosses 11–20, phase mechanics | ✅ | ✅ | ✅ | ⬜ | Airborne, stances, weak points, illusions, pulses, 3-phase final boss and ending |
| 8 | Co-op parties, boss scaling, multiplayer progression | ✅ | ✅ (Party, Encounter) | ✅ | ⬜ | HP scaling and rescaling, individual rewards |
| 9 | Death recovery, advanced equipment, achievements, optional content | ✅ | ✅ (Death, Achievement) | ✅ | ⬜ | Hollow Vale, Ashen Pit PvP, 24 achievements, build presets |
| 10 | Cosmetic and convenience monetisation | ✅ | ✅ (Receipt) | ✅ | ⬜ | All products disabled until IDs are configured |
| 11 | Visual/audio polish, accessibility, mobile, performance | ✅ (baseline) | – | ✅ | ⬜ | Atmosphere, telegraph colours, settings, touch/gamepad. Music needs licensed IDs |
| 12 | Regression, security review, release prep | ✅ | ✅ 127 tests | ✅ | ⬜ | Independent tester review: 14 findings, all addressed (see QA_REPORT.md) |

## Manual Studio playtests still required

Run these with the game published and API services enabled. Use **Test → Clients and Servers** for the multiplayer items.

**Core**
- [ ] Join, class selection appears, each of the six classes spawns with the right loadout and abilities.
- [ ] Movement, sprint drain, dodge distance (light / heavy / overloaded), camera collision.
- [ ] Lock-on: acquire, switch (wheel / D-pad), breaks on death, distance and line of sight.
- [ ] Light combo, charged heavy, block (stamina drain, guard break), parry vs gold telegraph, riposte on a staggered enemy, backstab.
- [ ] The weapon Tool appears in hand and the slash animation plays for other clients.
- [ ] Mobile: every touch button is reachable and the layout doesn't overlap the thumbstick. Gamepad: every binding works and menus are navigable.

**Death and persistence**
- [ ] Death drops embers at the right spot; recovery works once; a second death loses the first marker.
- [ ] Fall into the void → the marker appears at the last ground position.
- [ ] Die in an arena → the marker appears at the Tower Gate.
- [ ] Leave and rejoin: level, inventory, equipment, marker, quests and tower progress all persist.
- [ ] Join the same account on two servers → the second session takes the lock and the first stops saving (kicked).
- [ ] Shut down the server → BindToClose saves (check on rejoin).

**World and economy**
- [ ] Every shop: buy, quantity, limits, locked stock. Sell back for less than the purchase price.
- [ ] Blacksmith preview matches the result; materials and currency are deducted once.
- [ ] Shrines: rest restores everything, fast travel works, level-up allocation works only at a shrine.
- [ ] Every training challenge can be completed and failed. The daily and +5 caps are respected.
- [ ] Chests open once per character. Discoveries award XP once. The Vale stays sealed before floor 10.
- [ ] Enemy AI: aggro, leash, return-and-heal, stuck recovery near walls and buildings, cave navigation.

**Bosses (repeat for each of the 20)**
- [ ] The arena builds, the boss spawns facing the players, and the intro title card shows.
- [ ] Every attack's telegraph matches its real hit area. Recoveries leave a punish window.
- [ ] Phase transitions fire at the right HP. Mechanics work: twins enrage (6), ambient hazards (7, 11, 16, 19), armour break (10, 19), airborne/landing (12), stances (13), weak points (16), illusions (17, 20), counter stance (4, 9).
- [ ] Victory: rewards once, next floor unlocks, return to the gate. Defeat: the arena cleans up.
- [ ] Replay rewards are reduced, and the unique drop chance works.

**Co-op**
- [ ] Party invite / accept / kick / promote / leave. A non-leader can't start an encounter.
- [ ] A member without the floor unlocked is left behind and told why.
- [ ] A member dies or disconnects mid-fight → boss HP rescales and the remaining players can still win.
- [ ] Everyone dies → the boss resets. No duplicate rewards after rejoin.
- [ ] PvP pit: damage only between players both in the pit; no embers lost.

**Performance**
- [ ] A 12-player server with active zones and 3 concurrent arenas: check server heartbeat, network receive rate and client FPS on a low-end mobile device.
