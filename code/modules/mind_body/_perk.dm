// /datum/perk base class.
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

	/// Threshold-capstone gate: points that must already be spent in this perk's
	/// category before it can be picked. 0 = no threshold. Unlike `requires`, this
	/// rewards deep investment by ANY combination of perks in the category, not a
	/// specific chain — the road to a capstone can run through any build.
	var/category_spend_required = 0

	/// Body var_changes — assoc list mirroring /datum/trait.var_changes. Applied to
	/// the synthesized species datum. Leave null for Mind perks and override grant().
	var/list/var_changes = null

	/// Declarative numeric effects, folded into the mob's fx cache on grant:
	///   fx_mult[hook] — multiplied into perk_mult(hook) (default 1).
	///   fx_add[hook]  — summed into perk_add(hook) (default 0).
	/// A gameplay site reads the aggregate; new perks sharing a hook need no site code.
	var/list/fx_mult = null
	var/list/fx_add = null

	/// Optional component to attach on grant / detach on revoke.
	var/added_component_path = null

	/// Sort priority used by the React tree layout to order perks within a tier.
	/// Lower comes first (top-most or left-most). Default 0; perks within the same
	/// tier with equal sort_priority fall back to name-based ordering. Useful for
	/// putting chain-head perks before standalones or stamping "this perk should
	/// be the first thing players see in this tree".
	var/sort_priority = 0

	/// Explicit column position in the tree layout (in column units). null means
	/// "auto-layout decides". When set, the React side places the perk at exactly
	/// this column instead of computing one from the subtree algorithm.
	var/tree_x = null

	/// Explicit row position (tier) in the tree layout. null means auto-derive
	/// from the requires DAG. Allows the author to lift a perk to a specific tier
	/// regardless of its requires chain depth.
	var/tree_y = null

/datum/perk/proc/grant(mob/living/carbon/human/target, datum/preferences/preferences)
	if(istype(target))
		target.grant_perk(type)
		target.fold_perk_fx(src)
	if(added_component_path && !target.GetComponent(added_component_path))
		target.AddComponent(added_component_path)

/datum/perk/proc/revoke(mob/living/carbon/human/target, datum/preferences/preferences)
	if(istype(target))
		target.revoke_perk(type)
		target.rebuild_perk_fx()
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
