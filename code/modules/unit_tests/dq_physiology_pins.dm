/**
 * The physiology vector pin (doc/rewrite/proposals/stat_layer.md, D8): what the oxygen-transport chain gives for the scenarios that move the
 * factors it reads, recorded from the code before the physiology's invalidation was narrowed to the factors it reads, and kept after it.
 *
 *   dq_physiology_vector_pin   a fresh human per scenario, advanced in physiology steps of two seconds; at each checkpoint the vector
 *                              (ventilation, oxygenation, perfusion, oxygen debt, heart rate, blood pressure, respiratory rate) is a row.
 *
 * Rows are text, one file: code/modules/unit_tests/snapshots/factors/physiology.txt (key => value). A missing or empty file is recorded by the
 * next run; `bash tools/dq_focused_test.sh --bless dq_physiology_vector_pin` rewrites it. Numbers compare as text, rounded to four places.
 */

/// The scenarios: name -> the proc that sets one up on a fresh human; checkpoints are physiology steps.
/proc/physiology_pin_scenarios()
	return list("healthy", "choking", "respiratory_arrest", "bvm", "cyanide", "dexalin_debt", "blood_loss", "deep_debt", "arrhythmia")

/proc/physiology_pin_checkpoints(scenario)
	switch(scenario)
		if("healthy", "dexalin_debt", "bvm")
			return list(1, 5)
		if("deep_debt")
			return list(1, 3)
	return list(1, 10, 30)

/// Puts `H` into the scenario.
/proc/physiology_pin_setup(mob/living/carbon/human/H, scenario)
	switch(scenario)
		if("choking")
			H.body.afflict(/datum/affliction/airway_obstruction)
		if("respiratory_arrest")
			H.body.afflict(/datum/affliction/respiratory_arrest)
		if("bvm")
			H.body.afflict(/datum/affliction/respiratory_arrest)
			var/obj/item/bag_valve_mask/bvm = new
			bvm.apply_ventilation(H)
			qdel(bvm)
		if("cyanide")
			H.bloodstr.add_reagent(REAGENT_ID_CYANIDE, 10)
		if("dexalin_debt")
			H.add_oxygen_debt(40, "physiology pin")
			H.bloodstr.add_reagent(REAGENT_ID_DEXALIN, 20)
		if("blood_loss")
			H.vessel.remove_reagent(REAGENT_ID_BLOOD, H.species.blood_volume * 0.6)
		if("deep_debt")
			H.add_oxygen_debt(80, "physiology pin")
		if("arrhythmia")
			H.body.afflict(/datum/affliction/cardiac_arrhythmia)

/// The vector as the pin writes it.
/proc/physiology_pin_row(mob/living/carbon/human/H)
	var/list/bp = H.body.blood_pressure()
	return "vent=[round(H.body.ventilation(), 0.0001)] oxy=[round(H.body.oxygenation(), 0.0001)] perf=[round(H.body.perfusion(), 0.0001)] debt=[round(H.oxygen_debt(), 0.0001)] hr=[round(H.body.heart_rate(), 0.0001)] bp=[length(bp) ? "[round(bp[1], 0.0001)]/[round(bp[2], 0.0001)]" : "none"] rr=[round(H.body.respiratory_rate(), 0.0001)]"

/datum/unit_test/dq_physiology_vector_pin

/datum/unit_test/dq_physiology_vector_pin/Run()
	var/list/rows = list()
	for(var/scenario in physiology_pin_scenarios())
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
		physiology_pin_setup(H, scenario)
		var/stepped = 0
		for(var/checkpoint in physiology_pin_checkpoints(scenario))
			while(stepped < checkpoint)
				H.body.physiology_tick(2)
				stepped++
			rows["[scenario]@[checkpoint]"] = physiology_pin_row(H)
		qdel(H)
	var/file_name = "code/modules/unit_tests/snapshots/factors/physiology.txt"
	var/list/expected = list()
	for(var/line in dq_snapshot_file_rows(file_name))
		var/at = findtext(line, " => ")
		if(at)
			expected[copytext(line, 1, at)] = copytext(line, at + 4)
	if(dq_snapshot_blessing() || !length(expected))
		var/list/keys = list()
		for(var/key in rows)
			keys += key
		sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc))
		var/list/lines = list()
		for(var/key in keys)
			lines += "[key] => [rows[key]]"
		fdel(file_name)
		text2file("[jointext(lines, "\n")]\n", file_name)
		log_test("physiology pin: recorded [length(rows)] row(s)")
		return
	var/list/problems = list()
	for(var/key in rows)
		if(isnull(expected[key]))
			problems += "new: [key] => [rows[key]]"
		else if(expected[key] != rows[key])
			problems += "changed: [key]\n   was: [expected[key]]\n   now: [rows[key]]"
	for(var/key in expected)
		if(isnull(rows[key]))
			problems += "missing: [key]"
	if(length(problems))
		TEST_FAIL("[length(problems)] physiology pin row(s) differ:\n[jointext(problems, "\n")]")
