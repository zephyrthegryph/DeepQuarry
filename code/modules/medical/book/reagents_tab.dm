// DQ Medical Reference — Reagents tab builder.
//
// For each reagent the encyclopedia surfaces:
//   - what conditions it cures (cured_by inversion)
//   - what conditions it worsens (worsened_by inversion)
//   - side-effect conditions it spawns above a threshold (single-chem
//     `caused_by_chems` entries on /datum/medical_issue/condition)
//   - interaction conditions it participates in (multi-chem
//     `caused_by_chems` entries)
//   - the overdose condition (if any) — caused_by_chems with subcategory
//     "Overdose"
//   - the recipe(s) that produce it (SSchemistry registry)
//   - a clinical category for grouping in the left-pane index

/obj/item/book/dq_medical_reference/proc/_dq_book_reagents()
	var/list/by_id = list()

	// First pass: invert cured_by / worsened_by AND collect every
	// condition that's chem-caused (so we can attribute it to its
	// reagents below). The reagents named here form the medical "seed"
	// set — anything they reference (including via the recipe graph)
	// is medically relevant; anything not reachable from the seed
	// isn't and gets filtered out below.
	var/list/datum/medical_issue/condition/chem_caused = list()
	for(var/T in subtypesof(/datum/medical_issue/condition))
		var/datum/medical_issue/condition/proto = dq_proto(T)
		if(proto.cured_by)
			for(var/id in proto.cured_by)
				LAZYINITLIST(by_id[id])
				LAZYINITLIST(by_id[id]["cures"])
				by_id[id]["cures"] += list(list(
					"id"   = "[T]",
					"name" = proto.name,
					"band" = dq_describe_cure_strength(proto.cured_by[id]),
				))
		if(proto.worsened_by)
			for(var/id in proto.worsened_by)
				LAZYINITLIST(by_id[id])
				LAZYINITLIST(by_id[id]["worsens"])
				by_id[id]["worsens"] += list(list(
					"id"   = "[T]",
					"name" = proto.name,
					"band" = dq_describe_worsen_strength(proto.worsened_by[id]),
				))
		if(length(proto.caused_by_chems))
			chem_caused += proto
			for(var/id in proto.caused_by_chems)
				LAZYINITLIST(by_id[id])

	// Second pass: transitive closure BACKWARD through the recipe graph
	// only. A reagent counts as medical if it appears as ingredient,
	// catalyst, or inhibitor of any chain whose end product is itself
	// medical. Phoron is the canonical case — not flagged medical itself
	// but used as a catalyst for inaprovaline, so it belongs in the
	// index. Bounded iteration because the recipe graph terminates at
	// element-level inputs.
	//
	// We deliberately don't follow recipes FORWARD here. A medical
	// reagent's "used in" index is built below and shown to the reader,
	// but pulling those products into the medical set would balloon the
	// index — phoron catalyses dozens of unrelated cocktails and
	// industrial reactions, all of which would otherwise drag their own
	// ingredients in transitively and bury the medically-useful chems.
	var/list/used_in_by_id = _dq_build_used_in_index()
	var/changed = TRUE
	var/iterations = 0
	while(changed && iterations < 10)
		changed = FALSE
		iterations++
		for(var/id in by_id.Copy())
			var/list/recipe = _dq_reagent_recipe(id)
			if(!length(recipe))
				continue
			for(var/list/rcp in recipe)
				for(var/list/ing in rcp["required"])
					if(!(ing["id"] in by_id))
						by_id[ing["id"]] = list()
						changed = TRUE
				for(var/list/cat in rcp["catalysts"])
					if(!(cat["id"] in by_id))
						by_id[cat["id"]] = list()
						changed = TRUE
				for(var/list/inh in rcp["inhibitors"])
					if(!(inh["id"] in by_id))
						by_id[inh["id"]] = list()
						changed = TRUE

	var/list/out = list()
	for(var/id in by_id)
		var/list/entry = list()
		entry["id"]          = id
		entry["name"]        = dq_reagent_display_name(id)
		entry["category"]    = dq_reagent_category(id)
		entry["description"] = dq_reagent_description(id)
		entry["cures"]       = by_id[id]["cures"] || list()
		entry["worsens"]     = by_id[id]["worsens"] || list()
		entry["recipe"]          = _dq_reagent_recipe(id)
		// Filter the Used-In list: only show destinations that are
		// themselves in the medical index, and dedupe by id (some
		// reagents have multiple recipes that produce the same
		// downstream product).
		var/list/raw_uses = used_in_by_id[id] || list()
		var/list/uses_seen = list()
		var/list/uses_filtered = list()
		for(var/list/u in raw_uses)
			if(uses_seen[u["id"]])
				continue
			if(!(u["id"] in by_id))
				continue
			uses_seen[u["id"]] = TRUE
			uses_filtered += list(u)
		entry["used_in"]         = uses_filtered
		entry["overdose"]        = _dq_reagent_overdose_for(id, chem_caused)
		entry["side_effects"]    = _dq_reagent_side_effects_for(id, chem_caused)
		entry["interactions"]    = _dq_reagent_interactions_for(id, chem_caused)
		out += list(entry)
	return out


/// Returns reagent_id -> list of { id, name } entries naming reagents
/// this one can be combined to produce. Walks both the instant and
/// distilling reaction registries once. Each input reagent (required,
/// catalyst, or inhibitor) gets the product attributed.
///
/// "Used in" exposes the inverse of Recipe — given inaprovaline, what
/// can a chemist make with it? Same source data, opposite direction.
/proc/_dq_build_used_in_index()
	var/list/out = list()
	if(!SSchemistry?.chemical_reactions)
		return out
	for(var/datum/decl/chemical_reaction/CR in SSchemistry.chemical_reactions)
		if(CR.wiki_flag & WIKI_SPOILER)
			continue
		var/result = CR.result
		if(!result)
			continue
		// Required ingredients: this reagent is an ingredient of `result`.
		for(var/RQ in CR.required_reagents)
			LAZYINITLIST(out[RQ])
			out[RQ] |= list(list(
				"id"   = result,
				"name" = dq_reagent_display_name(result),
			))
		// Catalysts go in the same "used in" bucket so a chemist
		// looking up phoron sees every reaction it accelerates.
		for(var/CL in CR.catalysts)
			LAZYINITLIST(out[CL])
			out[CL] |= list(list(
				"id"   = result,
				"name" = dq_reagent_display_name(result),
			))
	return out


/// Recipe(s) that produce this reagent. Returns a list of entries —
/// most reagents have one recipe but a few have multiple paths.
/proc/_dq_reagent_recipe(reagent_id)
	if(!SSchemistry?.chemical_reactions_by_product)
		return null
	var/list/reactions = SSchemistry.chemical_reactions_by_product[reagent_id]
	var/list/out = list()
	if(length(reactions))
		for(var/datum/decl/chemical_reaction/CR in reactions)
			if(CR.wiki_flag & WIKI_SPOILER)
				continue
			out += list(_dq_reagent_recipe_entry(CR))
	if(SSchemistry.distilled_reactions_by_product)
		var/list/distilled = SSchemistry.distilled_reactions_by_product[reagent_id]
		if(length(distilled))
			for(var/datum/decl/chemical_reaction/distilling/CR in distilled)
				if(CR.wiki_flag & WIKI_SPOILER)
					continue
				out += list(_dq_reagent_recipe_entry(CR, distilling = TRUE))
	return length(out) ? out : null


/proc/_dq_reagent_recipe_entry(datum/decl/chemical_reaction/CR, distilling = FALSE)
	var/list/entry = list()
	entry["distilling"] = distilling
	entry["result_amount"] = CR.result_amount
	var/list/reqs = list()
	for(var/RQ in CR.required_reagents)
		reqs += list(list(
			"id"     = RQ,
			"name"   = dq_reagent_display_name(RQ),
			"amount" = CR.required_reagents[RQ],
		))
	entry["required"] = reqs
	var/list/catal = list()
	for(var/CL in CR.catalysts)
		catal += list(list(
			"id"   = CL,
			"name" = dq_reagent_display_name(CL),
		))
	entry["catalysts"] = catal
	var/list/inhib = list()
	for(var/IH in CR.inhibitors)
		inhib += list(list(
			"id"   = IH,
			"name" = dq_reagent_display_name(IH),
		))
	entry["inhibitors"] = inhib
	if(distilling)
		var/datum/decl/chemical_reaction/distilling/D = CR
		if(D.temp_range)
			entry["temp_min"] = D.temp_range[1]
			entry["temp_max"] = D.temp_range[2]
	return entry


/// Overdose info: prefers an authored /datum/medical_issue/condition with
/// subcategory "Overdose" that the reagent is the (single) cause of.
/// Falls back to the upstream `overdose` threshold without a condition
/// link if no overdose condition is authored — that lets the encyclopedia
/// still warn medics about the threshold for chems we haven't documented.
/proc/_dq_reagent_overdose_for(reagent_id, list/datum/medical_issue/condition/chem_caused)
	for(var/datum/medical_issue/condition/proto as anything in chem_caused)
		if(proto.subcategory != "Overdose")
			continue
		if(length(proto.caused_by_chems) != 1)
			continue
		if(!(reagent_id in proto.caused_by_chems))
			continue
		var/list/entry = list(
			"threshold"   = proto.caused_by_chems[reagent_id],
			"condition_id"   = "[proto.type]",
			"condition_name" = proto.name,
			"description"    = proto.clinical_description,
			"lingers"        = proto.chem_scaling,
		)
		// Niche cures: conditions this OD directly drains at peak severity.
		if(length(proto.od_cures_externally))
			var/list/drains = list()
			for(var/target_type in proto.od_cures_externally)
				drains += list(list(
					"id"   = "[target_type]",
					"name" = _dq_condition_name(target_type),
				))
			entry["drains"] = drains
		// Combat / utility upsides: the od_boost keys, in plain text
		// readable form. Only emit when the condition actually has any.
		if(length(proto.od_boost))
			var/list/boosts = list()
			for(var/key in proto.od_boost)
				boosts += list(list(
					"key"      = key,
					"strength" = proto.od_boost[key],
				))
			entry["boosts"] = boosts
		return entry
	// Fall back to the bare upstream OD threshold so the encyclopedia
	// at least flags "this reagent has a dangerous threshold".
	if(!SSchemistry?.chemical_reagents)
		return null
	var/datum/reagent/R = SSchemistry.chemical_reagents[reagent_id]
	if(!R?.overdose)
		return null
	return list("threshold" = R.overdose)


/// Single-chem (= side effect) conditions that name this reagent as
/// their sole trigger. Returns one entry per condition.
/proc/_dq_reagent_side_effects_for(reagent_id, list/datum/medical_issue/condition/chem_caused)
	var/list/out = list()
	for(var/datum/medical_issue/condition/proto as anything in chem_caused)
		if(proto.subcategory == "Overdose")
			continue
		if(length(proto.caused_by_chems) != 1)
			continue
		if(!(reagent_id in proto.caused_by_chems))
			continue
		out += list(list(
			"id"           = "[proto.type]",
			"name"         = proto.name,
			"threshold"    = proto.caused_by_chems[reagent_id],
			"description"  = proto.clinical_description,
		))
	return out


/// Multi-chem (= interaction) conditions that include this reagent.
/// Each entry names the other reagent(s) required and the resulting
/// condition.
/proc/_dq_reagent_interactions_for(reagent_id, list/datum/medical_issue/condition/chem_caused)
	var/list/out = list()
	for(var/datum/medical_issue/condition/proto as anything in chem_caused)
		if(length(proto.caused_by_chems) < 2)
			continue
		if(!(reagent_id in proto.caused_by_chems))
			continue
		var/list/others = list()
		for(var/other_id in proto.caused_by_chems)
			if(other_id == reagent_id)
				continue
			others += list(list(
				"id"     = other_id,
				"name"   = dq_reagent_display_name(other_id),
				"amount" = proto.caused_by_chems[other_id],
			))
		out += list(list(
			"id"           = "[proto.type]",
			"name"         = proto.name,
			"threshold"    = proto.caused_by_chems[reagent_id],
			"other_chems"  = others,
			"description"  = proto.clinical_description,
		))
	return out


/// Reference-book category for a reagent id.
/proc/dq_reagent_category(reagent_id)
	var/static/list/cat
	if(!cat)
		cat = list(
			// --- Trauma & wound management ---
			REAGENT_ID_BICARIDINE     = "Trauma",
			REAGENT_ID_BICARIDAZE     = "Trauma",
			REAGENT_ID_KELOTANE       = "Trauma",
			REAGENT_ID_DERMALINE      = "Trauma",
			REAGENT_ID_OSTEODAXON     = "Trauma",
			// --- Organ repair (the *-daxon family) ---
			REAGENT_ID_PERIDAXON         = "Organ repair",
			REAGENT_ID_CORDRADAXON       = "Organ repair",
			REAGENT_ID_RESPIRODAXON      = "Organ repair",
			REAGENT_ID_HEPANEPHRODAXON   = "Organ repair",
			REAGENT_ID_GASTIRODAXON      = "Organ repair",
			REAGENT_ID_ALKYSINE          = "Organ repair",
			REAGENT_ID_SYNAPTIZINE       = "Organ repair",
			REAGENT_ID_IMIDAZOLINE       = "Organ repair",
			REAGENT_ID_REZADONE          = "Organ repair",
			REAGENT_ID_NECROXADONE       = "Organ repair",
			// --- Anti-infective ---
			REAGENT_ID_SPACEACILLIN   = "Anti-infective",
			REAGENT_ID_COROPHIZINE    = "Anti-infective",
			// --- Toxicology ---
			REAGENT_ID_ANTITOXIN      = "Toxicology",
			REAGENT_ID_CARTHATOLINE   = "Toxicology",
			// --- Environmental ---
			REAGENT_ID_LEPORAZINE     = "Environmental",
			REAGENT_ID_HYRONALIN      = "Environmental",
			REAGENT_ID_ARITHRAZINE    = "Environmental",
			REAGENT_ID_RYETALYN       = "Environmental",
			// --- Respiratory support ---
			REAGENT_ID_DEXALIN        = "Respiratory support",
			REAGENT_ID_DEXALINP       = "Respiratory support",
			// --- Cardiac / vital stabilisers ---
			REAGENT_ID_INAPROVALINE   = "Vital stabiliser",
			REAGENT_ID_TRICORDRAZINE  = "Vital stabiliser",
			REAGENT_ID_NUTRIMENT      = "Vital stabiliser",
			REAGENT_ID_IRON           = "Vital stabiliser",
			// --- Analgesia ---
			REAGENT_ID_PARACETAMOL    = "Analgesic",
			REAGENT_ID_TRAMADOL       = "Analgesic",
			REAGENT_ID_OXYCODONE      = "Analgesic",
			// --- Stimulants (rarely indicated medically; contraindicated for most conditions) ---
			REAGENT_ID_HYPERZINE      = "Stimulant",
		)
	return cat[reagent_id] || "Other"
