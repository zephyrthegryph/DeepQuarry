// DQ Medical Reference — Purity tab builder.
//
// What a mixture carries besides its reagents (code/domains/world_model/reagents/contaminants.dm): the four grades with their purity
// bands (a readout: no recipe asks for one), every contaminant reagent (what it is and what it does to a patient), the processes that make
// chemicals out of block structures, and the ways to purify a mixture: the temperature each recipe wants (code/content/reagents/reactions/reaction_temperatures.dm), the boiling
// points (code/content/reagents/reagents/boiling_points.dm), the filters (code/content/reagents/purification/filters.dm), neutralisation and the hot plate and
// condenser. All of it is read from the reagent types, the tables and the transformation rules, never written out here.

/proc/_dq_book_purity()
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
			"floor"       = C.filter_floor,
		))
	out["contaminants"] = contaminants
	var/list/processes = list()
	for(var/process_id in GLOB.chem_processes)
		var/datum/chem_process/P = GLOB.chem_processes[process_id]
		processes += list(list("id" = P.id, "name" = P.name, "text" = P.desc, "kinds" = P.kinds.Copy(), "reserved" = P.reserved))
	out["processes"] = processes
	out["temperature_classes"] = _dq_book_temperature_classes()
	out["recipe_temperatures"] = _dq_book_recipe_temperatures()
	out["boiling_points"] = _dq_book_boiling_points()
	out["methods"] = _dq_book_methods()
	return out

/// A temperature in the book: degrees Celsius, one decimal at most.
/proc/_dq_book_celsius(kelvin)
	return round(kelvin - T0C, 0.1)

/// Each temperature class: its name and its working range and ideal band, Celsius.
/proc/_dq_book_temperature_classes()
	var/list/out = list()
	for(var/class in GLOB.reaction_temperature_classes)
		var/list/band = GLOB.reaction_temperature_classes[class]
		out += list(list(
			"id"         = class,
			"range_low"  = _dq_book_celsius(band[1]),
			"ideal_low"  = _dq_book_celsius(band[2]),
			"ideal_high" = _dq_book_celsius(band[3]),
			"range_high" = _dq_book_celsius(band[4]),
		))
	return out

/// The recipes that need more than a bench at room temperature: every chemistry recipe not filed under a room-temperature class, with its class and band.
/proc/_dq_book_recipe_temperatures()
	var/list/out = list()
	for(var/datum/xform/CR as anything in GLOB.xform_rules)
		if(CR.medium != MEDIUM_REAGENTS || CR.regime != REGIME_INSTANT || !ispath(CR.rule_type, /transformation/chem) || !CR.result)
			continue
		if(CR.wiki & WIKI_SPOILER)
			continue
		var/class = reaction_temperature_class(CR.rule_type)
		if(class == REACTION_TEMP_AMBIENT || class == REACTION_TEMP_GENTLE)
			continue
		var/list/band = reaction_temperature_profile(CR.rule_type)
		out += list(list(
			"id"         = CR.result,
			"name"       = dq_reagent_display_name(CR.result),
			"class"      = class,
			"ideal_low"  = _dq_book_celsius(band[2]),
			"ideal_high" = _dq_book_celsius(band[3]),
			"range_low"  = _dq_book_celsius(band[1]),
			"range_high" = _dq_book_celsius(band[4]),
		))
	return out

/// The boiling points worth knowing: every contaminant, then the reagents the table names, Celsius (a point above 3000 C is "never").
/proc/_dq_book_boiling_points()
	var/list/out = list()
	for(var/id in contaminant_ids())
		var/datum/reagent/contaminant/C = contaminant_def(id)
		out += list(list("id" = id, "name" = C.name, "celsius" = _dq_book_celsius(C.boiling_point_k()), "never" = C.boiling_point_k() >= BOILING_POINT_NEVER))
	for(var/id in GLOB.reagent_boiling_points)
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[id]
		if(!R)
			continue
		out += list(list("id" = id, "name" = R.name, "celsius" = _dq_book_celsius(R.boiling_point_k()), "never" = R.boiling_point_k() >= BOILING_POINT_NEVER))
	return out

/// The ways to purify a mixture: what each does and what it takes out.
/proc/_dq_book_methods()
	var/list/out = list()
	out += list(list("name" = "Temperature", "text" = "A recipe is clean inside its ideal band. Off the band but inside its range it still goes, but leaves organic residue (too cold) or a reactive impurity and a loss of product (too hot), more the further off it is. Outside its range nothing happens."))
	out += list(list("name" = "Catalysts", "text" = "A catalyst belongs to a process. A dissolved acid (sulphuric) or base (lye) is spent into acid or base residue; an enzyme works at gentle heat and leaves endotoxin. A sheet of a material with catalytic activity, dropped into a glass container (\"Take out the catalyst\" from its menu), is the solid catalyst of the routes that run on one: it no longer widens the band of every recipe. Sulfur and heavy metals poison a sheet, and heavy metals kill an enzyme."))
	out += list(list("name" = "Interference", "text" = "Acid and base cancel into salts. Water undoes a condensation (an ester or amide splits back into its acid and alcohol or amine). Oxidiser left over attacks the next product. Peroxide detonates when its container is heated."))
	out += list(list("name" = "Hot plate", "text" = "Stand a glass container on a hot plate, set the dial in Celsius and switch it on: it feeds heat into the container up to the dial, never past it, drawing power while on, and lets the contents react and boil. It only heats: a container hotter than the dial cools on its own."))
	out += list(list("name" = "Ice and baths", "text" = "Water below 0 C freezes into ice and ice above 0 C melts, each unit taking or giving heat, so ice and water hold a container at 0 C while any ice is left. The ice machine chills a container of water into ice. Stand a smaller open container in a larger one (grab-stance click, \"Stand it in the bath\") and their heat is shared: an ice bath chills the inner container into the band of a cold recipe, and a warm bath on the hot plate warms it. A pour into a bath goes into the bath, never the inner container."))
	out += list(list("name" = "Boiling and the condenser", "text" = "A container hotter than a reagent's boiling point loses that reagent, gradually, and the vapour is gone. A condenser on or next to the hot plate collects the vapour into a container under its spout: distillation. What boils comes over; what never boils (salts, heavy metals) stays behind."))
	out += list(list("name" = "Neutralisation", "text" = "Acid residue and a base (lye, ammonia, diethylamine), or base residue and an acid (sulphuric, polytrinic), make salts and water. Measure it: too little leaves residue, too much leaves the base or the acid."))
	for(var/list/row in list(list("paper filter", chem_filter_strengths(/obj/item/chem_filter/paper)), list("charcoal filter", chem_filter_strengths(/obj/item/chem_filter/charcoal))))
		var/list/taken = list()
		var/list/strengths = chem_filter_catches(row[2])
		for(var/id in strengths)
			var/datum/reagent/contaminant/C = contaminant_def(id)
			taken += "[C.name] ([round(strengths[id] * 100)]%)"
		out += list(list("name" = row[1], "text" = "Fit a funnel on a beaker and put the filter in it: what is poured in is filtered. It takes [jointext(taken, ", ")] while fresh, keeps a little of the product, and clogs when it fills."))
	out += list(list("name" = "Ion-exchange (sorbent) filter", "text" = "Line a paper filter with a sheet of an engineered material. Its sorption stat takes ionic, metallic, sulfurous and oily contaminants (salts, heavy metals, sulfur, oils); its catalytic activity takes oxidisers and sulfur; its antimicrobial activity takes endotoxin."))
	return out
