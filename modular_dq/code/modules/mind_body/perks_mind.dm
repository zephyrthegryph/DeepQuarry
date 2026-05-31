// DQAdd — Mind perks. Each tree is a job sub-role, multiple sub-roles share one
// department pool. All perks set `tree`; init_perks derives `category` from the tree
// automatically. Perk effects are mostly "stubs" for now — name + icon + descriptive
// promise — that other systems will read off mob flags or selected_perks lookups as
// content lands. Treat the descriptions as a roadmap, not a contract.

// ─── Command — Captain ──────────────────────────────────────────────────────────────

/datum/perk/mind/cmd_captain_composure
	name = "Composure"
	desc = "Hard-won emotional control. Your Command radio messages cut through interruptions."
	icon_name = "comment-dots"
	cost = 1
	tree = PERK_TREE_MIND_CMD_CAPTAIN

/datum/perk/mind/cmd_captain_authority
	name = "Authority"
	desc = "When you give an order over comms, the responding crewmember moves 10% faster for 30s."
	icon_name = "bullhorn"
	cost = 2
	tree = PERK_TREE_MIND_CMD_CAPTAIN
	requires = list(/datum/perk/mind/cmd_captain_composure)

/datum/perk/mind/cmd_captain_strategy
	name = "Strategy"
	desc = "You see the wider picture. Tactical map info — power, atmos, antag status — is summarised in one Command HUD."
	icon_name = "chess-king"
	cost = 3
	tree = PERK_TREE_MIND_CMD_CAPTAIN
	requires = list(/datum/perk/mind/cmd_captain_authority)

// ─── Command — Head of Personnel ────────────────────────────────────────────────────

/datum/perk/mind/cmd_hop_paperwork
	name = "Paperwork"
	desc = "You file requisition forms and access changes 50% faster on the ID console."
	icon_name = "file-lines"
	cost = 1
	tree = PERK_TREE_MIND_CMD_HOP

/datum/perk/mind/cmd_hop_diplomacy
	name = "Diplomacy"
	desc = "Whispered words. Crewmembers you speak to gain a small mood boost for 60s."
	icon_name = "handshake"
	cost = 2
	tree = PERK_TREE_MIND_CMD_HOP

/datum/perk/mind/cmd_hop_quartermaster
	name = "Department Master"
	desc = "You can grant Cargo / Civilian access on any ID computer without a head-of-department override."
	icon_name = "id-badge"
	cost = 3
	tree = PERK_TREE_MIND_CMD_HOP
	requires = list(/datum/perk/mind/cmd_hop_paperwork)

// ─── Security — Officer ─────────────────────────────────────────────────────────────

/datum/perk/mind/sec_officer_threat
	name = "Threat Assessment"
	desc = "You spot concealed weapons during an examine. Visible sidearms are surfaced in the exam text."
	icon_name = "eye"
	cost = 1
	tree = PERK_TREE_MIND_SEC_OFFICER

/datum/perk/mind/sec_officer_restraint
	name = "Restraint Training"
	desc = "Cuff application is 25% faster and your grab pulls are harder to break."
	icon_name = "handcuffs"
	cost = 2
	tree = PERK_TREE_MIND_SEC_OFFICER

/datum/perk/mind/sec_officer_reflexes
	name = "Combat Reflexes"
	desc = "Trained for contact. First stun in a fight no longer staggers you."
	icon_name = "bolt-lightning"
	cost = 3
	tree = PERK_TREE_MIND_SEC_OFFICER
	requires = list(/datum/perk/mind/sec_officer_threat)

// ─── Security — Detective ───────────────────────────────────────────────────────────

/datum/perk/mind/sec_det_forensic
	name = "Forensic Eye"
	desc = "Pick up trace evidence at a glance. Examining a crime scene surfaces nearby fingerprints / DNA."
	icon_name = "magnifying-glass"
	cost = 1
	tree = PERK_TREE_MIND_SEC_DETECTIVE

/datum/perk/mind/sec_det_interrogate
	name = "Interrogator"
	desc = "Cuffed suspects you examine reveal their last 5 minutes of suit-sensor history."
	icon_name = "user-secret"
	cost = 2
	tree = PERK_TREE_MIND_SEC_DETECTIVE

/datum/perk/mind/sec_det_intuition
	name = "Intuition"
	desc = "Subtle hunches. Antag radio chatter you overhear is highlighted in your chat log."
	icon_name = "lightbulb"
	cost = 3
	tree = PERK_TREE_MIND_SEC_DETECTIVE
	requires = list(/datum/perk/mind/sec_det_interrogate)

// ─── Security — Warden ──────────────────────────────────────────────────────────────

/datum/perk/mind/sec_warden_quartermaster
	name = "Armoury Quartermaster"
	desc = "You catalog every brig issue. The armoury checkout console shows who pulled what."
	icon_name = "warehouse"
	cost = 1
	tree = PERK_TREE_MIND_SEC_WARDEN

/datum/perk/mind/sec_warden_lockdown
	name = "Lockdown"
	desc = "Cell-door overrides for prisoners you've processed don't trip the standard 30s cooldown."
	icon_name = "lock"
	cost = 2
	tree = PERK_TREE_MIND_SEC_WARDEN

/datum/perk/mind/sec_warden_keymaster
	name = "Keymaster"
	desc = "Your ID acts as a master key on Security brig doors — no separate Warden ID needed."
	icon_name = "key"
	cost = 3
	tree = PERK_TREE_MIND_SEC_WARDEN
	requires = list(/datum/perk/mind/sec_warden_quartermaster)

// ─── Engineering — Atmos Tech ───────────────────────────────────────────────────────

/datum/perk/mind/eng_atmos_reader
	name = "Vent Reader"
	desc = "Atmos analyser readings include a one-line suggested fix."
	icon_name = "wind"
	cost = 1
	tree = PERK_TREE_MIND_ENG_ATMOS

/datum/perk/mind/eng_atmos_balancer
	name = "Pressure Balancer"
	desc = "Setting vent/scrubber pressure on a control panel snaps to safe defaults."
	icon_name = "gauge"
	cost = 2
	tree = PERK_TREE_MIND_ENG_ATMOS

/datum/perk/mind/eng_atmos_firefighter
	name = "Firefighter"
	desc = "Burn damage taken while fighting an active fire is reduced 30%."
	icon_name = "fire-extinguisher"
	cost = 3
	tree = PERK_TREE_MIND_ENG_ATMOS
	requires = list(/datum/perk/mind/eng_atmos_reader)

// ─── Engineering — Engine Tech ──────────────────────────────────────────────────────

/datum/perk/mind/eng_engine_wirework
	name = "Wirework"
	desc = "Wire-puzzle outcomes are revealed without trial-and-error."
	icon_name = "plug"
	cost = 1
	tree = PERK_TREE_MIND_ENG_ENGINE

/datum/perk/mind/eng_engine_tesla
	name = "Tesla Whisperer"
	desc = "You can examine the engine to see its current containment + decay timers."
	icon_name = "bolt"
	cost = 2
	tree = PERK_TREE_MIND_ENG_ENGINE

/datum/perk/mind/eng_engine_overdrive
	name = "Overdrive"
	desc = "APCs you maintain charge 25% faster from external power."
	icon_name = "battery-full"
	cost = 3
	tree = PERK_TREE_MIND_ENG_ENGINE
	requires = list(/datum/perk/mind/eng_engine_wirework)

// ─── Engineering — Salvage ──────────────────────────────────────────────────────────

/datum/perk/mind/eng_salvage_scrapper
	name = "Scrapper"
	desc = "Deconstructing machinery returns 15% more parts on average."
	icon_name = "screwdriver"
	cost = 1
	tree = PERK_TREE_MIND_ENG_SALVAGE

/datum/perk/mind/eng_salvage_jury_rig
	name = "Jury Rig"
	desc = "You can patch breached walls with metal sheets without needing welding fuel."
	icon_name = "hammer"
	cost = 2
	tree = PERK_TREE_MIND_ENG_SALVAGE

/datum/perk/mind/eng_salvage_pack_rat
	name = "Pack Rat"
	desc = "Your utility belt holds two extra small items."
	icon_name = "box-archive"
	cost = 1
	tree = PERK_TREE_MIND_ENG_SALVAGE

// ─── Medical — Doctor ───────────────────────────────────────────────────────────────

/datum/perk/mind/med_doc_anatomy
	name = "Anatomy"
	desc = "Examining a patient surfaces visibly damaged organs and bleeds."
	icon_name = "bone"
	cost = 1
	tree = PERK_TREE_MIND_MED_DOCTOR

/datum/perk/mind/med_doc_triage
	name = "Triage"
	desc = "You assess crit priority at a glance. Patients you're treating display a colour-coded priority HUD."
	icon_name = "bell-concierge"
	cost = 2
	tree = PERK_TREE_MIND_MED_DOCTOR

/datum/perk/mind/med_doc_cpr
	name = "CPR Mastery"
	desc = "CPR you perform restores 15% more oxygen damage per cycle and works on borderline crit patients."
	icon_name = "heart-circle-bolt"
	cost = 3
	tree = PERK_TREE_MIND_MED_DOCTOR
	requires = list(/datum/perk/mind/med_doc_triage)

// ─── Medical — Surgeon ──────────────────────────────────────────────────────────────

/datum/perk/mind/med_surg_focus
	name = "Surgical Focus"
	desc = "Surgery steps complete 15% faster."
	icon_name = "scissors"
	cost = 1
	tree = PERK_TREE_MIND_MED_SURGEON

/datum/perk/mind/med_surg_clean
	name = "Sterile Field"
	desc = "Surgeries you perform are 25% less likely to introduce infection."
	icon_name = "soap"
	cost = 2
	tree = PERK_TREE_MIND_MED_SURGEON

/datum/perk/mind/med_surg_organ
	name = "Organ Transplant"
	desc = "Transplant surgeries take 30% less time and the recipient suffers no shock damage."
	icon_name = "heart-pulse"
	cost = 3
	tree = PERK_TREE_MIND_MED_SURGEON
	requires = list(/datum/perk/mind/med_surg_focus)

// ─── Medical — Chemist ─────────────────────────────────────────────────────────────

/datum/perk/mind/med_chem_pharma
	name = "Pharmacology"
	desc = "Reagent overdose thresholds for you are 25% higher."
	icon_name = "pills"
	cost = 1
	tree = PERK_TREE_MIND_MED_CHEMIST

/datum/perk/mind/med_chem_synth
	name = "Synth Master"
	desc = "Chemistry reactions you start in a dispenser auto-bring to the correct temperature."
	icon_name = "vial"
	cost = 2
	tree = PERK_TREE_MIND_MED_CHEMIST

/datum/perk/mind/med_chem_grenadier
	name = "Grenadier"
	desc = "Chemical-grenade assembly takes one fewer step and a wider igniter list works."
	icon_name = "explosion"
	cost = 3
	tree = PERK_TREE_MIND_MED_CHEMIST
	requires = list(/datum/perk/mind/med_chem_synth)

// ─── Research — Scientist ──────────────────────────────────────────────────────────

/datum/perk/mind/res_sci_method
	name = "Methodology"
	desc = "Research scanner results include a one-line prior interpretation."
	icon_name = "atom"
	cost = 1
	tree = PERK_TREE_MIND_RES_SCIENTIST

/datum/perk/mind/res_sci_anomaly
	name = "Anomaly Intuition"
	desc = "Anomaly classification scans are 20% faster and rarely return 'unknown'."
	icon_name = "wand-magic-sparkles"
	cost = 2
	tree = PERK_TREE_MIND_RES_SCIENTIST

/datum/perk/mind/res_sci_overclock
	name = "Overclock"
	desc = "Research console cooldowns reduced 25%."
	icon_name = "gauge-high"
	cost = 3
	tree = PERK_TREE_MIND_RES_SCIENTIST
	requires = list(/datum/perk/mind/res_sci_method)

// ─── Research — Roboticist ─────────────────────────────────────────────────────────

/datum/perk/mind/res_robo_assembly
	name = "Assembly"
	desc = "Mech / cyborg assembly steps take 25% less time."
	icon_name = "robot"
	cost = 1
	tree = PERK_TREE_MIND_RES_ROBOTICIST

/datum/perk/mind/res_robo_calibration
	name = "Calibration"
	desc = "Cyborgs you assemble start with +50 cell charge."
	icon_name = "screwdriver-wrench"
	cost = 2
	tree = PERK_TREE_MIND_RES_ROBOTICIST

/datum/perk/mind/res_robo_diag
	name = "Diagnostic Subsystem"
	desc = "Diagnostic scans on machinery reveal hidden wire-fault state."
	icon_name = "microchip"
	cost = 3
	tree = PERK_TREE_MIND_RES_ROBOTICIST
	requires = list(/datum/perk/mind/res_robo_assembly)

// ─── Research — Xeno-Archaeology ───────────────────────────────────────────────────

/datum/perk/mind/res_xeno_dig
	name = "Careful Excavation"
	desc = "Excavation tool use never destroys artifacts."
	icon_name = "brush"
	cost = 1
	tree = PERK_TREE_MIND_RES_XENOARCH

/datum/perk/mind/res_xeno_catalog
	name = "Cataloguer"
	desc = "Artifact analysers always return a verbose effect description."
	icon_name = "book"
	cost = 2
	tree = PERK_TREE_MIND_RES_XENOARCH

/datum/perk/mind/res_xeno_curator
	name = "Curator"
	desc = "Field-deployed artifacts you set up retain their unique effects after pickup."
	icon_name = "landmark"
	cost = 3
	tree = PERK_TREE_MIND_RES_XENOARCH
	requires = list(/datum/perk/mind/res_xeno_catalog)

// ─── Cargo — Quartermaster ────────────────────────────────────────────────────────

/datum/perk/mind/cargo_qm_market
	name = "Market Sense"
	desc = "Supply order prices show their last-week average alongside the current rate."
	icon_name = "clipboard-list"
	cost = 1
	tree = PERK_TREE_MIND_CARGO_QM

/datum/perk/mind/cargo_qm_trader
	name = "Trader"
	desc = "Orders you approve cost 5% less department credits."
	icon_name = "money-bill-trend-up"
	cost = 2
	tree = PERK_TREE_MIND_CARGO_QM

/datum/perk/mind/cargo_qm_logistics
	name = "Logistics"
	desc = "Mail bundles you sort are delivered 50% faster."
	icon_name = "truck-fast"
	cost = 3
	tree = PERK_TREE_MIND_CARGO_QM
	requires = list(/datum/perk/mind/cargo_qm_market)

// ─── Cargo — Cargo Tech ───────────────────────────────────────────────────────────

/datum/perk/mind/cargo_tech_loader
	name = "Loader"
	desc = "You move heavy crates 25% faster."
	icon_name = "boxes-stacked"
	cost = 1
	tree = PERK_TREE_MIND_CARGO_TECH

/datum/perk/mind/cargo_tech_inventory
	name = "Inventory Eye"
	desc = "Examining a crate reveals every item inside without opening it."
	icon_name = "eye"
	cost = 2
	tree = PERK_TREE_MIND_CARGO_TECH

/datum/perk/mind/cargo_tech_dispatcher
	name = "Dispatcher"
	desc = "Disposal-bin destination sorting respects multi-tag routes you assign."
	icon_name = "compass"
	cost = 3
	tree = PERK_TREE_MIND_CARGO_TECH
	requires = list(/datum/perk/mind/cargo_tech_loader)

// ─── Cargo — Miner ────────────────────────────────────────────────────────────────

/datum/perk/mind/cargo_miner_pickaxe
	name = "Strong Strokes"
	desc = "Pickaxe / drill mining cycles are 20% faster."
	icon_name = "gem"
	cost = 1
	tree = PERK_TREE_MIND_CARGO_MINER

/datum/perk/mind/cargo_miner_geologist
	name = "Geologist"
	desc = "Mining scanner returns rarer ore types from further away."
	icon_name = "mountain"
	cost = 2
	tree = PERK_TREE_MIND_CARGO_MINER

/datum/perk/mind/cargo_miner_pathfinder
	name = "Pathfinder"
	desc = "Quarry-floor hazards (gas, fauna) are flagged on your HUD before you reach them."
	icon_name = "route"
	cost = 3
	tree = PERK_TREE_MIND_CARGO_MINER
	requires = list(/datum/perk/mind/cargo_miner_geologist)

// ─── Civilian — Bartender ─────────────────────────────────────────────────────────

/datum/perk/mind/civ_bartender_pour
	name = "Steady Pour"
	desc = "Drinks you mix never spill and always end at exactly the requested volume."
	icon_name = "martini-glass"
	cost = 1
	tree = PERK_TREE_MIND_CIV_BARTENDER

/datum/perk/mind/civ_bartender_recipe
	name = "Cocktail Repertoire"
	desc = "Drinks you serve apply a small mood boost to the patron for 60s."
	icon_name = "wine-glass"
	cost = 2
	tree = PERK_TREE_MIND_CIV_BARTENDER

/datum/perk/mind/civ_bartender_bouncer
	name = "Bouncer"
	desc = "Disarm attempts inside the bar succeed 25% more often."
	icon_name = "hand"
	cost = 3
	tree = PERK_TREE_MIND_CIV_BARTENDER
	requires = list(/datum/perk/mind/civ_bartender_pour)

// ─── Civilian — Chef ──────────────────────────────────────────────────────────────

/datum/perk/mind/civ_chef_knife
	name = "Knife Skills"
	desc = "Food prep is 25% faster and chopped ingredients yield an extra portion."
	icon_name = "utensils"
	cost = 1
	tree = PERK_TREE_MIND_CIV_CHEF

/datum/perk/mind/civ_chef_seasoning
	name = "Seasoning"
	desc = "Dishes you serve grant a small mood buff to the diner."
	icon_name = "pepper-hot"
	cost = 2
	tree = PERK_TREE_MIND_CIV_CHEF

/datum/perk/mind/civ_chef_pastry
	name = "Pastry"
	desc = "Baking recipes complete in one fewer step and produce an extra serving."
	icon_name = "cookie-bite"
	cost = 3
	tree = PERK_TREE_MIND_CIV_CHEF
	requires = list(/datum/perk/mind/civ_chef_knife)

// ─── Civilian — Botanist ──────────────────────────────────────────────────────────

/datum/perk/mind/civ_bot_greenthumb
	name = "Green Thumb"
	desc = "Plants you tend grow 15% faster."
	icon_name = "seedling"
	cost = 1
	tree = PERK_TREE_MIND_CIV_BOTANIST

/datum/perk/mind/civ_bot_breeder
	name = "Breeder"
	desc = "Hybrid splices succeed 20% more often when you operate the pad."
	icon_name = "flask"
	cost = 2
	tree = PERK_TREE_MIND_CIV_BOTANIST

/datum/perk/mind/civ_bot_harvest
	name = "Bountiful Harvest"
	desc = "Harvests you collect yield one extra unit on average."
	icon_name = "wheat-awn"
	cost = 3
	tree = PERK_TREE_MIND_CIV_BOTANIST
	requires = list(/datum/perk/mind/civ_bot_greenthumb)

// ─── Civilian — Janitor ───────────────────────────────────────────────────────────

/datum/perk/mind/civ_jan_sweep
	name = "Sweeping Stroke"
	desc = "Your mop / pushbroom clears a wider tile pattern per swipe."
	icon_name = "broom"
	cost = 1
	tree = PERK_TREE_MIND_CIV_JANITOR

/datum/perk/mind/civ_jan_no_slip
	name = "Steady Feet"
	desc = "You never slip on wet floors and your wet-floor signs deter would-be slippers."
	icon_name = "shoe-prints"
	cost = 2
	tree = PERK_TREE_MIND_CIV_JANITOR

/datum/perk/mind/civ_jan_immaculate
	name = "Immaculate"
	desc = "Spaces you clean stay clean — debris and stains don't accumulate for 5 minutes."
	icon_name = "spray-can-sparkles"
	cost = 3
	tree = PERK_TREE_MIND_CIV_JANITOR
	requires = list(/datum/perk/mind/civ_jan_sweep)
