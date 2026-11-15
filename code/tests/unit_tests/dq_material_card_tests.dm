// The material card (doc/material_engineering_implementation.md): six core stats on one scale, traits shown only when present,
// a batch that is composition + temper + flaws, trace effects with their breakdown, and stacks that merge like a beaker of solid.

/// The row of `notes` (a stat's breakdown) labelled `label`, or null.
/datum/unit_test/proc/dq_card_note(datum/material/M, id, label)
	for(var/list/row as anything in LAZYACCESS(M.stat_notes, id))
		if(row[1] == label)
			return row
	return null

/// A processed material registered from `batch`.
/datum/unit_test/proc/dq_card_material(datum/material_batch/batch)
	return get_material_by_name(register_processed_material(batch))

/datum/unit_test/dq_material_card_is_six_stats

/datum/unit_test/dq_material_card_is_six_stats/Run()
	TEST_ASSERT_EQUAL(length(MATERIAL_CARD_STATS), 6, "the card is six stats")
	for(var/name in GLOB.name_to_material)
		var/datum/material/M = GLOB.name_to_material[name]
		for(var/stat in MATERIAL_CARD_STATS)
			TEST_ASSERT(isnum(M.card_value(stat)), "[name]'s [stat] is a number")
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	// Everything else is derived from the card.
	TEST_ASSERT_EQUAL(steel.melting_point(), 1800, "steel melts at 1800 K, from its heat resistance")
	TEST_ASSERT_EQUAL(steel.toughness * MATERIAL_HP_PER_TOUGHNESS, 150, "steel's hit points follow its toughness")
	TEST_ASSERT(steel.conductive(), "steel conducts")
	TEST_ASSERT(!get_material_by_name(MAT_GLASS).conductive(), "glass does not conduct")
	TEST_ASSERT(get_material_by_name(MAT_STEEL).electrical_resistivity() < get_material_by_name(MAT_GLASS).electrical_resistivity(), "resistivity is the inverse of conductivity")
	TEST_ASSERT(get_material_by_name(MAT_DIAMOND).brittleness() > steel.brittleness(), "strength outrunning toughness is brittleness")
	TEST_ASSERT(!length(steel.trait_lines()), "steel shows no trait lines: a trait it lacks is not listed")
	var/datum/material/etching = get_material_by_name(MAT_ETCHING_CERAMIC)
	TEST_ASSERT(etching.trait(MT_CATALYTIC) > 0, "etching ceramic is catalytic")
	TEST_ASSERT(length(etching.trait_lines()) == 1 && findtext(etching.trait_lines()[1], "Catalytic"), "and shows exactly that trait")

/datum/unit_test/dq_material_traces_lower_and_raise_stats

/datum/unit_test/dq_material_traces_lower_and_raise_stats/Run()
	var/datum/material_batch/clean = new
	clean.add_material(MAT_IRON, 10)
	var/datum/material/clean_material = dq_card_material(clean)
	var/datum/material_batch/sulfurous = new
	sulfurous.add_material(MAT_IRON, 10)
	sulfurous.add_substance("sulfur", 0.3, 0)
	var/datum/material/sulfur_material = dq_card_material(sulfurous)
	TEST_ASSERT(sulfur_material.toughness < clean_material.toughness, "sulfur makes the batch brittle (toughness [sulfur_material.toughness] vs [clean_material.toughness])")
	var/list/sulfur_note = dq_card_note(sulfur_material, MATERIAL_STAT_TOUGHNESS, "sulfur")
	TEST_ASSERT(sulfur_note && sulfur_note[2] < 0, "the toughness breakdown names sulfur and its loss")
	TEST_ASSERT(findtext(sulfur_material.stat_breakdown(MATERIAL_STAT_TOUGHNESS), "sulfur -"), "and says so in words: [sulfur_material.stat_breakdown(MATERIAL_STAT_TOUGHNESS)]")

	var/datum/material_batch/hydrogenous = new
	hydrogenous.add_material(MAT_IRON, 10)
	hydrogenous.add_substance("hydrogen", 0.3, 0)
	TEST_ASSERT(dq_card_material(hydrogenous).toughness < clean_material.toughness, "dissolved hydrogen embrittles")

	var/datum/material_batch/leaded = new
	leaded.add_material(MAT_IRON, 10)
	leaded.add_substance("lead", 0.3, 0)
	var/datum/material/lead_material = dq_card_material(leaded)
	TEST_ASSERT(lead_material.strength < clean_material.strength, "lead softens")
	TEST_ASSERT(lead_material.trait(MT_TOXIC) > 0, "and makes the stock toxic, so surgical tools made of it poison")
	TEST_ASSERT(!clean_material.trait(MT_TOXIC), "clean stock is not toxic")

	var/datum/material_batch/carbonaceous = new
	carbonaceous.add_material(MAT_IRON, 10)
	carbonaceous.add_substance("carbon", 0.3, 0)
	var/datum/material/carbon_material = dq_card_material(carbonaceous)
	TEST_ASSERT(carbon_material.strength > clean_material.strength, "carbon strengthens iron")
	TEST_ASSERT(carbon_material.conductivity < clean_material.conductivity, "and costs conductivity")
	var/list/carbon_note = dq_card_note(carbon_material, MATERIAL_STAT_STRENGTH, "carbon")
	TEST_ASSERT(carbon_note && carbon_note[2] > 0, "the strength breakdown names the carbon")

	// Wanted additives are just composition: carbon is listed beside the iron, there is no separate impurity list and no scalar purity.
	TEST_ASSERT(carbonaceous.composition["carbon"] > 0 && carbonaceous.composition[MAT_IRON] == 10, "carbon is composition")
	TEST_ASSERT_EQUAL(carbonaceous.bulk_composition()[MAT_IRON], 10, "the bulk materials are the batch's amount")
	TEST_ASSERT_NULL(carbonaceous.bulk_composition()["carbon"], "a trace is not bulk")
	qdel(clean)
	qdel(sulfurous)
	qdel(hydrogenous)
	qdel(leaded)
	qdel(carbonaceous)

/datum/unit_test/dq_material_trace_effect_saturates

/datum/unit_test/dq_material_trace_effect_saturates/Run()
	var/datum/material_trace/sulfur = GLOB.material_traces["sulfur"]
	var/list/small = sulfur.effect_at(1)
	var/list/limit = sulfur.effect_at(sulfur.limit)
	var/list/past = sulfur.effect_at(sulfur.limit * 4)
	TEST_ASSERT(small[MATERIAL_STAT_TOUGHNESS] > limit[MATERIAL_STAT_TOUGHNESS], "more sulfur costs more toughness up to its limit")
	TEST_ASSERT_EQUAL(past[MATERIAL_STAT_TOUGHNESS], limit[MATERIAL_STAT_TOUGHNESS], "past its limit a trace is an ingredient and changes nothing more")

/datum/unit_test/dq_material_temper_and_anneal

/datum/unit_test/dq_material_temper_and_anneal/Run()
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 4)
	var/melt = batch.melting_temperature()
	material_batch_set_temperature(batch, melt * 0.7)
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_SOLUTION_TREAT), "hot steel can be solution-treated")
	var/soft_strength = batch.strength
	var/soft_toughness = batch.toughness
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_QUENCH, "water"), "and quenched")
	TEST_ASSERT(batch.temper > MATERIAL_TEMPER_DEFAULT, "quenching hardens the temper")
	TEST_ASSERT(batch.strength > soft_strength, "hard stock is stronger ([batch.strength] vs [soft_strength])")
	TEST_ASSERT(batch.toughness < soft_toughness, "and less tough ([batch.toughness] vs [soft_toughness])")
	TEST_ASSERT(findtext(dq_card_material(batch).stat_breakdown(MATERIAL_STAT_STRENGTH), "tempered +"), "the strength breakdown credits the temper")
	var/hard_strength = batch.strength
	var/hard_flaws = batch.flaws
	// Annealing: heat it again, let it cool without quenching.
	material_batch_set_temperature(batch, melt * 0.7)
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_SOLUTION_TREAT), "hardened stock can be heated again")
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_ANNEAL), "and annealed")
	TEST_ASSERT(batch.temper < MATERIAL_TEMPER_DEFAULT, "annealing softens the temper")
	TEST_ASSERT(batch.strength < hard_strength, "annealed stock is weaker than hardened stock")
	TEST_ASSERT(batch.flaws < hard_flaws, "and has fewer flaws")
	TEST_ASSERT(!batch.apply_process(MATERIAL_PROCESS_ANNEAL), "stock that was not held hot cannot be annealed")
	qdel(batch)

/datum/unit_test/dq_material_purify_strips_leachable_traces

/datum/unit_test/dq_material_purify_strips_leachable_traces/Run()
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 4)
	batch.add_substance("sulfur", 0.1, 0)
	batch.add_substance("carbon", 0.1, 0)
	var/flaws = batch.flaws
	TEST_ASSERT(batch.apply_process(MATERIAL_PROCESS_PURIFY), "an acid wash")
	TEST_ASSERT_NULL(batch.composition["sulfur"], "strips sulfur")
	TEST_ASSERT(batch.composition["carbon"] > 0, "and leaves the carbon that was wanted")
	TEST_ASSERT(batch.flaws < flaws, "and the batch has fewer flaws")
	qdel(batch)

/datum/unit_test/dq_material_stacks_merge_like_a_beaker

/datum/unit_test/dq_material_stacks_merge_like_a_beaker/Run()
	var/turf/floor = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/item/stack/material/steel/a = allocate(/obj/item/stack/material/steel, floor, 10)
	var/obj/item/stack/material/steel/b = allocate(/obj/item/stack/material/steel, floor, 10)
	a.traces_rolled = TRUE
	b.traces_rolled = TRUE
	a.trace_amounts = list("sulfur" = 0.2)
	b.trace_amounts = list("sulfur" = 0.6, "carbon" = 0.1)
	a.assayed = TRUE
	b.assayed = FALSE
	TEST_ASSERT(!a.assayed || !b.assayed, "one half is unassayed")
	TEST_ASSERT_EQUAL(b.transfer_to(a, 10), 10, "the same material merges whatever lot each came from")
	TEST_ASSERT_EQUAL(a.get_amount(), 20, "all twenty sheets are in one stack")
	TEST_ASSERT(abs(a.trace_amounts["sulfur"] - 0.8) < 0.0001, "the traces add by amount: sulfur [a.trace_amounts["sulfur"]]")
	TEST_ASSERT(abs(a.trace_amounts["carbon"] - 0.1) < 0.0001, "and a trace only one half had is still there")
	TEST_ASSERT(!a.assayed, "a merged stack is unassayed if either half was")
	// Splitting takes a share of the traces with the sheets.
	var/obj/item/stack/material/steel/part = a.split(5)
	TEST_ASSERT(part, "the stack splits")
	TEST_ASSERT(abs(part.trace_amounts["sulfur"] - 0.2) < 0.0001, "a quarter of the sheets takes a quarter of the sulfur ([part.trace_amounts["sulfur"]])")
	TEST_ASSERT(abs(a.trace_amounts["sulfur"] - 0.6) < 0.0001, "and leaves three quarters ([a.trace_amounts["sulfur"]])")
	// Ordinary building ignores traces: the stack's material is the plain steel everything else is built from.
	TEST_ASSERT_EQUAL(a.material, get_material_by_name(MAT_STEEL), "a stack with traces is still plain steel to a builder")
	qdel(part)

/datum/unit_test/dq_material_assay_reveals_traces

/datum/unit_test/dq_material_assay_reveals_traces/Run()
	var/turf/floor = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/item/stack/material/steel/stack = allocate(/obj/item/stack/material/steel, floor, 10)
	var/mob/living/carbon/human/viewer = allocate(/mob/living/carbon/human, floor)
	stack.traces_rolled = TRUE
	stack.trace_amounts = list("sulfur" = 0.2, "lead" = 0.1)
	TEST_ASSERT(!stack.assayed, "stock starts unassayed")
	var/before = jointext(stack.examine(viewer), "\n")
	TEST_ASSERT(findtext(before, "unassayed"), "its traces are hidden until read")
	TEST_ASSERT(!findtext(before, "sulfur"), "so the examine does not name them")
	TEST_ASSERT(findtext(before, "Strength 60"), "but the card is shown")
	var/list/lines = stack.assay(viewer)
	TEST_ASSERT(stack.assayed, "a spectrometer reading marks the stack assayed")
	TEST_ASSERT(length(lines) == 2, "and reads both traces: [jointext(lines, "; ")]")
	var/after = jointext(stack.examine(viewer), "\n")
	TEST_ASSERT(findtext(after, "sulfur") && findtext(after, "lead"), "an assayed stack names its traces")
	TEST_ASSERT(findtext(after, "toughness -"), "and their effects")

/datum/unit_test/dq_material_processed_stock_merges_by_identity

/datum/unit_test/dq_material_processed_stock_merges_by_identity/Run()
	var/turf/floor = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/datum/material_batch/first = new
	first.add_material(MAT_STEEL, 4)
	first.add_substance("sulfur", 0.04, 0)
	var/datum/material_batch/second = new
	second.add_material(MAT_STEEL, 4)
	second.add_substance("carbon", 0.2, 0)
	var/datum/material_batch/hard = new
	hard.add_material(MAT_STEEL, 4)
	hard.temper = 90
	hard.recalculate()
	var/obj/item/stack/material/processed_alloy/a = processed_spawn_stack(floor, first, 4)
	var/obj/item/stack/material/processed_alloy/b = processed_spawn_stack(floor, second, 4)
	var/obj/item/stack/material/processed_alloy/h = processed_spawn_stack(floor, hard, 4)
	own(a)
	own(b)
	own(h)
	a.assayed = TRUE
	b.assayed = TRUE
	var/old_name = b.material.name
	TEST_ASSERT_EQUAL(h.transfer_to(b, 4), 0, "stock of a different temper does not merge")
	TEST_ASSERT_EQUAL(a.transfer_to(b, 4), 4, "the same bulk composition and temper merges whatever its traces")
	var/datum/material_batch/merged = b.physical_batch()
	TEST_ASSERT_EQUAL(merged.amount, 8, "the merged batch holds both")
	TEST_ASSERT(merged.composition["sulfur"] > 0 && merged.composition["carbon"] > 0, "and both traces")
	TEST_ASSERT(abs(merged.composition["sulfur"] - 0.04) < 0.0001 && abs(merged.composition["carbon"] - 0.2) < 0.0001, "added by amount")
	TEST_ASSERT(b.material.name != old_name, "the merged stock is a different registered material: its traces average")
	TEST_ASSERT(b.assayed, "assayed only because both halves were")
	b.assayed = FALSE
	TEST_ASSERT(!b.assayed, "and unassayed once either is not")

/datum/unit_test/dq_material_card_breakdown_on_examine

/datum/unit_test/dq_material_card_breakdown_on_examine/Run()
	var/turf/floor = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/mob/living/carbon/human/viewer = allocate(/mob/living/carbon/human, floor)
	var/datum/material_batch/batch = new
	batch.add_material(MAT_IRON, 10)
	batch.add_substance("sulfur", 0.3, 0)
	batch.temper = 60
	var/obj/item/stack/material/processed_alloy/stock = processed_spawn_stack(floor, batch, 10)
	own(stock)
	var/text = jointext(stock.examine(viewer), "\n")
	TEST_ASSERT(findtext(text, "Toughness") && findtext(text, "base") && findtext(text, "sulfur -"), "examine shows each stat with the steps behind it: [text]")
	TEST_ASSERT(findtext(text, "tempered"), "including the temper")
	var/datum/material/alloy = stock.material
	var/list/rows = alloy.card_rows()
	TEST_ASSERT_EQUAL(length(rows), 6 + length(alloy.trait_lines()), "the UI rows are the card plus the traits present")
	var/found = FALSE
	for(var/list/row as anything in rows)
		if(row["name"] == "Toughness")
			found = length(row["breakdown"]) > 1
	TEST_ASSERT(found, "the UI row for toughness carries its breakdown")

/datum/unit_test/dq_material_trait_appears_only_with_its_ingredients

/datum/unit_test/dq_material_trait_appears_only_with_its_ingredients/Run()
	var/datum/material_batch/plain = new
	plain.add_material(MAT_STEEL, 4)
	TEST_ASSERT(!length(dq_card_material(plain).trait_lines()), "plain steel stock has no traits to list")
	var/datum/material_batch/platinum = new
	platinum.add_material(MAT_STEEL, 3)
	platinum.add_material(MAT_PLATINUM, 1)
	var/datum/material/catalyst = dq_card_material(platinum)
	TEST_ASSERT(catalyst.trait(MT_CATALYTIC) > 0, "platinum in the melt makes the stock catalytic")
	TEST_ASSERT(findtext(jointext(catalyst.trait_lines(), ";"), "Catalytic"), "and the trait line shows")
	qdel(plain)
	qdel(platinum)
