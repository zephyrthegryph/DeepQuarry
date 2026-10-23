// DQ Medical Reference — Surgeries tab builder.
//
// Walks every /datum/dq_surgery subtype and emits one entry per
// surgery: body region, ordered steps, required tools, and the
// conditions it treats (linked back to the Conditions tab).

/obj/item/book/dq_medical_reference/proc/_dq_book_surgeries()
	var/list/out = list()
	for(var/T in subtypesof(/datum/dq_surgery))
		var/datum/dq_surgery/proto = dq_proto(T)
		var/list/entry = list()
		entry["id"]          = "[T]"
		entry["name"]        = proto.name
		entry["category"]    = proto.category || "Trauma"
		entry["subcategory"] = proto.subcategory
		entry["description"] = proto.description
		entry["body_region"] = proto.body_region
		entry["steps"]       = proto.steps?.Copy() || list()
		entry["tools"]       = proto.tools?.Copy() || list()
		var/list/treats = list()
		if(proto.treats)
			for(var/condition_type in proto.treats)
				treats += list(list(
					"id"   = "[condition_type]",
					"name" = _dq_condition_name(condition_type),
				))
		entry["treats"] = treats
		out += list(entry)
	return out
