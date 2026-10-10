# QA Report

This report covers two development agents:
- **Agent A (Developer):** implementation and self-checks.
- **Agent B (independent Tester):** code review and exploit research.

It records only what was actually done. **No Roblox Studio playtest has been run**, because the development environment had no Studio access. Every item below is either automated (offline) or the result of code review.

## Verification performed

| Check | Tool | Result |
|---|---|---|
| Unit, logic and balance tests | `tools/run_tests.sh` (standalone Luau 0.640, emulated DataModel) | **127 passed, 0 failed** (18 suites) |
| Type and lint analysis vs the Roblox API | luau-lsp 1.32.1 + Roblox definitions + Rojo sourcemap | **0 errors / 0 warnings** across `src/` and `tests/` |
| Place build | Rojo 7.4.4 `rojo build` | Builds `TowerOfTheFallen.rbxlx` |
| Independent review | Tester agent: all server services, cores and configs | 14 findings (1 High, 7 Medium, 6 Low); all addressed below |
| Selene lint | selene 0.27.1 | **Not run.** Selene couldn't download its Roblox standard library through the sandbox's TLS proxy. |

### Test suites

- **DataIntegrity:** every cross-reference is valid (items, loot, shops, quests, bosses, world). Each class starts with 74 attribute points. Sell price is always below buy price. Products grant cosmetics only.
- **Formulas, Geometry, Loot:** soft caps, XP curve, scaling, requirement penalty, upgrade clamps, hit shapes, deterministic RNG.
- **Inventory, Economy:** malicious quantities (0, −1, 1.5, NaN, ±inf, strings); no negative balances; lifetime limits; atomic failures checked with profile snapshots.
- **Progression, Profile:** class can only be picked once; XP and level cap; all-or-nothing allocation; corrupt-data repair without wiping progress; v1→v2 migration; idempotent reconcile.
- **Death:** a single recovery; proximity; second-death rule; expiry; no-loss deaths; marker survives a save/load round trip.
- **Receipt:** idempotent per PurchaseId; unknown products and products with ID 0 are rejected; bounded history.
- **Encounter, Party:** sequential unlocks; reward exactly once (including a replayed encounter id); replay rewards; dead or disconnected players don't qualify; wipe means failure; party permissions and caps.
- **Combat:** stamina, action locks, i-frames with latency grace, parry facing and the parryable flag, block and guard break, stagger immunity (anti stun-lock), status procs, poise, a server-measured heavy charge (added after the review).
- **Quest, Achievement, Training:** prerequisites, kill matching, collect consumption, autoclick detection, cooldowns, daily cap and the +5 cap.
- **BossFairness:** all 20 bosses have at least 3 attacks and at least 2 phases. First-strike windup is at least 0.42 s and combo follow-ups at least 0.35 s after floor scaling. Recovery is at least 0.30 s. Pulses have safe zones. Complexity rises from floors 1–5 to floors 16–20.
- **Balance:** simulated solo time-to-kill is 30–360 s for every class on every floor (up to 450 s for the final boss). No hit removes more than 60% of HP, and every boss can remove at least 15%.

Defects caught by the tests during development:
- Late-floor time-to-kill reached up to 726 s. Fixed by retuning boss HP growth (1.16 → 1.14) and late-boss defence.

Defects caught by static analysis:
- 30 nil-safety and type issues. All fixed.

## Independent Tester findings and resolutions

| ID | Sev | Finding | Resolution |
|---|---|---|---|
| D1 | **High** | A dead player could start empty encounters and fill all 12 arenas for 15 minutes (server-wide denial of service). | **Fixed.** `EnterFloor` rejects dead requesters; there is a 5 s per-player cooldown; the requester must be in the group; `startEncounter` refuses an empty group before taking a slot. |
| D2 | Med | Two weak points hit by one swing double-dipped, and weak points could be backstabbed (~5× damage). | **Fixed.** Melee collapses hits to one per root entity (the best weak point replaces its parent). Backstabs are disabled on boss parts. |
| D3 | Med | World enemies could be sniped from beyond aggro range, or from a safe zone, with no risk. | **Fixed.** Taking damage makes the AI chase the attacker if reachable; otherwise it resets home at full HP and clears contributors. No damage to world enemies from safe zones. |
| D4 | Med | A queued autosave could re-acquire the session lock after the player left or during shutdown. | **Fixed.** `Save` re-checks the released state and profile identity after waiting. Non-release saves are refused once the player has left. BindToClose marks profiles as released. |
| D5 | Med | Heavy-attack charge was client-reported (+60% damage for free). | **Fixed.** The charge is timed on the server between the `HeavyStart` and `Heavy` intents. Dodging cancels it. A test was added. |
| D6 | Med | Dodging cancelled the flask animation but the heal still landed. | **Fixed.** You can't dodge until the heal lands; a dodge before the heal cancels it. |
| D7 | Med | Network ownership could pass to a client after kinematic moves, letting an exploiter fling enemies into the void for rewards. | **Fixed (defensive).** `SetNetworkOwner(nil)` is re-applied after unanchoring. Void deaths give no rewards. *Needs Studio confirmation.* |
| D8 | Med | Another player could finish someone else's sparring challenge. | **Fixed.** The sparring partner is owner-only (others can't damage it), and success requires the owner's kill. |
| D9 | Low | Pulse safe zones could be out of sprint reach at high floors (up to 38%). | **Fixed.** One safe zone is seeded near each victim, and the windup is extended so the nearest zone is always reachable at sprint speed. |
| D10 | Low | A boss dying mid-dash could drop out of its death fade. | **Fixed.** The root is only unanchored if the entity is still alive. |
| D11 | Low | ShadowStep tripped the anti-cheat and could target foreign entities. | **Fixed.** Teleport whitelisting added; targets must be hittable roots, not dummies or weak points. |
| D12 | Low | Non-participants (for example flying exploiters) could damage arena bosses. | **Fixed.** Entities tagged with an encounter can only be hit by that encounter's participants (enforced centrally in `HitEntity` and the melee sweep). The anti-cheat still has no flight or noclip detection. *Open limitation.* |
| D13 | Low | The dodge drill passed while AFK; one ability counted several dummy hits. | **Fixed.** You must be within reach when each drill attack starts; only weapon swings count, at most once per swing. |
| D14 | Low | Ambient hazards always targeted player 1; ambient hazards were tied to twin #1; Heal ability healed PvP foes; a leader can pull members in; dead players get no boss reward. | **Fixed:** ambient hazards rotate targets and have their own arena caster; healing goes to party members only. **By design (documented):** standing at the gate counts as consent to join; dying before the boss falls forfeits that attempt's reward (Soulslike rule). |

### Areas the Tester checked and found sound

- Remote payload validation and rate limiting.
- Shop atomicity and limits; no arbitrage.
- Inventory validate-then-mutate.
- ProcessReceipt idempotency and save-before-grant.
- Encounter reward idempotency and floor gating.
- Ember recovery (owner-only, single credit).
- Progression requests.
- Respawn invulnerability against queued hits.
- Session-lock takeover logic.

### Not covered by the independent review

- The **client controllers** (input, lock-on camera, menus, mobile and gamepad). The Tester ran out of time. Only the Developer's self-review and type analysis apply to them.

## Defects found in the first Studio playtest (user report)

| ID | Sev | Finding | Resolution |
|---|---|---|---|
| S1 | **Critical** | The player fell through the world and died right after spawning. `WorldBuilder` set `Lighting.Technology`, which only Roblox can write. The error aborted the whole world build, so no terrain or map existed. | **Fixed.** `Technology` is now set in `default.project.json`. Each world-build step is isolated with pcall, and terrain is built first. A fall-rescue returns players who fall below Y = −60 to solid ground. New `tools/check_api_security.py` scans for writes to non-script-writable properties; it flags the old code and passes on the fix. |

## Known limitations / open items

1. **No Studio playtest yet.** The runtime behaviour of the Roblox-specific code still needs the manual playtests in `CHECKLIST.md`: physics, Humanoid movement, network ownership, UI layout, touch button placement, telegraph visuals and performance.
2. **Movement anti-cheat is horizontal-speed only.** There's no flight or noclip detection. Combat, economy and progression don't depend on trusting movement, and arena bosses can only be damaged by participants.
3. **No custom animations or music.** The game relies on procedural animation, Tool slash animations, built-in sounds and empty music slots, so licensed assets are needed for full polish.
4. **Balance is simulated.** TTK and damage bounds come from a model of the game, not from real players. Expect tuning after playtests.
5. **Parties are per-server.** There is no cross-server matchmaking; players use Roblox's join-friend flow to share a server.
6. **Lighting technology** is set to Future at runtime. Check performance on low-end mobile.

## Manual tests still required

See `docs/CHECKLIST.md` → *Manual Studio playtests still required*. Pay particular attention to D7 (network ownership after dashes) and to the two-server session-lock scenario.

## Update: sculpted boss models and rendering pass

- `BossModels.luau` gives each of the 20 bosses its own model, built from engine primitives with lights, Fire, Smoke and particles. No uploaded assets are used. If a builder errors, it falls back to the old generic model.
- **Verified offline:** a Roblox math/instance mock built all 21 models (20 bosses plus the second twin). For each model it checked:
  - every part is welded back to the root;
  - the swing motor is consistent and not welded shut;
  - Torso, ArmorPlate and WeakPoint attachments are present;
  - feet are on the ground;
  - the Reaper hovers 16 studs up;
  - at most 4 lights.
  - Silhouettes were reviewed in an offline preview: `docs/boss_models_preview.png`.
- **Rendering pass:**
  - PBR environment reflections, crisper shadows, depth of field (turned off by Reduced Effects), volumetric clouds and reflective water.
  - Bloom tuned so neon glows.
- **NOT verified in Studio:**
  - In-engine look, wedge orientation on spikes, and server performance with ~60–170 parts per boss.

## Update: catalyst move sets, double jump, flips and night lighting

- **Staff and seal:** three spells per light combo plus a heavy spell, each with its own mana cost. When you can't afford the next spell, the catalyst uses mana-free physical strikes, and each strike that lands restores 3 mana.
- **Movement:** a double jump. Double jump then dodge gives a fresh flip; dodge then jump gives a chained flip. Both are front or back flips depending on input, and both give dodge i-frames.
- **Night:** ClockTime 0.4, with a starry sky and a large moon. A strong cool ambient and per-region exposure keep the world readable, and the hub stays the brightest area.
- **Verified offline:**
  - 150 unit tests, including 17 new ones in `Catalyst.spec` and `Movement.spec`.
  - 38 integration checks (`tools/run_integration.sh`) that run the real client and server controllers. Three deliberately injected bugs were each caught.
  - Type check and API-permission check are clean.
- **NOT verified in Studio:**
  - How the flip looks and feels: rotating the root joint mid-air, and the jump heights.
  - How bright the night lighting is on real displays.
  - Animator interaction with Roblox's own jump animation.
