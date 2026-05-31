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

	/// Accent color for this tree's UI (hex). Used by the React panel for tab chip
	/// backgrounds, perk-card borders, etc. Chosen for legibility against a dark TGUI
	/// background, broadly themed off the department palette but de-conflicted (no two
	/// trees share a color).
	var/color = "#888888"

	/// FontAwesome icon name for the tree's tab chip. Optional.
	var/icon_name = null

	/// Perks bucketed into this tree at init. Path → /datum/perk singleton.
	var/list/perks

// ─── Body sub-trees ────────────────────────────────────────────────────────────────
// All four share the Body pool; the React panel groups them under one Body pane.
/datum/perk_tree/body
	abstract_type = /datum/perk_tree/body

/datum/perk_tree/body/strength
	id = PERK_TREE_BODY_STRENGTH
	display_name = "Strength"
	color = "#C0392B"
	icon_name = "dumbbell"

/datum/perk_tree/body/vigor
	id = PERK_TREE_BODY_VIGOR
	display_name = "Vigor"
	color = "#E67E22"
	icon_name = "heart-pulse"

/datum/perk_tree/body/speed
	id = PERK_TREE_BODY_SPEED
	display_name = "Speed"
	color = "#F1C40F"
	icon_name = "person-running"

/datum/perk_tree/body/endurance
	id = PERK_TREE_BODY_ENDURANCE
	display_name = "Endurance"
	color = "#8E44AD"
	icon_name = "shield-heart"

// ─── Mind trees ────────────────────────────────────────────────────────────────────
/datum/perk_tree/mind
	abstract_type = /datum/perk_tree/mind

/datum/perk_tree/mind/command
	id = PERK_TREE_MIND_COMMAND
	display_name = "Command"
	description = "Leadership, presence, decisive judgement."
	color = "#4A90E2"
	icon_name = "star"

/datum/perk_tree/mind/security
	id = PERK_TREE_MIND_SECURITY
	display_name = "Security"
	description = "Threat reading, restraint training, situational reflexes."
	color = "#E74C3C"
	icon_name = "shield-halved"

/datum/perk_tree/mind/engineering
	id = PERK_TREE_MIND_ENGINEERING
	display_name = "Engineering"
	description = "Tooling, wiring, atmospherics, salvage."
	color = "#E67E22"
	icon_name = "screwdriver-wrench"

/datum/perk_tree/mind/medical
	id = PERK_TREE_MIND_MEDICAL
	display_name = "Medical"
	description = "Diagnosis, treatment, surgery, pharmacology."
	color = "#27AE60"
	icon_name = "stethoscope"

/datum/perk_tree/mind/research
	id = PERK_TREE_MIND_RESEARCH
	display_name = "Research"
	description = "Investigation, anomaly analysis, materials."
	color = "#9B59B6"
	icon_name = "flask"

/datum/perk_tree/mind/cargo
	id = PERK_TREE_MIND_CARGO
	display_name = "Cargo"
	description = "Logistics, requisitions, market knowledge."
	color = "#D4A017"
	icon_name = "box"

/datum/perk_tree/mind/civilian
	id = PERK_TREE_MIND_CIVILIAN
	display_name = "Civilian"
	description = "Social craft, service, hands-on trades."
	color = "#1ABC9C"
	icon_name = "users"

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
