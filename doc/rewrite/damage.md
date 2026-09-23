# Damage (track D)

Every hit follows one path: an entry point builds a **packet**, mitigation reduces it, and a **sink** applies it. Thresholds then decide what breaks.

The two sinks are already mostly unified:
- every `/obj` uses tg-style integrity (`uses_integrity = TRUE`);
- all mob harm goes through the body rewrite's `injure()`.

What is missing is the layer in between.

## 1. Today

**Entry points.** About 590 overrides, each converting a hit into damage its own way:

| Proc | Overrides |
|---|---|
| `bullet_act` | 139 |
| `ex_act` | 144 |
| `emp_act` | 109 |
| `fire_act` | 41 |
| `hitby` | 35 |
| `attack_generic` | 57 |
| `blob_act` | 27 |
| `throw_impact` | 28 |
| `electrocute_act` | 6 |

Weapon hits on objects are 30 hand-written `take_damage(W.force, …)` calls inside `attackby`.

**Pools and armour**
- **Walls** keep their own `damage` var, with material caps.
- **About 15 separate health pools:**
  - item `health` for material weapons and armour;
  - blob2 `integrity`;
  - mecha component `integrity`, next to the mech's own atom integrity;
  - modular computer `damage`;
  - tank `integrity`;
  - plant `health`;
  - shield projector `shield_health`;
  - target `hp`;
  - rig `take_hit()`;
  - space suit breaches;
  - and others.
- **Mechs** have their own model: `absorbDamage`, `components_handle_damage`, `dynbulletdamage`.
- **Armour:**
  - a per-instance `armor = list(melee, bullet, …)` on items, with 762 types overriding it;
  - `run_armor_check` returns a percentage with ±25% random variance;
  - no armour datums, and no soak model.

**Duplicated ladders**
- **`ex_act`:** 45 severity switches; about 86 of them contain `qdel(src)`.
- **Machinery "broken":** 16 `atom_break` overrides, 6 `set_broken` definitions, and 32 set / 17 clear `BROKEN` sites.
- **Flavour text** at 1/4, 1/2 and 3/4 integrity is written out by hand 26 times.
- **Sharp to blunt:** armour turning sharp hits into blunt hits via `prob(getarmor)` has 6 copies.

**Bugs:** B2 (`fire_act` argument order), B3 (weapon melee never lands on non-human carbons), B17 (`BURN` and `FIRE` are the same string) and B20 (62 `take_damage` calls with one argument).

**Unused material properties.** Material science defines toughness, yield strength and elasticity, but none of them reach impacts today.

## 2. The packet

A damage packet is pooled and reused, not a new datum per hit.

| Field | Meaning |
|---|---|
| `amounts` | Amount per kind: blunt, sharp, pierce, thermal, cold, shock, corrosive, toxic, radiation, ionic, blast |
| `penetration` | Armour penetration |
| `zone`, `direction` | Where the hit lands and where it comes from |
| `source`, `attacker`, `weapon` | For logging, reactions and contracts |
| `flags` | Edge, projectile, silent, ignore resistance, … |

**Mapping to `injure()` kinds** (agreed with the body rewrite, Sept 2026). Ionic maps to `INJURY_ELECTRIC`, and each body part's biology decides the effect. Digestion, neural and cellular stay internal to the body and have no packet kinds.

**Division of work (agreed):** mob mitigation stays inside `injure()`, which applies armour, then shields, then resistance factors, then species/part multipliers. Armour goes through one lookup, `/mob/living/proc/injury_armor(kind, zone)`. The packet carries penetration, which `injury_armor` consumes, and the equipment aggregates later replace that proc's body. §4 applies to objects; for mobs, it describes what `injury_armor` computes.

| Packet kind | `injure()` kind today |
|---|---|
| Blunt | Blunt / bruise |
| Sharp | Cut |
| Pierce | Pierce |
| Thermal | Burn |
| Cold | Frostbite (today flattened into burn wounds) |
| Shock | Electric (today flattened into burn) |
| Corrosive | Corrosive (today flattened into burn) |
| Toxic | Toxin |
| Radiation | Radiation affliction |
| Ionic | Electric, for synthetic bodies |
| Blast | Blunt, plus a pressure effect |
| Pain | `INJURY_PAIN` (stun and nonlethal weapons; replaces HALLOSS) |

`INJURY_ASPHYXIA` is being deleted by the body rewrite (decision 3 in `doc/refactor_brief.md`), so there is no asphyxia packet kind.

## 3. Entry points become adapters

Every entry point builds a packet and calls `receive_damage(packet)`. Each override that only converted damage is deleted.

| Entry point | Adapter builds |
|---|---|
| Projectile hit (`bullet_act`) | Kinds from the projectile's damage type and flags, plus penetration |
| Weapon hit (`attackby` on objects, and melee on mobs) | Kinds from `force`, `sharp`, `edge` and damage type |
| Thrown impact (`hitby`, `throw_impact`) | Blunt, or sharp, from the thrown force (today computed 9 different ways) |
| Explosion (`ex_act`) | Blast, from the propagated severity, in batches (§7) |
| EMP (`emp_act`) | Ionic, from the severity, with one shared ladder |
| Fire (`fire_act`) | Thermal flux into the heat model; damage comes from heat rules ([temperature.md](temperature.md)) |
| Acid | Corrosive. Today acid bypasses damage completely and `qdel`s anything over `meltdose`. |
| Simple mob attacks (`attack_generic`) | Kinds from the attacker's profile |
| Blob, shock | Their kinds |

## 4. Mitigation

These are applied in order:
1. **Shields.** A block check, for holders with a shield.
2. **Equipment covering the zone.** The per-zone armour aggregate, composed through layers on equip ([containment.md §6](containment.md#6-equipment)). It is not added up on every hit.
3. **Innate armour.** Interned, immutable armour datums shared by type. They replace the 762 per-type lists, and gain fire, acid and cold values where they matter.
4. **Material response.** For objects and material-built items: hardness against blunt, toughness and yield strength against sharp and pierce, melting point against thermal. These properties already exist; they just aren't used.
5. **Resistances.** Species and body factors (the body rewrite).

**How the numbers work**
- **Soak.** Soak is **deterministic**: a flat soak plus a percentage reduction, reduced by penetration. The ±25% random variance goes away, and the randomness stays in the hit roll.
- **Kind conversion.** Converting sharp into blunt (a stab stopped by body armour becomes a bruise) is one rule on the armour datum, replacing its 6 copies.

## 5. Where damage lands

- **Integrity** for every object:
  - Walls move onto it, with material caps becoming their integrity.
  - The ~15 separate pools are deleted.
  - Machinery integrity already comes from the average integrity of its parts; with C6 that reads from part tiers.
- **`injure()`** for mobs: the packet's kinds are passed on through the agreed mapping.
- **Body model for mechs** (with the body rewrite):
  - Mech components become body parts of a machine body plan: hull, actuators, armour plates, electrical, life support.
  - Internal damage flags become afflictions: fire, tank breach, short circuit, control damage.
  - `absorbDamage`, `components_handle_damage` and `dynbulletdamage` are deleted.
  - Repairs are interactions.
  - This needs a body host interface, because `/datum/body` is owned by `/mob/living` today.
- **Borgs** already use the body model (machine plan).
- **Simple vehicles** stay on integrity.

**D3 status (Sept 2026).** Done:
- **Walls** use integrity. `max_integrity` is the material cap (plating plus reinforcement), set by `update_material()`, which keeps damage already taken. Projectiles, throws, generic attacks and blobs reach walls through the turf adapters (`projectile_damage`, `thrown_damage`, `receive_generic_attack`, `deal_damage`). Wall-rot multiplies each hit by ten in `run_atom_armor()`. Welder repair calls `repair_damage()`, and zero integrity dismantles the wall.
- **Pools converted:** blob2 `integrity`, the old `/obj/effect/blob` `blob_health`, energy-field `strength` (20 integrity to the Renwick; the field drops below one Renwick and is never destroyed), simple-door `hardness` (10 integrity to the point), target `hp`, tank `integrity` (the pressure seal, ten per old point), shield-projector `shield_health`, modular-computer and hardware `damage`/`max_damage`/`broken_damage`/`damage_failure` (now `integrity_failure`), material weapon, armour, ashtray and barbed-wire item `health` (`MATERIAL_WEAR_UNIT` integrity per blow), smoleworld building `health`, and mech component `integrity`.
- The **energy shield** segment has no pool of its own: it drains the generator's shared energy. It gains a `receive_damage()` sink that maps kinds to shield damage types.
- **Mechs:** `receive_damage()` now applies packets through the mech's own model (`take_damage` → `absorbDamage` → `components_handle_damage`). Projectiles and throws keep `dynbulletdamage`/`dynhitby`. The body-model step above is still to do.

**D5 shims.** Some explosion and EMP procs still read or write an old var, so a mirror or accumulator survives until D5 deletes the ladder:
- simple door `hardness`: `ex_act` subtracts from it, and `CheckHardness()` moves it onto integrity;
- shield projector `max_shield_health`: `emp_act` reads it, and it mirrors `max_integrity`;
- mech component `integrity`: `emp_act` reads it, and it mirrors `get_integrity()`;
- modular computer `take_damage(amount, component_probability, damage_casing)`: `ex_act` and `emp_act` still make this legacy call, and the override forwards it to `damage_computer()`;
- energy shield `take_damage(damage, SHIELD_DAMTYPE_*, hitby)`: `ex_act`, `emp_act` and `fire_act` still call it.

**Not converted (listed):**
- **Growth or other stats, not integrity:** hydroponics tray `health`, spreading-vine `health`/`max_health` (they drive growth stage and maturity), `/obj/effect/dark` `health` (a light balance), anomaly `curr_health`, laser-tag hits and supermatter `damage` (instability).
- **Equipment on mobs** (the body rewrite): rig `take_hit()`, space-suit breaches and NIF `durability`.
- **Organs:** item `health` survives only for them.

## 6. Thresholds and destruction

Each type declares its breakpoints as rules ([rules.md §4](rules.md#4-rules)):
- **Damaged at X%.** Generated flavour text replaces the 26 hand-written lines.
- **Broken at Y%.** A base `/obj/machinery/atom_break` sets `BROKEN`, sends `COMSIG_MACHINERY_BROKEN` and emits the reactor event. The 16 subtype overrides and 6 `set_broken` definitions are deleted.
- **Destroyed at 0.** Debris entries, then each slot's drop policy through the ledger ([containment.md §2](containment.md#2-the-ledger)).
  - Latent contents are resolved as data: destroyed entries are removed, and only survivors that land on a turf are created.

## 7. Explosions and EMPs

- Propagation stays in DM, because it is under 5% of explosion cost. The rest is side effects.
- **Batched delivery.** The affected atoms receive their packets in budgeted batches, grouped by type. Containers resolve their latent contents in bulk.
- **What's deleted:** the `ex_act` severity ladders, the structure and item base "`prob` then `qdel`" behaviour, and the duplicated EMP ladder (`living_defense.dm:261` and `projectile.dm:711`).
- **Batched power topology.** Explosions batch their power topology changes (M3) instead of calling `makepowernets()`.

## 8. Repair

Repair is the inverse pipeline. An interaction (welder, nanopaste, a repair kit) builds a repair packet, and the sink applies it: `repair_damage` for integrity, `mend()` for bodies. Welder repair of walls (today `take_damage(-damage)`) goes through it.

## 9. Tests and lint

**Tests**
- Every entry point: an adapter test (which packet it produces).
- Mitigation: a table-driven test per armour datum and material.
- Every declared threshold: a rule test.
- A major_events regression.

**Lint**
- No `take_damage` or `injure()` outside the adapters and the pipeline (D1, D3).
- No per-type `armor = list(…)` (D2).
- No `set_broken` or `atom_break` overrides that only set flags (D4).
