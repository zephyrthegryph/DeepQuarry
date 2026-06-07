// DQAdd — /datum/perk_tree + global registry.
//
// Trees are pure presentation: each one groups perks (visually within the active
// category tab). A tree belongs to a category — its perks draw down that category's
// pool. Body categories have a single same-id tree; Mind categories (departments)
// have several sub-role trees that share the department pool.

GLOBAL_LIST_INIT(perk_trees, init_perk_trees())
GLOBAL_LIST_INIT(all_perks, init_perks())

/datum/perk_tree
	abstract_type = /datum/perk_tree

	var/id = null

	/// Sub-role name shown on the sub-tab (e.g. "Atmos Tech").
	var/display_name = "Unnamed Tree"

	/// Optional short blurb beneath the tab title.
	var/description = ""

	/// Override accent — usually inherited from the parent category. Set on the tree
	/// only when a sub-role wants its own tint.
	var/color = null

	/// FontAwesome icon on the sub-tab.
	var/icon_name = null

	/// PERK_CATEGORY_* id of the parent category.
	var/category = null

	/// Path → /datum/perk singleton. Populated at init.
	var/list/perks

// ─── Body trees (one per category, named the same as the category) ──────────────────

/datum/perk_tree/body
	abstract_type = /datum/perk_tree/body

/datum/perk_tree/body/strength
	id = PERK_TREE_BODY_STRENGTH
	display_name = "Strength"
	category = PERK_CATEGORY_BODY_STRENGTH

/datum/perk_tree/body/vigor
	id = PERK_TREE_BODY_VIGOR
	display_name = "Vigor"
	category = PERK_CATEGORY_BODY_VIGOR

/datum/perk_tree/body/speed
	id = PERK_TREE_BODY_SPEED
	display_name = "Speed"
	category = PERK_CATEGORY_BODY_SPEED

/datum/perk_tree/body/endurance
	id = PERK_TREE_BODY_ENDURANCE
	display_name = "Endurance"
	category = PERK_CATEGORY_BODY_ENDURANCE

// ─── Mind trees (sub-roles inside each department) ──────────────────────────────────

/datum/perk_tree/mind
	abstract_type = /datum/perk_tree/mind

// Command
/datum/perk_tree/mind/command_captain
	id = PERK_TREE_MIND_CMD_CAPTAIN
	display_name = "Captain"
	category = PERK_CATEGORY_MIND_COMMAND
	icon_name = "crown"

/datum/perk_tree/mind/command_hop
	id = PERK_TREE_MIND_CMD_HOP
	display_name = "Head of Personnel"
	category = PERK_CATEGORY_MIND_COMMAND
	icon_name = "user-tie"

// Security
/datum/perk_tree/mind/security_officer
	id = PERK_TREE_MIND_SEC_OFFICER
	display_name = "Officer"
	category = PERK_CATEGORY_MIND_SECURITY
	icon_name = "user-shield"

/datum/perk_tree/mind/security_detective
	id = PERK_TREE_MIND_SEC_DETECTIVE
	display_name = "Detective"
	category = PERK_CATEGORY_MIND_SECURITY
	icon_name = "magnifying-glass"

/datum/perk_tree/mind/security_warden
	id = PERK_TREE_MIND_SEC_WARDEN
	display_name = "Warden"
	category = PERK_CATEGORY_MIND_SECURITY
	icon_name = "key"

// Engineering
/datum/perk_tree/mind/engineering_atmos
	id = PERK_TREE_MIND_ENG_ATMOS
	display_name = "Atmos Tech"
	category = PERK_CATEGORY_MIND_ENGINEERING
	icon_name = "wind"

/datum/perk_tree/mind/engineering_engine
	id = PERK_TREE_MIND_ENG_ENGINE
	display_name = "Engine Tech"
	category = PERK_CATEGORY_MIND_ENGINEERING
	icon_name = "bolt"

/datum/perk_tree/mind/engineering_salvage
	id = PERK_TREE_MIND_ENG_SALVAGE
	display_name = "Salvage"
	category = PERK_CATEGORY_MIND_ENGINEERING
	icon_name = "screwdriver"

// Medical
/datum/perk_tree/mind/medical_doctor
	id = PERK_TREE_MIND_MED_DOCTOR
	display_name = "Doctor"
	category = PERK_CATEGORY_MIND_MEDICAL
	icon_name = "user-doctor"

/datum/perk_tree/mind/medical_surgeon
	id = PERK_TREE_MIND_MED_SURGEON
	display_name = "Surgeon"
	category = PERK_CATEGORY_MIND_MEDICAL
	icon_name = "scissors"

/datum/perk_tree/mind/medical_chemist
	id = PERK_TREE_MIND_MED_CHEMIST
	display_name = "Chemist"
	category = PERK_CATEGORY_MIND_MEDICAL
	icon_name = "vial"

// Research
/datum/perk_tree/mind/research_scientist
	id = PERK_TREE_MIND_RES_SCIENTIST
	display_name = "Scientist"
	category = PERK_CATEGORY_MIND_RESEARCH
	icon_name = "atom"

/datum/perk_tree/mind/research_roboticist
	id = PERK_TREE_MIND_RES_ROBOTICIST
	display_name = "Roboticist"
	category = PERK_CATEGORY_MIND_RESEARCH
	icon_name = "robot"

/datum/perk_tree/mind/research_xenoarch
	id = PERK_TREE_MIND_RES_XENOARCH
	display_name = "Xeno-Archaeology"
	category = PERK_CATEGORY_MIND_RESEARCH
	icon_name = "brush"

// Cargo
/datum/perk_tree/mind/cargo_qm
	id = PERK_TREE_MIND_CARGO_QM
	display_name = "Quartermaster"
	category = PERK_CATEGORY_MIND_CARGO
	icon_name = "clipboard-list"

/datum/perk_tree/mind/cargo_tech
	id = PERK_TREE_MIND_CARGO_TECH
	display_name = "Cargo Tech"
	category = PERK_CATEGORY_MIND_CARGO
	icon_name = "boxes-stacked"

/datum/perk_tree/mind/cargo_miner
	id = PERK_TREE_MIND_CARGO_MINER
	display_name = "Miner"
	category = PERK_CATEGORY_MIND_CARGO
	icon_name = "gem"

// Civilian
/datum/perk_tree/mind/civilian_bartender
	id = PERK_TREE_MIND_CIV_BARTENDER
	display_name = "Bartender"
	category = PERK_CATEGORY_MIND_CIVILIAN
	icon_name = "martini-glass"

/datum/perk_tree/mind/civilian_chef
	id = PERK_TREE_MIND_CIV_CHEF
	display_name = "Chef"
	category = PERK_CATEGORY_MIND_CIVILIAN
	icon_name = "utensils"

/datum/perk_tree/mind/civilian_botanist
	id = PERK_TREE_MIND_CIV_BOTANIST
	display_name = "Botanist"
	category = PERK_CATEGORY_MIND_CIVILIAN
	icon_name = "seedling"

/datum/perk_tree/mind/civilian_janitor
	id = PERK_TREE_MIND_CIV_JANITOR
	display_name = "Janitor"
	category = PERK_CATEGORY_MIND_CIVILIAN
	icon_name = "broom"

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
		if(!P.tree)
			continue
		var/datum/perk_tree/T = GLOB.perk_trees[P.tree]
		if(!T)
			continue
		// Derive the perk's pool category from its tree if not explicitly set, so
		// authors only have to set `tree` and the pool linkage follows automatically.
		if(!P.category)
			P.category = T.category
		.[path] = P
		LAZYSET(T.perks, path, P)
