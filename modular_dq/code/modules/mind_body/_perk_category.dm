// DQAdd — /datum/perk_category + registry.
//
// A category owns ONE pool, drawn down by every perk in every tree whose `category` id
// matches. For Body, each category has a single tree. For Mind, each category (a
// department) owns multiple sub-role trees that all share its pool.
//
// Pool size at world init: see GLOB.perk_categories — categories are instantiated then
// looked up by id by both the validator (`dq_pool_for_category_and_age`) and the React
// UI (which renders one tab per category).

GLOBAL_LIST_INIT(perk_categories, init_perk_categories())

/datum/perk_category
	abstract_type = /datum/perk_category

	/// One of the PERK_CATEGORY_* ids. Required.
	var/id = null

	/// Human-readable name shown on the category tab.
	var/display_name = "Unnamed Category"

	/// Short blurb shown in the category header.
	var/description = ""

	/// Accent hex used for the tab chip, the pool fill bar, and perk-card borders.
	var/color = "#888888"

	/// FontAwesome icon name for the tab chip.
	var/icon_name = null

	/// PERK_CATEGORY_TYPE_BODY or PERK_CATEGORY_TYPE_MIND. Decides which top-level pane.
	var/category_type = PERK_CATEGORY_TYPE_BODY

// ─── Body categories ────────────────────────────────────────────────────────────────

/datum/perk_category/body
	abstract_type = /datum/perk_category/body
	category_type = PERK_CATEGORY_TYPE_BODY

/datum/perk_category/body/strength
	id = PERK_CATEGORY_BODY_STRENGTH
	display_name = "Strength"
	description = "Force, brute mitigation, carry capacity."
	color = "#C0392B"
	icon_name = "dumbbell"

/datum/perk_category/body/vigor
	id = PERK_CATEGORY_BODY_VIGOR
	display_name = "Vigor"
	description = "Health pool, recovery, raw vitality."
	color = "#E67E22"
	icon_name = "heart-pulse"

/datum/perk_category/body/speed
	id = PERK_CATEGORY_BODY_SPEED
	display_name = "Speed"
	description = "Movement, reflexes, agility."
	color = "#F1C40F"
	icon_name = "person-running"

/datum/perk_category/body/endurance
	id = PERK_CATEGORY_BODY_ENDURANCE
	display_name = "Endurance"
	description = "Stamina, resistance, hazard tolerance."
	color = "#8E44AD"
	icon_name = "shield-heart"

// ─── Mind departments ───────────────────────────────────────────────────────────────

/datum/perk_category/mind
	abstract_type = /datum/perk_category/mind
	category_type = PERK_CATEGORY_TYPE_MIND

/datum/perk_category/mind/command
	id = PERK_CATEGORY_MIND_COMMAND
	display_name = "Command"
	description = "Leadership, presence, decisive judgement."
	color = "#4A90E2"
	icon_name = "star"

/datum/perk_category/mind/security
	id = PERK_CATEGORY_MIND_SECURITY
	display_name = "Security"
	description = "Threat reading, restraint, investigation."
	color = "#E74C3C"
	icon_name = "shield-halved"

/datum/perk_category/mind/engineering
	id = PERK_CATEGORY_MIND_ENGINEERING
	display_name = "Engineering"
	description = "Tooling, wiring, atmospherics, salvage."
	color = "#E67E22"
	icon_name = "screwdriver-wrench"

/datum/perk_category/mind/medical
	id = PERK_CATEGORY_MIND_MEDICAL
	display_name = "Medical"
	description = "Diagnosis, surgery, pharmacology."
	color = "#27AE60"
	icon_name = "stethoscope"

/datum/perk_category/mind/research
	id = PERK_CATEGORY_MIND_RESEARCH
	display_name = "Research"
	description = "Investigation, anomaly analysis, robotics."
	color = "#9B59B6"
	icon_name = "flask"

/datum/perk_category/mind/cargo
	id = PERK_CATEGORY_MIND_CARGO
	display_name = "Cargo"
	description = "Logistics, requisitions, mining."
	color = "#D4A017"
	icon_name = "box"

/datum/perk_category/mind/civilian
	id = PERK_CATEGORY_MIND_CIVILIAN
	display_name = "Civilian"
	description = "Service, crafting, hospitality."
	color = "#1ABC9C"
	icon_name = "users"

/proc/init_perk_categories()
	. = list()
	for(var/path in valid_subtypesof(/datum/perk_category))
		var/datum/perk_category/C = new path
		if(!C.id)
			continue
		.[C.id] = C
