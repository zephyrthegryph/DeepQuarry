// DQAdd — /datum/perk base class.
//
// One singleton per perk path. Registered into GLOB.all_perks at world init. Each perk
// knows its tree (one of the PERK_TREE_* ids), its category (body vs mind for budget
// accounting), its cost, and optional requires (path list of perks that must be selected
// first — enables small skill-tree branches inside a tree without a full graph engine).
//
// Body perks declare `var_changes` (assoc list of species/mob vars → values) and are
// applied by the body apply hook same way traits apply theirs. Mind perks override
// grant(target, prefs) / revoke(target, prefs) to wire in their effect (add component,
// register signal, set a mob flag, etc.).
//
// Subtypes only need to set name / desc / cost / tree / category and either var_changes
// (body) or override grant() (mind). Everything else flows from the base.

/datum/perk
	abstract_type = /datum/perk

	var/name = "Unnamed Perk"
	var/desc = "This perk has no description yet."

	/// One of PERK_CATEGORY_BODY / PERK_CATEGORY_MIND. Tells the budget code which pool
	/// the `cost` is drawn from.
	var/category = PERK_CATEGORY_MIND

	/// One of the PERK_TREE_* ids in _defines.dm. Used by the UI to group perks.
	var/tree = null

	/// Point cost. Body threshold perks: 1 per perk (the threshold gate does the gating).
	/// Mind perks: typical range 1-3.
	var/cost = 1

	/// Body threshold perks: minimum linear Body points spent before this perk is buyable.
	/// 0 means "no threshold gate" (e.g. for mind perks). Body perks set this to one of
	/// BODY_TIER_LOW / MID / HIGH.
	var/body_tier_threshold = 0

	/// Optional: list of other /datum/perk subpaths that must already be selected before
	/// this perk can be picked. Lets us build small dependency chains inside a tree.
	var/list/requires = null

	/// Body var_changes — assoc list mirroring /datum/trait.var_changes. Applied to the
	/// synthesized species datum. Mind perks should leave this null and override grant()
	/// instead; the body apply hook ignores Mind perks' var_changes.
	var/list/var_changes = null

	/// Optional component to attach on grant/detach on revoke. Mind perks lean on this for
	/// "this perk attaches Component X" effects.
	var/added_component_path = null

/datum/perk/proc/grant(mob/living/carbon/human/target, datum/preferences/preferences)
	if(added_component_path && !target.GetComponent(added_component_path))
		target.AddComponent(added_component_path)

/datum/perk/proc/revoke(mob/living/carbon/human/target, datum/preferences/preferences)
	if(added_component_path)
		var/datum/component/C = target.GetComponent(added_component_path)
		if(C)
			qdel(C)

/// Apply this perk's var_changes to the synthesized species. Mirrors the body of
/// /datum/trait.apply(). Mind perks with no var_changes are a no-op here.
/datum/perk/proc/apply_var_changes(datum/species/S)
	if(!var_changes || !S)
		return
	for(var/V in var_changes)
		if(V == "flags") // Bitflag merge, like traits.
			S.vars[V] |= var_changes[V]
		else
			S.vars[V] = var_changes[V]

/// Body-perk subtype: category is locked to body, default tree is the body catalog.
/datum/perk/body
	abstract_type = /datum/perk/body
	category = PERK_CATEGORY_BODY
	tree = PERK_TREE_BODY

/// Mind-perk subtype: category is locked to mind. Subtypes set `tree` per department.
/datum/perk/mind
	abstract_type = /datum/perk/mind
	category = PERK_CATEGORY_MIND
