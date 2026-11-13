// Unit tests for the chemistry half of the medical reference book (code/content/medical/book/): every drug is listed with what it treats, its
// strains, hides and adds, its recipe with the grade each graded ingredient needs, and the purity section lists the registry. The book is built
// from the reagents, the conditions and the transformation rules, so these tests read the same data back.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Every drug the book lists (the combat stimulants have their own group, tested in the first test).
/proc/dq_book_drug_ids()
	return list(
		REAGENT_ID_TRICORDRAZINE, REAGENT_ID_PERIDAXON, REAGENT_ID_INAPROVALINE, REAGENT_ID_PANACILLIN, REAGENT_ID_REZADONE,
		REAGENT_ID_BICARIDINE, REAGENT_ID_MYELAMINE, REAGENT_ID_OSTEODAXON, REAGENT_ID_KELOTANE, REAGENT_ID_DERMALINE,
		REAGENT_ID_ANTITOXIN, REAGENT_ID_CARTHATOLINE, REAGENT_ID_ARITHRAZINE, REAGENT_ID_HYRONALIN, REAGENT_ID_CORDRADAXON,
		REAGENT_ID_RESPIRODAXON, REAGENT_ID_HEPANEPHRODAXON, REAGENT_ID_GASTIRODAXON, REAGENT_ID_IMIDAZOLINE, REAGENT_ID_ALKYSINE,
		REAGENT_ID_SYNAPTIZINE, REAGENT_ID_DEXALINP, REAGENT_ID_EPINEPHRINE, REAGENT_ID_NOREPINEPHRINE, REAGENT_ID_LEPORAZINE,
		REAGENT_ID_COROPHIZINE, REAGENT_ID_SPACEACILLIN, REAGENT_ID_STERILIZINE, REAGENT_ID_PARACETAMOL, REAGENT_ID_TRAMADOL,
		REAGENT_ID_OXYCODONE, REAGENT_ID_CALCIUMCARBONATE, REAGENT_ID_ADRANOL, REAGENT_ID_ETHYLREDOXRAZINE, REAGENT_ID_IRONSALINE,
		REAGENT_ID_TERCOZOLAM, REAGENT_ID_ANTICONVULSANT,
	)

/// The reagents tab entry of a reagent id, or null.
/datum/unit_test/proc/_book_reagent_entry(list/reagents, reagent_id)
	for(var/list/entry in reagents)
		if(entry["id"] == reagent_id)
			return entry
	return null


/// Every drug has an entry with a non-empty "what it treats" line, and the combat stimulants sit in their own group.
/datum/unit_test/dq_book_lists_every_drug

/datum/unit_test/dq_book_lists_every_drug/Run()
	var/obj/item/book/dq_medical_reference/book = allocate(/obj/item/book/dq_medical_reference)
	var/list/reagents = book._dq_book_reagents()
	for(var/reagent_id in dq_book_drug_ids())
		var/list/entry = _book_reagent_entry(reagents, reagent_id)
		TEST_ASSERT_NOTNULL(entry, "the book has no entry for [reagent_id]")
		TEST_ASSERT(length(entry["treats_text"]), "[reagent_id] has no 'treats' text")
	for(var/reagent_id in list(REAGENT_ID_HYPERZINE, REAGENT_ID_CLARIDYL, REAGENT_ID_BLOODSEALER, REAGENT_ID_PERFORMANCEPEAKER))
		var/list/entry = _book_reagent_entry(reagents, reagent_id)
		TEST_ASSERT_NOTNULL(entry, "the book has no entry for the combat stimulant [reagent_id]")
		TEST_ASSERT_EQUAL(entry["category"], "Combat stimulants", "[reagent_id] is listed under the combat stimulants")


/// A drug that declares strains shows a strains line per organ, one that declares hides a hides line per reading, from the reagent itself.
/datum/unit_test/dq_book_shows_strains_and_hides

/datum/unit_test/dq_book_shows_strains_and_hides/Run()
	var/obj/item/book/dq_medical_reference/book = allocate(/obj/item/book/dq_medical_reference)
	var/list/reagents = book._dq_book_reagents()
	var/strained = 0
	var/hiding = 0
	for(var/list/entry in reagents)
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[entry["id"]]
		if(!R)
			continue
		TEST_ASSERT_EQUAL(length(entry["strains"]), length(R.strains), "[R.id]: one strains line per strained organ")
		TEST_ASSERT_EQUAL(length(entry["hides"]), length(R.hides), "[R.id]: one hides line per masked reading")
		if(length(R.strains))
			strained++
			for(var/list/row in entry["strains"])
				TEST_ASSERT(length(row["text"]) && length(row["band"]), "[R.id]: a strain line has its organ and band")
		if(length(R.hides))
			hiding++
			for(var/label in entry["hides"])
				TEST_ASSERT(length(label), "[R.id]: a hides line is not empty")
	TEST_ASSERT(strained, "at least one drug declares strains")
	TEST_ASSERT(hiding, "at least one drug declares hides")
	// The strain bands follow the DRUG_STRAIN_* defines.
	TEST_ASSERT_EQUAL(dq_describe_strain(DRUG_STRAIN_MILD), "mild", "mild strain band")
	TEST_ASSERT_EQUAL(dq_describe_strain(DRUG_STRAIN_MODERATE), "moderate", "moderate strain band")
	TEST_ASSERT_EQUAL(dq_describe_strain(DRUG_STRAIN_HEAVY), "heavy", "heavy strain band")
	// Every HIDE_* key has a label of its own.
	for(var/key in list(HIDE_PAIN, HIDE_PAIN_LOCATION, HIDE_ORGAN_MILD, HIDE_PULSE_IRREGULAR, HIDE_INTERNAL_BLEEDING, HIDE_LUNG_HEART, HIDE_FEVER, HIDE_SYMPTOM_SUPPRESSION))
		TEST_ASSERT(GLOB.dq_hide_labels[key], "no book label for the reading [key]")


/// Nausea, seizure and the crooked fracture are conditions of the book, with what treats them; the drug that adds nausea lists it as an add.
/datum/unit_test/dq_book_conditions_nausea_seizure_malunion

/datum/unit_test/dq_book_conditions_nausea_seizure_malunion/Run()
	var/obj/item/book/dq_medical_reference/book = allocate(/obj/item/book/dq_medical_reference)
	var/list/by_id = list()
	for(var/list/entry in book._dq_book_conditions())
		by_id[entry["id"]] = entry
	for(var/condition_type in list(/datum/affliction/nausea, /datum/affliction/seizure, /datum/affliction/malunion))
		var/list/condition = by_id["[condition_type]"]
		TEST_ASSERT_NOTNULL(condition, "the conditions tab lacks [condition_type]")
		TEST_ASSERT(length(condition["mechanisms"]), "[condition_type] shows what treats it")
	var/list/seizure = by_id["[/datum/affliction/seizure]"]
	TEST_ASSERT(length(seizure["raised_by"]), "the seizure condition lists what moves proneness")
	var/list/malunion = by_id["[/datum/affliction/malunion]"]
	TEST_ASSERT(length(malunion["surgeries"]), "the crooked fracture lists the surgery that corrects it")
	// The drug that adds nausea lists it, with its kind.
	var/list/panacillin = _book_reagent_entry(book._dq_book_reagents(), REAGENT_ID_PANACILLIN)
	var/found = FALSE
	for(var/list/side in panacillin["side_effects"])
		if(side["id"] == "[/datum/affliction/nausea/panacillin]")
			found = TRUE
			TEST_ASSERT_EQUAL(side["kind"], "nausea", "panacillin nausea is flagged as nausea")
	TEST_ASSERT(found, "panacillin lists its nausea among what it adds")


/// The purity section lists every contaminant of the registry and the four grades with their bands.
/datum/unit_test/dq_book_purity_section

/datum/unit_test/dq_book_purity_section/Run()
	var/obj/item/book/dq_medical_reference/book = allocate(/obj/item/book/dq_medical_reference)
	var/list/purity = book._dq_book_purity()
	var/list/grades = purity["grades"]
	TEST_ASSERT_EQUAL(length(grades), 4, "four grades")
	for(var/list/grade in grades)
		TEST_ASSERT_EQUAL(grade["band"], purity_band_text(grade["id"]), "the band of [grade["name"]] is the registry's")
		TEST_ASSERT_EQUAL(grade["name"], grade_name(grade["id"]), "the name of grade [grade["id"]]")
	var/list/listed = list()
	for(var/list/row in purity["contaminants"])
		listed += row["id"]
		TEST_ASSERT(length(row["name"]) && length(row["effect"]), "[row["id"]] has a name and an effect")
	var/list/defs = contaminant_defs()
	TEST_ASSERT_EQUAL(length(listed), length(defs), "every contaminant of the registry is listed")
	for(var/id in defs)
		TEST_ASSERT(id in listed, "contaminant [id] is not in the purity section")
	TEST_ASSERT(length(purity["graded_recipes"]), "the purity section lists the recipes that ask for a grade")


/// A recipe that needs a grade shows the grade's name on the ingredient.
/datum/unit_test/dq_book_recipe_shows_grade

/datum/unit_test/dq_book_recipe_shows_grade/Run()
	var/obj/item/book/dq_medical_reference/book = allocate(/obj/item/book/dq_medical_reference)
	var/list/reagents = book._dq_book_reagents()
	var/checked = 0
	for(var/datum/xform/CR as anything in GLOB.xform_rules)
		if(CR.medium != MEDIUM_REAGENTS || !ispath(CR.rule_type, /transformation/chem) || !length(CR.needs_grade) || !CR.result)
			continue
		if(CR.wiki & WIKI_SPOILER)
			continue
		var/list/entry = _book_reagent_entry(reagents, CR.result)
		if(!entry)
			continue
		for(var/list/recipe in entry["recipe"])
			// Two recipes can make one drug: only the entry with this rule's own ingredients speaks for it.
			var/same_rule = length(recipe["required"]) == length(CR.reagent_takes)
			for(var/list/ingredient in recipe["required"])
				if(!(ingredient["id"] in CR.reagent_takes))
					same_rule = FALSE
			if(!same_rule)
				continue
			for(var/list/ingredient in recipe["required"])
				var/min_grade = CR.needs_grade[ingredient["id"]]
				if(!min_grade)
					continue
				TEST_ASSERT_EQUAL(ingredient["grade"], grade_name(min_grade), "[CR.result]: [ingredient["id"]] shows the grade it needs")
				checked++
	TEST_ASSERT(checked, "at least one graded recipe was read back")

#endif
