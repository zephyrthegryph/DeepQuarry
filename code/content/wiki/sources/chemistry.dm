// The wiki's chemistry source: one article per reagent (chem/<id>), and the purity guide (chem/purity). A drug the medical data knows is filed
// under Medical/Drugs/<its clinical category> with its medical uses on the first tab and its chemistry on the second; every other reagent under
// Chemistry/Reagents/<its family>, read from its type and its wiki flags. The catch-all family is "Other", which the window sorts last.
// A reagent flagged WIKI_SPOILER has no article, and a link to one is plain text.

/proc/wiki_chem_id(reagent_id)
	return "chem/[reagent_id]"

/// The family a non-medical reagent is filed under.
/proc/wiki_reagent_family(datum/reagent/R)
	if(istype(R, /datum/reagent/contaminant))
		return "Contaminants"
	if(istype(R, /datum/reagent/ethanol))
		return "Alcoholic drinks"
	if(istype(R, /datum/reagent/drink) || (R.wiki_flag & WIKI_DRINK))
		return "Drinks"
	if(istype(R, /datum/reagent/nutriment) || (R.wiki_flag & WIKI_FOOD))
		return "Food"
	if(istype(R, /datum/reagent/toxin))
		return "Toxins"
	if(istype(R, /datum/reagent/drugs))
		return "Recreational drugs"
	if(istype(R, /datum/reagent/acid))
		return "Acids"
	if(istype(R, /datum/reagent/blood))
		return "Blood"
	if(istype(R, /datum/reagent/chem_block) || chem_structure_of(R.id))
		return "Chemical feedstock and intermediates"
	return "Other"

/// The medical book's reagent entries by id, built once.
GLOBAL_TABLE(wiki_med_reagents_table, GLOBAL_PROC_REF(build_wiki_med_reagents))

/proc/build_wiki_med_reagents()
	var/list/by_id = list()
	for(var/list/entry in dq_medical_book_data()["reagents"])
		by_id[entry["id"]] = entry
	return by_id

/// What every reagent goes into, built once (reagent id -> list of { id, name }).
GLOBAL_TABLE(wiki_used_in_table, GLOBAL_PROC_REF(build_wiki_used_in))

/proc/build_wiki_used_in()
	return _dq_build_used_in_index()

/// An inline link to a reagent, or its plain name when it has no article.
/proc/wiki_chem_ref(reagent_id)
	var/name = dq_reagent_display_name(reagent_id)
	return wiki_title(wiki_chem_id(reagent_id)) ? wiki_ref(wiki_chem_id(reagent_id), name) : name

/// A link to a reagent for a links block (no id when it has no article: shown as plain text).
/proc/wiki_chem_link(reagent_id, note, tone)
	return wiki_link(wiki_title(wiki_chem_id(reagent_id)) ? wiki_chem_id(reagent_id) : null, dq_reagent_display_name(reagent_id), note, tone)

/proc/wiki_source_chemistry(list/index)
	wiki_add(index, WIKI_ID_PURITY, "Purity and contaminants", "Chemistry", "Grades, contaminants, and every way to make a mixture cleaner.", null, GLOBAL_PROC_REF(wiki_purity_body), null)
	var/list/medical = GLOBAL_TABLE_GET(wiki_med_reagents_table)
	var/list/registry = SSchemistry.ready().chemical_reagents
	for(var/id in registry)
		var/datum/reagent/R = registry[id]
		if(!R?.name || (R.wiki_flag & WIKI_SPOILER))
			continue
		var/list/entry = medical[id]
		var/path
		if(entry && (dq_reagent_category_table()[id] || length(R.treatment_tags) || length(entry["cures"])))
			path = "Medical/Drugs/[dq_reagent_category_table()[id] || "Other"]"
		else
			path = "Chemistry/Reagents/[wiki_reagent_family(R)]"
		wiki_set_swatch(wiki_add(index, wiki_chem_id(id), R.name, path, null, null, GLOBAL_PROC_REF(wiki_reagent_body), id), R.color)

/proc/wiki_reagent_body(reagent_id)
	var/datum/reagent/R = SSchemistry.ready().chemical_reagents[reagent_id]
	var/list/entry = GLOBAL_TABLE_GET(wiki_med_reagents_table)[reagent_id]
	var/list/intro = list(wiki_p(R.description || "No description is recorded for this chemical."))
	if(istype(R, /datum/reagent/contaminant))
		var/datum/reagent/contaminant/C = R
		intro += list(wiki_kv(list(
			list("Contaminant role", capitalize("[C.contaminant_role]")),
			list("In a patient", C.effect_text || "Nothing."),
			list("Filter floor", "No filter takes it below [round(C.filter_floor * 100, 0.1)]% of the mixture."),
		)))
		intro += list(wiki_note("A contaminant: chemistry windows list it grey and after the real reagents. See [wiki_ref(WIKI_ID_PURITY, "purity")].", "grey"))
	var/list/chemistry = wiki_reagent_chemistry_blocks(reagent_id, entry)
	if(!entry)
		return intro + chemistry
	var/list/medicine = wiki_reagent_medical_blocks(reagent_id, entry, R)
	var/list/tabs = list()
	if(length(medicine))
		tabs += list(wiki_tab("Medical use", medicine))
	if(length(chemistry))
		tabs += list(wiki_tab("Chemistry", chemistry))
	if(!length(tabs))
		return intro
	return intro + list(wiki_tabs(tabs))

/// What a drug does in a patient: mechanisms, what it treats (by mechanism), what it worsens, effects, strains, masks, drawbacks, side effects,
/// interactions and overdose.
/proc/wiki_reagent_medical_blocks(reagent_id, list/r, datum/reagent/R)
	var/list/blocks = list()
	var/list/context = wiki_med_context()
	var/list/facts = list(list("Category", r["category"]))
	if(r["overdose"]?["threshold"])
		facts += list(list("Overdose", "above [r["overdose"]["threshold"]]u"))
	blocks += list(wiki_kv(facts))
	if(R?.treatment_tags)
		var/list/tags = R.treatment_tags.Copy()
		sortTim(tags, GLOBAL_PROC_REF(cmp_numeric_dsc), TRUE)
		var/list/mechs = list()
		for(var/tag in tags)
			mechs += list(wiki_link(wiki_mech_id(tag), dq_treatment_tag_name(tag), dq_describe_cure_strength(tags[tag]), "good"))
		blocks += list(wiki_h("Mechanisms"), wiki_links("Provides", mechs))
		blocks += list(wiki_h("Treats"))
		for(var/tag in tags)
			var/list/items = list()
			var/list/rates = context["tag_treats"][tag]
			for(var/T in rates)
				items += list(wiki_link(wiki_cond_id(T), capitalize(_dq_condition_name(T)), dq_describe_cure_strength(rates[T] * tags[tag]), "good"))
			if(length(items))
				blocks += list(wiki_links("Through [wiki_mech_ref(tag)]", items))
	var/list/direct = list()
	var/list/direct_rates = context["direct_cures"][reagent_id]
	for(var/T in direct_rates)
		direct += list(wiki_link(wiki_cond_id(T), capitalize(_dq_condition_name(T)), dq_describe_cure_strength(direct_rates[T]), "good"))
	if(length(direct))
		blocks += list(wiki_links("Specifically", direct))
	var/list/worse = list()
	for(var/list/x in r["worsens"])
		worse += list(wiki_link(wiki_cond_id(x["id"]), capitalize(x["name"]), x["band"], "bad"))
	if(length(worse))
		blocks += list(wiki_h("Makes worse"), wiki_links("Conditions", worse))
	if(length(r["effects"]))
		blocks += list(wiki_h("Effects"), wiki_ul(r["effects"]))
	var/list/cautions = list()
	for(var/list/strain in r["strains"])
		cautions += "[capitalize(strain["band"])] strain on the [wiki_title(wiki_organ_id(strain["organ"])) ? wiki_ref(wiki_organ_id(strain["organ"]), lowertext(wiki_organ_name(strain["organ"]))) : strain["organ"]]."
	for(var/hide in r["hides"])
		cautions += "Masks [hide] on instruments while in the blood."
	cautions += r["drawbacks"]
	if(r["seizure_proneness"])
		cautions += "[r["seizure_proneness"] > 0 ? "Raises" : "Lowers"] [wiki_ref(wiki_cond_id(/datum/affliction/seizure), "seizure")] proneness by [abs(r["seizure_proneness"])]."
	if(length(cautions))
		blocks += list(wiki_h("Cautions"), wiki_ul(cautions))
	var/list/side = list()
	for(var/list/s in r["side_effects"])
		side += list(wiki_link(wiki_cond_id(s["id"]), capitalize(s["name"]), "above [s["threshold"]]u", "average"))
	if(length(side))
		blocks += list(wiki_h("Side effects"), wiki_links("Brings on", side))
	if(length(r["interactions"]))
		blocks += list(wiki_h("Interactions"))
		for(var/list/x in r["interactions"])
			var/list/others = list()
			for(var/list/o in x["other_chems"])
				others += wiki_chem_ref(o["id"])
			blocks += list(wiki_p("With [english_list(others)]: [wiki_ref(wiki_cond_id(x["id"]), capitalize(x["name"]))].[x["conflict"] ? " The two work against each other." : ""]"))
			var/list/lines = list()
			for(var/list/shift in x["shifts"])
				lines += replacetext(capitalize(shift["text"]), shift["name"], wiki_chem_ref(shift["id"]))
			lines += x["effects"]
			if(length(lines))
				blocks += list(wiki_ul(lines))
	var/list/od = r["overdose"]
	if(od)
		blocks += list(wiki_h("Overdose"))
		if(od["condition_id"])
			blocks += list(wiki_p("Above [od["threshold"]]u it brings on [wiki_ref(wiki_cond_id(od["condition_id"]), od["condition_name"])][od["lingers"] ? ", which lingers after the drug is gone" : ""]."))
		else
			blocks += list(wiki_p("Above [od["threshold"]]u it does the patient harm."))
		var/list/drains = list()
		for(var/list/d in od["drains"])
			drains += list(wiki_link(wiki_cond_id(d["id"]), capitalize(d["name"]), "at peak overdose", "good"))
		if(length(drains))
			blocks += list(wiki_links("Its overdose clears", drains))
		if(length(od["effects"]))
			blocks += list(wiki_ul(od["effects"]))
	return blocks

/// A reagent's chemistry: its structure, the recipes that make it, the processes that act on it and what it goes into.
/proc/wiki_reagent_chemistry_blocks(reagent_id, list/entry)
	var/list/blocks = list()
	var/list/structure = entry ? entry["blocks"] : _dq_reagent_blocks(reagent_id)
	if(structure)
		var/list/parts = list()
		for(var/core in structure["cores"])
			parts += "[replacetext(core, "_", " ")] core"
		for(var/group in structure["groups"])
			parts += "[replacetext(group, "_", " ")] group"
		for(var/link in structure["links"])
			parts += "[link] link"
		if(structure["cation"])
			parts += "[structure["cation"]] / [structure["anion"]] ions"
		var/tier = chem_tier_of(reagent_id)
		blocks += list(wiki_kv(list(
			list("Formula", "[structure["formula"]] ([structure["class"]])[tier ? ", tier [tier]" : ""]"),
			list("Built of", english_list(parts)),
			list("Tags", english_list(structure["tags"])),
		)))
	var/list/recipes = entry ? entry["recipe"] : _dq_reagent_recipe(reagent_id)
	if(length(recipes))
		var/list/lines = list()
		for(var/list/rcp in recipes)
			var/list/takes = list()
			for(var/list/ing in rcp["required"])
				takes += "[ing["amount"]]u [wiki_chem_ref(ing["id"])]"
			var/list/notes = list()
			if(rcp["process"])
				notes += "[rcp["process"]][rcp["catalyst_kind"] && rcp["catalyst_kind"] != "none" ? " on [replacetext(rcp["catalyst_kind"], "_", " ")]" : ""]"
			if(!isnull(rcp["ideal_low"]))
				notes += "clean at [rcp["ideal_low"]] to [rcp["ideal_high"]] C"
			if(rcp["route_kind"])
				notes += rcp["route_kind"]
			if(rcp["distilling"])
				notes += "distilled"
			var/list/catalysts = list()
			for(var/list/cat in rcp["catalysts"])
				catalysts += wiki_chem_ref(cat["id"])
			if(length(catalysts))
				notes += "catalyst [english_list(catalysts)]"
			var/list/inhibitors = list()
			for(var/list/inh in rcp["inhibitors"])
				inhibitors += wiki_chem_ref(inh["id"])
			if(length(inhibitors))
				notes += "stopped by [english_list(inhibitors)]"
			lines += "[jointext(takes, " + ")] makes [rcp["result_amount"]]u[length(notes) ? " ([jointext(notes, "; ")])" : ""]."
		blocks += list(wiki_h("How it is made"), wiki_ul(lines))
	var/list/routes = entry ? entry["acted_on"] : _dq_reagent_routes_from(reagent_id)
	if(length(routes))
		var/list/lines = list()
		for(var/list/a in routes)
			lines += "[a["process"]][length(a["with"]) ? " with [english_list(a["with"])]" : ""][a["kind"] && a["kind"] != "none" ? " on [replacetext(a["kind"], "_", " ")]" : ""] gives [english_list(a["gives"])][a["product"] ? "" : " (residue only)"][isnull(a["low"]) ? "" : ", clean at [a["low"]] to [a["high"]] C"]."
		blocks += list(wiki_h("Processes that act on it"), wiki_ul(lines))
	var/list/used = list()
	var/list/seen = list()
	for(var/list/u in GLOBAL_TABLE_GET(wiki_used_in_table)[reagent_id])
		if(seen[u["id"]])
			continue
		seen[u["id"]] = TRUE
		used += list(wiki_chem_link(u["id"]))
	if(length(used))
		blocks += list(wiki_h("Used to make"), wiki_links("Products", used))
	return blocks

// ---- purity ----

/// The purity guide, as tabs: how purity works now, the grades, every contaminant, temperatures, boiling points, the ways to purify, processes.
/proc/wiki_purity_body()
	var/list/purity = dq_medical_book_data()["purity"]
	var/list/tabs = list()
	tabs += list(wiki_tab("How it works", wiki_markup_blocks({"Purity belongs to the whole mixture: one minus the volume of contaminants over the total volume of what is in the container. It is computed, never stored, and nothing is attached to any one reagent.
- A contaminant is a reagent of its own, with a volume. 2u of heavy metals is 2u in the beaker. It is poured, mixed, splashed, drunk and metabolised like anything else, and does its own harm in a patient.
- Every transfer moves the mixture as it is: pouring, a syringe, the chem master and a dispense all take the same share of every reagent, contaminants included. Diluting lowers the contaminant share; nothing removes it for free.
- No machine picks one chemical out of a mixture. The chemical dispenser has no per-reagent remove or isolate, and the chem master moves or discards the whole mixture.
- Chemistry windows (the dispenser, the chem master, scanners) list contaminants in grey, after the real reagents, each with its own volume, and say the mixture's grade.
- Dispenser stock comes with its own contaminants, rolled for each cartridge each round. Recharging keeps the same profile, so a recharge never raises purity.
- The grade is a readout. No recipe asks for a grade: purity is the natural fallout of how a batch was made.
## Making it cleaner
Make it clean in the first place (the right temperature and catalyst), then take out what you can: boil and condense, filter, neutralise. See the other tabs."})))
	var/list/grade_rows = list()
	for(var/list/g in purity["grades"])
		grade_rows += list(list(g["name"], g["band"]))
	tabs += list(wiki_tab("Grades", list(wiki_table(list("Grade", "Purity"), grade_rows))))
	var/list/contaminant_rows = list()
	for(var/list/c in purity["contaminants"])
		contaminant_rows += list(list(wiki_chem_ref(c["id"]), capitalize("[c["role"]]"), c["effect"] || c["description"], "[round(c["floor"] * 100, 0.1)]%"))
	tabs += list(wiki_tab("Contaminants", list(wiki_p("Every contaminant, what it does to a patient, and the share of the mixture below which no filter takes it."), wiki_table(list("Contaminant", "Role", "Effect", "Filter floor"), contaminant_rows))))
	var/list/class_rows = list()
	for(var/list/t in purity["temperature_classes"])
		class_rows += list(list(capitalize("[t["id"]]"), "[t["ideal_low"]] to [t["ideal_high"]] C", "[t["range_low"]] to [t["range_high"]] C"))
	var/list/recipe_rows = list()
	for(var/list/t in purity["recipe_temperatures"])
		recipe_rows += list(list(wiki_chem_ref(t["id"]), capitalize("[t["class"]]"), "[t["ideal_low"]] to [t["ideal_high"]] C", "[t["range_low"]] to [t["range_high"]] C"))
	tabs += list(wiki_tab("Temperature", list(
		wiki_p("Inside a recipe's ideal band the product is clean. Off the band but inside its range it still reacts but leaves organic residue (too cold) or a reactive impurity and a loss of product (too hot), more the further off. Outside the range nothing reacts."),
		wiki_h("Classes"), wiki_table(list("Class", "Ideal", "Range"), class_rows),
		wiki_h("Recipes that need more than room temperature"), wiki_table(list("Product", "Class", "Ideal", "Range"), recipe_rows),
	)))
	var/list/boil_rows = list()
	for(var/list/b in purity["boiling_points"])
		boil_rows += list(list(wiki_chem_ref(b["id"]), b["never"] ? "never boils" : "[b["celsius"]] C"))
	tabs += list(wiki_tab("Boiling points", list(wiki_p("Above its boiling point a reagent leaves the container gradually as vapour. A condenser collects it; what never boils stays behind."), wiki_table(list("Reagent", "Boils at"), boil_rows))))
	var/list/method_blocks = list()
	for(var/list/m in purity["methods"])
		method_blocks += list(wiki_h(capitalize(m["name"])), wiki_p(m["text"]))
	tabs += list(wiki_tab("Ways to purify", method_blocks))
	var/list/process_rows = list()
	for(var/list/p in purity["processes"])
		process_rows += list(list(p["name"], p["text"]))
	tabs += list(wiki_tab("Processes", list(wiki_table(list("Process", "What it does"), process_rows))))
	return list(wiki_p("How clean a mixture is, what the impurities are and how to take them out."), wiki_tabs(tabs))
