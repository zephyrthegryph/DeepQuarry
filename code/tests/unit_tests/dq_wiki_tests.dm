// The station wiki (code/content/wiki/): every article has a title, a place and a body; no id is used twice; every link resolves; the medical
// pages cover every catalogued condition and every treatment mechanism; every catalogued medical entry carries a description of its own.

/// No two sources add the same id.
/datum/unit_test/dq_wiki_no_duplicate_ids

/datum/unit_test/dq_wiki_no_duplicate_ids/Run()
	wiki_index()
	TEST_ASSERT(!length(GLOB.wiki_duplicate_ids), "article ids added twice: [english_list(GLOB.wiki_duplicate_ids)]")

/// Every article has a title, a section and a body with something in it.
/datum/unit_test/dq_wiki_every_article_has_body

/datum/unit_test/dq_wiki_every_article_has_body/Run()
	var/list/empty = list()
	for(var/id in wiki_index())
		var/list/article = wiki_article(id)
		if(!article["title"] || !article["path"] || !wiki_body_has_content(article["blocks"]))
			empty += id
	TEST_ASSERT(!length(empty), "[length(empty)] article(s) with no title, section or body: [english_list(empty.Copy(1, min(length(empty), 30) + 1))]")

/// Every link in every article (links blocks and inline [[id]] links, tabs included) names an article that exists.
/datum/unit_test/dq_wiki_links_resolve

/datum/unit_test/dq_wiki_links_resolve/Run()
	var/list/index = wiki_index()
	var/list/broken = list()
	for(var/id in index)
		for(var/target in wiki_link_ids(wiki_article(id)["blocks"]))
			if(isnull(target))
				continue
			if(!index[target])
				broken |= "[id] -> [target]"
	TEST_ASSERT(!length(broken), "[length(broken)] broken link(s): [english_list(broken.Copy(1, min(length(broken), 30) + 1))]")

/// The generated medical pages cover every catalogued condition, every symptom, every trigger, every finding step and every treatment
/// mechanism a condition or a drug names, and each mechanism is explained.
/datum/unit_test/dq_wiki_medical_coverage

/datum/unit_test/dq_wiki_medical_coverage/Run()
	var/list/index = wiki_index()
	for(var/T in GLOBAL_TABLE_GET(dq_catalogued_affliction_types))
		TEST_ASSERT(index[wiki_cond_id(T)], "no wiki article for the condition [T]")
		var/datum/affliction/proto = dq_proto(T)
		for(var/tag in proto.treated_by)
			TEST_ASSERT(GLOB.dq_treatment_tag_names[tag], "[T] is treated by [tag], which has no name")
		for(var/tag in proto.worsened_by_tags)
			TEST_ASSERT(GLOB.dq_treatment_tag_names[tag], "[T] is worsened by [tag], which has no name")
	var/list/table = GLOBAL_TABLE_GET(dq_reagent_tag_table)
	for(var/id in table)
		for(var/tag in table[id])
			TEST_ASSERT(GLOB.dq_treatment_tag_names[tag], "[id] provides [tag], which has no name")
	for(var/tag in GLOB.dq_treatment_tag_names)
		TEST_ASSERT(index[wiki_mech_id(tag)], "no wiki article for the mechanism [tag]")
		TEST_ASSERT(wiki_treatment_about(tag), "the mechanism [tag] has no explanation in GLOB.wiki_treatment_about")
	for(var/T in subtypesof(/datum/affliction_symptom))
		var/datum/affliction_symptom/symptom = T
		if(initial(symptom.abstract_type) == T)
			continue
		TEST_ASSERT(index[wiki_sym_id(T)], "no wiki article for the symptom [T]")
	for(var/datum/affliction_trigger/c as anything in affliction_triggers_registry())
		TEST_ASSERT(index[wiki_trigger_id(c.type)], "no wiki article for the trigger [c.type]")
	for(var/datum/surgical_step/S as anything in surgical_steps())
		if(S.finds)
			TEST_ASSERT(index[wiki_surgery_id(S.type)], "no wiki article for the finding step [S.type]")
	TEST_ASSERT(index[WIKI_ID_MEDICAL_INDEX] && index[WIKI_ID_PURITY] && index[WIKI_ID_HOME], "the front, medical and purity pages exist")

/// Every catalogued medical entry has a description of its own: conditions, symptoms, triggers and the drugs the book files by category.
/datum/unit_test/dq_wiki_medical_entries_described

/datum/unit_test/dq_wiki_medical_entries_described/Run()
	var/list/data = dq_medical_book_data()
	var/list/missing = list()
	for(var/list/entry in data["conditions"])
		if(!entry["description"])
			missing += "condition [entry["id"]]"
	for(var/list/entry in data["symptoms"])
		if(!entry["clinical_description"])
			missing += "symptom [entry["id"]]"
	for(var/list/entry in data["causes"])
		if(!entry["description"])
			missing += "trigger [entry["id"]]"
	for(var/list/entry in data["surgeries"])
		if(!entry["description"])
			missing += "surgical step [entry["id"]]"
	for(var/id in dq_reagent_category_table())
		if(!dq_reagent_description(id))
			missing += "drug [id]"
	TEST_ASSERT(!length(missing), "[length(missing)] medical entr(ies) with no description: [english_list(missing.Copy(1, min(length(missing), 40) + 1))]")

/// A condition's causes gather every route: a trigger, another condition's complication and a chemical each show on the page they cause.
/datum/unit_test/dq_wiki_causes_aggregate

/datum/unit_test/dq_wiki_causes_aggregate/Run()
	var/list/causes = wiki_med_context()["causes"]
	var/list/concussion_causes = list()
	for(var/list/link in causes[wiki_cond_id(/datum/affliction/subdural_hematoma)])
		concussion_causes += link["id"]
	TEST_ASSERT(wiki_trigger_id(/datum/affliction_trigger/injury/blunt_head) in concussion_causes, "a subdural hematoma lists the head blow that causes it")
	var/multi = 0
	for(var/cond_id in causes)
		if(length(causes[cond_id]) > 1)
			multi++
	TEST_ASSERT(multi >= 10, "at least ten conditions list more than one cause (found [multi])")

/// Markup: headings, bullets, numbered steps, notes and paragraphs; inline links are found.
/datum/unit_test/dq_wiki_markup

/datum/unit_test/dq_wiki_markup/Run()
	var/list/blocks = wiki_markup_blocks("One line\nstill one.\n\n## Head\n- a\n- b\n1. first\n2. second\n> careful")
	TEST_ASSERT_EQUAL(length(blocks), 5, "paragraph, heading, bullets, steps and note")
	TEST_ASSERT_EQUAL(blocks[1]["t"], "One line still one.", "lines of a paragraph join")
	TEST_ASSERT_EQUAL(blocks[3]["k"], "ul", "bullets")
	TEST_ASSERT_EQUAL(blocks[4]["items"][2], "second", "numbered steps lose their numbers")
	var/list/ids = wiki_text_link_ids("See [wiki_ref("a/b", "label")] and [wiki_ref("c")].")
	TEST_ASSERT_EQUAL(jointext(ids, ","), "a/b,c", "inline links are found with and without a label")

/// The window sends the index once and the article the reader is on.
/datum/unit_test/dq_wiki_window_sends_one_article

/datum/unit_test/dq_wiki_window_sends_one_article/Run()
	var/datum/station_wiki/wiki = allocate(/datum/station_wiki)
	var/list/static_data = wiki.ui_static_data(null)
	TEST_ASSERT(length(static_data["index"]) > 100, "the index lists the articles")
	TEST_ASSERT(wiki_article(WIKI_ID_MEDICAL_INDEX), "the medical index is an article")

/// Every catalogued item and machine has a description of its own (its design's or its type's), and is filed in a department or the
/// uncategorised bucket.
/datum/unit_test/dq_wiki_catalogue_described

/datum/unit_test/dq_wiki_catalogue_described/Run()
	var/list/index = wiki_index()
	var/list/missing = list()
	var/count = 0
	for(var/id in index)
		if(findtext(id, "cat/") != 1)
			continue
		count++
		var/list/article = index[id]
		if(!wiki_catalogue_description(article["body_key"]))
			missing += "[article["body_key"]]"
		var/list/parts = splittext(article["path"], "/")
		TEST_ASSERT(parts[1] == "Uncategorised" || (length(parts) >= 3 && parts[2] == "Catalogue"), "[id] is filed at [article["path"]]")
	TEST_ASSERT(count > 100, "the catalogue lists the station's things ([count])")
	TEST_ASSERT(!length(missing), "[length(missing)] catalogued thing(s) with no description: [english_list(missing.Copy(1, min(length(missing), 40) + 1))]")

/// The departments, their jobs, the manuals and the lore are in the wiki.
/datum/unit_test/dq_wiki_station_content

/datum/unit_test/dq_wiki_station_content/Run()
	var/list/index = wiki_index()
	for(var/id in list(wiki_dept_id(DEPARTMENT_ENGINEERING), wiki_dept_id(DEPARTMENT_MEDICAL), wiki_dept_id(DEPARTMENT_RESEARCH), wiki_dept_id(DEPARTMENT_CARGO), wiki_dept_id(DEPARTMENT_SECURITY)))
		TEST_ASSERT(index[id], "no department page [id]")
	var/jobs = 0
	var/lore = 0
	var/manuals = 0
	for(var/id in index)
		if(findtext(id, "job/") == 1)
			jobs++
		else if(findtext(id, "lore/") == 1)
			lore++
		else if(findtext(id, "manual/") == 1)
			manuals++
	TEST_ASSERT(jobs >= 10, "the jobs have pages ([jobs])")
	TEST_ASSERT(lore >= 10, "the lore has pages ([lore])")
	TEST_ASSERT(manuals >= 5, "the manuals have pages ([manuals])")

/// Every department with work to explain has at least one guide, and the guides are filed under their department.
/datum/unit_test/dq_wiki_guides

/datum/unit_test/dq_wiki_guides/Run()
	var/list/index = wiki_index()
	for(var/id in list("guide/chemistry/lab", "guide/medical/triage", "guide/medical/surgery", "guide/engineering/power", "guide/engineering/atmos", "guide/research/basics", "guide/cargo/ordering", "guide/cargo/trade_ships", "guide/cargo/haggling", "guide/cargo/black_market"))
		TEST_ASSERT(index[id], "no guide [id]")
		TEST_ASSERT(findtext(index[id]["path"], "/Guides"), "[id] is filed at [index[id]["path"]], not under a department's guides")
