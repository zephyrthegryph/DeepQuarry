// DQAdd — /datum/perk_tree base + global registry.
//
// Trees are presentation: they group perks by theme so the React panel can render one
// section per tree without each perk having to know about UI groupings. A perk's `tree`
// var (a PERK_TREE_* string id) decides which tree it slots into.
//
// One singleton per /datum/perk_tree subtype, instantiated into GLOB.perk_trees keyed by
// the tree id. Perks are auto-bucketed into the right tree at world init by walking
// GLOB.all_perks.

GLOBAL_LIST_INIT(perk_trees, init_perk_trees())
GLOBAL_LIST_INIT(all_perks, init_perks())

/datum/perk_tree
	abstract_type = /datum/perk_tree

	/// One of the PERK_TREE_* ids. Required.
	var/id = null

	/// Human-readable name shown in the UI tab/dropdown.
	var/display_name = "Unnamed Tree"

	/// Short blurb shown beneath the tree name.
	var/description = ""

	/// Perks bucketed into this tree at init. Path → /datum/perk singleton.
	var/list/perks

/datum/perk_tree/body
	id = PERK_TREE_BODY
	display_name = "Body"
	description = "Physical conditioning. Linear stat tweaks plus threshold perks at 3/6/9 spent points."

/datum/perk_tree/mind
	abstract_type = /datum/perk_tree/mind

/datum/perk_tree/mind/command
	id = PERK_TREE_MIND_COMMAND
	display_name = "Command"
	description = "Leadership, presence, decisive judgement."

/datum/perk_tree/mind/security
	id = PERK_TREE_MIND_SECURITY
	display_name = "Security"
	description = "Threat reading, restraint training, situational reflexes."

/datum/perk_tree/mind/engineering
	id = PERK_TREE_MIND_ENGINEERING
	display_name = "Engineering"
	description = "Tooling, wiring, atmospherics, salvage."

/datum/perk_tree/mind/medical
	id = PERK_TREE_MIND_MEDICAL
	display_name = "Medical"
	description = "Diagnosis, treatment, surgery, pharmacology."

/datum/perk_tree/mind/research
	id = PERK_TREE_MIND_RESEARCH
	display_name = "Research"
	description = "Investigation, anomaly analysis, materials."

/datum/perk_tree/mind/cargo
	id = PERK_TREE_MIND_CARGO
	display_name = "Cargo"
	description = "Logistics, requisitions, market knowledge."

/datum/perk_tree/mind/civilian
	id = PERK_TREE_MIND_CIVILIAN
	display_name = "Civilian"
	description = "Social craft, service, hands-on trades."

/datum/perk_tree/mind/synthetic
	id = PERK_TREE_MIND_SYNTHETIC
	display_name = "Synthetic"
	description = "Subsystem knowledge, network protocols, low-level diagnostics."

/proc/init_perk_trees()
	. = list()
	for(var/path in valid_subtypesof(/datum/perk_tree))
		var/datum/perk_tree/T = new path
		if(!T.id)
			continue
		.[T.id] = T

/proc/init_perks()
	. = list()
	if(!GLOB.perk_trees)
		GLOB.perk_trees = init_perk_trees()
	for(var/path in valid_subtypesof(/datum/perk))
		var/datum/perk/P = new path
		// Skip intermediate path nodes (/datum/perk/mind/medical and friends) — they're
		// concrete from DM's POV but have no tree set and shouldn't show up in any
		// catalog. Real perks always declare both tree and a non-default name.
		if(!P.tree)
			continue
		.[path] = P
		var/datum/perk_tree/T = GLOB.perk_trees[P.tree]
		if(T)
			LAZYSET(T.perks, path, P)
