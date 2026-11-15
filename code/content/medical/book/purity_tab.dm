// DQ Medical Reference — Purity tab builder.
//
// What a mixture carries besides its reagents (code/domains/world_model/reagents/contaminants.dm): the four grades with their purity
// bands, every contaminant reagent (what it is and what it does to a patient), and the recipes that ask for a minimum grade of the
// mixture (`needs_grade`). All of it is read from the reagent types and the transformation rules, never written out here.

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
	for(var/id in contaminant_ids())
		var/datum/reagent/contaminant/C = contaminant_def(id)
		contaminants += list(list(
			"id"          = C.id,
			"name"        = C.name,
			"role"        = C.contaminant_role,
			"description" = C.description,
			"effect"      = C.effect_text,
		))
	out["contaminants"] = contaminants
	// Where graded recipes apply: every chemistry rule with a minimum grade of the mixture.
	var/list/graded = list()
	for(var/datum/xform/CR as anything in GLOB.xform_rules)
		if(CR.medium != MEDIUM_REAGENTS || !ispath(CR.rule_type, /transformation/chem) || !CR.needs_grade)
			continue
		if(CR.wiki & WIKI_SPOILER)
			continue
		graded += list(list(
			"id"    = CR.result,
			"name"  = dq_reagent_display_name(CR.result),
			"grade" = grade_name(CR.needs_grade),
			"band"  = purity_band_text(CR.needs_grade),
		))
	out["graded_recipes"] = graded
	return out
