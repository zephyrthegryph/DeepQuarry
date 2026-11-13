// DQ Medical Reference — Surgeries tab builder.
//
// There are no fixed procedures to list. Surgery is opening a site, answering what is found in it, and closing, so the tab is
// built from the same data the operating room runs on: one entry for opening and closing, then one per finding step
// (`/datum/surgical_step` with `finds`), with the tools it takes, the body region it works in and the conditions it answers to
// (linked back to the Conditions tab). Nothing here is written by hand beyond each step's own one-sentence `about`.

/// The finding steps that answer to an affliction type: affliction typepath -> list of /datum/surgical_step.
/proc/build_surgical_steps_answering()
	var/list/answering = list()
	for(var/datum/surgical_step/S as anything in surgical_steps())
		if(!S.finds)
			continue
		for(var/affliction_type in S.treated_afflictions())
			var/list/steps = answering[affliction_type]
			if(!steps)
				steps = list()
				answering[affliction_type] = steps
			steps += S
	return answering

GLOBAL_TABLE(surgical_steps_answering_table, GLOBAL_PROC_REF(build_surgical_steps_answering))

/// The finding steps that answer to an affliction type, built once.
/proc/surgical_steps_answering()
	return GLOBAL_TABLE_GET(surgical_steps_answering_table)

/// Display names of a step's tools: the named tools it takes at full quality, then the qualities an improvised tool needs.
/proc/surgical_step_tool_names(datum/surgical_step/S)
	. = list()
	for(var/tool_type in S.allowed_tools)
		if(S.allowed_tools[tool_type] < 100)
			continue
		var/obj/tool_path = tool_type
		. |= capitalize(initial(tool_path.name))
	for(var/quality in S.allowed_tool_qualities)
		. |= "Any tool with the [quality] quality"

/obj/item/book/dq_medical_reference/proc/_dq_book_surgeries()
	var/list/out = list()
	out += list(_dq_book_access_entry())
	for(var/datum/surgical_step/S as anything in surgical_steps())
		if(S.finds)
			out += list(_dq_book_step_entry(S))
	return out

/// Opening and closing: the only fixed part of any operation.
/obj/item/book/dq_medical_reference/proc/_dq_book_access_entry()
	var/list/entry = list()
	entry["id"] = "surgery_access"
	entry["name"] = "Opening and closing a site"
	entry["category"] = "Access"
	entry["subcategory"] = null
	entry["description"] = "Every operation opens a site, answers what is found in it, and closes it. These are the only steps that are always the same; what lies between them depends on what the patient has."
	entry["body_region"] = "Any limb"
	entry["steps"] = list(
		"Cut through the skin with a scalpel.",
		"Retract the skin. Opening a limb this far shows what is in it: inspect the limb hands-on (grab the patient, target the limb, grab-click) or read the operating computer, and every finding is listed with the steps that answer to it.",
		"Where the limb is encased (the chest, the head), saw through and retract the bone to reach the organs inside.",
		"Answer each finding in any order by using the matching tool on the targeted limb. When several findings answer to the same tool, the most urgent goes first: bleeders, then the worst-off organ, a finding organ before a healthy one.",
		"Set the bone layer, then cauterize the incision closed. A prosthesis is opened and closed through its maintenance hatch instead.",
	)
	var/list/tools = list()
	for(var/step_type in list(/datum/surgical_step/access/incise, /datum/surgical_step/access/retract, /datum/surgical_step/access/saw, /datum/surgical_step/access/pry_bone, /datum/surgical_step/set_bone, /datum/surgical_step/cauterize))
		tools |= surgical_step_tool_names(surgical_step(step_type))
	entry["tools"] = tools
	entry["treats"] = list()
	return entry

/obj/item/book/dq_medical_reference/proc/_dq_book_step_entry(datum/surgical_step/S)
	var/list/entry = list()
	entry["id"] = "[S.type]"
	entry["name"] = S.name
	entry["category"] = S.book_category
	entry["subcategory"] = null
	entry["description"] = S.about
	entry["body_region"] = S.zones ? "Limbs it applies to" : (S.scope == SURGERY_SCOPE_PART ? "The opened limb" : "The opened limb and the organs in it")
	var/list/tools = surgical_step_tool_names(S)
	entry["steps"] = list(
		"Open the site (see Opening and closing a site) and read the findings.",
		"Pick this step when the findings below are there. It works at the retracted flesh[S.needs_full_access ? " or deeper: where the limb is encased, once the bone is retracted" : ""].",
		"[capitalize(S.begin_text)] the patient with [english_list(tools)].",
		"Give the patient pain relief or anaesthesia first: a patient who feels the step flinches and it goes wrong.",
		"Answer the other findings in any order, then close the site.",
	)
	entry["tools"] = tools
	var/list/treats = list()
	for(var/condition_type in S.treated_afflictions())
		treats += list(list(
			"id"   = "[condition_type]",
			"name" = _dq_condition_name(condition_type),
		))
	entry["treats"] = treats
	return entry
