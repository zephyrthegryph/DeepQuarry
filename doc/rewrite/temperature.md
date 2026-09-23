# Temperature (track H, on the heat domain M4)

The goal is one thermal model:
- **Rust** owns every temperature that is simulated, whether in gas, turf solids, objects, machines, mobs or containers ([simulation.md §7](simulation.md#7-heat-m4)).
- **DM** reads temperatures, adds heat, declares thermal properties and reacts to thresholds.

Energy is conserved everywhere, in SI units.

## 1. Today

**About seven separate models, each with its own maths.** Only a few conserve energy.

| Model | Where | Problem |
|---|---|---|
| Gas | Rust mixtures | Fine. But the Rust `temperature_share` binds are never called, and DM uses `add_thermal_energy`, which makes 3 FFI calls per use (49 callers). |
| Turf solids | Rust `superconduct.rs` | Scans every node on every pass; wraps across map edges (B1); only loses heat to space above T20C; Stefan–Boltzmann is commented out |
| Mobs | `bodytemperature` var | Written directly in 94 places. Relaxes one-way (the room air never changes). Clothing is scanned every `Life()`. There are two damage ladders. |
| Items | None | Only hotspot `fire_act` damage, and B2 breaks that |
| Reagents | None | Only distilling checks temperature; the bunsen burner and distillery track a temperature that nothing reads |
| Machines | Per machine | Freezers and space heaters delete heat (B9); the heater outputs 2.5× its power (B10); cryo mixes in a phantom reservoir (B11); none scale by `wait` |
| Solid materials | `material_service` | The only energy-conserving solid model, with a phase buffer and heap scheduling |

**Other problems**
- **Dead paths** (DEAD3): `temperature_expose`, `atmos_expose`, `burn_turf`, `adjacent_fire_act`, and the `to_be_destroyed` flag, which is never read.
- **Constants** (B12, and the units column below):
  - two phoron ignition temperatures;
  - Rust and DM thresholds that differ;
  - 310.15/310.055 K hardcoded 19 times;
  - human heat capacity given as 280,000, 100 and 3,500 J/K in different places;
  - gas specific heat per mole but material specific heat per kg.
- **Always-processing items:** heat-exchange pipes on walls, cryo, cookers, suit coolers and rigs, cooling alloys, and burning mobs (which call `hotspot_expose` every tick).

## 2. Target

### 2.1 The DM API

```dm
/atom/proc/get_temperature()                  // from the view (or overlay); ambient if the atom has no heat node
/atom/proc/add_heat(joules)                   // a command; creates the heat node on first divergence
/atom/proc/thermal_properties()               // from materials and type properties: heat capacity, conductance, emissivity
REACT_WHEN(src, THRESHOLD(src, CH_HEAT_TEMPERATURE, ABOVE, KELVIN(373)))
```

- **Replaces** the ad-hoc `return_temperature()` procs on `/turf` (which returns the solid's temperature), gas mixtures, tanks, canisters and mecha. There is one meaning everywhere.
- **Generated constants.** Units, thresholds and material defaults come from Rust. There are no hardcoded body temperatures and no duplicate ignition points.

### 2.2 Heat nodes are created on demand

- An item, machine or container follows the temperature of its surroundings until something heats or cools it directly. Only then does it get a heat node, which it keeps until it returns to equilibrium.
- A container's heat node includes its contents' heat capacity. Latent entries never have nodes ([containment.md §4.2](containment.md#42-how-a-container-stands-in-for-its-contents)).
- Coupled to a large reservoir, a node follows the exact relaxation solution, so nothing is stepped until conditions change.

## 3. Mobs (H2, with the body rewrite)

- **The body heat node.** Each mob has one in Rust, and a `bodytemperature` setter replaces the 94 direct writes. The body rewrite's thermal life system owns metabolic heat and regulation through its thermo strategies (endotherm, ectotherm, heatsink, none: `doc/mob_life_architecture.md` §4.2). Rust owns exchange with the environment.
- **Coupling to the environment:**
  - turf air, or the interior of an occupied slot (cryo, a belly, a mech cockpit, a sleeper);
  - clothing, as insulation in series from the per-zone equipment aggregate ([containment.md §6](containment.md#6-equipment));
  - contact with held and buckled things.

  Exchange runs both ways, so rooms warm up with people in them.
- **Thresholds.** Comfort, damage and the species limits (about 120 overrides) become `Band` watches on the body node. The life system wakes only when the band changes, and there is one damage ladder.
- **Space and radiation.** Stefan–Boltzmann heat loss, with one model instead of three.

## 4. Items, cooking, reagents (H3)

- **Items** get thermal properties from their materials. The thresholds are melting, ignition, cooking and cook-off, and each is a rule ([rules.md §4](rules.md#4-rules)).
- **Cooking.** A cooking appliance is a heat source coupled to its contents. "Cooked" is a rule on time above temperature, which replaces the cooker's own temperature variable and fixed loss.
- **Reagent holders** get a heat capacity from their reagents' specific heats. Reactions that need a temperature subscribe to a `ThresholdSet` on the holder. The bunsen burner and distillery become heat sources, so the temperature they track finally matters. Water's latent heat is one rule, replacing its copy in foam.
- **Food and drink** add heat to the body node through the API instead of writing `bodytemperature` (about 31 writes today).

## 5. Fire and burning (H3)

- **Hotspots** stay in the gas field as per-tile effects. They heat everything on the tile through its heat node, which replaces calling `fire_act` on every atom in the tile on every SSair fire.
- **Ignition** is a threshold rule on a thing's temperature against its ignition point. `ignition_point` exists on 20 materials but is used only by phoron combustion today.
- **Burning** is a state with three parts:
  - a heat source, in watts;
  - an integrity damage stream through the damage pipeline;
  - oxygen consumption through a gas command.

  It ends when the thing runs out of fuel or oxygen, or its temperature drops below a limit. The burning component's flat `10 * seconds_per_tick` damage is replaced.
- **Burning mobs** use the same state. They stop calling `hotspot_expose` every tick and stop passing fire stacks as a temperature (B16).

## 6. Machines (H4)

One **thermal regulator** behaviour covers:
- heaters and freezers (thermomachines);
- space heaters and thermoregulators (`airconditioner.dm`);
- cryo;
- suit coolers and rig cooling;
- heat exchangers;
- the TEG's coupling.

| Regulator field | Meaning |
|---|---|
| Target temperature | The temperature it drives towards |
| Coupled node | A gas mixture, or the machine's own interior |
| Maximum power | Scaled by part tier ([containment.md §5](containment.md#5-machine-internals-c6)) |
| Heat pump | Limited by its coefficient of performance; rejected heat goes to the hot side or the environment |
| Power draw | Published to the power domain |

It replaces five copies of the coefficient-of-performance maths, the heat-deleting coolers, the heater that outputs more energy than it draws, and cryo's phantom reservoir. The supermatter keeps its own behaviour, but emits heat through the API instead of clamping the gas to 10,000 K.

## 7. Materials

- Heat capacity, conductance, emissivity, melting, ignition and critical temperatures, and latent heat all come from `/datum/material` (`_materials.dm:219-297`), and composites derive them.
- Fixing the conductance scale (B8) makes wall materials matter.
- `material_service`'s thermal state moves to Rust heat nodes (M4), and SSmaterial_services is deleted (S4). Its non-thermal state stays with material science.

## 8. Tests and lint

**Tests**
- Energy conservation across every coupling type.
- Reference relaxation curves.
- Each regulator conserves energy.
- Threshold rule tests for melting, ignition, cooking and reactions.
- Mob band wake tests, with the body rewrite.

**Lint**
- No direct `bodytemperature` writes (H2).
- No raw heat-exchange formulas in DM (H4).
- No hardcoded body temperatures or duplicate thermal constants (H1).
