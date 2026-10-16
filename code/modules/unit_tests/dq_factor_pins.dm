/**
 * Body-factor table pins (doc/rewrite/proposals/stat_layer.md, section 4.3): recorded from the OLD fold before the body's factors moved onto
 * the stat store, and kept through every wave after it.
 *
 *   dq_factor_table_pin   every factor table a source declares (afflictions and their stages, reagents and their species tables, body effects,
 *                         species, traits, perks, forms) at every scale and stack count that applies to it: the factors the old fold gives
 *                         it alone, as the 67 body-factor stats (and the armour kinds) that moved from 0 or 1, recorded by name.
 *
 * The test checks three things for every row: the old fold (the oracle) still gives the recorded vector, so the table has not changed since it
 * was pinned; hold_table() on a mob that holds nothing else gives the same vector within a relative 1e-5 (exactly for bit fields), so the engine
 * composes a table the way the old fold did; and the row is there at all. Rows are text, one file per source kind under
 * code/modules/unit_tests/snapshots/factors/ (key => value). A missing or empty file is recorded by the next run;
 * `bash tools/dq_focused_test.sh --bless dq_factor_table_pin` rewrites it after an intended change to a table.
 */
#define DQ_FACTOR_PIN_DIR "code/modules/unit_tests/snapshots/factors/"

/// The pinned kinds of source, one file each.
/proc/factor_pin_kinds()
	return list("afflictions", "stages", "reagents", "effects", "species", "traits", "perks", "forms")

/// The rows of one kind as cases: list(key, table, scale, stacks), in a stable order.
/proc/factor_pin_cases(kind)
	var/list/cases = list()
	switch(kind)
		if("afflictions")
			for(var/path in subtypesof(/datum/affliction))
				var/datum/affliction/typed = path
				if(!initial(typed.catalogued))
					continue
				var/datum/affliction/proto = dq_proto(path)
				if(!proto || proto.abstract_type == path || !length(proto.factors))
					continue
				for(var/scale in list(0.25, 0.5, 1))
					cases += list(list("[path]", proto.factors, scale, 1))
		if("stages")
			for(var/path in subtypesof(/datum/affliction))
				var/datum/affliction/typed = path
				if(!initial(typed.catalogued))
					continue
				var/datum/affliction/proto = dq_proto(path)
				if(!proto || proto.abstract_type == path)
					continue
				var/list/stages = TYPE_TABLE_GET(proto, affliction_stages)
				for(var/stage_id in stages)
					var/list/entry = stages[stage_id]
					if(length(entry["factors"]))
						cases += list(list("[path]#[stage_id]", entry["factors"], 1, 1))
		if("reagents")
			var/list/reagents = SSchemistry.ready().chemical_reagents
			var/list/ids = list()
			for(var/reagent_id in reagents)
				ids += "[reagent_id]"
			sortTim(ids, GLOBAL_PROC_REF(cmp_text_asc))
			for(var/reagent_id in ids)
				var/datum/reagent/R = reagents[reagent_id]
				if(length(R.factors))
					for(var/scale in list(0.25, 1, 2, 4))
						cases += list(list("[reagent_id]", R.factors, scale, 1))
				for(var/tag in R.species_factors)
					var/alist/merged = R.merged_species_factors(tag)
					if(length(merged))
						for(var/scale in list(0.25, 1, 2, 4))
							cases += list(list("[reagent_id]@[tag]", merged, scale, 1))
		if("effects")
			for(var/path in subtypesof(/datum/body_effect))
				var/datum/body_effect/def = body_effect_def(path)
				if(!def || !length(def.factors))
					continue
				for(var/stacks in list(1, 2, 3))
					cases += list(list("[path]", def.factors, 1, stacks))
		if("species")
			for(var/species_name in GLOB.all_species)
				var/datum/species/S = GLOB.all_species[species_name]
				if(length(S?.factor_baseline))
					cases += list(list("[species_name]", S.factor_baseline, 1, 1))
		if("traits")
			for(var/trait_path in GLOB.all_traits)
				var/datum/trait/T = GLOB.all_traits[trait_path]
				if(length(T?.factors))
					cases += list(list("[trait_path]", T.factors, 1, 1))
		if("perks")
			for(var/path in subtypesof(/datum/perk))
				var/datum/perk/proto = dq_proto(path)
				if(proto && length(proto.factors))
					cases += list(list("[path]", proto.factors, 1, 1))
		if("forms")
			for(var/path in subtypesof(/datum/form))
				var/datum/form/proto = dq_proto(path)
				if(proto && length(proto.factors))
					cases += list(list("[path]", proto.factors, 1, 1))
	return cases

/// The old fold of one table at `scale`, `stacks` times, as the oracle's vector (indexed by BF_*), or null when nothing moved.
/proc/factor_pin_old_vector(alist/table, scale, stacks)
	var/list/acc = null
	for(var/i in 1 to stacks)
		acc = oracle_accumulate(acc, table, scale)
	return oracle_finalize(acc)

/// A vector as the pin writes it: the factors that are not at their baseline, as "name=value" in id order, or "-" when none is.
/proc/factor_pin_text(list/vector)
	var/list/parts = list()
	for(var/id in 1 to BF_COUNT)
		var/stat_id = bf_stat_id(id)
		if(!stat_id || !vector)
			continue
		if(vector[id] != oracle_baseline(id))
			parts += "[stat_label(stat_id)]=[num2text(vector[id], 8)]"
	return length(parts) ? jointext(parts, " ") : "-"

/// The values of a pin row as name -> number.
/proc/factor_pin_parse(text)
	. = list()
	if(text == "-")
		return
	for(var/part in splittext(text, " "))
		var/at = findtext(part, "=")
		.[copytext(part, 1, at)] = text2num(copytext(part, at + 1))

/// Every name a pin row can hold, to compare the engine's whole vector against a row.
/proc/factor_pin_names()
	var/static/list/names
	if(!names)
		names = list()
		for(var/id in 1 to BF_COUNT)
			var/stat_id = bf_stat_id(id)
			if(stat_id)
				names[stat_label(stat_id)] = stat_id
	return names

/// A pin file's rows as key => value.
/proc/factor_pin_read(name)
	. = list()
	for(var/line in dq_snapshot_file_rows("[DQ_FACTOR_PIN_DIR][name].txt"))
		var/at = findtext(line, " => ")
		if(at)
			.[copytext(line, 1, at)] = copytext(line, at + 4)

/// The pin file rewritten with `rows` (key => value), sorted by key.
/proc/factor_pin_write(name, list/rows)
	var/list/keys = list()
	for(var/key in rows)
		keys += key
	sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc))
	var/list/lines = list()
	for(var/key in keys)
		lines += "[key] => [rows[key]]"
	var/file_name = "[DQ_FACTOR_PIN_DIR][name].txt"
	fdel(file_name)
	text2file("[jointext(lines, "\n")]\n", file_name)

/datum/unit_test/dq_factor_table_pin
	tier = TEST_TIER_NORMAL

/datum/unit_test/dq_factor_table_pin/Run()
	var/mob/living/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	var/datum/stat_def/probe = stat_def_of(STAT_SLOWDOWN)
	TEST_ASSERT_NOTNULL(probe, "the body factor stats are declared")
	var/list/problems = list()
	var/total = 0
	for(var/kind in factor_pin_kinds())
		var/list/recorded = factor_pin_read(kind)
		var/list/rows = list()
		for(var/list/case as anything in factor_pin_cases(kind))
			var/key = "[case[1]]|[case[3]]|[case[4]]"
			var/alist/table = case[2]
			var/list/old = factor_pin_old_vector(table, case[3], case[4])
			rows[key] = factor_pin_text(old)
			total++
			// The old fold reproduces the recorded vector (the table has not moved since it was pinned).
			if(length(recorded) && !dq_snapshot_blessing())
				if(isnull(recorded[key]))
					problems += "[kind]: new row [key] => [rows[key]]"
				else if(recorded[key] != rows[key])
					problems += "[kind]: [key] was [recorded[key]], the old fold now gives [rows[key]]"
			// hold_table() on a bare mob gives the same vector.
			var/mismatch = factor_pin_engine_mismatch(M, table, case[3], case[4], length(recorded) && !dq_snapshot_blessing() && recorded[key] ? recorded[key] : rows[key])
			if(mismatch)
				problems += "[kind]: [key]: [mismatch]"
		if(dq_snapshot_blessing() || !length(recorded))
			factor_pin_write(kind, rows)
			log_test("factor pin [kind]: recorded [length(rows)] row(s)")
		else
			for(var/key in recorded)
				if(isnull(rows[key]))
					problems += "[kind]: row [key] is no longer produced"
	log_test("factor pin: [total] row(s) checked")
	if(length(problems))
		var/report = "[length(problems)] factor pin row(s) differ:"
		var/shown = 0
		for(var/problem in problems)
			report += "\n[problem]"
			if(++shown >= 40)
				report += "\n... and [length(problems) - shown] more"
				break
		TEST_FAIL(report)

/// Holds `table` on `M` from a fresh source at `scale` and `stacks`, reads every body-factor stat and compares with the pin row's values (relative
/// 1e-5, exactly for bit fields); releases it. Null when they agree, else what differs.
/proc/factor_pin_engine_mismatch(mob/living/M, alist/table, scale, stacks, row_text)
	var/obj/e3_source/source = new
	hold_table(M, source, body_table_stat_keys(table), scale, stacks)
	var/list/expected = factor_pin_parse(row_text)
	var/list/names = factor_pin_names()
	var/list/bad = list()
	for(var/name in names)
		var/stat_id = names[name]
		var/def_base = stat_def_of(stat_id).base
		var/want = isnull(expected[name]) ? def_base : expected[name]
		var/have = stat_value(M, stat_id)
		var/exact = (stat_id == STAT_SIGHT_FLAGS || stat_id == STAT_ACTION_BLOCKS)
		var/ok = exact ? (have == want) : (abs(have - want) <= 0.00001 * max(1, abs(want)))
		if(!ok)
			bad += "[name] engine [have], pin [want]"
	qdel(source)
	return length(bad) ? jointext(bad, "; ") : null
