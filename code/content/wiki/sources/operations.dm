// The wiki's operations source: tables read from the game's own data that a guide links to, so the guide's numbers never go stale.
//   ops/fusion_reactions   every R-UST reaction (the REGIME_FUSION transformations): reactants, energy, radiation, instability, what it makes
//   ops/expedition_contracts  every expedition contract a pilot can take (GLOB.expedition_mission_types): what it asks and what it pays
//   ops/alert_levels       the station's alert levels and the announcement each one makes (the server's alert_desc_* config)

/proc/wiki_source_operations(list/index)
	wiki_add(index, "ops/fusion_reactions", "Fusion reactions", "Engineering/Power", "Every reaction the R-UST can run, read from its reaction table.", null, GLOBAL_PROC_REF(wiki_fusion_reactions_body), null)
	wiki_add(index, "ops/expedition_contracts", "Expedition contracts", "Exploration", "Every contract a pilot can take, and what it pays.", null, GLOBAL_PROC_REF(wiki_expedition_contracts_body), null)
	wiki_add(index, "ops/alert_levels", "Alert levels", "Security", "The station's alert levels and what each one means.", null, GLOBAL_PROC_REF(wiki_alert_levels_body), null)

/proc/wiki_fusion_reactions_body()
	var/list/rows = list()
	for(var/datum/xform/X as anything in xform_rules_in(MEDIUM_FIELD, REGIME_FUSION))
		var/list/products = list()
		for(var/id in X.field_products)
			products += wiki_chem_ref(id)
		rows += list(list("[wiki_chem_ref(X.reactant_a)] + [wiki_chem_ref(X.reactant_b)]", "[X.energy_in]", "[X.energy_out]", "[X.radiation]", "[X.instability]", "[X.min_level]", "[X.min_heat]", english_list(products, nothing_text = "-")))
	var/list/blocks = list(wiki_p("The R-UST's field fuses pairs of reactants. Each reaction takes the energy in to start and gives the energy out; radiation and instability are added to the field for every pair. A reaction runs only while the field holds at least its minimum energy and the plasma is at least its minimum heat."))
	blocks += list(wiki_table(list("Reactants", "Energy in", "Energy out", "Radiation", "Instability", "Minimum field energy", "Minimum plasma heat", "Makes"), rows))
	blocks += list(wiki_note("Field strength sets the field's size: up to 50 it is one tile, up to 200 three, up to 500 five, above that seven."))
	return blocks

/proc/wiki_expedition_contracts_body()
	var/list/rows = list()
	for(var/mission_type in GLOB.expedition_mission_types)
		var/list/pays = list()
		var/datum/expedition_mission/first
		for(var/band in GLOB.expedition_threat_bands)
			var/datum/expedition_mission/M = new mission_type(GLOB.expedition_threat_bands[band])
			pays += "[band]: [M.reward_cash] Thalers, [M.reward_points] survey points"
			if(!first)
				first = M
			else
				spent(M)
		rows += list(list(first.name, first.desc, jointext(pays, "; "), first.time_limit ? "[first.time_limit / (1 MINUTES)] minutes" : "None"))
		spent(first)
	var/list/blocks = list(wiki_p("A pilot takes one contract per vessel from the flight console and picks its threat band ([english_list(GLOB.expedition_threat_bands)]). See [wiki_ref("guide/exploration/expeditions", "going on an expedition")]."))
	blocks += list(wiki_table(list("Contract", "What it asks", "Pays (before bonus objectives)", "Time limit"), rows))
	blocks += list(wiki_note("On completion the survey points are logged for the program and the cash is paid once: half split between the surviving crew on the site (to their ID's account), the rest to the exploration budget. Completed bonus objectives add to both."))
	return blocks

/proc/wiki_alert_levels_body()
	var/list/rows = list()
	rows += list(list("Green", CONFIG_GET(string/alert_desc_green)))
	rows += list(list("Yellow", CONFIG_GET(string/alert_desc_yellow_upto)))
	rows += list(list("Violet", CONFIG_GET(string/alert_desc_violet_upto)))
	rows += list(list("Orange", CONFIG_GET(string/alert_desc_orange_upto)))
	rows += list(list("Blue", CONFIG_GET(string/alert_desc_blue_upto)))
	rows += list(list("Red", CONFIG_GET(string/alert_desc_red_upto)))
	rows += list(list("Delta", CONFIG_GET(string/alert_desc_delta)))
	var/list/blocks = list(wiki_p("The alert level tells the crew how serious things are. Command sets Green, Yellow, Blue, Orange and Violet from a communications console; Red needs two heads of staff swiping their cards at keycard authentication devices together. Each level makes the announcement below when it is raised to."))
	blocks += list(wiki_table(list("Level", "Announcement"), rows))
	return blocks
