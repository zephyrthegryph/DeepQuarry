/**
 * Transformation pins (doc/rewrite/proposals/transformations.md, section 12): the outcome of every chemical rule, recorded on the legacy code
 * (the old /datum/decl/chemical_reaction types) before any of it moved, and kept byte-identical through the conversion to transformations.
 *
 *   dq_xform_outcome_pin   every rule settled once on a canonical subject (each input at four times its minimum, the catalysts present, the subject
 *                          its `required` type names): which rules fired and in what order, what the subject holds at the end of the fixed point,
 *                          what appeared around it, how many contract events the settle emitted, whether the rule is marked important.
 *                          A distilling rule is settled at the two ends and the middle of its temperature window and just outside it.
 *   dq_xform_overlap_pin   every pair of rules that compete for a reactant (the same first input, the same family, a compatible subject and window): a
 *                          subject holding the union of their inputs; the winner and the leftovers. This is the pin that proves a change of ordering.
 *
 * Rows are `key => value` text, one file per test under code/modules/unit_tests/snapshots/xform/. A rule's key is its type path below the root of
 * the rule types (`instant/carthatoline`, `distilling/biomass`, `instant/slime/grey_new_slime`), which the conversion kept. The recorders read rules
 * through /datum/xform_pin_rule, which dq_xform_pin_rules() fills from the compiled rules.
 *
 * An empty or missing file is recorded by the next run; `bash tools/dq_focused_test.sh --bless <test>` rewrites it. Record on one unsharded world.
 * Every row seeds the global rng first, so a rule whose tail rolls dice is reproducible.
 */
#define DQ_XFORM_PIN_DIR "code/modules/unit_tests/snapshots/xform/"
/// The inputs of a canonical subject are this many times the rule's minimum.
#define DQ_XFORM_SCALE 4
/// The seed of the global rng before each settle.
#define DQ_XFORM_SEED 4421
/// The volume of a canonical subject's holder: large enough that the product is never truncated.
#define DQ_XFORM_VOLUME 100000
#define DQ_XFORM_FAMILY_INSTANT "instant"
#define DQ_XFORM_FAMILY_DISTILLING "distilling"
#define DQ_XFORM_FAMILY_SLIME "slime"

/// One rule as the pins read it, whatever form it is declared in.
/datum/xform_pin_rule
	/// The rule's type path below the root of the rule types.
	var/key
	var/family = DQ_XFORM_FAMILY_INSTANT
	/// reagent id => amount consumed per unit of extent.
	var/list/takes
	var/list/catalysts
	var/list/blocked_by
	var/result
	var/result_amount = 0
	/// The type of the thing that must hold the reagents (a slime extract), or null.
	var/subject_type
	var/important = FALSE
	/// A distilling rule's temperature window and its gas conditions.
	var/temp_lo
	var/temp_hi
	var/require_gas
	var/rejects_gas
	var/min_pressure
	var/max_pressure
	/// The compiled rule.
	var/datum/xform/rule

/// Every chemical rule of the compiled tables, in order: what the chemistry tests walk.
/proc/dq_chem_rules()
	. = list()
	for(var/datum/xform/X as anything in GLOB.xform_rules)
		if(X.medium == MEDIUM_REAGENTS && ispath(X.rule_type, /transformation/chem))
			. += X

/// Every chemical rule as a pin record, key => record, in no particular order (callers sort the keys).
/proc/dq_xform_pin_rules()
	. = list()
	var/root_length = length("/transformation/chem/") + 1
	for(var/datum/xform/X as anything in dq_chem_rules())
		var/datum/xform_pin_rule/R = new
		R.key = copytext("[X.rule_type]", root_length)
		R.takes = X.reagent_takes
		R.catalysts = X.reagent_catalysts
		R.blocked_by = X.reagent_blocked
		R.result = X.result
		R.result_amount = X.result_amount
		R.important = X.important
		R.rule = X
		R.subject_type = X.subject_type
		if(X.regime == REGIME_DISTILLING)
			R.family = DQ_XFORM_FAMILY_DISTILLING
			var/list/window = X.bands[1]
			R.temp_lo = window[1]
			R.temp_hi = window[2]
			var/list/ambient = xform_cond_ambient(X.holds)
			R.require_gas = ambient[1]
			R.rejects_gas = ambient[2]
			R.min_pressure = ambient[3]
			R.max_pressure = ambient[4]
		else if(ispath(X.rule_type, /transformation/chem/instant/slime))
			R.family = DQ_XFORM_FAMILY_SLIME
		.[R.key] = R

/// The key of the rule a reaction notice names.
/proc/dq_xform_pin_key_of(thing)
	var/datum/xform/X = thing
	return copytext("[X.rule_type]", length("/transformation/chem/") + 1)

/// The sorted keys of a record list.
/proc/dq_xform_sorted_keys(list/rules)
	var/list/keys = list()
	for(var/key in rules)
		keys += key
	sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc))
	return keys

/// A pin file's rows as key => value.
/proc/dq_xform_pin_read(name)
	. = list()
	for(var/line in dq_snapshot_file_rows("[DQ_XFORM_PIN_DIR][name].txt"))
		var/at = findtext(line, " => ")
		if(!at)
			continue
		.[copytext(line, 1, at)] = copytext(line, at + 4)

/// Writes key => value rows over a pin file (under `dir`).
/proc/dq_xform_pin_write(dir, name, list/rows)
	var/file_name = "[dir][name].txt"
	fdel(file_name)
	var/list/lines = list()
	for(var/key in dq_xform_sorted_keys(rows))
		lines += "[key] => [rows[key]]"
	text2file("[jointext(lines, "\n")]\n", file_name)

/// Compares the rows a run made with the recorded file: null when they agree, else the report. A missing or empty file is recorded instead.
/proc/dq_xform_pin_compare(name, list/rows)
	var/list/expected = dq_xform_pin_read(name)
	if(dq_snapshot_blessing() || !length(expected))
		dq_xform_pin_write(DQ_XFORM_PIN_DIR, name, rows)
		fdel("data/test-snapshots/xform/[name].txt")
		log_test("xform pin [name]: recorded [length(rows)] row(s)")
		return null
	var/list/problems = list()
	for(var/key in dq_xform_sorted_keys(rows))
		if(isnull(expected[key]))
			problems += "new: [key] => [copytext(rows[key], 1, 300)]"
		else if(expected[key] != rows[key])
			problems += "changed: [key]\n   was: [copytext(expected[key], 1, 400)]\n   now: [copytext(rows[key], 1, 400)]"
	for(var/key in expected)
		if(isnull(rows[key]))
			problems += "missing: [key]"
	if(!length(problems))
		fdel("data/test-snapshots/xform/[name].txt")
		return null
	dq_xform_pin_write("data/test-snapshots/xform/", name, rows)
	var/report = "[length(problems)] xform pin row(s) of [name] differ (current rows in data/test-snapshots/xform/[name].txt):"
	var/shown = 0
	for(var/problem in problems)
		report += "\n[problem]"
		if(++shown >= 40)
			report += "\n... and [length(problems) - shown] more"
			break
	return report

/// What a holder contains, sorted: `id:volume id:volume`.
/proc/dq_xform_contents_text(datum/reagents/H)
	var/list/parts = list()
	for(var/datum/reagent/R as anything in H.reagent_list)
		parts += "[R.id]:[round(R.volume, 0.0001)]"
	sortTim(parts, GLOBAL_PROC_REF(cmp_text_asc))
	return length(parts) ? jointext(parts, " ") : "-"

/// The atoms around `T` that are not turfs, landmarks or `skip`: the scene a settle may add to.
/proc/dq_xform_scene(turf/T, atom/skip)
	. = list()
	for(var/atom/movable/AM in range(2, T))
		if(AM == skip || istype(AM, /obj/effect/landmark))
			continue
		. += AM

/// Contract events published, deduplicated or rejected so far: the sum counts every emission.
/proc/dq_xform_contract_emissions()
	return SScontracts ? SScontracts.events_published + SScontracts.events_deduplicated + SScontracts.events_rejected : 0

/// What is new around `T` since `before` (a dq_xform_scene() list), as sorted `type+count`; the new atoms are deleted.
/proc/dq_xform_scene_delta(turf/T, atom/skip, list/before)
	var/list/counts = list()
	for(var/atom/movable/AM in dq_xform_scene(T, skip))
		if(AM in before)
			continue
		counts["[AM.type]"]++
		qdel(AM)
	var/list/parts = list()
	for(var/type in counts)
		parts += "[type]+[counts[type]]"
	sortTim(parts, GLOBAL_PROC_REF(cmp_text_asc))
	return length(parts) ? jointext(parts, ",") : "-"

/// Puts a rule's inputs in a holder, scaled, and tops its catalysts up to their minimum. The reagents are added without reacting.
/proc/dq_xform_fill(datum/reagents/H, list/takes, list/catalysts)
	for(var/id in takes)
		H.add_reagent(id, takes[id] * DQ_XFORM_SCALE, safety = 1)
	for(var/id in catalysts)
		var/short = catalysts[id] - H.get_reagent_amount(id)
		if(short > 0)
			H.add_reagent(id, short, safety = 1)

/// The union of two rules' inputs: each reagent at the larger amount.
/proc/dq_xform_union(list/a, list/b)
	. = list()
	for(var/id in a)
		.[id] = a[id]
	for(var/id in b)
		.[id] = max(.[id] || 0, b[id])

/// Sets the gas of a distilling tester up for a rule (what /obj/distilling_tester/proc/test_distilling() does before it settles).
/proc/dq_xform_distill_setup(obj/distilling_tester/D, datum/xform_pin_rule/R)
	QDEL_SWAP(D.GM, new /datum/gas_mixture)
	if(R.require_gas)
		D.GM.adjust_gas(R.require_gas, 100)
	else
		if(R.rejects_gas == GAS_N2)
			D.GM.adjust_gas(GAS_O2, 100 - LINDA_GAS_AMT(D.GM, GAS_O2))
		else
			D.GM.adjust_gas(GAS_N2, 100 - LINDA_GAS_AMT(D.GM, GAS_N2))
	if(R.min_pressure)
		heat_set(D.GM, (R.min_pressure * CELL_VOLUME) / (LINDA_GAS_AMT(D.GM, R.require_gas) * R_IDEAL_GAS_EQUATION))

/// A subject for a rule: its slime extract, a distilling tester, or a beaker, on `T`, holding room for anything.
/proc/dq_xform_make_subject(datum/xform_pin_rule/R, turf/T, subject_type = null)
	var/obj/subject
	if(R.family == DQ_XFORM_FAMILY_DISTILLING)
		subject = new /obj/distilling_tester(T)
	else if(subject_type && ispath(subject_type, /obj/item/slime_extract))
		subject = new subject_type(T)
	else
		subject = new /obj/item/reagent_containers/glass/beaker(T)
	subject.reagents.maximum_volume = DQ_XFORM_VOLUME
	return subject

// ---- the outcome pin ----

/datum/unit_test/dq_xform_outcome_pin
	tier = TEST_TIER_EXHAUSTIVE
	is_sweep_test = TRUE
	/// The rules a settle fired, in order (filled by the notice).
	var/list/fired_keys = list()

/datum/unit_test/dq_xform_outcome_pin/proc/on_reacted(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/reagents_holder_reacted/event = N
	for(var/rule in event.rules)
		fired_keys += dq_xform_pin_key_of(rule)

/// Settles `subject` once and returns the row text of what happened. `before_scene` is dq_xform_scene() of the subject's turf before the fill.
/datum/unit_test/dq_xform_outcome_pin/proc/settle(obj/subject, turf/T)
	fired_keys = list()
	var/list/scene = dq_xform_scene(T, subject)
	var/emitted = dq_xform_contract_emissions()
	rand_seed(DQ_XFORM_SEED)
	observe(subject.reagents, /datum/notice/reagents_holder_reacted, src, then(PROC_REF(on_reacted)))
	subject.reagents.handle_reactions()
	unobserve(subject.reagents, /datum/notice/reagents_holder_reacted, src)
	var/uses = "-"
	if(istype(subject, /obj/item/slime_extract))
		var/obj/item/slime_extract/extract = subject
		uses = "[extract.uses]"
	return "fired=[length(fired_keys) ? jointext(fired_keys, ",") : "-"]; end=[dq_xform_contents_text(subject.reagents)]; spawned=[dq_xform_scene_delta(T, subject, scene)]; contract=[dq_xform_contract_emissions() - emitted]; uses=[uses]"

/datum/unit_test/dq_xform_outcome_pin/Run()
	var/list/rules = dq_xform_pin_rules()
	var/turf/T = test_floor()
	var/list/rows = list()
	var/list/keys = dq_xform_sorted_keys(rules)
	log_test("xform outcome pin: [length(keys)] rule(s)")
	for(var/key in keys)
		var/datum/xform_pin_rule/R = rules[key]
		rows[key] = row_for(R, T)
	var/failure = dq_xform_pin_compare("chem_outcome", rows)
	TEST_ASSERT(isnull(failure), failure)

/datum/unit_test/dq_xform_outcome_pin/proc/row_for(datum/xform_pin_rule/R, turf/T)
	var/obj/subject = dq_xform_make_subject(R, T, R.subject_type)
	var/text = "important=[R.important ? 1 : 0]; "
	if(istype(subject, /obj/distilling_tester))
		var/obj/distilling_tester/tester = subject
		text += distilling_row(R, tester, T)
	else
		dq_xform_fill(subject.reagents, R.takes, R.catalysts)
		text += "match=[matches(R, subject.reagents) ? 1 : 0]; [settle(subject, T)]"
	qdel(subject)
	return text

/// Whether the rule's own test passes on a holder right now (xform_matches(): the old can_happen()).
/datum/unit_test/dq_xform_outcome_pin/proc/matches(datum/xform_pin_rule/R, datum/reagents/H)
	return xform_matches(R.rule, H)

/// A distilling rule at the ends and the middle of its window, and a degree outside it either way.
/datum/unit_test/dq_xform_outcome_pin/proc/distilling_row(datum/xform_pin_rule/R, obj/distilling_tester/D, turf/T)
	var/list/parts = list()
	var/list/temps = list("p0" = R.temp_lo, "p50" = (R.temp_lo + R.temp_hi) / 2, "p100" = R.temp_hi, "below" = R.temp_lo - 1, "above" = R.temp_hi + 1)
	for(var/label in temps)
		D.reagents.clear_reagents()
		dq_xform_distill_setup(D, R)
		dq_xform_fill(D.reagents, R.takes, R.catalysts)
		D.current_temp = temps[label]
		var/scene_before = dq_xform_scene(T, D)
		rand_seed(DQ_XFORM_SEED)
		D.reagents.handle_reactions()
		var/product = R.result ? round(D.reagents.get_reagent_amount(R.result), 0.0001) : "-"
		parts += "[label]=[product]"
		if(label == "p50")
			parts += "end50=[dq_xform_contents_text(D.reagents)]"
			parts += "gas50=[round(D.GM.return_temperature(), 0.01)]"
			parts += "spawned50=[dq_xform_scene_delta(T, D, scene_before)]"
		else
			dq_xform_scene_delta(T, D, scene_before)
	return jointext(parts, "; ")

// ---- the overlap pin ----

/datum/unit_test/dq_xform_overlap_pin
	tier = TEST_TIER_EXHAUSTIVE
	is_sweep_test = TRUE
	var/list/fired_keys = list()

/datum/unit_test/dq_xform_overlap_pin/proc/on_reacted(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/reagents_holder_reacted/event = N
	for(var/rule in event.rules)
		fired_keys += dq_xform_pin_key_of(rule)

/// The rules that share their first input (the bucket the legacy index put them in), per family: anchor text => list of records.
/datum/unit_test/dq_xform_overlap_pin/proc/buckets(list/rules)
	var/list/by_anchor = list()
	for(var/key in dq_xform_sorted_keys(rules))
		var/datum/xform_pin_rule/R = rules[key]
		var/anchor = "[R.family]|[R.takes[1]]"
		if(R.family == DQ_XFORM_FAMILY_SLIME)
			anchor += "|[R.subject_type]"
		LAZYADD(by_anchor[anchor], R)
	return by_anchor

/datum/unit_test/dq_xform_overlap_pin/Run()
	var/list/rules = dq_xform_pin_rules()
	var/turf/T = test_floor()
	var/list/rows = list()
	var/list/by_anchor = buckets(rules)
	var/list/anchors = dq_xform_sorted_keys(by_anchor)
	for(var/anchor in anchors)
		var/list/bucket = by_anchor[anchor]
		for(var/i in 1 to length(bucket))
			for(var/j in i + 1 to length(bucket))
				var/datum/xform_pin_rule/A = bucket[i]
				var/datum/xform_pin_rule/B = bucket[j]
				var/row = pair_row(A, B, T)
				if(row)
					rows["[A.key] + [B.key]"] = row
	log_test("xform overlap pin: [length(rows)] pair(s)")
	var/failure = dq_xform_pin_compare("chem_overlap", rows)
	TEST_ASSERT(isnull(failure), failure)

/// The row for a pair, or null when the two cannot meet (their temperature windows do not overlap).
/datum/unit_test/dq_xform_overlap_pin/proc/pair_row(datum/xform_pin_rule/A, datum/xform_pin_rule/B, turf/T)
	var/temperature
	if(A.family == DQ_XFORM_FAMILY_DISTILLING)
		var/lo = max(A.temp_lo, B.temp_lo)
		var/hi = min(A.temp_hi, B.temp_hi)
		if(lo > hi)
			return null
		temperature = (lo + hi) / 2
	var/obj/subject = dq_xform_make_subject(A, T, A.subject_type)
	if(istype(subject, /obj/distilling_tester))
		var/obj/distilling_tester/tester = subject
		dq_xform_distill_setup(tester, A)
		tester.current_temp = temperature
	dq_xform_fill(subject.reagents, dq_xform_union(A.takes, B.takes), dq_xform_union(A.catalysts, B.catalysts))
	fired_keys = list()
	var/list/scene = dq_xform_scene(T, subject)
	rand_seed(DQ_XFORM_SEED)
	observe(subject.reagents, /datum/notice/reagents_holder_reacted, src, then(PROC_REF(on_reacted)))
	subject.reagents.handle_reactions()
	unobserve(subject.reagents, /datum/notice/reagents_holder_reacted, src)
	var/row = "fired=[length(fired_keys) ? jointext(fired_keys, ",") : "-"]; end=[dq_xform_contents_text(subject.reagents)]; spawned=[dq_xform_scene_delta(T, subject, scene)]"
	qdel(subject)
	return row

// ---- the debug path ----

/// The audit and observability a reaction carried survive the conversion: an important rule is still marked and still logs, and a product still emits its
/// contract event. (Nothing calls log_chemical_reaction() on master, so nothing registers it on the notice either; the proc and the mark are what is kept.)
/datum/unit_test/dq_xform_debug_path

/datum/unit_test/dq_xform_debug_path/Run()
	var/datum/xform/K = xform_of(/transformation/chem/instant/kelotane)
	TEST_ASSERT(K, "kelotane is a compiled rule")
	TEST_ASSERT(K.important, "a rule marked important keeps the mark")
	var/before = length(GLOB.chemical_reaction_logs)
	log_chemical_reaction(test_floor(), K, 1)
	TEST_ASSERT_EQUAL(length(GLOB.chemical_reaction_logs), before + 1, "the chemistry log takes the rule's entry")
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker, test_floor())
	B.reagents.maximum_volume = 1000
	var/emitted = dq_xform_contract_emissions()
	B.reagents.add_reagent(REAGENT_ID_SILICON, 5)
	B.reagents.add_reagent(REAGENT_ID_CARBON, 5)
	TEST_ASSERT(B.reagents.has_reagent(REAGENT_ID_KELOTANE), "the rule fired")
	TEST_ASSERT(dq_xform_contract_emissions() > emitted, "its product emitted a contract event")
