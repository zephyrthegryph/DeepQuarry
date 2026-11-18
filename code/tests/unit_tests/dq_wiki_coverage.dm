// Wiki coverage: every player-facing thing the game defines has an article, and every catalogued thing describes itself. The report lists each
// category's count and what is missing (data/wiki_coverage.txt and the test log). Each category's missing count is a ratchet: it may only go
// down. When a count falls, lower its number here in the same commit; never raise one (document the thing instead).

/// Category -> the most uncovered or undescribed entries allowed. Lower only.
GLOBAL_LIST_INIT(wiki_coverage_ceiling, list(
	"objects without an article" = 0,
	"catalogued objects without a description" = 0,
	"reagents without an article" = 0,
	"jobs without an article" = 0,
	"gases without an article" = 0,
	"materials without an article" = 0,
	"plants without an article" = 0,
	"creatures without an article" = 0,
	"creatures without a description" = 0,
	"systems without a guide" = 0,
))

/// The mechanics a player has to learn that no data source explains: each needs a hand-written guide with this id.
GLOBAL_LIST_INIT(wiki_required_system_guides, list(
	"guide/chemistry/lab", "guide/medical/triage", "guide/medical/surgery", "guide/engineering/power", "guide/engineering/atmos",
	"guide/research/basics", "guide/cargo/ordering", "guide/cargo/trade_ships", "guide/cargo/haggling", "guide/cargo/salvage", "guide/cargo/ore_processing",
	"guide/civilian/botany", "guide/civilian/kitchen", "guide/engineering/materials", "guide/security/basics", "guide/exploration/expeditions",
))

/// Category -> list(missing names) and the number checked, for every category. The coverage report.
/proc/wiki_coverage_report()
	var/list/index = wiki_index()
	var/list/missing = list()
	var/list/checked = list()
	var/list/sources = GLOBAL_TABLE_GET(wiki_catalogue_sources_table)
	var/list/objects = list()
	for(var/key in list("designs", "packs", "made", "vended", "placed", "kinds"))
		for(var/path in sources[key])
			objects[path] = TRUE
	var/list/no_article = list()
	var/list/no_desc = list()
	for(var/path in objects)
		var/obj/O = path
		if(!initial(O.name))
			continue
		if(!index[wiki_cat_id(path)])
			no_article += "[path]"
		else if(!wiki_catalogue_description(path))
			no_desc += "[path]"
	missing["objects without an article"] = no_article
	checked["objects without an article"] = length(objects)
	missing["catalogued objects without a description"] = no_desc
	checked["catalogued objects without a description"] = length(objects)
	var/list/reagents = list()
	var/list/registry = SSchemistry.ready().chemical_reagents
	for(var/id in registry)
		var/datum/reagent/R = registry[id]
		if(R?.name && !(R.wiki_flag & WIKI_SPOILER) && !index[wiki_chem_id(id)])
			reagents += "[id]"
	missing["reagents without an article"] = reagents
	checked["reagents without an article"] = length(registry)
	var/list/jobs = list()
	var/job_count = 0
	for(var/datum/department/D as anything in SSjob.get_all_department_datums())
		if(!D.visible || D.centcom_only)
			continue
		for(var/title in D.jobs)
			job_count++
			if(!index[wiki_job_id(title)])
				jobs |= "[title]"
	missing["jobs without an article"] = jobs
	checked["jobs without an article"] = job_count
	var/list/gases = list()
	for(var/gas_type in subtypesof(/datum/gas))
		var/datum/gas/G = gas_type
		if(initial(G.name) && !index[wiki_gas_id(gas_type)])
			gases += "[gas_type]"
	missing["gases without an article"] = gases
	checked["gases without an article"] = length(subtypesof(/datum/gas))
	var/list/materials = list()
	for(var/name in GLOB.name_to_material)
		if(!index[wiki_material_id(GLOB.name_to_material[name])])
			materials += name
	missing["materials without an article"] = materials
	checked["materials without an article"] = length(GLOB.name_to_material)
	var/list/plants = list()
	var/list/seeds = plants_seeds()
	for(var/name in seeds)
		var/datum/seed/S = seeds[name]
		if(S.type != /datum/seed && !S.mysterious && !(S.wiki_flag & WIKI_SPOILER) && !index[wiki_plant_id(S)])
			plants += name
	missing["plants without an article"] = plants
	checked["plants without an article"] = length(seeds)
	var/list/fauna_missing = list()
	var/list/fauna_undescribed = list()
	var/list/fauna = wiki_fauna_types()
	for(var/path in fauna)
		var/mob/M = path
		if(!index[wiki_fauna_id(path)])
			fauna_missing += "[path]"
		else if(!initial(M.desc))
			fauna_undescribed += "[path]"
	missing["creatures without an article"] = fauna_missing
	checked["creatures without an article"] = length(fauna)
	missing["creatures without a description"] = fauna_undescribed
	checked["creatures without a description"] = length(fauna)
	var/list/guides = list()
	for(var/id in GLOB.wiki_required_system_guides)
		if(!index[id])
			guides += id
	missing["systems without a guide"] = guides
	checked["systems without a guide"] = length(GLOB.wiki_required_system_guides)
	return list("missing" = missing, "checked" = checked)

/datum/unit_test/dq_wiki_coverage

/datum/unit_test/dq_wiki_coverage/Run()
	var/list/report = wiki_coverage_report()
	var/list/lines = list("Station Wiki coverage ([length(wiki_index())] articles)")
	for(var/category in report["missing"])
		var/list/names = report["missing"][category]
		lines += "[category]: [length(names)] of [report["checked"][category]]"
		for(var/name in names)
			lines += "    [name]"
	var/text = jointext(lines, "\n")
	fdel("data/wiki_coverage.txt")
	text2file(text, "data/wiki_coverage.txt")
	for(var/category in report["missing"])
		var/list/names = report["missing"][category]
		log_world("WIKI COVERAGE: [category]: [length(names)] of [report["checked"][category]]")
		var/ceiling = GLOB.wiki_coverage_ceiling[category]
		TEST_ASSERT(!isnull(ceiling), "the coverage category [category] has no ceiling")
		TEST_ASSERT(length(names) <= ceiling, "[category]: [length(names)], above the ratchet of [ceiling]; document them: [english_list(names.Copy(1, min(length(names), 20) + 1))]")
