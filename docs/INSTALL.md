# Installation and Studio Setup

## 1. Tools

| Tool | Purpose | Version used |
|---|---|---|
| [Rojo](https://github.com/rojo-rbx/rojo/releases) | Sync/build the project into Roblox | 7.4.4 |
| [Luau CLI](https://github.com/luau-lang/luau/releases) | Offline test runner | 0.640 |
| [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp/releases) (optional) | Type analysis with Roblox definitions | 1.32.1 |
| Python 3 | Builds the offline test bundle | 3.x |

## 2. Get the game into Studio

**Option A: build a place file**

```bash
rojo build default.project.json -o TowerOfTheFallen.rbxlx
```
Open `TowerOfTheFallen.rbxlx` in Roblox Studio.

**Option B: live sync**

1. Install the Rojo Studio plugin.
2. Run `rojo serve` in the repository root.
3. In Studio, open a new Baseplate, then click **Rojo → Connect**.
4. Delete the default `Baseplate` part from Workspace. The world builds its own terrain at runtime.

## 3. Required Studio settings

1. **Game Settings → Security → Enable Studio Access to API Services**. Without it, DataStores are unavailable, so the game runs in memory-only mode and the HUD shows *"Studio test mode: progress is NOT being saved"*. This is intentional and safe.
2. Publish the place (File → Publish to Roblox) before testing saving, receipts or leaderboards.
3. `Workspace.StreamingEnabled` is set to `true` by the project. The tower model is marked *Persistent* so the landmark is always visible.

## 4. Running

- Press **Play** to test solo.
- Use **Test → Clients and Servers** with 2–4 players to test co-op, parties, PvP and reward distribution.
- On first join you will see class selection. After choosing, talk to **Ilya the Guide** for a tutorial.
- The Tower Gate is north of the hub. Training Grounds are to the east, the Ashen Pit to the west.

## 5. Running the automated tests

**Offline (no Studio):**

```bash
LUAU=/path/to/luau tools/run_tests.sh
```

**Integration scenarios (no Studio):** these run the real client `CombatController` and the server `CombatService` against a mocked Roblox runtime with a simulated clock. They cover the double jump, both flip combos, flip i-frames and cooldown, staff spells (projectile count, spread, pierce, mana costs) and the mana-free strikes (mana siphon).

```bash
LUAU=/path/to/luau tools/run_integration.sh
```

**In Studio:** select `Workspace`, add a **boolean attribute `RunTests = true`**, then press Play. Results print to Output and are reported through `TestService`.

## 6. Monetisation configuration (optional)

All products ship disabled (`Id = 0`) in `src/shared/Config/Products.luau`. To enable them:

1. Create Developer Products and the Game Pass in the Creator Dashboard. Suggested prices are listed in the config.
2. Put the numeric IDs into `Products.luau`.
3. Only cosmetics and the build-preset convenience pass can be configured. The receipt handler grants only `Cosmetic` / `Cosmetics` entries.

## 7. Audio, animations and art

- **Sound effects** use Roblox's built-in `rbxasset://sounds/...` content (sword slash/lunge, unsheath, ping).
- **Music and ambience** IDs are intentionally empty in `src/shared/Config/Audio.luau`. Add licensed `rbxassetid://` IDs to enable them.
- **Animations:** players use the default character animations plus the Tool slash/lunge animations, which the server triggers. Enemies and bosses use procedural Motor6D swing animations, ground telegraphs and model movement. For custom animations, upload them and play them from `AttackExecutor` / `CombatController` (there is a clear hook where `EntityModels.windup/strike` is called).

## 8. Publishing checklist

- [ ] API services enabled; publish to a private test place first.
- [ ] Run the in-Studio test suite (`RunTests = true`).
- [ ] Complete the manual playtest list in `docs/CHECKLIST.md`.
- [ ] Configure product IDs (optional) and test one purchase per product in a private server.
- [ ] Set the experience's maturity questionnaire, devices (PC, mobile, console) and max players (recommended 12–16).

## 9. Promo and admin codes

- Players redeem codes in **Menu (Tab) → Codes**.
- Codes are defined in `src/server/Config/PromoCodes.luau`, which is server-only and never sent to clients.
  - `MaxUses` is a global limit across all servers, enforced atomically with a DataStore counter. In Studio memory mode the counter resets every session.
  - Each code works once per character.
- **Admin codes** unlock an admin panel on the Codes tab with: Never Die (toggle), Unlock all, All upgrades, All items and All customisations.
- Anyone who can read this repository or the `.rbxlx` file can read the codes. Change them before sharing the repository or the place file.
