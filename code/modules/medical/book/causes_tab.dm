// DQ Medical Reference — Causes tab builder.
//
// Iterates dq_causes_registry() and emits one entry per cause with its
// display name, category, kind (damage / organ damage / progression /
// blood loss / infection), and the conditions it can produce. Also
// holds the cause-shape helpers used elsewhere: _dq_cause_kind,
// _dq_cause_link, and _dq_cure_type_for.

/obj/item/book/dq_medical_reference/proc/_dq_book_causes()
	var/list/out = list()
	for(var/datum/dq_cause/c as anything in dq_causes_registry())
		var/list/entry = list()
		entry["id"]          = "[c.type]"
		entry["name"]        = c.name
		entry["category"]    = c.category || "Trauma"
		entry["subcategory"] = c.subcategory
		entry["description"] = c.description
		entry["kind"]        = _dq_cause_kind(c)
		var/list/produces_out = list()
		for(var/datum/dq_cause_outcome/o as anything in c.produces)
			var/list/po = list()
			po["id"]   = "[o.condition_type]"
			po["name"] = _dq_condition_name(o.condition_type)
			po["band"] = dq_describe_cascade_chance(o.chance)
			po["tier"] = o.tier  // present for organ-damage tiered causes
			po["requires_present"] = o.requires_present ? _dq_condition_name(o.requires_present) : null
			po["requires_absent"]  = o.requires_absent ? _dq_condition_name(o.requires_absent) : null
			produces_out += list(po)
		entry["produces"] = produces_out
		out += list(entry)
	return out


/proc/_dq_cause_kind(datum/dq_cause/c)
	if(istype(c, /datum/dq_cause/damage_event))
		return "damage"
	if(istype(c, /datum/dq_cause/organ_damage))
		return "organ damage"
	if(istype(c, /datum/dq_cause/severity_gate))
		return "progression"
	if(istype(c, /datum/dq_cause/blood_loss))
		return "blood loss"
	if(istype(c, /datum/dq_cause/germ_level))
		return "infection"
	return "cause"

/proc/_dq_cause_link(datum/dq_cause/c)
	return list("id" = "[c.type]", "name" = c.name, "kind" = _dq_cause_kind(c))


/// Returns either "curative" or "stabilising" for a condition typepath.
/// Cause-driven conditions (re-evaluated each tick by the emergent /
/// metric dispatchers) get "stabilising" because their cured_by chems
/// only suppress symptoms while the underlying cause holds; the
/// condition re-spawns once the chem wears off. One-shot conditions
/// (damage_event / severity_gate cascades) get "curative" because their
/// cured_by chems can permanently clear the condition.
/proc/_dq_cure_type_for(condition_typepath)
	// Chem-driven conditions clear when the chem leaves — they don't
	// need their own dq_cause record but they're still
	// stabilising-style (cured_by reagents only suppress while present).
	var/datum/medical_issue/condition/proto = dq_proto(condition_typepath)
	if(length(proto.caused_by_chems))
		return "stabilising"
	for(var/datum/dq_cause/c as anything in dq_causes_producing(condition_typepath))
		if(istype(c, /datum/dq_cause/organ_damage))
			return "stabilising"
		if(istype(c, /datum/dq_cause/metric_threshold))
			return "stabilising"
		if(istype(c, /datum/dq_cause/blood_loss))
			return "stabilising"
		if(istype(c, /datum/dq_cause/germ_level))
			return "stabilising"
	return "curative"
