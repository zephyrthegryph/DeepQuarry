// Surgery → condition-cure integration.
//
// Called from /datum/surgery_step's dispatch site (DQEdit in
// code/modules/surgery/surgery.dm). When a completing surgery_step
// matches the `completion_step` field of one of our /datum/dq_surgery
// records, the conditions listed in `treats` are cleared from the
// patient.
//
// Some upstream steps (e.g. /datum/surgery_step/internal/fix_organ)
// are reused by several distinct surgeries — lung repair, craniotomy,
// retinal repair — distinguished only by target_zone. So the lookup
// is step → list-of-surgeries, and the dispatcher filters by zone
// when a surgery declares a body_region.
//
// The body_region check is best-effort: it uses a small zone-keyword
// table so a record with body_region containing "head" only triggers
// for head zones, etc. A record with no body_region or an unknown
// region triggers for all zones (back-compat).

GLOBAL_LIST_EMPTY(dq_surgery_by_step)
GLOBAL_PROTECT(dq_surgery_by_step)

/proc/dq_surgeries_registry()
	if(length(GLOB.dq_surgery_by_step))
		return GLOB.dq_surgery_by_step
	for(var/T in subtypesof(/datum/dq_surgery))
		var/datum/dq_surgery/proto = new T()
		if(proto.completion_step)
			LAZYINITLIST(GLOB.dq_surgery_by_step[proto.completion_step])
			GLOB.dq_surgery_by_step[proto.completion_step] += proto
		else
			qdel(proto)
	return GLOB.dq_surgery_by_step


/// Lower-cased keywords drawn from each body_region phrase. A record
/// triggers when any of its keywords match the surgery's target zone.
/proc/_dq_zone_keywords_for(zone)
	switch(zone)
		if(BP_HEAD, O_EYES, O_MOUTH)
			return list("head")
		if(BP_TORSO, BP_GROIN)
			return list("torso", "chest")
		if(BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)
			return list("limb")
	return list()


/proc/_dq_surgery_matches_zone(datum/dq_surgery/surgery, zone)
	if(!surgery.body_region)
		return TRUE
	var/list/keywords = _dq_zone_keywords_for(zone)
	if(!length(keywords))
		return TRUE
	var/region = lowertext(surgery.body_region)
	// A body_region naming "Affected limb or torso" matches both
	// limb and torso zones; that's fine — both keyword sets pick it up.
	for(var/k in keywords)
		if(findtext(region, k))
			return TRUE
	return FALSE


/// Returns the union of `heals_organs` lists from every DQ surgery that
/// maps to the given `step_path` and whose `body_region` matches `zone`.
/// Used by the fix_organ DQEdit to restrict which internal organs a
/// shared surgery_step is allowed to repair — the upstream step zeros
/// every internal organ in the zone, which is more than any single DQ
/// surgery intends.
/proc/dq_organs_step_may_repair(step_path, zone)
	var/list/registry = dq_surgeries_registry()
	if(!length(registry))
		return null
	var/list/surgeries = registry[step_path]
	if(!length(surgeries))
		return null
	var/list/out
	for(var/datum/dq_surgery/surgery as anything in surgeries)
		if(!_dq_surgery_matches_zone(surgery, zone))
			continue
		if(!surgery.heals_organs)
			continue
		LAZYINITLIST(out)
		for(var/tag in surgery.heals_organs)
			out[tag] = TRUE
	return out


/proc/dq_apply_surgery_cures(datum/surgery_step/step, mob/living/carbon/human/patient, zone)
	if(!step || !patient)
		return
	var/list/registry = dq_surgeries_registry()
	if(!length(registry))
		return
	var/list/datum/dq_surgery/surgeries = registry[step.type]
	if(!length(surgeries))
		return
	for(var/datum/dq_surgery/surgery as anything in surgeries)
		if(!_dq_surgery_matches_zone(surgery, zone))
			continue
		var/drop = surgery.cure_severity
		for(var/datum/medical_issue/condition/C as anything in patient.get_all_conditions())
			if(!(C.type in surgery.treats))
				continue
			// Graduated cure: drop severity by `cure_severity`. When that
			// brings severity to ~0, the condition's own cure_issue path
			// removes it via check_progress; otherwise the surgery has
			// reduced the active problem but the patient still has
			// recovery to do.
			if(drop >= 100 || drop >= C.severity)
				C.cure_issue()
			else
				C.severity = max(0, C.severity - drop)
				// Force the symptom set to refresh on the next tick — a
				// post-surgery patient should stop presenting Critical-stage
				// symptoms once their severity has dropped, not wait until
				// the next band boundary is crossed naturally.
				C.last_reroll_band = -1
