// The wiki's medical source: one article per catalogued condition, symptom, trigger, surgical step, treatment mechanism and organ, read from
// the medical data (dq_medical_book_data(), code/content/medical/book/) and the cross-reference context below, both built once per world.
// Drugs are reagent articles (chemistry.dm) filed under Medical/Drugs.
//
// The context (wiki_med_context()) inverts what the data says one way so every page can say it the other way:
//   causes      condition id -> every way it comes about: each trigger that produces it, each condition whose complications lead to it
//               (progression gates, organ damage, systemic toxicity, critical-stage spawns), each chemical that causes it, the fracture it knits
//               out of, and its catalogued subtypes (a family's forms).
//   tag_treats  tag -> condition type -> rate; tag_worsens likewise; tag_steps tag -> surgical steps; organs tag -> what is known of it.

/// A condition's article id from its book id ("/datum/affliction/concussion", "body_state/withdrawal").
/proc/wiki_cond_id(raw)
	var/text = "[raw]"
	if(findtext(text, "/datum/affliction/") == 1)
		text = copytext(text, length("/datum/affliction/") + 1)
	return "med/cond/[text]"

/proc/wiki_sym_id(raw)
	return "med/sym/[replacetext("[raw]", "/datum/affliction_symptom/", "")]"

/proc/wiki_trigger_id(raw)
	return "med/trigger/[replacetext("[raw]", "/datum/affliction_trigger/", "")]"

/proc/wiki_surgery_id(raw)
	return "med/surgery/[replacetext("[raw]", "/datum/surgical_step/", "")]"

/proc/wiki_mech_id(tag)
	return "med/mech/[tag]"

/proc/wiki_organ_id(tag)
	return "med/organ/[replacetext("[tag]", " ", "_")]"

/proc/wiki_organ_name(tag)
	return capitalize(replacetext("[tag]", "_", " "))

/// "Hemostatic" as an inline link to its mechanism article.
/proc/wiki_mech_ref(tag)
	return wiki_ref(wiki_mech_id(tag), dq_treatment_tag_name(tag))

/// A condition's index section: Medical/Conditions/<category>.
/proc/wiki_cond_path(list/entry)
	return "Medical/Conditions/[entry["category"] || "Other"]"

// ---- the context ----

GLOBAL_TABLE(wiki_med_context_table, GLOBAL_PROC_REF(build_wiki_med_context))

/proc/wiki_med_context()
	return GLOBAL_TABLE_GET(wiki_med_context_table)

/// Adds a cause link to a condition's list once (by the cause's id; a second route through the same cause adds to its note).
/proc/wiki_med_add_cause(list/causes, cond_id, list/link)
	var/list/rows = causes[cond_id]
	if(!rows)
		rows = list()
		causes[cond_id] = rows
	for(var/list/row in rows)
		if(row["id"] == link["id"])
			if(link["note"] && !findtext(row["note"] || "", link["note"]))
				row["note"] = row["note"] ? "[row["note"]]; [link["note"]]" : link["note"]
			return
	rows += list(link)

/proc/build_wiki_med_context()
	var/list/data = dq_medical_book_data()
	var/list/causes = list()
	// Triggers: every outcome, with its chance and its conditions.
	for(var/datum/affliction_trigger/c as anything in affliction_triggers_registry())
		for(var/datum/affliction_trigger_outcome/o as anything in c.produces)
			var/list/notes = list(dq_describe_cascade_chance(o.chance))
			if(o.requires_present)
				notes += "if [_dq_condition_name(o.requires_present)] is present"
			if(o.requires_absent)
				notes += "unless [_dq_condition_name(o.requires_absent)] is present"
			wiki_med_add_cause(causes, wiki_cond_id(o.condition_type), wiki_link(wiki_trigger_id(c.type), c.name, jointext(notes, ", "), "average"))
	// Conditions leading to conditions: every complication group of every condition, reversed.
	for(var/list/entry in data["conditions"])
		for(var/list/group in entry["complications"])
			for(var/list/produced in group["conditions"])
				wiki_med_add_cause(causes, wiki_cond_id(produced["id"]), wiki_link(wiki_cond_id(entry["id"]), entry["name"], "through [lowertext(group["cause_name"])]"))
	// Chemicals: one link per chemical, the others an interaction needs in the note.
	for(var/T in GLOBAL_TABLE_GET(dq_catalogued_affliction_types))
		var/datum/affliction/proto = dq_proto(T)
		for(var/reagent_id in proto.caused_by_chems)
			var/list/others = list()
			for(var/other_id in proto.caused_by_chems)
				if(other_id != reagent_id)
					others += dq_reagent_display_name(other_id)
			var/note = "above [proto.caused_by_chems[reagent_id]]u in the blood[length(others) ? ", together with [english_list(others)]" : ""]"
			wiki_med_add_cause(causes, wiki_cond_id(T), wiki_link(wiki_chem_id(reagent_id), dq_reagent_display_name(reagent_id), note, "bad"))
		// A family's base lists its forms (each form has its own causes).
		var/parent = proto.parent_type
		if(parent && (parent in GLOBAL_TABLE_GET(dq_catalogued_affliction_types)))
			wiki_med_add_cause(causes, wiki_cond_id(parent), wiki_link(wiki_cond_id(T), proto.name, "a form of it, with its own causes"))
	// The fracture that knits out of line.
	var/datum/affliction/untreated_fracture/fracture = dq_proto(/datum/affliction/untreated_fracture)
	wiki_med_add_cause(causes, wiki_cond_id(fracture.crooked_into), wiki_link(wiki_cond_id(/datum/affliction/untreated_fracture), fracture.name, "when bone repair knits it before it is set"))

	// Mechanisms: which conditions each treats and worsens, which steps give it.
	var/list/tag_treats = list()
	var/list/tag_worsens = list()
	var/list/direct_cures = list()
	var/list/direct_worsens = list()
	var/list/organs = list()
	for(var/T in GLOBAL_TABLE_GET(dq_catalogued_affliction_types))
		var/datum/affliction/proto = dq_proto(T)
		for(var/tag in proto.treated_by)
			LAZYINITLIST(tag_treats[tag])
			tag_treats[tag][T] = proto.treated_by[tag]
		for(var/tag in proto.worsened_by_tags)
			LAZYINITLIST(tag_worsens[tag])
			tag_worsens[tag][T] = proto.worsened_by_tags[tag]
		for(var/id in proto.cured_by)
			LAZYINITLIST(direct_cures[id])
			direct_cures[id][T] = proto.cured_by[id]
		for(var/id in proto.worsened_by)
			LAZYINITLIST(direct_worsens[id])
			direct_worsens[id][T] = proto.worsened_by[id]
		// The organ it sits on, and the organs it damages.
		var/site = istext(proto.location) ? proto.location : (length(proto.caused_by_chems) ? proto.caused_by_chems_organ : null)
		if(site)
			wiki_med_organ(organs, site)["sits"] |= T
		for(var/organ_tag in proto.organ_damage_targets)
			wiki_med_organ(organs, organ_tag)["damaged_by"] |= T
	var/list/tag_steps = list()
	for(var/datum/surgical_step/S as anything in surgical_steps())
		for(var/tag in S.treatments)
			LAZYINITLIST(tag_steps[tag])
			tag_steps[tag] |= S
	for(var/datum/affliction_trigger/organ_integrity/c as anything in affliction_triggers_of_kind("/datum/affliction_trigger/organ_integrity"))
		if(c.organ)
			wiki_med_organ(organs, c.organ)["triggers"] |= c
	for(var/list/r in data["reagents"])
		for(var/list/strain in r["strains"])
			wiki_med_organ(organs, strain["organ"])["strained_by"] |= r["id"]
	return list(
		"causes" = causes,
		"tag_treats" = tag_treats,
		"tag_worsens" = tag_worsens,
		"tag_steps" = tag_steps,
		"direct_cures" = direct_cures,
		"direct_worsens" = direct_worsens,
		"organs" = organs,
	)

/proc/wiki_med_organ(list/organs, tag)
	var/list/row = organs[tag]
	if(!row)
		row = list("sits" = list(), "damaged_by" = list(), "triggers" = list(), "strained_by" = list())
		organs[tag] = row
	return row

// ---- the index ----

/proc/wiki_source_medical(list/index)
	var/list/data = dq_medical_book_data()
	wiki_add(index, WIKI_ID_MEDICAL_INDEX, "Medical reference", "Medical", "How to read the medical pages: conditions, drugs, mechanisms, surgery.", null, GLOBAL_PROC_REF(wiki_med_index_body), null)
	for(var/list/entry in data["conditions"])
		wiki_add(index, wiki_cond_id(entry["id"]), capitalize(entry["name"]), wiki_cond_path(entry), entry["subcategory"], null, GLOBAL_PROC_REF(wiki_med_condition_body), entry)
	for(var/list/entry in data["symptoms"])
		wiki_add(index, wiki_sym_id(entry["id"]), capitalize(entry["name"]), "Medical/Symptoms/[entry["category"] || "Other"]", entry["scanner_phrase"], null, GLOBAL_PROC_REF(wiki_med_symptom_body), entry)
	for(var/list/entry in data["causes"])
		wiki_add(index, wiki_trigger_id(entry["id"]), entry["name"], "Medical/Triggers/[entry["category"] || "Other"]", entry["kind"], null, GLOBAL_PROC_REF(wiki_med_trigger_body), entry)
	for(var/list/entry in data["surgeries"])
		wiki_add(index, wiki_surgery_id(entry["id"]), entry["name"], "Medical/Surgery/[entry["category"] || "Other"]", null, null, GLOBAL_PROC_REF(wiki_med_surgery_body), entry)
	for(var/tag in GLOB.dq_treatment_tag_names)
		wiki_add(index, wiki_mech_id(tag), dq_treatment_tag_name(tag), "Medical/Treatment mechanisms", wiki_treatment_about(tag), null, GLOBAL_PROC_REF(wiki_med_mechanism_body), tag)
	var/list/organs = wiki_med_context()["organs"]
	for(var/tag in organs)
		wiki_add(index, wiki_organ_id(tag), wiki_organ_name(tag), "Medical/Organs", null, null, GLOBAL_PROC_REF(wiki_med_organ_body), tag)

/proc/wiki_med_index_body()
	return wiki_markup_blocks({"The medical pages are built from the same data the body runs on, so what they say is what happens.
## How the pages fit together
- A **condition** is something wrong with a patient. Its page says what causes it, how it shows, what treats it and what it leads to.
- A **treatment mechanism** is how a treatment works: \[\[med/mech/hemostatic]], \[\[med/mech/antimicrobial]] and so on. A condition names the mechanisms that help it; drugs, tools and surgery name the mechanisms they provide. Each mechanism page lists both.
- A **trigger** is an event that can bring a condition on: an injury, organ damage, blood loss, an infection or an environmental reading.
- A **symptom** is what the patient feels, what others see and what a scanner reads.
- A **surgical step** answers a finding in an opened limb. Start with \[\[med/surgery/surgery_access]].
- **Drugs** are reagent pages under Medical/Drugs. Their chemistry (recipe, structure, processes) is on the same page. Purity is explained in \[\[chem/purity]].
## Curative or stabilising
A condition that comes from a lasting cause (an organ that stays damaged, blood that stays low, a chemical still in the blood) comes back while the cause lasts: its treatment only stabilises the patient. Fix the cause. Other conditions are cleared for good once treatment brings them to nothing.
"})

// ---- conditions ----

/// A links block per frequency band (symptom lists), most frequent first.
/proc/wiki_med_symptom_links(list/symptoms)
	. = list()
	for(var/band in list("almost always present", "often present", "sometimes present", "rarely present"))
		var/list/items = list()
		for(var/list/s in symptoms)
			if(s["frequency"] != band)
				continue
			// Body-state symptoms are plain descriptions, not catalogued symptoms.
			var/id = findtext(s["id"], "/datum/affliction_symptom/") == 1 ? wiki_sym_id(s["id"]) : null
			items += list(wiki_link(id, s["name"]))
		if(length(items))
			. += list(wiki_links(capitalize(band), items))

/// The drugs that provide `tag`, as links: strongest first, the note the strength they give this condition (rate * potency).
/proc/wiki_med_providers(tag, rate, tone)
	var/list/rows = list()
	var/list/table = GLOBAL_TABLE_GET(dq_reagent_tag_table)
	for(var/id in table)
		var/potency = table[id][tag]
		if(potency > 0 && wiki_title(wiki_chem_id(id)))
			rows[id] = potency
	sortTim(rows, GLOBAL_PROC_REF(cmp_numeric_dsc), TRUE)
	. = list()
	for(var/id in rows)
		var/strength = rate ? dq_describe_cure_strength(rate * rows[id]) : dq_describe_cure_strength(rows[id])
		. += list(wiki_link(wiki_chem_id(id), dq_reagent_display_name(id), strength, tone))

/proc/wiki_med_condition_body(list/c)
	var/list/blocks = list()
	var/list/context = wiki_med_context()
	var/cond_id = wiki_cond_id(c["id"])
	var/T = text2path(c["id"])
	var/datum/affliction/proto = ispath(T, /datum/affliction) ? dq_proto(T) : null
	blocks += list(wiki_p(c["description"]))
	var/list/facts = list(list("Category", c["subcategory"] ? "[c["category"]], [c["subcategory"]]" : c["category"]), list("Course", capitalize(c["progression"])))
	if(c["cure_type"] == "stabilising")
		facts += list(list("Treatment", "Stabilising: it lasts while its cause does. Treat the cause."))
	else
		facts += list(list("Treatment", "Curative: treatment clears it for good."))
	var/site = proto ? (istext(proto.location) ? proto.location : (length(proto.caused_by_chems) ? proto.caused_by_chems_organ : null)) : null
	if(site && wiki_title(wiki_organ_id(site)))
		facts += list(list("Site", wiki_ref(wiki_organ_id(site), wiki_organ_name(site))))
	if(proto)
		var/parent = proto.parent_type
		if(parent in GLOBAL_TABLE_GET(dq_catalogued_affliction_types))
			facts += list(list("A form of", wiki_ref(wiki_cond_id(parent), capitalize(_dq_condition_name(parent)))))
	blocks += list(wiki_kv(facts))

	var/list/causes = context["causes"][cond_id]
	if(length(causes))
		blocks += list(wiki_h("Causes"))
		var/list/by_kind = list("Injuries and events" = list(), "Other conditions" = list(), "Chemicals" = list())
		for(var/list/link in causes)
			if(findtext(link["id"], "med/trigger/") == 1)
				by_kind["Injuries and events"] += list(link)
			else if(findtext(link["id"], "chem/") == 1)
				by_kind["Chemicals"] += list(link)
			else
				by_kind["Other conditions"] += list(link)
		for(var/kind in by_kind)
			if(length(by_kind[kind]))
				blocks += list(wiki_links(kind, by_kind[kind]))

	var/list/stages = c["stages"]
	if(length(stages) > 1)
		var/list/tabs = list()
		for(var/list/stage in stages)
			var/list/stage_blocks = list()
			if(stage["description"])
				stage_blocks += list(wiki_p(stage["description"]))
			stage_blocks += wiki_med_symptom_links(stage["symptoms"])
			if(length(stage["effects"]))
				stage_blocks += list(wiki_h("Effects"), wiki_ul(stage["effects"]))
			if(!length(stage_blocks))
				stage_blocks += list(wiki_p("No symptoms of its own at this stage."))
			tabs += list(wiki_tab(stage["name"] || capitalize("[stage["id"]]"), stage_blocks))
		blocks += list(wiki_h("Stages"), wiki_tabs(tabs))
	else if(length(stages))
		var/list/stage = stages[1]
		if(length(stage["symptoms"]))
			blocks += list(wiki_h("Symptoms"))
			blocks += wiki_med_symptom_links(stage["symptoms"])
		if(length(stage["effects"]))
			blocks += list(wiki_h("Effects"), wiki_ul(stage["effects"]))

	// Treatment: one row per mechanism (what it is, then the drugs that give it), then the condition's own remedies, overdose cures, surgery.
	var/list/treatment = list()
	if(proto?.treated_by)
		var/list/tags = proto.treated_by.Copy()
		sortTim(tags, GLOBAL_PROC_REF(cmp_numeric_dsc), TRUE)
		for(var/tag in tags)
			var/list/providers = wiki_med_providers(tag, tags[tag], "good")
			var/label = "[wiki_mech_ref(tag)] ([dq_describe_cure_strength(tags[tag])])"
			if(!length(providers))
				treatment += list(wiki_note("[label]: given by tools or procedures, not by drugs. See the mechanism.", "good"))
			else
				treatment += list(wiki_links(label, providers))
	var/list/specific = list()
	for(var/id in proto?.cured_by)
		specific += list(wiki_link(wiki_chem_id(id), dq_reagent_display_name(id), dq_describe_cure_strength(proto.cured_by[id]), "good"))
	for(var/list/cure in (proto ? null : c["cures"]))
		specific += list(wiki_link(wiki_chem_id(cure["id"]), cure["name"], cure["band"], "good"))
	if(length(specific))
		treatment += list(wiki_links("Specific remedies", specific))
	var/list/od = list()
	for(var/list/cure in c["od_cures"])
		od += list(wiki_link(wiki_chem_id(cure["id"]), cure["name"], "dangerous: works by overdosing", "bad"))
	if(length(od))
		treatment += list(wiki_links("Overdose cures", od))
	var/list/surgery = list()
	for(var/list/s in c["surgeries"])
		surgery += list(wiki_link(wiki_surgery_id(s["id"]), s["name"], null, "good"))
	if(length(surgery))
		treatment += list(wiki_links("Surgery", surgery))
	if(length(treatment))
		blocks += list(wiki_h("Treatment"))
		blocks += treatment
	else if(proto?.recedes_without_cause || (proto && proto.progression_rate < 0))
		blocks += list(wiki_h("Treatment"), wiki_note("Nothing treats it directly: it fades on its own once its cause is gone."))

	var/list/avoid = list()
	if(proto?.worsened_by_tags)
		for(var/tag in proto.worsened_by_tags)
			var/list/providers = wiki_med_providers(tag, proto.worsened_by_tags[tag], "bad")
			if(length(providers))
				avoid += list(wiki_links("[wiki_mech_ref(tag)] ([dq_describe_worsen_strength(proto.worsened_by_tags[tag])])", providers))
	var/list/direct_bad = list()
	for(var/id in proto?.worsened_by)
		direct_bad += list(wiki_link(wiki_chem_id(id), dq_reagent_display_name(id), dq_describe_worsen_strength(proto.worsened_by[id]), "bad"))
	if(length(direct_bad))
		avoid += list(wiki_links("Specifically", direct_bad))
	if(length(avoid))
		blocks += list(wiki_h("Makes it worse"))
		blocks += avoid

	if(length(c["complications"]))
		blocks += list(wiki_h("Leads to"))
		for(var/list/group in c["complications"])
			var/list/items = list()
			for(var/list/produced in group["conditions"])
				items += list(wiki_link(wiki_cond_id(produced["id"]), capitalize(produced["name"])))
			var/label = group["cause_id"] && wiki_title(wiki_trigger_id(group["cause_id"])) ? wiki_ref(wiki_trigger_id(group["cause_id"]), group["cause_name"]) : capitalize(group["cause_name"])
			blocks += list(wiki_links(label, items))

	if(length(c["raised_by"]))
		var/list/raise = list()
		var/list/lower = list()
		for(var/list/x in c["raised_by"])
			var/list/link = wiki_link(wiki_chem_id(x["id"]), x["name"], "by [abs(x["value"])]", x["raises"] ? "bad" : "good")
			if(x["raises"])
				raise += list(link)
			else
				lower += list(link)
		blocks += list(wiki_h("Seizure proneness"))
		if(length(raise))
			blocks += list(wiki_links("Raised by", raise))
		if(length(lower))
			blocks += list(wiki_links("Lowered by", lower))
	return blocks

// ---- symptoms ----

/proc/wiki_med_symptom_body(list/s)
	var/list/blocks = list(wiki_p(s["clinical_description"]))
	var/list/facts = list(list("Noticed by", capitalize(english_list(s["audiences"]))))
	if(s["scanner_phrase"])
		facts += list(list("Scanners read", s["scanner_phrase"]))
	blocks += list(wiki_kv(facts))
	if(length(s["patient_messages"]))
		blocks += list(wiki_h("What the patient feels"), wiki_ul(s["patient_messages"]))
	if(length(s["public_emotes"]))
		blocks += list(wiki_h("What others see"), wiki_ul(s["public_emotes"]))
	var/list/by_band = list()
	for(var/list/x in s["seen_in"])
		LAZYADD(by_band[x["frequency"]], list(wiki_link(wiki_cond_id(x["id"]), capitalize(x["name"]))))
	if(length(by_band))
		blocks += list(wiki_h("Seen in"))
		for(var/band in list("almost always present", "often present", "sometimes present", "rarely present"))
			if(length(by_band[band]))
				blocks += list(wiki_links(capitalize(band), by_band[band]))
	return blocks

// ---- triggers ----

/proc/wiki_med_trigger_body(list/t)
	var/list/blocks = list(wiki_p(t["description"]))
	blocks += list(wiki_kv(list(list("Kind", capitalize(t["kind"])), list("Category", t["subcategory"] ? "[t["category"]], [t["subcategory"]]" : t["category"]))))
	var/list/items = list()
	for(var/list/o in t["produces"])
		var/list/notes = list(o["band"])
		if(o["tier"])
			notes += "at [lowertext("[o["tier"]]")] damage"
		if(o["requires_present"])
			notes += "if [o["requires_present"]] is present"
		if(o["requires_absent"])
			notes += "unless [o["requires_absent"]] is present"
		// Engineered contagion strains are not catalogued (their constructors roll a strain): named, not linked.
		var/catalogued = (text2path(o["id"]) in GLOBAL_TABLE_GET(dq_catalogued_affliction_types))
		items += list(wiki_link(catalogued ? wiki_cond_id(o["id"]) : null, capitalize(o["name"]), jointext(notes, ", "), "average"))
	blocks += list(wiki_h("Can bring on"), wiki_links("Conditions", items))
	return blocks

// ---- surgery ----

/proc/wiki_med_surgery_body(list/s)
	var/list/blocks = list(wiki_p(s["description"]))
	blocks += list(wiki_kv(list(list("Where", s["body_region"]), list("Category", s["category"]))))
	blocks += list(wiki_h("Steps"), wiki_ol(s["steps"]))
	if(s["id"] != "surgery_access")
		blocks += list(wiki_note("Every operation starts and ends the same way: [wiki_ref(wiki_surgery_id("surgery_access"), "opening and closing a site")]."))
	if(length(s["tools"]))
		blocks += list(wiki_h("Tools"), wiki_ul(s["tools"]))
	var/list/treats = list()
	for(var/list/x in s["treats"])
		treats += list(wiki_link(wiki_cond_id(x["id"]), capitalize(x["name"]), null, "good"))
	if(length(treats))
		blocks += list(wiki_h("Answers to"), wiki_links("Conditions", treats))
	return blocks

// ---- mechanisms ----

/proc/wiki_med_mechanism_body(tag)
	var/list/context = wiki_med_context()
	var/list/blocks = list(wiki_p(wiki_treatment_about(tag)))
	var/list/works = list()
	var/biology = treatment_tag_biology(tag)
	if(biology & BIOLOGY_ORGANIC)
		works += "organic bodies"
	if(biology & BIOLOGY_SYNTHETIC)
		works += "synthetic bodies"
	if(biology & BIOLOGY_NANOFORM)
		works += "nanoforms"
	blocks += list(wiki_kv(list(list("Works on", capitalize(english_list(works))))))
	var/guidance = analyzer_guidance_line(tag)
	if(guidance)
		blocks += list(wiki_note("Field guidance: [guidance]", "good"))
	blocks += list(wiki_h("Provided by"))
	var/list/drugs = wiki_med_providers(tag, null, "good")
	if(length(drugs))
		blocks += list(wiki_links("Drugs", drugs))
	var/list/steps = list()
	for(var/datum/surgical_step/S as anything in context["tag_steps"][tag])
		if(wiki_title(wiki_surgery_id(S.type)))
			steps += list(wiki_link(wiki_surgery_id(S.type), S.name, null, "good"))
	if(length(steps))
		blocks += list(wiki_links("Surgical steps", steps))
	if(!length(drugs) && !length(steps))
		blocks += list(wiki_p(treatment_tag_has_tool_source(tag) ? "Tools, kits and procedures, as the field guidance above says; no drug provides it." : "Nothing on the station provides it."))
	var/list/treats = list()
	var/list/rates = context["tag_treats"][tag]
	for(var/T in rates)
		treats += list(wiki_link(wiki_cond_id(T), capitalize(_dq_condition_name(T)), dq_describe_cure_strength(rates[T]), "good"))
	if(length(treats))
		blocks += list(wiki_h("Treats"), wiki_links("Conditions", treats))
	var/list/worsens = list()
	rates = context["tag_worsens"][tag]
	for(var/T in rates)
		worsens += list(wiki_link(wiki_cond_id(T), capitalize(_dq_condition_name(T)), dq_describe_worsen_strength(rates[T]), "bad"))
	if(length(worsens))
		blocks += list(wiki_h("Makes worse"), wiki_links("Conditions", worsens))
	return blocks

// ---- organs ----

/proc/wiki_med_organ_body(tag)
	var/list/row = wiki_med_context()["organs"][tag]
	var/list/blocks = list(wiki_p("What the medical data knows about the [lowertext(wiki_organ_name(tag))]: the conditions that sit on it, what damages it and what a damaged one leads to."))
	var/list/sits = list()
	for(var/T in row["sits"])
		sits += list(wiki_link(wiki_cond_id(T), capitalize(_dq_condition_name(T))))
	if(length(sits))
		blocks += list(wiki_links("Conditions here", sits))
	var/list/damaged = list()
	for(var/T in row["damaged_by"])
		damaged += list(wiki_link(wiki_cond_id(T), capitalize(_dq_condition_name(T)), null, "bad"))
	if(length(damaged))
		blocks += list(wiki_links("Damaged by", damaged))
	var/list/strained = list()
	for(var/id in row["strained_by"])
		strained += list(wiki_link(wiki_chem_id(id), dq_reagent_display_name(id), "strains it", "average"))
	if(length(strained))
		blocks += list(wiki_links("Drugs that strain it", strained))
	var/list/triggers = list()
	for(var/datum/affliction_trigger/c as anything in row["triggers"])
		triggers += list(wiki_link(wiki_trigger_id(c.type), c.name, "when it is damaged", "average"))
	if(length(triggers))
		blocks += list(wiki_links("Damage to it", triggers))
	return blocks
