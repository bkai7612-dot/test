# Design Reference

All numbers live in `src/shared/Config` (mostly `GameConfig.luau`). This document explains the rules behind them.

## Pillars → systems

| Pillar | Systems |
|---|---|
| Skill-based combat | Stamina economy, telegraphs, i-frames, parry windows, poise/stagger, ripostes, boss patterns |
| Exploration | Eight regions, 13 discoverable locations (4 secret), 11 one-time chests, 3 mini-bosses, a hidden vale |
| Progression | Levels, attributes with soft caps, scaling grades, upgrades, rarities, abilities |
| Co-op | Parties, shared arenas, HP scaling, individual rewards |
| Replayability | Boss replays with loot, achievements, titles, cosmetics, build presets, hybrid builds |

## Formulas (`src/shared/Logic/Formulas.luau`)

- **Soft caps.** `softCap(v) = Base + Σ segments` with a smaller gain per point in each segment. Examples: Health = 300 + 30/pt to 20, 20/pt to 40, 8/pt to 60, 2/pt to 99. Stamina, mana, equip load and weapon scaling follow the same pattern.
- **XP.** `xpToNext(L) = floor(60·L^1.45 + 40·L)`. Each level gives 1 attribute point. Levels cap at 120 and attributes at 99.
- **Weapon attack rating.** `D·R·(1+u·Up) + Σ D·R·G(grade)·S(attr)·(1+u'·Up)`. Here D is base damage, R is the rarity power (1.00–1.20), and G is the grade coefficient (S 1.2, A .95, B .75, C .5, D .3, E .15). If requirements aren't met, the weapon deals **60% damage and gains no scaling**. It's never locked, which keeps hybrid builds viable.
- **Upgrades.** Standard path is +10 (+9%/level). Unique boss gear is +5 (+18%/level). Armour is +5 (+8% defence/level).
- **Defence.** `absorption = min(0.72, def/(def+K))`. K is 160 for players and 120 for enemies. Defence buffs stack to a maximum of 80%.
- **Bosses.** HP = `1100·1.14^(f−1)·HealthMult`. Damage = `120·(1+0.16(f−1))`. Timing multiplier: windups `max(0.7, 1.08−0.02(f−1))`, recoveries `max(0.6, 1.1−0.03(f−1))`.
- **Party scaling.** Boss HP ×`1+0.7(n−1)` and poise ×`1+0.25(n−1)`. Boss damage doesn't scale.
- **Recommended level.** `5 + 4.5(f−1)`. Recommended upgrade level is `min(10, floor(f/2))`.

## Combat rules (`CombatCore`)

- **Costs.** A light attack costs 14 stamina and a heavy costs 26, each multiplied by the weapon type's multiplier. A dodge costs 18 (more when heavily loaded), and a parry costs 10. Stamina regenerates at 34/s after a 0.75 s delay, and at 40% speed while blocking. An action is allowed while stamina is above 0.
- **Dodge.** 0.32 s of i-frames and a 0.5 s cooldown. A dodge can cancel attack recovery but not the windup.
- **Parry.** 0.22 s window (shields can add more). It works only on attacks marked *Parryable* (gold telegraphs) while you face the attacker. Parrying an enemy staggers it. Parrying a boss removes 34% of its poise, or more against the Crimson Duelist.
- **Latency grace.** A hostile hit that resolves at time T is applied at T+0.15 s. A dodge registered in [T−0.32, T+0.15] or a parry in [T−window, T+0.15] still counts.
- **Block.** Covers 130° in front of you. Damage is reduced by the stability %, and blocking drains stamina. A guard break (stamina reaching 0) stuns for 1.1 s.
- **Poise and stagger.** If a hit's poise exceeds yours, you are staggered for 0.45 s. You then can't be staggered again for 1.2 s, which prevents stun-locks.
- **Criticals.** A riposte on a staggered enemy deals ×2.5. A backstab deals ×1.6 (never against bosses). Daggers add +0.5 to critical multipliers.
- **Status effects.** Bleed procs for a percentage of max HP (12% vs players, 8% vs enemies, 4% vs bosses). Poison and burn deal damage over time. Arcane and the Bloodstone Ring increase build-up.
- **Hits per swing** are capped at 6. Weak points take priority over their parent body, so damage isn't counted twice.

## Telegraph language

| Colour | Meaning | Correct answer |
|---|---|---|
| Gold | Parryable | Parry, block or dodge |
| White | Blockable, not parryable | Block or dodge |
| Red | Unblockable | Dodge or move away |
| Green disc | Safe zone (pulses, ring centres) | Stand inside it |
| Purple | Lingering hazard | Leave it |

The *High-contrast telegraphs* setting remaps these colours to cyan, white, magenta, green and orange.

## Bosses (see `BOSSES.md`)

- Every attack's authored windup, after floor scaling, stays **≥ 0.42 s** for the first strike and **≥ 0.35 s** for combo follow-ups. Recoveries stay **≥ 0.30 s**. Arena-wide pulses always have at least two safe zones with a radius of 8 or more and a windup of at least 2 s. `tests/BossFairness.spec` enforces all of this.
- Balance simulation (`tests/Balance.spec`): at the recommended level and gear, every class kills every boss solo in 30–360 s (the final boss up to 450 s). No single hit removes more than 60% of HP, and every boss can remove at least 15%.
- Difficulty escalates through new mechanics, longer combos, tighter timings and more phases, not only through bigger numbers.
- Phase changes play a 2 s invulnerable roar and announce the phase name.

## Death and currency recovery (`DeathCore`)

1. On death, all carried embers move to a recovery marker. The marker is placed at the death position, at the last solid ground if you fell out of the world, or in front of the Tower Gate if you died in an arena.
2. **Second death rule (`LosePrevious`):** dying again before recovering destroys the earlier marker. A configurable `Merge` rule exists as an alternative.
3. A marker expires after 2 hours of real time.
4. Only the owner can recover their marker, by walking within 9 studs. Recovery happens exactly once.
5. The marker is saved in the profile, so it survives disconnects and shutdowns. Equipment and purchases are never affected by death.
6. Deaths in the Ashen Pit (PvP) and in sparring cost nothing.
7. Respawning at your shrine refills your flask charges.

## Co-op encounter rules (`EncounterCore`)

- A solo player or a party leader starts an encounter at the Tower Gate. Party members standing within 40 studs who have the floor unlocked join. Anyone without it unlocked is told why and left out.
- Participants are fixed at the start, and nobody can join mid-fight. A participant who dies or disconnects is removed, and boss HP is rescaled down proportionally.
- When every participant is gone, the boss resets (the encounter fails).
- On victory, every participant who is still alive in the arena is rewarded **individually, once**. First clears unlock the next floor and grant the unique rewards. Replays grant 35% XP and currency, a replay loot roll, and a 12% chance at one of the boss's unique items.
- Up to 12 arenas can run at once on a server, each in its own slot.

## Training caps (`TrainingCore`)

The server measures every challenge itself (rep timing, dummy hits, avoided or parried drills, ordered course posts, sparring). Each challenge has its own cooldown. You can earn at most 12 training points per day, and every 10 points gives +1 to the challenge's attribute, up to **+5 per attribute in total**.

## Enemy spawning

There are 22 spawn zones with fixed maximum counts and respawn timers, and at most 120 active enemies in total. Enemies never spawn within 25 studs of a player. Enemies leash back to their home point, fully heal and forget damage contributors when pulled too far, which prevents kiting and farming exploits. Rewards go to every player who dealt at least 10% of the enemy's max HP, or who landed the killing blow. Loot is granted directly to each player's inventory, so it can't be stolen.

## Monetisation policy

Purchases can only be cosmetic (auras, weapon finishes, dyes) or a non-combat convenience (extra build-preset slots that store gear you already own). There are no boss skips, no currency sales, no combat power and no paid-only weapons. Products are disabled until real IDs are configured.
