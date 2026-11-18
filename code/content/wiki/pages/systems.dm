// System guides: the mechanics no data source explains (how a line of machines works together, what a tray needs). Each links to the
// generated pages (catalogue entries, plants, materials, reagents) for the numbers, so the guide stays true when the numbers change.

// ---- Cargo: mining ----

/datum/wiki_page/guide/cargo_ore_processing
	id = "guide/cargo/ore_processing"
	title = "Processing ore"
	path = "Cargo/Guides"
	summary = "From an ore box to sheets: the unloader, the material processor and the stacking machine."
	body = {"Ore comes back to the station in ore boxes and loose. The ore line turns it into sheets for the lathes and the market.
1. The \[\[cat/machinery/mineral/unloading_machine|unloading machine]] empties an ore box standing on its input side and moves loose items onto its output side.
2. The \[\[cat/machinery/mineral/processing_unit|material processor]] takes ore from its input side. Its \[\[cat/machinery/mineral/processing_unit_console|console]] sets what it does with each kind of ore: leave it, smelt it into sheets, compress it, or alloy it with other ores. It processes up to ten sheets' worth at a time while it is switched on.
3. The \[\[cat/machinery/mineral/stacking_machine|stacking machine]] gathers the sheets into stacks (fifty by default; its \[\[cat/machinery/mineral/stacking_unit_console|console]] changes the size and releases a partial stack).
Every ore processed adds to the console's unclaimed points, rarer ores more; insert an ID card in the console to have them paid into its account. Each sheet's material has its own page under Engineering/Materials."}

// ---- Civilian: botany ----

/datum/wiki_page/guide/civilian_botany
	id = "guide/civilian/botany"
	title = "Growing plants"
	path = "Civilian/Guides"
	summary = "Trays, water, nutrients, pests and weeds, harvesting and mutation."
	body = {"Plants grow in a \[\[cat/machinery/portable_atmospherics/hydroponics|hydroponics tray]] (or a soil plot) from a seed packet. Every plant has a page under Civilian/Botany/Plants with its growth time, yield, ideal light, temperature and pressure, and what it can mutate into.
## Keeping it alive
- Water: a tray holds up to 100 water and the plant drinks it every cycle. Pour water in from a bucket or beaker.
- Nutrients: up to 10. \[\[chem/eznutrient]], \[\[chem/left4zed]], \[\[chem/robustharvest]], \[\[chem/ammonia]] and \[\[chem/diethylamine]] all feed it; Robust Harvest also raises the yield and Left 4 Zed raises the chance of a mutation.
- Pests and weeds build up to 10 each and hurt the plant past its tolerance. Diethylamine kills pests; Plant-B-Gone kills weeds (and hurts the plant).
- Light, heat and pressure: outside the plant's tolerance it loses health. A plant's page gives its ideal and how far it can stray. A tray's own lamp is set from its menu (Set Light, 0 to 10), and its lid closes it off from the room's air.
- Toxins hurt it: chlorine, fluorine, acids, radium and toxin among them.
## Harvesting
When it is mature, harvest it with an empty hand. A plant that harvests repeatedly fruits again after its production time; any other is spent.
## Mutation
Mutagenic chemicals (\[\[chem/mutagen]], \[\[chem/radium]]) raise the tray's mutation level; at 100 the plant mutates, toward a variety on its page or into a new strain of itself. The \[\[cat/machinery/botany/extractor|lysis-isolation centrifuge]] and \[\[cat/machinery/botany/editor|bioballistic delivery system]] move single genes between seeds; the \[\[cat/machinery/seed_extractor|seed extractor]] turns produce back into seeds."}

// ---- Civilian: kitchen ----

/datum/wiki_page/guide/civilian_kitchen
	id = "guide/civilian/kitchen"
	title = "Cooking"
	path = "Civilian/Guides"
	summary = "The appliances, how recipes are matched, and where each dish's recipe is."
	body = {"A dish is made by putting its ingredients in the right appliance and running it. Every dish has a catalogue page under Civilian/Catalogue/Food and drink; its How it is made section lists the appliance, the ingredients, the reagents and the time.
## The appliances
- \[\[cat/machinery/microwave|Microwave]]: most simple dishes.
- \[\[cat/machinery/appliance/cooker/oven|Oven]], \[\[cat/machinery/appliance/cooker/grill|grill]] and \[\[cat/machinery/appliance/cooker/fryer|deep fryer]]: baked, grilled and fried food.
- \[\[cat/machinery/appliance/mixer/candy|Candy machine]] and \[\[cat/machinery/appliance/mixer/cereal|cereal maker]].
- The \[\[cat/machinery/processor|food processor]], the \[\[cat/machinery/reagentgrinder|grinder]] and the \[\[cat/machinery/gibber|gibber]] prepare ingredients.
## Matching
Of the appliance's recipes whose items and fruit are all inside it and whose reagents are exactly what it holds, the one with the most ingredients wins. Put in what a recipe asks for and no other reagents; a microwave with nothing that matches turns what it holds into a burned mess.
Drinks are mixed, not cooked: each drink is a reagent with its own page and recipe under Chemistry/Reagents."}

// ---- Engineering: materials ----

/datum/wiki_page/guide/engineering_materials
	id = "guide/engineering/materials"
	title = "Materials"
	path = "Engineering/Guides"
	summary = "The material card: six numbers that decide how anything made of a material behaves."
	body = {"Every material has a card of six numbers, and every other property is worked out from them. Each material has a page under Engineering/Materials with its card and its traits.
- Strength: how well it resists denting and cutting, and its armour value.
- Toughness: how much punishment it takes before it fails. Low toughness against high strength means brittle.
- Heat resistance: its melting point is 250 K plus 40 K per point (steel melts at 1800 K).
- Conductivity: one number for electricity and heat. Below 8 it does not conduct at all, so things made of it are insulated.
- Corrosion resistance: 100 is inert; lower corrodes faster in acids and other reactive chemicals.
- Weight: the mass of a sheet; heavy armour slows its wearer and heavy walls block more radiation.
## Traits
Some materials have traits, each with a strength out of 100: superconducting, catalytic, sorbent, radioactive, toxic, antimicrobial and others. A catalytic sheet speeds a reaction when dropped in a container (see \[\[guide/chemistry/lab|the chemistry lab]]); a sorbent one lines a filter.
## Using them
Use a stack of sheets in hand to see what it builds. Lathes take sheets as their stock; what a design costs is on its catalogue page. Power cable and cells are affected too: cable of a better conductor loses less power over a long run."}

// ---- Security ----

/datum/wiki_page/guide/security_basics
	id = "guide/security/basics"
	title = "Security equipment"
	path = "Security/Guides"
	summary = "Records, cameras, the brig, restraints and where Security keeps its gear."
	body = {"Security keeps the station's order with its consoles, its brig and its equipment. Every item below has its own catalogue page under Security.
## Consoles
- The \[\[cat/machinery/computer/secure_data|security records]] console holds every crew member's record: wanted status, notes and history.
- The \[\[cat/machinery/computer/security|camera]] console watches the station's camera networks.
- The \[\[cat/machinery/computer/prisoner|prisoner management]] console tracks and works implanted prisoners.
## The brig
- Each cell has a door timer: set the sentence and start it, and the cell opens itself when the time is up.
- \[\[cat/machinery/flasher|Flashers]] blind whoever is in front of them when triggered; \[\[cat/machinery/deployable/barrier|deployable barriers]] block a corridor.
## Gear
- The \[\[cat/machinery/vending/security|security vendor]] stocks restraints, flashes and other basics; the armoury holds the heavier weapons. Weapons, ammunition, armour and restraints each have a section under Security/Catalogue.
- \[\[cat/machinery/recharger|Rechargers]] recharge energy weapons and batons.
## Alerts
The station's alert level is set by Command; see \[\[ops/alert_levels|alert levels]] for what each one means."}

// ---- Exploration ----

/datum/wiki_page/guide/exploration_expeditions
	id = "guide/exploration/expeditions"
	title = "Going on an expedition"
	path = "Exploration/Guides"
	summary = "Taking a contract, flying to the site, finishing the objectives and getting paid."
	body = {"Expeditions send a crewed vessel to a site generated for the job: a cave, a derelict, a hostile outpost. Every contract and what it pays is in \[\[ops/expedition_contracts|expedition contracts]].
1. At a vessel's flight console, plot an expedition: choose a contract, then a threat band. Higher bands pay more and fight back harder. A vessel holds one assignment at a time, and only a vessel built for surface expeditions can take one.
2. The site is generated for the contract. The Flight Operations window shows the destination, the plan and its progress.
3. Engage the flight plan to fly there; abort to call it off. Abandon the expedition to give the assignment up.
4. On the site, finish the required objectives. Bonus objectives pay extra. Some contracts have a time limit.
5. When the required objectives are done the contract completes: its survey points are logged for the exploration program and its pay is split between the surviving crew on the site and the exploration budget.
> Your share is paid to the account on your ID card. Carry it."}
