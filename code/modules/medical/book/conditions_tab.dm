// DQ Medical Reference — Conditions tab builder.
//
// Walks every /datum/medical_issue/condition subtype, instantiates a
// prototype, and emits one TGUI entry per condition: clinical picture,
// cures (with cure-type curative/stabilising), worsens, caused-by
// causes, forward complications (via severity_gate + organ_damage
// causes), surgeries that treat it, and per-stage symptom/effect data.

/obj/item/book/dq_medical_reference/proc/_dq_book_conditions()
	var/list/out = list()
	for(var/T in subtypesof(/datum/medical_issue/condition))
		var/datum/medical_issue/condition/proto = dq_proto(T)
		var/list/entry = list()
		entry["id"]              = "[T]"
		entry["name"]            = proto.name
		entry["category"]        = proto.category || "General"
		entry["subcategory"]     = proto.subcategory
		entry["description"]     = proto.clinical_description || ""
		// Chem-driven conditions clear as soon as the trigger reagent
		// drops below threshold — they're presence-gated, not
		// severity-gated. The standard "stable until treated" /
		// "self-resolving" labels would lie about that.
		if(length(proto.caused_by_chems))
			entry["progression"] = "clears as the chem leaves the body"
		else
			entry["progression"] = dq_describe_progression(proto.progression_rate)

		// Cures and worsens.
		var/list/cures = list()
		if(proto.cured_by)
			for(var/id in proto.cured_by)
				cures += list(list(
					"id"   = id,
					"name" = dq_reagent_display_name(id),
					"band" = dq_describe_cure_strength(proto.cured_by[id]),
				))
		entry["cures"] = cures
		// Niche overdose cures: any reagent whose OD condition lists
		// THIS condition in its od_cures_externally drains. These are
		// dangerous-but-effective backup cures (bicaridine OD draining
		// subdural hematoma, cordradaxon OD restarting a stopped heart).
		// Surfaced as a separate "Overdose" group so a medic reading
		// this condition's cures sees both the safe path and the
		// chemical brute-force path.
		var/list/od_cures = list()
		for(var/CT in subtypesof(/datum/medical_issue/condition))
			var/datum/medical_issue/condition/od_proto = dq_proto(CT)
			if(od_proto.subcategory != "Overdose")
				continue
			if(!length(od_proto.od_cures_externally))
				continue
			if(!(T in od_proto.od_cures_externally))
				continue
			if(length(od_proto.caused_by_chems) != 1)
				continue
			for(var/id in od_proto.caused_by_chems)
				od_cures += list(list(
					"id"   = id,
					"name" = dq_reagent_display_name(id),
					"band" = dq_describe_cure_strength(od_proto.od_cures_externally[T]),
				))
		entry["od_cures"] = od_cures

		// "Curative" vs "stabilising": cause-driven conditions (spawned
		// by re-evaluating causes — organ_damage / metric_threshold /
		// blood_loss / germ_level) re-spawn while their cause holds, so
		// their `cured_by` reagents only suppress symptoms. One-shot
		// conditions (damage_event / severity_gate cascades) are cleared
		// permanently once severity hits zero. The book reader uses this
		// to know whether they're chasing a fix or buying time.
		entry["cure_type"] = _dq_cure_type_for(T)

		var/list/worsens = list()
		if(proto.worsened_by)
			for(var/id in proto.worsened_by)
				worsens += list(list(
					"id"   = id,
					"name" = dq_reagent_display_name(id),
					"band" = dq_describe_worsen_strength(proto.worsened_by[id]),
				))
		entry["worsens"] = worsens

		// Causes: every cause whose `produces` lists this type. The
		// entries name the cause's display name and id — the book links
		// these to the Causes tab.
		//
		// OD conditions also hardwire spawns from their Critical stage
		// via `always_spawns` (replacing the old severity_gate cascade).
		// We surface these as direct condition→condition links rather
		// than synthesising a cause datum: the OD itself IS the cause
		// of the complication.
		var/list/causes = list()
		for(var/datum/dq_cause/c as anything in dq_causes_producing(T))
			causes += list(_dq_cause_link(c))
		for(var/datum/medical_issue/condition/od_proto as anything in _dq_conditions_spawning(T))
			causes += list(list(
				"id"   = "[od_proto.type]",
				"name" = "[od_proto.name] (Critical)",
				"kind" = "condition",
			))
		entry["causes"] = causes

		// Chem-driven causes are a separate channel: the condition's
		// own `caused_by_chems` table lists reagent IDs and thresholds.
		// Emitted as a single row per condition — the row's `chems` list
		// is every reagent the condition needs above its threshold (one
		// chem for side-effect / OD conditions, two-or-more for
		// interaction conditions). The TGUI renders each row as a
		// separate line with "+" between chems, making it visually
		// obvious when a condition is an interaction.
		var/list/caused_by_reagents = list()
		if(length(proto.caused_by_chems))
			var/list/chems = list()
			for(var/reagent_id in proto.caused_by_chems)
				chems += list(list(
					"id"   = reagent_id,
					"name" = dq_reagent_display_name(reagent_id),
				))
			caused_by_reagents += list(list("chems" = chems))
		entry["caused_by_reagents"] = caused_by_reagents

		// Complications: forward links from this condition, grouped by
		// the cause they flow through. Two cause kinds contribute:
		//   - severity_gate causes whose source is this condition,
		//   - organ_damage causes watching an organ this condition
		//     damages.
		// Each entry shape: {cause_id, cause_name, conditions:[...]} so
		// the book can render the cause as a clickable section label
		// with the produced conditions as inline buttons.
		// Build (cause_id, cause_name, conditions[]) entries. Multiple
		// outcomes on a single cause that point at the same condition
		// (different stages of the same emergent) collapse into one
		// link — we dedupe by condition typepath. We also skip any
		// outcome that points at THIS condition (self-loop: e.g.
		// "Heart damage" complications would otherwise list "Heart
		// damage" itself because the heart_damage condition damages
		// the heart which the same cause watches).
		var/list/complications = list()
		var/list/comp_seen_causes = list()  // dedupe cause groups across all sources
		for(var/datum/dq_cause/severity_gate/g as anything in dq_severity_gates_from(T))
			var/list/produced = list()
			var/list/seen = list()
			for(var/datum/dq_cause_outcome/o as anything in g.produces)
				if(o.condition_type == T)
					continue
				if(seen["[o.condition_type]"])
					continue
				seen["[o.condition_type]"] = TRUE
				produced += list(list(
					"id"   = "[o.condition_type]",
					"name" = _dq_condition_name(o.condition_type),
				))
			if(length(produced))
				comp_seen_causes["[g.type]"] = TRUE
				complications += list(list(
					"cause_id"   = "[g.type]",
					"cause_name" = g.name,
					"conditions" = produced,
				))
		// Walk both the prototype and every authored stage to collect
		// the full set of damage types this condition can deal. Per-stage
		// organ damage (different organs at different OD stages) all
		// surfaces here, alongside mob-wide damage types (tox/oxy) which
		// resolve to their metric_threshold cause.
		var/list/dam_pairs = list()  // "type|tag" → TRUE for dedupe
		_dq_collect_damage_pairs(proto.organ_damage_type, proto.organ_damage_targets, proto.organ_damage_per_tick, proto.affectedorgan, proto.caused_by_chems_organ, dam_pairs)
		var/list/proto_stages = proto.get_stages()
		if(islist(proto_stages))
			for(var/sid in proto_stages)
				var/list/sd = proto_stages[sid]
				if(!sd)
					continue
				var/sd_type = isnull(sd["organ_damage_type"]) ? proto.organ_damage_type : sd["organ_damage_type"]
				var/list/sd_targets = isnull(sd["organ_damage_targets"]) ? proto.organ_damage_targets : sd["organ_damage_targets"]
				var/sd_rate = isnull(sd["organ_damage_per_tick"]) ? proto.organ_damage_per_tick : sd["organ_damage_per_tick"]
				_dq_collect_damage_pairs(sd_type, sd_targets, sd_rate, proto.affectedorgan, proto.caused_by_chems_organ, dam_pairs)
		// For each damage (type, tag) pair, find the matching cause and
		// emit it as a complication group whose conditions are the
		// failures the cause spawns.
		for(var/pair_key in dam_pairs)
			var/list/parts = splittext(pair_key, "|")
			var/dt = parts[1]
			var/tag = (length(parts) >= 2) ? parts[2] : ""
			var/datum/dq_cause/dc
			if(dt == "tox")
				dc = _dq_metric_cause_for("toxloss")
			else if(dt == "oxy")
				dc = _dq_metric_cause_for("oxyloss")
			else
				dc = _dq_organ_damage_cause_for(tag)
			if(!dc)
				continue
			if(comp_seen_causes["[dc.type]"])
				continue
			comp_seen_causes["[dc.type]"] = TRUE
			var/list/produced = list()
			var/list/seen = list()
			for(var/datum/dq_cause_outcome/o as anything in dc.produces)
				if(o.condition_type == T)
					continue
				if(seen["[o.condition_type]"])
					continue
				seen["[o.condition_type]"] = TRUE
				produced += list(list(
					"id"   = "[o.condition_type]",
					"name" = _dq_condition_name(o.condition_type),
				))
			if(length(produced))
				complications += list(list(
					"cause_id"   = "[dc.type]",
					"cause_name" = dc.name,
					"conditions" = produced,
				))
		// Hardwired stage spawns: any stage of THIS condition with a
		// non-empty always_spawns list contributes a complication group
		// labelled by the stage. OD conditions use this for their
		// Critical-stage cascades.
		var/list/own_stages = proto.get_stages()
		if(islist(own_stages))
			for(var/sid in own_stages)
				var/list/sd = own_stages[sid]
				var/list/spawns = sd && sd["always_spawns"]
				if(!length(spawns))
					continue
				var/list/produced = list()
				var/list/seen = list()
				for(var/spawn_type in spawns)
					if(spawn_type == T)
						continue
					if(seen["[spawn_type]"])
						continue
					seen["[spawn_type]"] = TRUE
					produced += list(list(
						"id"   = "[spawn_type]",
						"name" = _dq_condition_name(spawn_type),
					))
				if(length(produced))
					complications += list(list(
						"cause_id"   = null,
						"cause_name" = "[sid] stage",
						"conditions" = produced,
					))
		entry["complications"] = complications

		// Surgeries that treat this condition. The book renders each as
		// a clickable link to the Surgery tab.
		var/list/surgeries_treating = list()
		for(var/ST in subtypesof(/datum/dq_surgery))
			var/datum/dq_surgery/sp = dq_proto(ST)
			if(sp.treats && (T in sp.treats))
				surgeries_treating += list(list(
					"id"   = "[ST]",
					"name" = sp.name,
				))
		entry["surgeries"] = surgeries_treating

		// Staged conditions emit one entry per stage with that stage's
		// data; non-staged conditions emit a single anonymous "stage"
		// containing the default symptom_pool. The TGUI side renders
		// one section per stage. Damage isn't surfaced here — it folds
		// into the Complications section above so each damage type
		// shows up as a clickable cause link with the failures it can
		// spawn, without doubling up as a separate per-stage block.
		var/list/stages = proto.get_stages()
		var/list/stages_out = list()
		if(stages)
			for(var/stage_id in stages)
				var/list/sd = stages[stage_id]
				stages_out += list(_dq_emit_stage(stage_id, sd["name"], sd["description"], sd["symptom_pool"], sd["mechanical_effects"], sd["vital_effects"]))
		else
			stages_out += list(_dq_emit_stage(null, null, null, proto.symptom_pool, proto.mechanical_effects, proto.get_vital_effects()))
		entry["stages"] = stages_out
		// Keep entry["symptoms"] for back-compat: union of all stages'
		// symptoms so a casual reader sees what the condition can show.
		var/list/union_symptoms = list()
		var/list/seen_symptoms = list()
		for(var/list/sout in stages_out)
			for(var/list/s in sout["symptoms"])
				if(seen_symptoms[s["id"]])
					continue
				seen_symptoms[s["id"]] = TRUE
				union_symptoms += list(s)
		entry["symptoms"] = union_symptoms

		out += list(entry)
	return out


/// Build one stage entry for the book: id, name (override), description,
/// symptom list with frequency bands, mechanical effects, vital effects.
/proc/_dq_emit_stage(stage_id, stage_name, stage_desc, list/symptom_pool, list/mechanical_effects, list/vital_effects)
	var/list/syms = list()
	if(symptom_pool)
		for(var/sym_path in symptom_pool)
			var/datum/medical_symptom/S = dq_proto(sym_path)
			syms += list(list(
				"id"        = "[sym_path]",
				"name"      = S.name,
				"frequency" = dq_describe_symptom_frequency(symptom_pool[sym_path]),
			))
	var/list/mech = list()
	if(mechanical_effects)
		for(var/k in mechanical_effects)
			mech += list(list("key" = k, "value" = "[mechanical_effects[k]]"))
	var/list/vit = list()
	if(vital_effects)
		for(var/k in vital_effects)
			vit += list(list("key" = k, "value" = "[vital_effects[k]]"))
	return list(
		"id"                = stage_id,
		"name"              = stage_name,
		"description"       = stage_desc,
		"symptoms"          = syms,
		"mechanical_effects" = mech,
		"vital_effects"     = vit,
	)


/// Walk one (damage_type, organ_targets, rate) triple and add normalised
/// (type|tag) keys to `out` for every damage source it implies. Used by
/// the Complications builder to collect damage emitted across all stages
/// of a condition without double-counting. Tox/oxy use an empty tag.
/proc/_dq_collect_damage_pairs(damage_type, list/organ_targets, rate, default_organ, fallback_organ, list/out)
	if(!damage_type || !rate || rate <= 0)
		return
	if(damage_type == "tox")
		out["tox|"] = TRUE
		return
	if(damage_type == "oxy")
		out["oxy|"] = TRUE
		return
	var/list/tags = list()
	if(length(organ_targets))
		for(var/t in organ_targets)
			tags += t
	else
		var/o = default_organ || fallback_organ
		if(istext(o))
			tags += o
	for(var/tag in tags)
		out["[damage_type]|[tag]"] = TRUE


/// Find the /datum/dq_cause/organ_damage subtype watching a given organ
/// tag. Returns null when no cause is registered for that organ.
/proc/_dq_organ_damage_cause_for(organ_tag)
	if(!organ_tag)
		return null
	for(var/datum/dq_cause/organ_damage/c as anything in dq_causes_of_kind("/datum/dq_cause/organ_damage"))
		if(c.organ == organ_tag)
			return c
	return null


/// Find the /datum/dq_cause/metric_threshold subtype watching a given
/// scalar metric (e.g. "toxloss", "oxyloss"). Used by the Complications
/// builder to map mob-wide damage types to their umbrella cause.
/proc/_dq_metric_cause_for(metric_name)
	if(!metric_name)
		return null
	for(var/datum/dq_cause/metric_threshold/c as anything in dq_causes_of_kind("/datum/dq_cause/metric_threshold"))
		if(c.metric == metric_name)
			return c
	return null


/// Return every condition prototype whose get_stages() contains a stage
/// whose `always_spawns` list includes `target_type`. Used by the book's
/// Causes section to surface OD conditions as causes of the complication
/// they hardwire-spawn at Critical stage.
/proc/_dq_conditions_spawning(target_type)
	var/list/out = list()
	for(var/CT in subtypesof(/datum/medical_issue/condition))
		var/datum/medical_issue/condition/cproto = dq_proto(CT)
		var/list/stages = cproto.get_stages()
		if(!islist(stages))
			continue
		for(var/sid in stages)
			var/list/sd = stages[sid]
			var/list/spawns = sd && sd["always_spawns"]
			if(!length(spawns))
				continue
			if(target_type in spawns)
				out += cproto
				break
	return out
