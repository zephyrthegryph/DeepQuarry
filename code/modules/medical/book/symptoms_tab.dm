// DQ Medical Reference — Symptoms tab builder.
//
// Builds an index from condition prototypes back to the symptoms they
// can present, then walks every /datum/medical_symptom subtype and
// emits one entry per symptom with audiences, scanner phrase, patient
// messages, public emotes, and the conditions it appears in.

/obj/item/book/dq_medical_reference/proc/_dq_book_symptoms()
	var/list/condition_index = list()
	for(var/CT in subtypesof(/datum/medical_issue/condition))
		var/datum/medical_issue/condition/cproto = dq_proto(CT)
		// Track which (condition, symptom) pairs we've already indexed
		// so a symptom shared across multiple stages of the same
		// condition shows up once with its strongest frequency, not
		// duplicated. The frequency band picked is the highest weight
		// across all its appearances (top-level pool plus every stage).
		var/list/seen_for_this_condition = list()
		var/list/best_weight = list()
		if(cproto.symptom_pool)
			for(var/sym_path in cproto.symptom_pool)
				best_weight[sym_path] = cproto.symptom_pool[sym_path]
		// Pull every stage's pool too — many staged conditions only
		// declare their symptoms inside get_stages() (e.g. acute_radiation
		// keeps `skin_burns_minor` only on Moderate/Severe stages, with
		// no top-level pool), so an indexer that only walks the prototype's
		// `symptom_pool` would miss them.
		var/list/stages = cproto.get_stages()
		if(islist(stages))
			for(var/stage_id in stages)
				var/list/sd = stages[stage_id]
				var/list/spool = sd && sd["symptom_pool"]
				if(!spool)
					continue
				for(var/sym_path in spool)
					var/w = spool[sym_path]
					if(isnull(best_weight[sym_path]) || w > best_weight[sym_path])
						best_weight[sym_path] = w
		for(var/sym_path in best_weight)
			if(seen_for_this_condition[sym_path])
				continue
			seen_for_this_condition[sym_path] = TRUE
			LAZYINITLIST(condition_index[sym_path])
			condition_index[sym_path] += list(list(
				"id"        = "[CT]",
				"name"      = cproto.name,
				"frequency" = dq_describe_symptom_frequency(best_weight[sym_path]),
			))

	var/list/out = list()
	for(var/T in subtypesof(/datum/medical_symptom))
		var/datum/medical_symptom/proto = dq_proto(T)
		var/list/entry = list()
		entry["id"]          = "[T]"
		entry["name"]        = proto.name
		entry["category"]    = proto.category || "Subjective"
		entry["subcategory"] = proto.subcategory

		var/list/aud = list()
		if(proto.audiences & SYMPTOM_AUDIENCE_PATIENT)
			aud += "patient"
		if(proto.audiences & SYMPTOM_AUDIENCE_PUBLIC)
			aud += "public"
		if(proto.audiences & SYMPTOM_AUDIENCE_SCANNER)
			aud += "scanner"
		entry["audiences"]            = aud
		entry["clinical_description"] = proto.clinical_description || ""
		entry["patient_messages"]     = proto.get_patient_messages()?.Copy() || list()
		entry["public_emotes"]        = proto.get_public_emotes()?.Copy() || list()
		entry["scanner_phrase"]       = proto.scanner_phrase || ""
		entry["seen_in"]              = condition_index[T] || list()
		out += list(entry)
	return out
