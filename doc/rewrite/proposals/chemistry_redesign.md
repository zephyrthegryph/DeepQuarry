# Chemistry and materials redesign

Status: approved by the user on 2026-11-15, section by section. This is the design; the per-chemical tables are in `chem_recipes_draft.md` beside this file. Build stages are at the end.

## 1. Goals

- Making a chemical is a routing puzzle: several starting points and processes lead to the same product, and each route leaves different leftovers.
- No purity number and no grade gates. What is in the beaker is the whole story.
- Many departments and ordinary items feed in, so players can turn odd things into useful ones.
- Rounds differ: the traces carried by each source are rolled.
- Staples stay quick. Depth is for advanced work.

## 2. Block structures

Every chemistry chemical is a small block structure. Formula, class and tags are computed from it, and the book draws it.

- **Cores (10):** short chain, long chain, ring, double ring, sugar ring, amino, steroid, nitrogen ring, siloxane, phoron lattice. Slime extracts and expedition finds add exotic cores.
- **Groups (9):** hydroxyl, carbonyl, carboxyl, amine, nitro, halide, thiol, phosphate, metal centre. A core carries an unordered list of groups; there are no positions.
- **Links (2):** ester and amide, joining two cores.
- **Inorganics:** a positive and a negative ion.
- **Mixtures** (drinks, food, cultures, paints) have no structure and keep plain mixing recipes. Virology is unchanged.

Rule: **cores cannot be built from elements.** They come from feedstock. Processes only change groups, or join and split cores.

## 3. Processes

A process is a reaction triggered by a condition (heat, an added reagent, a catalyst). It acts on any chemical that has the blocks it needs, finished medicines included, so converting one chemical into another is the normal way to work. The product is whichever existing chemical has the resulting structure; if none exists the batch becomes organic residue. Routes are generated at boot into the ordinary reaction table, and the full generated list is pinned by a test.

| Group | Processes |
|---|---|
| Change a group | oxidise, reduce, halogenate, nitrate, substitute (halide to amine, thiol or cyanide), phosphorylate, decarboxylate |
| Join and split | condense, hydrolyse, ferment, crack, polymerise |
| Inorganic | neutralise, displace (also binds a metal to an acid group), electrolyse |

Equations balance, with 1u as one part. Whatever atoms are left over come out as a real chemical.

**Temperature.** Each process has a working temperature; each group has a temperature it survives. Running hot enough to go without a catalyst cooks the other groups into residue. The hot plate, boiling, the condenser and filters from the purification work are the tools.

**Process chemicals.** Twelve chemicals perform a process when poured in (hydride, strong oxidiser, bleach, nitrating mix, chlorinating agent, coupling agent, dry agent, caustic digest, yeast, enzyme, catalytic phoron, scavenger resin). They are less selective than the proper method and leave their own residue.

## 4. Catalysts

A catalyst belongs to the process. It lowers the temperature needed and decides which group is hit when two could be.

| Kind | Source | Trade-off | Killed by |
|---|---|---|---|
| Dissolved acid or base | dispenser | cheap; stays in the product as residue | the opposite (base or acid) |
| Solid metal or solid acid | material science | lifts out clean; the material's catalytic trait sets its strength | sulfur, heavy metals |
| Enzyme | botany, xenobiology | very selective; gentle heat only; leaves endotoxin | heavy metals, heat |

Poisoning forces an order of operations: strip the poison first, or pick another route.

## 5. Contaminants and separation

- Contaminants are real chemicals in the mixture. There is no purity number and no grade gate; pills and scanners list composition.
- **Trace-potent.** Contaminants act at low amounts, each with one clear symptom so a bad batch can be traced to a step: hydrochloric acid (burns), dioxin (skin lesions), nitrosamine (slow genetic damage), peroxide (detonates when next heated), methanol (blindness), heavy metals, endotoxin (fever), plasticiser, tar.
- **Per-type floor.** Each separation method only brings a contaminant type down to a floor share of the mixture. More of a type you already have costs nothing; each new type costs purity.
- **Separation tools:** filters catch by tag (charcoal: organics; ion-exchange sorbent: salts; paper: solids), boiling and the condenser separate by boiling point with no floor, and conversion turns two stuck types into one (acid plus base to salt and water).

## 6. Reactions between chemicals

- **Joining** by a process (tricordrazine is inaprovaline joined to dylovene).
- **Inorganic reactions** on contact.
- **Group clashes** on contact, so most chemicals react with something:

| Mixed | Result |
|---|---|
| Acid group + amine | a salt; both tied up until freed |
| Thiol + metal centre | the thiol takes the metal |
| Nitro + amine | nitrosamine |
| Oxidiser + thiol or hydroxyl | oxidised, usually ruined |
| Halide + amine, warm | an unintended joined molecule |
| Phosphate + calcium or iron | drops out as a solid |
| Nitro compound + reducer | runs hot, can ignite |

Clashes apply in containers and in the stomach (swallowed doses mix there). They do not apply in the bloodstream.

**Interference** between steps: leftover acid cancels a base step, leftover water undoes a condensation, leftover oxidiser attacks the next product.

## 7. Byproducts

Higher tiers give more interesting byproducts.

- **Useful:** soap-making gives glycerol; halogenating gives reusable hydrochloric acid; clonexadone leaves cryoxadone; the organ drugs leave amino acids; hydrolysing plastic gives coolant.
- **Poisonous:** citalopram leaves cyanide; mutagen leaves blistering fragments; dylovene leaves sulfur compounds; hot ring halogenation leaves dioxin; zombie powder leaves nerve toxin.

Poisons by accident are intended and are not rationed: they come out wherever the chemistry says so. Waste has to be neutralised, boiled off or bottled.

## 8. Tiers

| Tier | Steps | Needs |
|---|---|---|
| 1. Staples | 1 to 2 | dispenser and stocked precursors; gentle heat; no solid catalyst |
| 2. Standard | 2 to 3 | a staple plus one process |
| 3. Advanced | 4 to 5 | a material-science catalyst or another department's feedstock |
| 4. Exotic | 5 or more | expedition, xenobiology or creature inputs |

- The lab starts with bottles of 16 common precursors; cargo sells more.
- Every staple has a **dirty shortcut**: one step, always works, leaves trace-potent contaminants. The clean route is longer.
- Tier assignments, clean routes and shortcuts for every chemical are in the recipe draft.

## 9. Inputs

- **Dispenser:** keeps its cartridges (elements, water, ethanol, sugar, sulphuric acid). It is not clean; each cartridge rolls mild traces.
- **Feedstock:** by default any item grinds into the feedstock of what it is made of. About 60 items get hand-written rows (circuit boards, light tubes, soap, candles, food, organs, cigarette butts and so on).
- **Branded containers** (cleaner spray, pepper spray, glue, weed killer) become generic refillable containers with a starting fill and a label.
- **Rolled traces.** Every source has a fixed signature plus a small pool of extras.
  - Rolled per round for station stock; per lot for ore veins, cargo shipments and expedition sites.
  - Traces are hidden until assayed.
  - Each extra shuts or taxes a route. A roll never makes a chemical impossible. Rolls are logged.

## 10. Material science

- **Composition** is real substances; the free-text impurity list and the purity number go. A wanted additive and an unwanted trace are the same kind of thing.
- **Stat card:** strength, toughness, heat resistance, conductivity, corrosion resistance, weight, plus traits shown only when present (catalytic, sorbent, antimicrobial, superconducting and the exotic ones). Every stat shows its breakdown.
- **A batch** is composition, temper (soft to hard, with annealing) and flaws.
- **Trace effects** act per stat at low amounts (sulfur and dissolved hydrogen lower toughness; lead lowers strength and poisons tools).
- **Stacks** behave like a beaker of solid: same material merges and traces average; a merged stack is unassayed if either half was; different temper does not merge. Ordinary building ignores traces. Only workshop-made things carry a stat card.
- **Refining** uses the shared processes (reduce is smelting, oxidise is roasting, displace is fluxing, electrolyse is electrorefining, vacuum degassing boils off gas), each with a per-type floor.
- **Polymers** bridge the departments: chemistry makes the units, the workshop polymerises them. New materials: rubber, nylon, hard plastic, guncotton, aramid, carbon fibre. Existing borosilicate glass is the acid-proof vessel liner.
- Leaching runs both ways: a dirty catalyst or unlined vessel puts metal into the medicine, and a dirty chemical poured into a melt carries its traces into the metal.

## 11. The book

Each chemical shows its block diagram, tier, which processes act on it and what they give, its clean route and its shortcut.

## 12. Build stages

1. Chemistry engine: structures, processes, catalysts, floors, tag filters, gate removal, trace contaminants, book diagrams, burn medicines converted. (running)
2. Material stats: card, traits, breakdowns, composition, stacks, trace effects, assay. (running)
3. Convert the remaining chemistry recipes by family to the tiers, shortcuts, process chemicals, group clashes and byproducts.
4. Feedstocks, generic containers, rolled traces, dispenser pools, ore refining, polymers.

## 13. Later decisions

- Exotic blends get real routes (recipe draft, section 12).
- The hot plate and condenser are real machines: circuit board, buildable and dismantlable, still placed on tables. Other table-top devices without a board (rechargers and similar) get the same treatment.
- Conservation: printing and fabricating must match materials. What a design costs must cover what the item breaks down into, so nothing is created from nothing.
