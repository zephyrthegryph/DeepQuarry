// DQAdd — Mind perks, organized by department tree.
//
// These perks are "soft" — their effects mostly attach a component, set a flag, or grant
// a verb. They don't tweak species vars (that's the body side). The grant() proc here is
// authoritative for the perk's gameplay effect; the apply hook in apply_hooks/mind.dm
// just walks the prefs' selected list and calls grant() on each.
//
// Starter content: 3 perks per fleshed-out tree (Medical, Engineering, Security, Research,
// Civilian). The remaining trees (Command, Cargo, Synthetic) get a single placeholder so
// the UI has something to show — fill in as content lands.

// ─── Medical ────────────────────────────────────────────────────────────────────────────

/datum/perk/mind/medical/anatomy
	name = "Anatomy"
	desc = "Detailed knowledge of organ placement. You can identify damaged organs at a glance during an examination."
	cost = 1
	tree = PERK_TREE_MIND_MEDICAL

/datum/perk/mind/medical/pharmacology
	name = "Pharmacology"
	desc = "Better tolerance for both the side effects and the dosing of pharmaceuticals. Reagent overdose thresholds are 25% higher."
	cost = 2
	tree = PERK_TREE_MIND_MEDICAL
	requires = list(/datum/perk/mind/medical/anatomy)

/datum/perk/mind/medical/surgical_focus
	name = "Surgical Focus"
	desc = "Steady hands. Surgery steps complete 15% faster and are less likely to fail under stress."
	cost = 3
	tree = PERK_TREE_MIND_MEDICAL
	requires = list(/datum/perk/mind/medical/anatomy)

// ─── Engineering ────────────────────────────────────────────────────────────────────────

/datum/perk/mind/engineering/wirework
	name = "Wirework"
	desc = "You read wiring panels and APCs by colour at a glance. Wire-puzzle outcomes are revealed without trial-and-error."
	cost = 1
	tree = PERK_TREE_MIND_ENGINEERING

/datum/perk/mind/engineering/atmospherics
	name = "Atmospherics"
	desc = "Practiced reading of vent flows and pressure deltas. Atmos analyser readings include suggested fixes."
	cost = 2
	tree = PERK_TREE_MIND_ENGINEERING

/datum/perk/mind/engineering/salvage
	name = "Salvage"
	desc = "You know which pieces of a wreck are still worth something. Deconstructing machinery returns 15% more parts on average."
	cost = 2
	tree = PERK_TREE_MIND_ENGINEERING
	requires = list(/datum/perk/mind/engineering/wirework)

// ─── Security ───────────────────────────────────────────────────────────────────────────

/datum/perk/mind/security/threat_assessment
	name = "Threat Assessment"
	desc = "You spot concealed weapons and hostile intent before they escalate. Examining a person reveals visible sidearms."
	cost = 1
	tree = PERK_TREE_MIND_SECURITY

/datum/perk/mind/security/restraint_training
	name = "Restraint Training"
	desc = "Practiced cuffing and disarming technique. Cuff application is 25% faster and resisting your grab is harder."
	cost = 2
	tree = PERK_TREE_MIND_SECURITY

/datum/perk/mind/security/situational_reflexes
	name = "Situational Reflexes"
	desc = "Trained for contact. You don't suffer a stagger penalty the first time you're stunned in a fight."
	cost = 3
	tree = PERK_TREE_MIND_SECURITY
	requires = list(/datum/perk/mind/security/threat_assessment)

// ─── Research ───────────────────────────────────────────────────────────────────────────

/datum/perk/mind/research/methodology
	name = "Methodology"
	desc = "Disciplined hypothesis-testing habits. Research scanner results include a one-line prior interpretation."
	cost = 1
	tree = PERK_TREE_MIND_RESEARCH

/datum/perk/mind/research/anomaly_intuition
	name = "Anomaly Intuition"
	desc = "Field experience with weird readings. Anomaly classification scans are 20% faster and rarely give 'unknown' results."
	cost = 2
	tree = PERK_TREE_MIND_RESEARCH

/datum/perk/mind/research/materials_science
	name = "Materials Science"
	desc = "Hands-on knowledge of alloy behaviour. Smelting and centrifuge cycles yield 10% more usable output."
	cost = 2
	tree = PERK_TREE_MIND_RESEARCH

// ─── Civilian ───────────────────────────────────────────────────────────────────────────

/datum/perk/mind/civilian/social_craft
	name = "Social Craft"
	desc = "Practiced ear for register and tone. You can write a longer custom-say variant and your speech bubbles render larger."
	cost = 1
	tree = PERK_TREE_MIND_CIVILIAN

/datum/perk/mind/civilian/service
	name = "Service"
	desc = "Bartending, cooking, hosting — pick a counter and you know the rhythm. Drinks and dishes you serve apply a small mood buff."
	cost = 2
	tree = PERK_TREE_MIND_CIVILIAN

/datum/perk/mind/civilian/handy
	name = "Handy"
	desc = "Casual familiarity with the trades. You can use a wider range of basic tools without a fumble check."
	cost = 2
	tree = PERK_TREE_MIND_CIVILIAN

// ─── Command (stub) ─────────────────────────────────────────────────────────────────────

/datum/perk/mind/command/composure
	name = "Composure"
	desc = "Hard-won emotional control. You can issue clear orders through Command radio without your message getting cut off by interruptions."
	cost = 1
	tree = PERK_TREE_MIND_COMMAND

// ─── Cargo (stub) ───────────────────────────────────────────────────────────────────────

/datum/perk/mind/cargo/market_sense
	name = "Market Sense"
	desc = "You read manifests like a trader. Supply order prices show their last-week average alongside the current rate."
	cost = 1
	tree = PERK_TREE_MIND_CARGO

