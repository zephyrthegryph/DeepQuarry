// DQ Medical Reference — Purity tab builder.
//
// What a reagent carries besides the reagent (code/domains/world_model/reagents/contaminants.dm): the four grades with their purity
// bands, every contaminant in the registry (what it is and what it does to a patient), and the recipes that ask for a minimum grade
// (`needs_grade`). All of it is read from the registry and the transformation rules, never written out here.

/obj/item/book/dq_medical_reference/proc/_dq_book_purity()
	var/list/out = list()
	var/list/grades = list()
	for(var/grade in list(GRADE_CRUDE, GRADE_STANDARD, GRADE_PHARMA, GRADE_REAGENT))
		grades += list(list(
			"id"   = grade,
			"name" = grade_name(grade),
			"band" = purity_band_text(grade),
		))
	out["grades"] = grades
	var/list/contaminants = list()
	var/list/defs = contaminant_defs()
	for(var/id in defs)
		var/datum/contaminant/C = defs[id]
		contaminants += list(list(
			"id"          = C.id,
			"name"        = C.name,
			"role"        = C.role,
			"description" = C.desc,
			"effect"      = C.effect_text,
		))
	out["contaminants"] = contaminants
	// Where graded recipes apply: every chemistry rule with a minimum grade, and what each graded ingredient needs.
	var/list/graded = list()
	for(var/datum/xform/CR as anything in GLOB.xform_rules)
		if(CR.medium != MEDIUM_REAGENTS || !ispath(CR.rule_type, /transformation/chem) || !length(CR.needs_grade))
			continue
		if(CR.wiki & WIKI_SPOILER)
			continue
		var/list/needs = list()
		for(var/reagent_id in CR.needs_grade)
			needs += list(list(
				"id"    = reagent_id,
				"name"  = dq_reagent_display_name(reagent_id),
				"grade" = grade_name(CR.needs_grade[reagent_id]),
			))
		graded += list(list(
			"id"    = CR.result,
			"name"  = dq_reagent_display_name(CR.result),
			"needs" = needs,
		))
	out["graded_recipes"] = graded
	return out
