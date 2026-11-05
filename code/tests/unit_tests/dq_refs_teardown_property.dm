// The teardown property (doc/rewrite/proposals/relations.md, migration plan S4 step 3), generated over the declared relation tables.
//
// For every latent-safe movable type that declares a light relation (ref_one / ref_many / links) to a type the sweep can make, link a holder
// to a target through the declared var, then delete either end:
//   - the survivor keeps no stale var: a deleted target is gone from the holder's var; a deleted holder is gone from the target's reverse index
//     (and from the target's partner var of a paired relation);
//   - the deleted one is freed at once: nothing but the collector's queue entry references it (counted against a control datum deleted the same way);
//   - the BYOND built-ins are cleared: no loc, no contents, no vis_contents.
// The exhaustive tier sweeps every such type; the normal tier checks a fixed number of them.

/// Set once the reference finder has run for a failing case of the teardown property.
GLOBAL_VAR_INIT(dq_prop_searched, FALSE)

/// A datum counted as the control for the extra-reference count.
/datum/dq_prop_control

/// The references to the datum `ref_text` names, counted in a frame of its own (its local, plus whatever else holds it). 0 once it was freed.
/proc/dq_prop_refs(ref_text)
	var/datum/D = locate(ref_text)
	if(!D)
		return 0
	return refcount(D)

/// The reference count of a datum deleted the way the subjects are and held by nothing else: the most any subject may report.
/proc/dq_prop_control_refs()
	var/ref_text = dq_prop_control_delete()
	return dq_prop_refs(ref_text)

/proc/dq_prop_control_delete()
	var/datum/dq_prop_control/control = new
	. = ref(control)
	qdel(control)

/// A latent-safe, concrete type the sweep can make for the declared relation target `path`: `path` itself or its first such subtype.
/proc/dq_prop_target_path(path)
	if(!ispath(path, /atom/movable))
		return null
	for(var/atom/movable/candidate as anything in typesof(path))
		if(!is_abstract(candidate) && latent_type_safe(candidate))
			return candidate
	return null

/// The relation entries of `holder_path` the property covers: list(var name, target path), light relations to a type the sweep can make.
/proc/dq_prop_pairs(holder_path)
	. = list()
	var/atom/movable/H = new_unmaterialized(holder_path, null)
	if(!H)
		return
	var/datum/own_table/T = own_table_of(H)
	for(var/var_name in T.ref_vars)
		var/list/entry = T.entries[var_name]
		if(length(entry) >= OWNE_UNINDEXED && entry[OWNE_UNINDEXED]) // no reverse index to check
			continue
		var/target_path = dq_prop_target_path(entry[OWNE_TYPE])
		if(target_path)
			. += list(list(var_name, target_path))
	qdel(H, TRUE)

/// TRUE when holder var `var_name` of `H` still names the datum `ref_text` names.
/proc/dq_prop_names(atom/movable/H, var_name, ref_text)
	for(var/datum/member as anything in own_values(H, var_name))
		if(ref(member) == ref_text)
			return TRUE
	return FALSE

/// One case: link a holder to a target through `var_name`, delete `which` ("target" or "holder"), return the problems found.
/proc/dq_prop_case(holder_path, var_name, target_path, which, control_refs)
	var/list/problems = list()
	var/atom/movable/H = new_unmaterialized(holder_path, null)
	var/atom/movable/T = new_unmaterialized(target_path, null)
	if(!H || !T)
		return problems
	var/list/entry = own_table_of(H).entries[var_name]
	var/where = "[holder_path].[var_name] -> [target_path], deleting the [which]"
	if(entry[OWNE_LIST])
		rel_try_add(H, var_name, T)
	else
		rel_try_set(H, var_name, T)
	if(!dq_prop_names(H, var_name, ref(T)))
		qdel(H, TRUE)
		qdel(T, TRUE)
		return problems // the link was refused (a pair that needs more than two ends): not this property's case
	if(!rel_names(H, var_name, T))
		problems += "[where]: the reverse index does not name the holder after the link"
	var/holder_ref = ref(H)
	var/target_ref = ref(T)
	var/holder_slot = slot_known(H)
	var/partner_var = entry[OWNE_PARTNER]
	var/victim_ref
	if(which == "target")
		victim_ref = target_ref
		qdel(T, TRUE)
		problems += dq_prop_built_ins(T, where)
		T = null
		if(dq_prop_names(H, var_name, target_ref))
			problems += "[where]: the holder's var still names the deleted target"
	else
		victim_ref = holder_ref
		qdel(H, TRUE)
		problems += dq_prop_built_ins(H, where)
		H = null
		if(T && !QDELETED(T))
			if(holder_slot && T.refs_in && T.refs_in[holder_slot])
				problems += "[where]: the target's reverse index still has a row for the deleted holder"
			if(partner_var && (partner_var in T.vars) && dq_prop_names(T, partner_var, holder_ref))
				problems += "[where]: the target's partner var still names the deleted holder"
	var/refs = dq_prop_refs(victim_ref)
	if(refs > control_refs)
		problems += "[where]: the deleted [which] is still referenced after qdel() ([refs] references, a control datum reads [control_refs])"
#ifdef REFERENCE_TRACKING
		// The first one gets the reference finder, so the log names the holder ("## REF SEARCH Found" lines).
		if(!GLOB.dq_prop_searched)
			GLOB.dq_prop_searched = TRUE
			var/datum/holder_of_it = locate(victim_ref)
			holder_of_it?.find_references(refs - control_refs)
#endif
	if(H && !QDELETED(H))
		qdel(H, TRUE)
	if(T && !QDELETED(T))
		qdel(T, TRUE)
	return problems

/// The BYOND built-ins of a deleted movable: out of the world, nothing inside, nothing shown on it.
/proc/dq_prop_built_ins(atom/movable/D, where)
	. = list()
	if(D.loc)
		. += "[where]: the deleted [D.type] still has a loc ([D.loc.type])"
	if(length(D.contents))
		. += "[where]: the deleted [D.type] still has [length(D.contents)] thing(s) inside"
	if(length(D.vis_contents))
		. += "[where]: the deleted [D.type] still shows [length(D.vis_contents)] vis_contents"

/// Latent-safe movable types that declare a covered relation, in type order, at most `limit` (0: all).
/proc/dq_prop_holder_types(limit = 0)
	. = list()
	for(var/atom/movable/path as anything in typesof(/atom/movable))
		if(is_abstract(path) || !latent_type_safe(path))
			continue
		if(length(dq_prop_pairs(path)))
			. += path
			if(limit && length(.) >= limit)
				return

/datum/unit_test/dq_refs_teardown_property
	is_sweep_test = TRUE
	tier = TEST_TIER_EXHAUSTIVE

/datum/unit_test/dq_refs_teardown_property/Run()
	var/control_refs = dq_prop_control_refs()
	var/list/problems = list()
	var/cases = 0
	for(var/atom/movable/holder_path as anything in sweep_types(dq_prop_holder_types(holder_limit())))
		for(var/list/pair as anything in dq_prop_pairs(holder_path))
			for(var/which in list("target", "holder"))
				cases++
				problems += dq_prop_case(holder_path, pair[1], pair[2], which, control_refs)
	TEST_ASSERT(cases >= min_cases(), "the property covered only [cases] case(s), fewer than [min_cases()]: the declared relation tables stopped reaching latent-safe types")
	if(length(problems))
		TEST_FAIL("[length(problems)] problem(s) across [cases] case(s):\n[jointext(problems, "\n")]")

/// How many holder types the run covers (0: all).
/datum/unit_test/dq_refs_teardown_property/proc/holder_limit()
	return 0

/// The fewest cases a run must reach.
/datum/unit_test/dq_refs_teardown_property/proc/min_cases()
	return 50

/// Normal tier: the first holder types in type order.
/datum/unit_test/dq_refs_teardown_property/representative
	is_sweep_test = FALSE
	tier = TEST_TIER_NORMAL

/datum/unit_test/dq_refs_teardown_property/representative/holder_limit()
	return 12

/datum/unit_test/dq_refs_teardown_property/representative/min_cases()
	return 4
