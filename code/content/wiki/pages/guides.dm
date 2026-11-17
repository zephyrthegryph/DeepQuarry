// How-to guides, one per job a department does often. Each is wiki markup (wiki.dm); links point at the generated pages (mechanisms, reagents,
// surgery, manuals, catalogue entries) so a guide stays short and the detail stays with the data. A department adds a guide by adding a
// subtype here or in its own folder.

/datum/wiki_page/guide

// ---- Research: chemistry ----

/datum/wiki_page/guide/chem_lab
	id = "guide/chemistry/lab"
	title = "Working the chemistry lab"
	path = "Research/Guides"
	summary = "From the dispenser to a clean, labelled product: temperature, baths, boiling, filters and the chem master."
	body = {"Chemistry is mixing, at the right temperature, and then cleaning up what the mixing left behind. Every reagent has a page with its recipes; this guide is the workflow.
## 1. Get your stock
1. Take a beaker and dispense the ingredients from the chemical dispenser. A dispense of N units is N units of the cartridge's mixture: each cartridge carries its own contaminants for the shift, and recharging it keeps them.
2. Read the beaker with a chemistry scanner: contaminants are listed grey, after the real reagents, and the mixture's grade is shown. See \[\[chem/purity|purity and contaminants]].
## 2. Mix at the right temperature
- Most recipes are clean at room temperature. Some want warmth, heat or cold: the Temperature tab of \[\[chem/purity|the purity guide]] lists every recipe with its ideal band and its working range.
- Inside the ideal band the product is clean. Off the band but in range it still reacts and leaves residue (too cold) or a reactive impurity and less product (too hot). Outside the range nothing happens.
- **Heat:** stand the beaker on the hot plate, set the dial in Celsius and switch it on. It heats up to the dial and never past it; it does not cool.
- **Cold:** the ice machine turns water into ice. Stand a small open container in a larger one holding ice and water (grab-stance click, "Stand it in the bath"): the bath holds the inner container near 0 C while any ice is left. A warm bath on the hot plate warms its inner container the same way.
- **Catalysts:** a process may want a dissolved acid or base (spent into residue), an enzyme (gentle heat, leaves endotoxin) or a sheet of a catalytic material dropped into the container.
## 3. Take out what you can
- **Boil and condense:** heat past a reagent's boiling point and it leaves as vapour, gradually. A condenser on or beside the hot plate collects the vapour into the container under its spout: distillation. What never boils (salts, heavy metals) stays behind.
- **Filter:** fit a funnel on a beaker and put a filter in it; whatever is poured in goes through. Paper takes solids, charcoal takes organics, a sorbent filter (a paper filter lined with a material sheet) takes what its material is good at. Every filter keeps a little product, clogs as it fills, and no filter takes a contaminant below its floor.
- **Neutralise:** acid residue and a base (or base residue and an acid) make salts and water. Measure it, or you leave the other behind.
## 4. Bottle it
- The chem master moves or discards the whole mixture: a transfer takes the same share of every reagent, contaminants included. Nothing on the station separates one chemical out of a mixture for free.
- Label what you make. A doctor reads the drug's page under Medical/Drugs for doses and overdoses."}

// ---- Medical ----

/datum/wiki_page/guide/med_triage
	id = "guide/medical/triage"
	title = "Treating a patient"
	path = "Medical/Guides"
	summary = "Scan, find the cause, treat by mechanism, watch for what it leads to."
	body = {"## Scan
1. Scan the patient. The basic analyzer reads signs (shock, bleeding, a fracture) rather than names; the improved and advanced analyzers name more, and the advanced analyzer's guidance names a treatment for each finding.
2. Look each finding up. A condition page says what causes it, how it shows, what treats it and what it leads to.
## Treat by mechanism
- A condition does not care which drug you give: it answers to mechanisms such as \[\[med/mech/hemostatic]], \[\[med/mech/antimicrobial]] or \[\[med/mech/tissue_repair]]. Each mechanism page lists every drug, tool and surgical step that provides it.
- A stabilising condition comes back while its cause lasts (a damaged organ, low blood, a chemical still in the blood). Treat the cause as well.
- Check a drug's Cautions before giving it: strains on organs, readings it masks, and its overdose.
## When drugs are not enough
- Torn organs, severed tendons, cut vessels and embedded objects need surgery: see \[\[guide/medical/surgery|operating]].
- Read the \[\[med/index|medical reference]] for how the pages fit together."}

/datum/wiki_page/guide/med_surgery
	id = "guide/medical/surgery"
	title = "Operating"
	path = "Medical/Guides"
	summary = "Open, answer the findings, close. Pain relief first."
	body = {"Surgery is not a list of fixed procedures. You open a site, answer what you find, and close it. The steps are in \[\[med/surgery/surgery_access|opening and closing a site]].
1. Give pain relief or anaesthesia first (\[\[med/mech/analgesic]]): a patient who feels the step flinches and it goes wrong.
2. Open the site with a scalpel and a retractor. Inspect the limb or read the operating computer: every finding is listed with the step that answers it.
3. Where the limb is encased (the chest, the head), saw and retract the bone to reach the organs.
4. Answer each finding with its tool. When several answer to the same tool, the most urgent goes first: bleeders, then the worst-off organ.
5. Set the bone layer, then cauterize the incision closed.
Every finding step has its own page under Medical/Surgery, with the tools it takes and the conditions it answers."}

// ---- Engineering ----

/datum/wiki_page/guide/eng_power
	id = "guide/engineering/power"
	title = "Keeping the power on"
	path = "Engineering/Guides"
	summary = "Where the station's power comes from, how it gets to the rooms, and what to check when it fails."
	body = {"Power is made by the engines and generators, stored, carried by cable and handed to each room by its area power controller (APC).
## Making power
- The engines each have their own manual: \[\[manual/supermatterengineoperatingmanual|the supermatter engine]], \[\[manual/teslaengineusersguide|the Tesla engine]], \[\[manual/rustoperatingmanual|the R-UST fusion reactor]], \[\[manual/particleacceleratorusersguide|the particle accelerator]] and \[\[manual/rotaryelectricgeneratormanual|the rotary generator]].
- Solar arrays give a steady trickle in daylight; the instructions come with the panels.
## Getting it to the rooms
- Cable carries power between machines. Lay it with a coil; cut it with wirecutters. A break anywhere in a run starves everything past it.
- Each room's APC runs its lighting, equipment and environment channels from its own cell. A drained APC shuts its channels off one by one.
## When it fails
1. Check the engine is running and the storage is charging.
2. Follow the cable from the storage toward the dark rooms and look for breaks.
3. Check the APC: its cell, its breaker and its channels.
Engineering's tools and parts are in its catalogue, under Engineering in the index."}

/datum/wiki_page/guide/eng_atmos
	id = "guide/engineering/atmos"
	title = "Atmospherics basics"
	path = "Engineering/Guides"
	summary = "Air, pressure, canisters, pumps and the pipe network."
	body = {"Every tile holds a mixture of gases with a pressure and a temperature, and gas flows from high pressure to low. A hull breach vents a room to space; a fire heats it and burns its oxygen.
## The tools
- Canisters hold gas under pressure. Connect one to a port to fill or drain a pipe network, or open its valve into the room.
- Pumps move gas along pipes; scrubbers take unwanted gases out of a room; vents put air back in.
- An atmospheric analyzer reads a tile or a pipe: its pressure, temperature and what it is made of.
## Pipes
The pipe dispenser and the pipes themselves are explained in \[\[manual/pipesandyougettingtoknowyourscarytools|Pipes and You]]. Before working outside or in a vented room, read \[\[manual/evagearandyounotspendingalldayinside2ndedition|EVA Gear and You]]."}

// ---- Research ----

/datum/wiki_page/guide/research_basics
	id = "guide/research/basics"
	title = "Research and fabrication"
	path = "Research/Guides"
	summary = "Research nodes unlock designs; lathes and fabricators print them from materials."
	body = {"Research is a tree of nodes. Each node costs research points, needs the nodes before it, and unlocks designs. Every node has a page under Research/Research nodes, and every design's product has a catalogue page saying where it is printed and from what.
## Printing
- An autolathe prints common tools and parts from steel and glass.
- A protolathe prints what research unlocks; a circuit imprinter prints circuit boards; the exosuit and prosthetics fabricators print exosuit and robot parts.
- Feed the machines materials; what a design costs is on its catalogue page. Recycling an object gives back up to what it was made of.
See \[\[manual/researchanddevelopment101|Research and Development 101]] for the department's own manual and \[\[guide/chemistry/lab|working the chemistry lab]] for the chemists."}

// ---- Cargo ----

/datum/wiki_page/guide/cargo_ordering
	id = "guide/cargo/ordering"
	title = "Ordering supplies"
	path = "Cargo/Guides"
	summary = "Supply packs, points and the shuttle."
	body = {"Cargo buys what the station needs in supply packs. Every pack has a page under Cargo/Supply packs listing its cost, whether it is locked to an access, and what is inside, each item linked to its catalogue page.
1. A department asks for what it needs at a supply console.
2. Cargo approves the order against its points and sends for it.
3. The crate arrives on the supply shuttle. A locked crate opens only for the access it names.
Mining brings ore back for the station's materials; the mining tools are under Cargo in the index."}
