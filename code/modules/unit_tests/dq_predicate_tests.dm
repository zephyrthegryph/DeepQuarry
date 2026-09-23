// Predicate language (code/datums/properties/predicates.dm): each clause kind,
// combinators, reason text, unit checking at compile, watch marking, and a
// table over sample actors and items.

// ---- Fixtures ----

/obj/item/dq_pred_test
	name = "predicate test item"
	w_class = ITEMSIZE_SMALL
	MATERIAL_BULK(MAT_STEEL, 1000)

/obj/item/dq_pred_test/heavy
	w_class = ITEMSIZE_LARGE
	MATERIAL_BULK(MAT_STEEL, 12000)

/obj/item/dq_pred_test/knife
	sharp = TRUE

/obj/item/dq_pred_test/welder
	tool_qualities = list(TOOL_WELDER)

/obj/item/dq_pred_test/welder/advanced
	tool_qualities = list(TOOL_WELDER = 2)

/obj/item/dq_pred_test/proc/dq_is_ready(mob/actor, atom/target, obj/item/held)
	return name == "ready" ? TRUE : "it isn't ready"

/proc/dq_pred_test_global(mob/actor, atom/target, obj/item/held)
	return istype(held, /obj/item/dq_pred_test/knife)

/// A handed mob whose hands are set directly: r_hand is the active hand.
/mob/living/dq_pred_test

/mob/living/dq_pred_test/dq_has_free_hand()
	return !l_hand || !r_hand

/mob/living/dq_pred_test/proc/hold(obj/item/right, obj/item/left)
	r_hand = right
	l_hand = left
	hand = null

/datum/predicate/dq_test_weld_light
	name = "weld a light thing"
	test_only = TRUE
	spec = list(
		REQ_REACH_ADJACENT,
		REQ_TOOL_TIER(TOOL_WELDER, 2),
		REQ_BELOW(PRED_TARGET, PROP_MASS, KG(5)),
	)

/datum/predicate/dq_test_bad_units
	test_only = TRUE
	spec = list(REQ_BELOW(PRED_TARGET, PROP_MASS, KELVIN(373)))

// A channel-backed temperature, for watch marking. Built into a private registry.
/datum/property_def/dq_pred_test_temperature
	id = "dq_pred_test_temperature"
	name = "Temperature"
	unit = PROP_UNIT_KELVIN
	aggregator = PROP_AGG_MAX
	high_word = "hot"
	low_word = "cold"
	test_only = TRUE

/datum/property_provider/dq_pred_test_domain
	property = "dq_pred_test_temperature"
	source = PROP_SOURCE_DOMAIN
	applies_to = /obj
	unit = PROP_UNIT_KELVIN
	test_only = TRUE

/// A floor turf with four more open floor turfs east of it, for reach tests.
/datum/unit_test/proc/dq_pred_open_row()
	for(var/turf/simulated/floor/T in world)
		var/turf/cur = T
		var/ok = TRUE
		for(var/i in 1 to 4)
			cur = get_step(cur, EAST)
			if(!istype(cur, /turf/simulated/floor) || cur.density)
				ok = FALSE
				break
		if(ok)
			return T
	return null

/datum/unit_test/proc/dq_pred(list/spec, label = "test")
	var/datum/predicate/P = new
	P.name = label
	P.spec = spec
	P.compile()
	return P

// ---- Clause kinds ----

/datum/unit_test/dq_predicate_clauses

/datum/unit_test/dq_predicate_clauses/Run()
	var/mob/living/dq_pred_test/actor = allocate(/mob/living/dq_pred_test)
	var/obj/item/dq_pred_test/light = allocate(/obj/item/dq_pred_test)
	var/obj/item/dq_pred_test/heavy/heavy = allocate(/obj/item/dq_pred_test/heavy)
	var/obj/item/dq_pred_test/knife/knife = allocate(/obj/item/dq_pred_test/knife)
	var/obj/item/dq_pred_test/welder/welder = allocate(/obj/item/dq_pred_test/welder)
	var/obj/item/dq_pred_test/welder/advanced/advanced = allocate(/obj/item/dq_pred_test/welder/advanced)

	// Tags.
	var/datum/predicate/sharp = dq_pred(list(REQ_TAG(PRED_TARGET, TAG_SHARP)))
	TEST_ASSERT(sharp.check(actor, knife, null), "the knife is sharp")
	TEST_ASSERT_EQUAL(sharp.why_not(actor, light, null), "must be sharp", "tag reason")
	TEST_ASSERT_NULL(sharp.why_not(actor, knife, null), "a pass has no reason")
	var/datum/predicate/blunt = dq_pred(list(REQ_NO_TAG(PRED_TARGET, TAG_SHARP)))
	TEST_ASSERT(blunt.check(actor, light, null), "negated tag passes on a blunt item")
	TEST_ASSERT_EQUAL(blunt.why_not(actor, knife, null), "must not be sharp", "negated tag reason")
	var/datum/predicate/held_sharp = dq_pred(list(REQ_TAG(PRED_HELD, TAG_SHARP)))
	TEST_ASSERT_EQUAL(held_sharp.why_not(actor, light, null), "needs something sharp in hand", "held tag reason with empty hands")
	TEST_ASSERT(held_sharp.check(actor, light, knife), "held knife is sharp")

	// Comparisons with units.
	var/datum/predicate/under5 = dq_pred(list(REQ_BELOW(PRED_TARGET, PROP_MASS, KG(5))))
	TEST_ASSERT(under5.check(actor, light, null), "1 kg is below 5 kg")
	TEST_ASSERT_EQUAL(under5.why_not(actor, heavy, null), "too heavy: 12 kg > 5 kg", "comparison reason")
	var/datum/predicate/over5 = dq_pred(list(REQ_ABOVE(PRED_TARGET, PROP_MASS, KG(5))))
	TEST_ASSERT_EQUAL(over5.why_not(actor, light, null), "too light: 1 kg < 5 kg", "low reason")
	var/datum/predicate/at_most1 = dq_pred(list(REQ_AT_MOST(PRED_TARGET, PROP_MASS, KG(1))))
	TEST_ASSERT(at_most1.check(actor, light, null), "1 kg is at most 1 kg")
	var/datum/predicate/below1 = dq_pred(list(REQ_BELOW(PRED_TARGET, PROP_MASS, KG(1))))
	TEST_ASSERT_EQUAL(below1.why_not(actor, light, null), "too heavy: 1 kg, must be below 1 kg", "equal-value reason")
	var/datum/predicate/at_least = dq_pred(list(REQ_AT_LEAST(PRED_TARGET, PROP_SIZE_CLASS, SIZE_CLASS(ITEMSIZE_LARGE))))
	TEST_ASSERT(at_least.check(actor, heavy, null), "large is at least large")
	TEST_ASSERT_EQUAL(at_least.why_not(actor, light, null), "too small: size [ITEMSIZE_SMALL] < size [ITEMSIZE_LARGE]", "size reason")
	var/datum/predicate/exact = dq_pred(list(REQ_EQUALS(PRED_TARGET, PROP_SIZE_CLASS, SIZE_CLASS(ITEMSIZE_SMALL))))
	TEST_ASSERT(exact.check(actor, light, null), "equality")
	TEST_ASSERT_EQUAL(exact.why_not(actor, heavy, null), "size class must be size [ITEMSIZE_SMALL], is size [ITEMSIZE_LARGE]", "equality reason")
	var/datum/predicate/not_under5 = dq_pred(list(REQ_NOT(REQ_BELOW(PRED_TARGET, PROP_MASS, KG(5)))))
	TEST_ASSERT(not_under5.check(actor, heavy, null), "NOT below 5 kg passes at 12 kg")
	TEST_ASSERT_EQUAL(not_under5.why_not(actor, light, null), "too light: 1 kg < 5 kg", "NOT inverts the comparison and its reason")
	var/datum/predicate/band = dq_pred(list(REQ_BETWEEN(PRED_TARGET, PROP_MASS, KG(0.5), KG(2))))
	TEST_ASSERT(band.check(actor, light, null), "1 kg is within 0.5..2 kg")
	TEST_ASSERT_EQUAL(band.why_not(actor, heavy, null), "too heavy: 12 kg, must be 0.5 kg to 2 kg", "band reason")
	var/datum/predicate/outside = dq_pred(list(REQ_NOT(REQ_BETWEEN(PRED_TARGET, PROP_MASS, KG(0.5), KG(2)))))
	TEST_ASSERT(outside.check(actor, heavy, null), "negated band passes outside")
	TEST_ASSERT(!outside.check(actor, light, null), "negated band fails inside")
	var/datum/predicate/held_heavier = dq_pred(list(REQ_COMPARE(PRED_HELD, PROP_MASS, PRED_CMP_GT, PRED_TARGET, PROP_MASS)))
	TEST_ASSERT(held_heavier.check(actor, light, heavy), "held 12 kg outweighs a 1 kg target")
	TEST_ASSERT_EQUAL(held_heavier.why_not(actor, heavy, light), "the held item is too light: 1 kg < 12 kg", "relational reason")
	TEST_ASSERT_EQUAL(held_heavier.why_not(actor, heavy, null), "needs something in hand", "relational with nothing held")

	// Tools and tiers.
	var/datum/predicate/weld = dq_pred(list(REQ_TOOL(TOOL_WELDER)))
	TEST_ASSERT(weld.check(actor, light, welder), "a welder welds")
	TEST_ASSERT_EQUAL(weld.why_not(actor, light, knife), "needs a welder", "tool reason")
	var/datum/predicate/weld2 = dq_pred(list(REQ_TOOL_TIER(TOOL_WELDER, 2)))
	TEST_ASSERT(!weld2.check(actor, light, welder), "a plain welder is tier 1")
	TEST_ASSERT(weld2.check(actor, light, advanced), "the advanced welder is tier 2")
	TEST_ASSERT_EQUAL(weld2.why_not(actor, light, welder), "needs a welder (tier 2)", "tier reason")
	TEST_ASSERT_EQUAL(dq_pred(list(REQ_TOOL(TOOL_ANALYZER))).why_not(actor, light, null), "needs an analyzer", "article")

	// Hands.
	var/datum/predicate/free = dq_pred(list(REQ_HAND_FREE))
	actor.hold(null, null)
	TEST_ASSERT(free.check(actor, light, null), "empty hands are free")
	actor.hold(welder, knife)
	TEST_ASSERT_EQUAL(free.why_not(actor, light, welder), "needs a free hand", "hands full")
	var/datum/predicate/in_hand = dq_pred(list(REQ_TARGET_IN_HAND))
	TEST_ASSERT(in_hand.check(actor, knife, welder), "the knife is in the off hand")
	TEST_ASSERT_EQUAL(in_hand.why_not(actor, light, welder), "must be held in hand", "in-hand reason")
	actor.hold(null, null)
	var/datum/predicate/holding = dq_pred(list(REQ_HOLDING))
	TEST_ASSERT_EQUAL(holding.why_not(actor, light, null), "needs something in hand", "holding reason")
	var/datum/predicate/empty = dq_pred(list(REQ_EMPTY_HANDED))
	TEST_ASSERT_EQUAL(empty.why_not(actor, light, knife), "needs an empty hand", "empty-handed reason")

	// Reach and self.
	var/turf/start = dq_pred_open_row()
	TEST_ASSERT(start, "found five open tiles in a row")
	actor.forceMove(start)
	var/obj/item/dq_pred_test/near = allocate(/obj/item/dq_pred_test, locate(start.x + 1, start.y, start.z))
	var/obj/item/dq_pred_test/far = allocate(/obj/item/dq_pred_test, locate(start.x + 4, start.y, start.z))
	var/datum/predicate/adjacent = dq_pred(list(REQ_REACH_ADJACENT))
	TEST_ASSERT(adjacent.check(actor, near, null), "one tile away is adjacent")
	TEST_ASSERT_EQUAL(adjacent.why_not(actor, far, null), "too far away", "reach reason")
	var/datum/predicate/reach3 = dq_pred(list(REQ_REACH(3)))
	TEST_ASSERT(reach3.check(actor, near, null), "within 3 tiles")
	TEST_ASSERT_EQUAL(reach3.why_not(actor, far, null), "too far away (more than 3 tiles)", "range reason")
	var/datum/predicate/self = dq_pred(list(REQ_SELF))
	TEST_ASSERT(self.check(actor, actor, null), "self")
	TEST_ASSERT_EQUAL(dq_pred(list(REQ_NOT_SELF)).why_not(actor, actor, null), "can't be done to yourself", "not-self reason")

	// Procs.
	var/datum/predicate/ready = dq_pred(list(REQ_TARGET_STATE(/obj/item/dq_pred_test/proc/dq_is_ready)))
	light.name = "ready"
	TEST_ASSERT(ready.check(actor, light, null), "proc returns TRUE")
	light.name = "unready"
	TEST_ASSERT_EQUAL(ready.why_not(actor, light, null), "it isn't ready", "a proc's text is the reason")
	TEST_ASSERT_EQUAL(ready.why_not(actor, actor, null), "not possible right now", "a subject without the proc fails")
	var/datum/predicate/global_proc = dq_pred(list(REQ_PROC(/proc/dq_pred_test_global, "needs the knife")))
	TEST_ASSERT(global_proc.check(actor, light, knife), "global proc passes")
	TEST_ASSERT_EQUAL(global_proc.why_not(actor, light, welder), "needs the knife", "FALSE uses the declared reason")

// ---- Combinators ----

/datum/unit_test/dq_predicate_combinators

/datum/unit_test/dq_predicate_combinators/Run()
	var/mob/living/dq_pred_test/actor = allocate(/mob/living/dq_pred_test)
	var/obj/item/dq_pred_test/light = allocate(/obj/item/dq_pred_test)
	var/obj/item/dq_pred_test/heavy/heavy = allocate(/obj/item/dq_pred_test/heavy)
	var/obj/item/dq_pred_test/knife/knife = allocate(/obj/item/dq_pred_test/knife)
	var/obj/item/dq_pred_test/welder/welder = allocate(/obj/item/dq_pred_test/welder)

	// ALL reports the first failing clause, in declaration order.
	var/datum/predicate/all = dq_pred(list(REQ_TOOL(TOOL_WELDER), REQ_BELOW(PRED_TARGET, PROP_MASS, KG(5))))
	TEST_ASSERT_EQUAL(all.why_not(actor, heavy, knife), "needs a welder", "first failing clause wins")
	TEST_ASSERT_EQUAL(all.why_not(actor, heavy, welder), "too heavy: 12 kg > 5 kg", "then the next")
	TEST_ASSERT(all.check(actor, light, welder), "both pass")

	// ANY joins its children's reasons.
	var/datum/predicate/any = dq_pred(list(REQ_ANY(REQ_TOOL(TOOL_WELDER), REQ_TAG(PRED_HELD, TAG_SHARP))))
	TEST_ASSERT(any.check(actor, light, welder), "welder satisfies ANY")
	TEST_ASSERT(any.check(actor, light, knife), "knife satisfies ANY")
	TEST_ASSERT_EQUAL(any.why_not(actor, light, null), "needs a welder or needs something sharp in hand", "ANY reason")

	// NOT over ALL is ANY of the negations (De Morgan), and nests.
	var/datum/predicate/not_all = dq_pred(list(REQ_NOT(REQ_ALL(REQ_TAG(PRED_TARGET, TAG_SHARP), REQ_BELOW(PRED_TARGET, PROP_MASS, KG(5))))))
	TEST_ASSERT(!not_all.check(actor, knife, null), "a light knife is sharp AND light")
	TEST_ASSERT(not_all.check(actor, light, null), "not sharp")
	TEST_ASSERT(not_all.check(actor, heavy, null), "not light")
	TEST_ASSERT_EQUAL(not_all.why_not(actor, knife, null), "must not be sharp or too light: 1 kg < 5 kg", "negated ALL reason")
	var/datum/predicate/double_not = dq_pred(list(REQ_NOT(REQ_NOT(REQ_TAG(PRED_TARGET, TAG_SHARP)))))
	TEST_ASSERT(double_not.check(actor, knife, null), "NOT NOT is the clause")
	TEST_ASSERT(!double_not.check(actor, light, null), "NOT NOT fails like the clause")

	// BECAUSE replaces a reason, including a whole group's.
	var/datum/predicate/because = dq_pred(list(REQ_BECAUSE(REQ_ALL(REQ_TOOL(TOOL_WELDER), REQ_HOLDING), "needs a lit welder")))
	TEST_ASSERT_EQUAL(because.why_not(actor, light, null), "needs a lit welder", "BECAUSE on a group")
	TEST_ASSERT_EQUAL(dq_pred(list(REQ_BECAUSE(REQ_TAG(PRED_TARGET, TAG_SHARP), "too dull"))).why_not(actor, light, null), "too dull", "BECAUSE on a leaf")

	// A single clause works as a whole spec.
	TEST_ASSERT(dq_pred(REQ_TAG(PRED_TARGET, TAG_SHARP)).check(actor, knife, null), "a bare clause is a spec")

	// Shared singletons: compiled once per declaration.
	TEST_ASSERT(PREDICATE(/datum/predicate/dq_test_weld_light) == PREDICATE(/datum/predicate/dq_test_weld_light), "one instance per type")
	var/datum/predicate/keyed = dq_predicate_for("dq_pred_test_key", list(REQ_HOLDING))
	TEST_ASSERT(keyed == dq_predicate_for("dq_pred_test_key", list(REQ_HAND_FREE)), "keyed specs compile once")
	TEST_ASSERT(PREDICATE_PASSES(keyed, actor, light, knife), "keyed predicate evaluates")
	TEST_ASSERT_EQUAL(PREDICATE_REASON(keyed, actor, light, null), "needs something in hand", "PREDICATE_REASON")

// ---- Compile-time validation ----

/datum/unit_test/dq_predicate_validation

/datum/unit_test/dq_predicate_validation/Run()
	// Declared predicates compile cleanly at boot.
	for(var/error in dq_predicates_validate(dq_property_registry()))
		TEST_FAIL(error)
	var/datum/predicate/fixture = PREDICATE(/datum/predicate/dq_test_weld_light)
	TEST_ASSERT(isnull(fixture.errors), "the fixture compiles")

	// Kelvin against kilograms fails, and the predicate then always fails.
	var/datum/predicate/bad = new /datum/predicate/dq_test_bad_units
	TEST_ASSERT(!bad.compile(), "a unit mismatch fails compilation")
	TEST_ASSERT(dq_errors_mention(bad.errors, "compares mass (kg) with 373 K"), "unit mismatch reported: [jointext(bad.errors, "; ")]")
	var/obj/item/dq_pred_test/light = allocate(/obj/item/dq_pred_test)
	TEST_ASSERT(!bad.check(null, light, null), "an invalid predicate never passes")

	var/list/cases = list(
		"bare number" = list(list(PRED_OP_CMP, PRED_TARGET, PROP_MASS, PRED_CMP_LT, 5)),
		"unknown property dq_nope" = list(REQ_BELOW(PRED_TARGET, "dq_nope", KG(5))),
		"sharp is a tag" = list(REQ_BELOW(PRED_TARGET, TAG_SHARP, RATIO(1))),
		"mass is a measure" = list(REQ_TAG(PRED_TARGET, PROP_MASS)),
		"unknown tag dq_nope" = list(REQ_TAG(PRED_TARGET, "dq_nope")),
		"unknown subject" = list(REQ_TAG(7, TAG_SHARP)),
		"bounds reversed" = list(REQ_BETWEEN(PRED_TARGET, PROP_MASS, KG(5), KG(1))),
		"compares mass (kg) with melting_point (K)" = list(REQ_COMPARE(PRED_TARGET, PROP_MASS, PRED_CMP_LT, PRED_HELD, PROP_MELTING_POINT)),
		"unknown comparison" = list(REQ_COMPARE(PRED_TARGET, PROP_MASS, "~", PRED_HELD, PROP_MASS)),
		"unknown clause" = list(list("frobnicate")),
		"has no clauses" = list(),
		"REQ_TOOL needs" = list(REQ_TOOL_TIER(TOOL_WELDER, 0)),
	)
	for(var/expected in cases)
		var/datum/predicate/P = new
		P.name = expected
		P.spec = cases[expected]
		TEST_ASSERT(!P.compile(), "[expected] should not compile")
		TEST_ASSERT(dq_errors_mention(P.errors, expected), "expected an error mentioning '[expected]', got [jointext(P.errors || list(), "; ")]")

// ---- Watch marking ----

/datum/unit_test/dq_predicate_watchable

/datum/unit_test/dq_predicate_watchable/Run()
	var/datum/property_registry/registry = new(
		list(new /datum/property_def/dq_pred_test_temperature, new /datum/property_def/mass),
		list(new /datum/property_provider/dq_pred_test_domain, new /datum/property_provider/material/mass),
	)
	var/datum/predicate/P = new
	P.name = "watch test"
	P.spec = list(
		REQ_ABOVE(PRED_TARGET, "dq_pred_test_temperature", KELVIN(373)),
		REQ_NOT(REQ_BETWEEN(PRED_TARGET, "dq_pred_test_temperature", KELVIN(200), KELVIN(300))),
		REQ_COMPARE(PRED_TARGET, "dq_pred_test_temperature", PRED_CMP_GT, PRED_ACTOR, "dq_pred_test_temperature"),
		REQ_BELOW(PRED_TARGET, PROP_MASS, KG(5)),
		REQ_EQUALS(PRED_TARGET, "dq_pred_test_temperature", KELVIN(300)),
		REQ_HAND_FREE,
	)
	TEST_ASSERT(P.compile(registry), "compiles against the private registry: [jointext(P.errors || list(), "; ")]")
	TEST_ASSERT_EQUAL(length(P.watchable), 3, "threshold, band and difference on the channel-backed property")
	var/datum/pred_node/cmp/threshold = P.watchable[1]
	TEST_ASSERT_EQUAL(threshold.watch_kind, PRED_WATCH_THRESHOLD, "threshold kind")
	TEST_ASSERT_EQUAL(threshold.op, PRED_CMP_GT, "threshold op")
	TEST_ASSERT_EQUAL(threshold.value, 373, "threshold value")
	var/datum/pred_node/band/band = P.watchable[2]
	TEST_ASSERT_EQUAL(band.watch_kind, PRED_WATCH_BAND, "band kind")
	TEST_ASSERT(band.outside, "the negated band is marked outside")
	var/datum/pred_node/rel/difference = P.watchable[3]
	TEST_ASSERT_EQUAL(difference.watch_kind, PRED_WATCH_DIFFERENCE, "difference kind")

	// NOT folds into the threshold's operator.
	var/datum/predicate/negated = new
	negated.spec = list(REQ_NOT(REQ_ABOVE(PRED_TARGET, "dq_pred_test_temperature", KELVIN(373))))
	negated.compile(registry)
	var/datum/pred_node/cmp/inverted = negated.watchable[1]
	TEST_ASSERT_EQUAL(inverted.op, PRED_CMP_LTE, "NOT > is <=")

// ---- Table ----

/datum/unit_test/dq_predicate_table

/datum/unit_test/dq_predicate_table/Run()
	var/mob/living/dq_pred_test/actor = allocate(/mob/living/dq_pred_test)
	var/turf/start = dq_pred_open_row()
	TEST_ASSERT(start, "found five open tiles in a row")
	actor.forceMove(start)
	var/alist/items = alist(
		"light" = allocate(/obj/item/dq_pred_test, locate(start.x + 1, start.y, start.z)),
		"heavy" = allocate(/obj/item/dq_pred_test/heavy, locate(start.x + 1, start.y, start.z)),
		"far" = allocate(/obj/item/dq_pred_test, locate(start.x + 4, start.y, start.z)),
		"welder" = allocate(/obj/item/dq_pred_test/welder),
		"advanced" = allocate(/obj/item/dq_pred_test/welder/advanced),
		"knife" = allocate(/obj/item/dq_pred_test/knife),
	)
	var/datum/predicate/weld_light = PREDICATE(/datum/predicate/dq_test_weld_light)
	// target, held, other hand, expected reason (null = passes)
	var/list/rows = list(
		list("light", "advanced", null, null),
		list("light", "welder", null, "needs a welder (tier 2)"),
		list("light", "knife", null, "needs a welder (tier 2)"),
		list("light", null, null, "needs a welder (tier 2)"),
		list("heavy", "advanced", null, "too heavy: 12 kg > 5 kg"),
		list("far", "advanced", null, "too far away"),
		list("heavy", "knife", null, "needs a welder (tier 2)"),
		list("light", "advanced", "knife", null),
	)
	for(var/list/row as anything in rows)
		var/atom/target = items[row[1]]
		var/obj/item/held = row[2] ? items[row[2]] : null
		actor.hold(held, row[3] ? items[row[3]] : null)
		var/reason = weld_light.why_not(actor, target, held)
		TEST_ASSERT_EQUAL(reason, row[4], "[row[1]] with [row[2] || "nothing"]")
		TEST_ASSERT_EQUAL(weld_light.check(actor, target, held), isnull(row[4]), "check agrees with why_not for [row[1]] with [row[2] || "nothing"]")
