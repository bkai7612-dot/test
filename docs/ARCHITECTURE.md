# Architecture

## Principles

1. **The server is authoritative.** Clients send *intents* (for example "light attack", "buy item X ×2", "enter floor 5"). The server decides every outcome: hits, damage, rewards, purchases and progression.
2. **The logic is pure where possible.** Rules live in `src/server/Core` and `src/shared/Logic` as functions over plain tables, with an explicit `now`. The offline test suite exercises them, and they behave identically in Studio.
3. **The design is data-driven.** Every class, item, enemy, boss, attack, loot table, shop, quest, achievement, cosmetic, product, training challenge and world location is defined in `src/shared/Config`.
4. **Each service has one responsibility.** Every Roblox-facing system is a module with `Init(services)` and `Start()`. `Bootstrap.server.luau` creates the remotes and initialises the services in dependency order.

## DataModel mapping

| Rojo path | Roblox location | Contents |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Shared` | `Config/*`, `Logic/{Formulas,Stats,Geometry}`, `Util/{Rng,Signal}`, `Net` |
| `src/server` | `ServerScriptService.Server` | `Bootstrap` (Script), `TestRunner` (Script), `Core/*`, `Services/*` |
| `src/client` | `StarterPlayerScripts.Client` | `Main` (LocalScript), `Controllers/*` |
| `src/character/Health.server.luau` | `StarterCharacterScripts.Health` | Empty override that disables passive regeneration |
| `tests` | `ServerStorage.Tests` | `TestKit`, `Helpers`, `*.spec` |
| (runtime) | `Workspace.Map`, `.Entities`, `.Arenas`, `.Telegraphs`, `.Projectiles`, `.LostEmbers` | World and transient instances built by the server |
| (runtime) | `ReplicatedStorage.Remotes` | RemoteEvents / RemoteFunction created by `Net.setupServer()` |

The interface is built in code into `PlayerGui` (`TotfHUD`, `TotfMenu`) instead of being stored in StarterGui, so that the whole game can be versioned as text.

## Server services (initialisation order)

| Service | Responsibility |
|---|---|
| DataService | DataStore load/save with session locking, retries, autosave, BindToClose and a Studio memory fallback |
| NotifyService | Toasts and banners sent to clients |
| RequestService | A single RemoteFunction router with rate limiting and pcall isolation |
| TelegraphService | Ground telegraphs, hazard zones and impact flashes |
| EntityService | Registry of damageable NPC entities. Applies armour, counter stances, weak points and contribution tracking |
| WorldBuilder | Builds the lighting, terrain, tower, hub, NPCs, shrines, chests, training grounds and regions, plus the arena factory |
| PlayerStateService | Per-player runtime: profile, stats, combat state, spawning, regen and status ticks, vitals replication, profile sync |
| AntiCheatService | Movement speed sanity checks, with a whitelist for server teleports |
| ProjectileService | Server-simulated projectiles |
| AttackExecutor | Runs any enemy or boss attack definition: telegraph → windup → resolve → recovery |
| CombatService | Validates player actions, computes damage, applies hostile hits with latency grace, abilities, flask and items |
| ProgressionService | The single path for rewards (XP, currency, items, abilities, titles, cosmetics). Also kill stats, quest events, achievements and character requests |
| InventoryService | Equip/unequip, sell, blacksmith upgrades, build presets and the held weapon Tool |
| ShopService | Merchant purchases |
| InteractionService | NPC proximity prompts and proximity validation |
| CheckpointService | Ember Shrines: rest, respawn point, fast travel |
| DeathService | Death handling, currency drop markers, recovery, respawn |
| QuestService | Accept, abandon and turn in quests |
| ExplorationService | Regions, discoveries, chests and the Hollow Vale gate |
| EnemyService | Spawn zones, AI state machine, pathfinding fallback, rewards |
| PartyService | Parties per server |
| BossService | Tower encounters: arena instancing, boss controllers, mechanics, victory and defeat |
| TrainingService | Server-measured training challenges |
| CosmeticService | Auras, weapon skins, dyes and title tags (visual only) |
| PurchaseService | ProcessReceipt and game pass checks |
| LeaderboardService | leaderstats, OrderedDataStore boards |

## Pure cores (`src/server/Core`) and shared logic

`ProfileSchema` (defaults, migrations, validation), `InventoryCore`, `EconomyCore`, `ProgressionCore`, `DeathCore`, `ReceiptCore`, `LootCore`, `EncounterCore`, `PartyCore`, `QuestCore`, `AchievementCore`, `TrainingCore`, `CombatCore`, `BossBrain`, and in shared: `Formulas`, `Stats`, `Geometry`, `Rng`.
Every mutating core function **validates first and mutates second**, so a rejected request leaves the profile byte-for-byte unchanged. The tests check this directly by comparing snapshots.

## Networking

| Remote | Direction | Payload |
|---|---|---|
| `Action` (RemoteEvent) | C→S | `{ Kind = Light/Heavy/Dodge/Parry/Block/Sprint/Ability/Flask/Item/Rep, ... }` |
| `Request` (RemoteFunction) | C→S→C | `(name, payload) → { Ok, Result / Error }` |
| `Profile` | S→C | Sanitised profile snapshot plus derived stats |
| `Notify` | S→C | Toasts and banners |
| `Fx` | S→C | Damage numbers, hurt, parry, rewards, cooldowns |
| `Boss` | S→C | Encounter start, bars, phases, victory, defeat, end, ending |
| `OpenUI` | S→C | Open an NPC, shrine or tower menu |
| `Party` | S→C | Party state and invites |
| `Training` | S→C | Training HUD state |

High-frequency vitals (health, stamina, mana, flask, currency, level, region) replicate as **Player attributes**, so they don't require remote events.

### Request names

`ChooseClass, AllocateAttributes, SetAbilitySlot, SetTitle, SaveSettings, Equip, Unequip, Sell, UpgradePreview, Upgrade, UseItem, SavePreset, LoadPreset, Buy, AcceptQuest, AbandonQuest, TurnInQuest, Travel, EnterFloor, LeaveArena, PartyInvite, PartyRespond, PartyLeave, PartyKick, PartyPromote, EquipCosmetic, PromptProduct, PromptPass`

## Security model

- **Damage:** clients never send damage or targets for melee. The server resolves cones and lines from server-side character positions. Projectiles are simulated on the server, and the aim direction is clamped to within 75° of the character's facing.
- **Timing:** action locks, cooldowns, stamina and mana are checked in `CombatCore`. Requests are token-bucket rate limited (20/s).
- **Economy:** prices, stock, limits and floor gates come from the server config. Quantities must be integers from 1 to 20. NaN, infinity and non-numbers are rejected. Validation happens before mutation, and sell prices are always below buy prices (a test covers this).
- **Proximity:** shops, the blacksmith, quest givers, shrines, chests, training stations and the tower gate are all distance-checked on the server.
- **Progression:** a floor is unlocked only when `HighestCleared ≥ floor − 1`. Rewards are idempotent per encounter (`Rewarded` set plus `profile.Tower.RewardedEncounters`).
- **Death recovery:** a marker is tied to its owner's profile, so only the owner can recover it. Recovery clears the marker and credits currency in the same synchronous step.
- **Purchases:** `ProcessReceipt` is idempotent by `PurchaseId`. The server returns `PurchaseGranted` only after a successful save. Clients can only ask the server to show the purchase prompt.
- **Persistence:** session locks prevent two servers writing the same profile. A server that loses its lock stops writing and kicks the player. Corrupt data is repaired field by field with logged corrections, never silently wiped.
- **Movement:** characters are client-simulated (a Roblox constraint). `AntiCheatService` resets players after sustained impossible speeds.
