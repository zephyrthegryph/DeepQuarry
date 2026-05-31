// DQAdd — /datum/perk base class.
//
// Each perk belongs to a tree (visual grouping); each tree belongs to a category
// (pool bucket). The perk's *category* (the PERK_KIND_* it draws from) is derived
// from the tree's parent category, but stored on the perk for fast lookup so the
// validator and apply hook don't have to chase indirections.
//
// Body perks declare `var_changes` (assoc list of species/mob vars → values) and the
// apply hook applies them the same way traits apply theirs. Mind perks override
// grant(target, prefs) / revoke(target, prefs).

/datum/perk
	abstract_type = /datum/perk

	var/name = "Unnamed Perk"
	var/desc = "This perk has no description yet."

	/// FontAwesome icon name shown on the perk card. Defaults to a neutral circle so
	/// unset perks still render something.
	var/icon_name = "circle-dot"

	/// PERK_KIND_BODY or PERK_KIND_MIND. Tells the budget code which side draws this perk.
	var/perk_kind = PERK_KIND_MIND

	/// PERK_CATEGORY_* id of the parent category. Pool draws this on lookup.
	var/category = null

	/// PERK_TREE_* id of the visual grouping the perk lives in.
	var/tree = null

	/// Point cost out of the category's pool. Typical range 1-3.
	var/cost = 1

	/// Optional: list of other /datum/perk subpaths that must already be selected.
	var/list/requires = null

	/// Body var_changes — assoc list mirroring /datum/trait.var_changes. Applied to
	/// the synthesized species datum. Leave null for Mind perks and override grant().
	var/list/var_changes = null

	/// Optional component to attach on grant / detach on revoke.
	var/added_component_path = null

/datum/perk/proc/grant(mob/living/carbon/human/target, datum/preferences/preferences)
	if(added_component_path && !target.GetComponent(added_component_path))
		target.AddComponent(added_component_path)

/datum/perk/proc/revoke(mob/living/carbon/human/target, datum/preferences/preferences)
	if(added_component_path)
		var/datum/component/C = target.GetComponent(added_component_path)
		if(C)
			qdel(C)

/// Apply this perk's var_changes to the synthesized species.
/datum/perk/proc/apply_var_changes(datum/species/S)
	if(!var_changes || !S)
		return
	for(var/V in var_changes)
		if(V == "flags") // Bitflag merge, like traits.
			S.vars[V] |= var_changes[V]
		else
			S.vars[V] = var_changes[V]

/datum/perk/body
	abstract_type = /datum/perk/body
	perk_kind = PERK_KIND_BODY

/datum/perk/mind
	abstract_type = /datum/perk/mind
	perk_kind = PERK_KIND_MIND
