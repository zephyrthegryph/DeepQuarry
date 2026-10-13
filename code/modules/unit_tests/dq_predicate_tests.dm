// Real requirement fixture data and final-form behavior tests.
// ---- Fixtures ----

/obj/item/dq_pred_test
	name = "predicate test item"
	w_class = ITEMSIZE_SMALL
	MATERIAL_BULK(MAT_STEEL, 1000)

/obj/item/dq_pred_test/heavy
	w_class = ITEMSIZE_LARGE
	MATERIAL_BULK(MAT_STEEL, 12000)

/obj/item/dq_pred_test/knife

CAPABILITIES(/obj/item/dq_pred_test/knife)
	configure(item_combat(sharp = TRUE))

/obj/item/dq_pred_test/welder
	tool_qualities = list(TOOL_WELDER)

/obj/item/dq_pred_test/welder/advanced
	tool_qualities = list(TOOL_WELDER = 2)

/obj/item/dq_pred_test/proc/dq_is_ready(datum/act/op/A)
	return name == "ready" ? null : "it isn't ready"

/// A handed mob whose hands are set directly: r_hand is the active hand.
/mob/living/dq_pred_test

/mob/living/dq_pred_test/dq_has_free_hand()
	return !get_equipped_item(SLOT_ID_HAND_L) || !get_equipped_item(SLOT_ID_HAND_R)

/mob/living/dq_pred_test/has_hands_to_hold()
	return TRUE

/mob/living/dq_pred_test/proc/hold(obj/item/right, obj/item/left)
	for(var/obj/item/held as anything in get_all_held_items())
		if(loc)
			held.forceMove(loc)
		else
			held.moveToNullspace()
	move_into(src, SLOT_ID_HAND_R, right, src)
	move_into(src, SLOT_ID_HAND_L, left, src)
	set_hand(null)

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

// Native coverage of the existing numeric predicate clauses and ordered weld table.
// Existing dq_pred_test item/actor fixtures stay included until full test migration.
/datum/unit_test/dq_native_predicate_numeric
	abstract_type = /datum/unit_test/dq_native_predicate_numeric

/datum/unit_test/dq_native_predicate_numeric/proc/reason(datum/entry/part/req/R, mob/actor, datum/target, obj/item/held = null)
	var/datum/act/op/A = take(/datum/act/op)
	A.actor = actor
	A.target = target
	A.holder = target
	A.set_held_provider(held)
	try
		. = op_req_check(A, R)
	catch(var/exception/E)
		A.release()
		throw E
	A.release()

/datum/unit_test/dq_native_predicate_numeric/clauses/Run()
	var/mob/living/dq_pred_test/actor = allocate(/mob/living/dq_pred_test)
	var/obj/item/dq_pred_test/light = allocate(/obj/item/dq_pred_test)
	var/obj/item/dq_pred_test/heavy/heavy = allocate(/obj/item/dq_pred_test/heavy)
	TEST_ASSERT_EQUAL(dq_property(light, PROP_MASS), 1, "actual light material mass is 1 kg")
	TEST_ASSERT_EQUAL(dq_property(heavy, PROP_MASS), 12, "actual heavy material mass is 12 kg")
	TEST_ASSERT_NULL(reason(req_measure(PROP_MASS, SIM_COMPARE_LT, KG(5)), actor, light), "1 kg is below 5 kg")
	TEST_ASSERT_EQUAL(reason(req_measure(PROP_MASS, SIM_COMPARE_LT, KG(5)), actor, heavy), "too heavy: 12 kg > 5 kg", "exact old high reason")
	TEST_ASSERT_EQUAL(reason(req_measure(PROP_MASS, SIM_COMPARE_GT, KG(5)), actor, light), "too light: 1 kg < 5 kg", "exact old low reason")
	TEST_ASSERT_NULL(reason(req_measure(PROP_MASS, SIM_COMPARE_LTE, KG(1)), actor, light), "inclusive upper bound")
	TEST_ASSERT_EQUAL(reason(req_measure(PROP_MASS, SIM_COMPARE_LT, KG(1)), actor, light), "too heavy: 1 kg, must be below 1 kg", "strict equality refuses")
	TEST_ASSERT_NULL(reason(req_measure(PROP_SIZE_CLASS, SIM_COMPARE_GTE, SIZE_CLASS(ITEMSIZE_LARGE)), actor, heavy), "size inclusive lower bound")
	TEST_ASSERT_EQUAL(reason(req_measure(PROP_SIZE_CLASS, SIM_COMPARE_GTE, SIZE_CLASS(ITEMSIZE_LARGE)), actor, light), "too small: size [ITEMSIZE_SMALL] < size [ITEMSIZE_LARGE]", "exact old size reason")
	TEST_ASSERT_NULL(reason(req_measure(PROP_SIZE_CLASS, SIM_COMPARE_EQ, SIZE_CLASS(ITEMSIZE_SMALL)), actor, light), "size equality")
	TEST_ASSERT_EQUAL(reason(req_measure(PROP_SIZE_CLASS, SIM_COMPARE_EQ, SIZE_CLASS(ITEMSIZE_SMALL)), actor, heavy), "size class must be size [ITEMSIZE_SMALL], is size [ITEMSIZE_LARGE]", "size equality refusal")
	TEST_ASSERT_NULL(reason(req_measure_not(PROP_MASS, SIM_COMPARE_LT, KG(5)), actor, heavy), "inverted comparison passes")
	TEST_ASSERT_EQUAL(reason(req_measure_not(PROP_MASS, SIM_COMPARE_LT, KG(5)), actor, light), "too light: 1 kg < 5 kg", "NOT folds comparison and reason")
	TEST_ASSERT_NULL(reason(req_band(PROP_MASS, KG(0.5), KG(2)), actor, light), "inside band")
	TEST_ASSERT_EQUAL(reason(req_band(PROP_MASS, KG(0.5), KG(2)), actor, heavy), "too heavy: 12 kg, must be 0.5 kg to 2 kg", "exact band reason")
	TEST_ASSERT_NULL(reason(req_band(PROP_MASS, KG(0.5), KG(2), outside = TRUE), actor, heavy), "outside band")
	TEST_ASSERT(!isnull(reason(req_band(PROP_MASS, KG(0.5), KG(2), outside = TRUE), actor, light)), "outside band rejects inside")
	var/datum/entry/part/req/R = req_property_compare(PROP_MASS, SIM_COMPARE_GT, PROP_MASS, ON_HELD, ON_TARGET)
	TEST_ASSERT_NULL(reason(R, actor, light, heavy), "actual held 12 kg outweighs target 1 kg")
	TEST_ASSERT_EQUAL(reason(R, actor, heavy, light), "the held item is too light: 1 kg < 12 kg", "relative reason preserved")
	TEST_ASSERT_EQUAL(reason(R, actor, heavy), "needs something in hand", "missing held operand refuses")

/datum/unit_test/dq_native_predicate_numeric/validation/Run()
	for(var/kind in list("wrong unit", "bare number", "unknown property", "tag as measure", "unknown role", "reversed band", "cross units", "unknown comparator"))
		var/caught = FALSE
		try
			switch(kind)
				if("wrong unit")
					req_measure(PROP_MASS, SIM_COMPARE_LT, KELVIN(373))
				if("bare number")
					req_measure(PROP_MASS, SIM_COMPARE_LT, 5, null)
				if("unknown property")
					req_measure("dq_nope", SIM_COMPARE_LT, KG(5))
				if("tag as measure")
					req_measure(TAG_SHARP, SIM_COMPARE_LT, RATIO(1))
				if("unknown role")
					req_measure(PROP_MASS, SIM_COMPARE_LT, KG(5), of = 999)
				if("reversed band")
					req_band(PROP_MASS, KG(5), KG(1))
				if("cross units")
					req_property_compare(PROP_MASS, SIM_COMPARE_LT, PROP_MELTING_POINT)
				if("unknown comparator")
					req_measure(PROP_MASS, "~", KG(5))
		catch(var/exception/E)
			caught = TRUE
			TEST_ASSERT(length(E.name), "[kind] supplies a diagnostic")
		TEST_ASSERT(caught, "[kind] is genuinely rejected by native constructor")

/obj/item/dq_pred_test/proc/native_weld_tier_two(datum/act/op/A)
	var/obj/item/I = A.held_provider()
	return I && dq_tool_tier(I, TOOL_WELDER) >= 2 ? null : "needs a welder (tier 2)"

/datum/unit_test/dq_native_predicate_numeric/table/Run()
	var/mob/living/dq_pred_test/actor = allocate(/mob/living/dq_pred_test)
	var/turf/start = dq_pred_open_row()
	TEST_ASSERT(start, "real five-open-tile reach fixture exists")
	actor.forceMove(start)
	var/alist/items = alist(
		"light" = allocate(/obj/item/dq_pred_test, locate(start.x + 1, start.y, start.z)),
		"heavy" = allocate(/obj/item/dq_pred_test/heavy, locate(start.x + 1, start.y, start.z)),
		"far" = allocate(/obj/item/dq_pred_test, locate(start.x + 4, start.y, start.z)),
		"welder" = allocate(/obj/item/dq_pred_test/welder),
		"advanced" = allocate(/obj/item/dq_pred_test/welder/advanced),
		"knife" = allocate(/obj/item/dq_pred_test/knife),
	)
	var/datum/entry/part/req/plan = all_of(req_range(1, because = "too far away"), req(PROC_REF(native_weld_tier_two)), req_measure(PROP_MASS, SIM_COMPARE_LT, KG(5)))
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
		var/obj/item/target = items[row[1]]
		var/obj/item/held = row[2] ? items[row[2]] : null
		actor.hold(held, row[3] ? items[row[3]] : null)
		var/actual = reason(plan, actor, target, held)
		TEST_ASSERT_EQUAL(actual, row[4], "[row[1]] with [row[2]] preserves ordered old table refusal")
		TEST_ASSERT_EQUAL(isnull(actual), isnull(row[4]), "allowed/refused agrees for each actual row")

/datum/property_provider/dq_native_temperature
	property = "dq_pred_test_temperature"
	source = PROP_SOURCE_DOMAIN
	applies_to = /obj/item/dq_native_numeric_source
	unit = PROP_UNIT_KELVIN
	test_only = TRUE
/datum/property_provider/dq_native_temperature/instance_value(datum/D)
	var/obj/item/dq_native_numeric_source/F = D
	return F.value
/datum/property_provider/dq_native_temperature/requirement_read_keys(datum/D)
	var/obj/item/dq_native_numeric_source/F = D
	return list(list(F, nameof(F.value)))

/datum/unit_test/dq_native_predicate_numeric/watchable/Run()
	var/datum/property_def/D = allocate(/datum/property_def/dq_pred_test_temperature)
	var/datum/property_provider/P = allocate(/datum/property_provider/dq_native_temperature)
	var/datum/property_registry/registry = allocate(/datum/property_registry, list(D), list(P))
	TEST_ASSERT(!length(registry.errors), "actual Kelvin provider private registry validates")
	var/obj/item/dq_native_numeric_source/left = allocate(/obj/item/dq_native_numeric_source)
	var/obj/item/dq_native_numeric_source/right = allocate(/obj/item/dq_native_numeric_source)
	left.set_value(400)
	right.set_value(350)
	var/datum/act/op/A = take(/datum/act/op)
	A.target = left
	A.holder = left
	A.set_held_provider(right)
	var/datum/entry/part/req/T = req_measure("dq_pred_test_temperature", SIM_COMPARE_GT, KELVIN(373), registry = registry)
	var/datum/entry/part/req/B = req_band("dq_pred_test_temperature", KELVIN(200), KELVIN(300), outside = TRUE, registry = registry)
	var/datum/entry/part/req/C = req_property_compare("dq_pred_test_temperature", SIM_COMPARE_GT, "dq_pred_test_temperature", ON_TARGET, ON_HELD, registry = registry)
	var/datum/entry/part/req/all = all_of(T, B, C)
	TEST_ASSERT_EQUAL(all.children[1], T, "threshold remains first ordered requirement")
	TEST_ASSERT_EQUAL(all.children[2], B, "outside band remains second")
	TEST_ASSERT_EQUAL(all.children[3], C, "difference remains third")
	TEST_ASSERT_EQUAL(T.args["compare"], SIM_COMPARE_GT, "threshold comparator metadata retained")
	TEST_ASSERT_EQUAL(T.args["value"], 373, "threshold bound retained")
	TEST_ASSERT(B.args["outside"], "negated band representation retains outside")
	var/datum/entry/part/req/inverted = req_measure_not("dq_pred_test_temperature", SIM_COMPARE_GT, KELVIN(373), registry = registry)
	TEST_ASSERT_EQUAL(inverted.args["compare"], SIM_COMPARE_LTE, "NOT > folds to <=")
	TEST_ASSERT_NULL(op_req_check(A, all), "all actual Kelvin conditions initially hold")
	var/list/reads = all.read_keys(A)
	TEST_ASSERT(length(reads) >= 7, "ordered plan exposes each borrowed registry and both actual source dependencies")
	left.set_value(373)
	TEST_ASSERT(!isnull(op_req_check(A, T)), "strict threshold refuses equal value")
	TEST_ASSERT_NULL(op_req_check(A, inverted), "inverted threshold permits equal value")
	left.set_value(300)
	TEST_ASSERT(!isnull(op_req_check(A, B)), "outside band refuses inclusive high edge")
	left.set_value(200)
	TEST_ASSERT(!isnull(op_req_check(A, B)), "outside band refuses inclusive low edge")
	left.set_value(199)
	TEST_ASSERT_NULL(op_req_check(A, B), "outside band passes immediately below edge")
	left.set_value(400)
	right.set_value(400)
	TEST_ASSERT(!isnull(op_req_check(A, C)), "dynamic difference refuses equality")
	right.set_value(399)
	TEST_ASSERT_NULL(op_req_check(A, C), "dynamic difference recovers below left")
	left.set_value(null)
	TEST_ASSERT_EQUAL(op_req_check(A, inverted), "temperature unknown", "inverted threshold cannot silently accept absent value")
	A.release()


// Final null-or-reason test callbacks; no legacy predicate compiler is invoked.
/obj/item/dq_pred_test/proc/native_sharp(datum/act/op/A)
	return dq_has_tag(A.target, TAG_SHARP) ? null : "must be sharp"
/obj/item/dq_pred_test/proc/native_blunt(datum/act/op/A)
	return dq_has_tag(A.target, TAG_SHARP) ? "must not be sharp" : null
/obj/item/dq_pred_test/proc/native_held_sharp(datum/act/op/A)
	var/obj/item/I = A.held_provider()
	return I && dq_has_tag(I, TAG_SHARP) ? null : "needs something sharp in hand"
/obj/item/dq_pred_test/proc/native_welder(datum/act/op/A)
	var/obj/item/I = A.held_provider()
	return I && dq_tool_tier(I, TOOL_WELDER) >= 1 ? null : "needs a welder"
/obj/item/dq_pred_test/proc/native_analyzer(datum/act/op/A)
	var/obj/item/I = A.held_provider()
	return I && dq_tool_tier(I, TOOL_ANALYZER) >= 1 ? null : "needs an analyzer"
/obj/item/dq_pred_test/proc/native_free_hand(datum/act/op/A)
	return A.actor?.dq_has_free_hand() ? null : "needs a free hand"
/obj/item/dq_pred_test/proc/native_in_hand(datum/act/op/A)
	return A.actor && (A.actor.get_active_hand() == A.target || A.actor.get_inactive_hand() == A.target) ? null : "must be held in hand"
/obj/item/dq_pred_test/proc/native_holding(datum/act/op/A)
	return A.held_provider() ? null : "needs something in hand"
/obj/item/dq_pred_test/proc/native_empty(datum/act/op/A)
	return A.held_provider() ? "needs an empty hand" : null
/obj/item/dq_pred_test/proc/native_self(datum/act/op/A)
	return A.actor == A.target ? null : "can only be done to yourself"
/obj/item/dq_pred_test/proc/native_not_self(datum/act/op/A)
	return A.actor == A.target ? "can't be done to yourself" : null
/obj/item/dq_pred_test/proc/native_ready(datum/act/op/A)
	if(!istype(A.target, /obj/item/dq_pred_test))
		return "not possible right now"
	var/obj/item/dq_pred_test/I = A.target
	return I.dq_is_ready(A)
/obj/item/dq_pred_test/proc/native_knife(datum/act/op/A)
	return istype(A.held_provider(), /obj/item/dq_pred_test/knife) ? null : "needs the knife"

/datum/unit_test/dq_native_predicate_numeric/nonnumeric/Run()
	var/mob/living/dq_pred_test/actor = allocate(/mob/living/dq_pred_test)
	var/obj/item/dq_pred_test/light = allocate(/obj/item/dq_pred_test)
	var/obj/item/dq_pred_test/knife/knife = allocate(/obj/item/dq_pred_test/knife)
	var/obj/item/dq_pred_test/welder/welder = allocate(/obj/item/dq_pred_test/welder)
	var/obj/item/dq_pred_test/welder/advanced/advanced = allocate(/obj/item/dq_pred_test/welder/advanced)
	// Holder remains a real callback owner even when the target is the actor.
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = light
	A.actor = actor
	A.target = knife
	TEST_ASSERT_NULL(op_req_check(A, req(PROC_REF(native_sharp))), "actual knife is sharp")
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_blunt))), "must not be sharp", "negative tag reason")
	A.target = light
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_sharp))), "must be sharp", "positive tag exact refusal")
	TEST_ASSERT_NULL(op_req_check(A, req(PROC_REF(native_blunt))), "actual light item is blunt")
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_held_sharp))), "needs something sharp in hand", "held tag empty refusal")
	A.set_held_provider(knife)
	TEST_ASSERT_NULL(op_req_check(A, req(PROC_REF(native_held_sharp))), "actual held tag passes")
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_welder))), "needs a welder", "wrong tool refusal")
	A.set_held_provider(welder)
	TEST_ASSERT_NULL(op_req_check(A, req(PROC_REF(native_welder))), "actual welder quality permits")
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_weld_tier_two))), "needs a welder (tier 2)", "plain welder fails tier two")
	A.set_held_provider(advanced)
	TEST_ASSERT_NULL(op_req_check(A, req(PROC_REF(native_weld_tier_two))), "actual advanced quality tier two permits")
	A.set_held_provider(null)
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_analyzer))), "needs an analyzer", "article unchanged")
	actor.hold(null, null)
	TEST_ASSERT_NULL(op_req_check(A, req(PROC_REF(native_free_hand))), "real empty hand permits")
	actor.hold(welder, knife)
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_free_hand))), "needs a free hand", "real full hands refuse")
	A.target = knife
	TEST_ASSERT_NULL(op_req_check(A, req(PROC_REF(native_in_hand))), "actual offhand item counts as held")
	A.target = light
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_in_hand))), "must be held in hand", "actual loose item refuses")
	actor.hold(null, null)
	A.set_held_provider(null)
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_holding))), "needs something in hand", "holding refuses empty")
	A.set_held_provider(knife)
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_empty))), "needs an empty hand", "empty-handed rejects actual item")
	A.target = actor
	TEST_ASSERT_NULL(op_req_check(A, req(PROC_REF(native_self))), "actual target actor permits self")
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_not_self))), "can't be done to yourself", "not-self reason unchanged")
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_ready))), "not possible right now", "wrong target type refusal")
	A.target = light
	light.name = "ready"
	TEST_ASSERT_NULL(op_req_check(A, req(PROC_REF(native_ready))), "real ready state permits")
	light.name = "unready"
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_ready))), "it isn't ready", "real unready state reason")
	TEST_ASSERT_NULL(op_req_check(A, req(PROC_REF(native_knife))), "actual knife selection permits")
	A.set_held_provider(welder)
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_knife))), "needs the knife", "selection refusal exact")
	A.release()

/datum/unit_test/dq_native_predicate_numeric/combinators/Run()
	var/mob/living/dq_pred_test/actor = allocate(/mob/living/dq_pred_test)
	var/obj/item/dq_pred_test/light = allocate(/obj/item/dq_pred_test)
	var/obj/item/dq_pred_test/heavy/heavy = allocate(/obj/item/dq_pred_test/heavy)
	var/obj/item/dq_pred_test/knife/knife = allocate(/obj/item/dq_pred_test/knife)
	var/obj/item/dq_pred_test/welder/welder = allocate(/obj/item/dq_pred_test/welder)
	var/datum/entry/part/req/all = all_of(req(PROC_REF(native_welder)), req_measure(PROP_MASS, SIM_COMPARE_LT, KG(5)))
	TEST_ASSERT_EQUAL(reason(all, actor, heavy, knife), "needs a welder", "ordered first refusal")
	TEST_ASSERT_EQUAL(reason(all, actor, heavy, welder), "too heavy: 12 kg > 5 kg", "ordered second refusal")
	TEST_ASSERT_NULL(reason(all, actor, light, welder), "both conditions permit")
	var/datum/entry/part/req/any = any_of(req(PROC_REF(native_welder)), req(PROC_REF(native_held_sharp)))
	TEST_ASSERT_NULL(reason(any, actor, light, welder), "ANY actual welder branch permits")
	TEST_ASSERT_NULL(reason(any, actor, light, knife), "ANY actual sharp branch permits")
	TEST_ASSERT_EQUAL(reason(any, actor, light), "needs a welder or needs something sharp in hand", "ANY joined reasons exact")
	var/datum/entry/part/req/not_all = any_of(req(PROC_REF(native_blunt)), req_measure_not(PROP_MASS, SIM_COMPARE_LT, KG(5)))
	TEST_ASSERT(!isnull(reason(not_all, actor, knife)), "light sharp knife fails both negated branches")
	TEST_ASSERT_NULL(reason(not_all, actor, light), "blunt branch permits")
	TEST_ASSERT_NULL(reason(not_all, actor, heavy), "heavy branch permits")
	TEST_ASSERT_EQUAL(reason(not_all, actor, knife), "must not be sharp or too light: 1 kg < 5 kg", "De Morgan exact reasons")
	// Double negation is declared as original positive requirement, not generic NOT over unknown.
	TEST_ASSERT_NULL(reason(req(PROC_REF(native_sharp)), actor, knife), "double-negated tag is positive clause")
	TEST_ASSERT(!isnull(reason(req(PROC_REF(native_sharp)), actor, light)), "double-negated tag fails same input")
	TEST_ASSERT_EQUAL(reason(req(PROC_REF(native_sharp), because = "too dull"), actor, light), "too dull", "leaf because overrides refusal")
	TEST_ASSERT_NULL(reason(req(PROC_REF(native_sharp)), actor, knife), "single native leaf is complete requirement")
	TEST_ASSERT_EQUAL(req(PROC_REF(native_holding)), req(PROC_REF(native_holding)), "identical native declarations intern once")
	TEST_ASSERT_NOTEQUAL(req(PROC_REF(native_holding)), req(PROC_REF(native_free_hand)), "different callbacks never collide")
	TEST_ASSERT_EQUAL(reason(req(PROC_REF(native_holding)), actor, light), "needs something in hand", "native interned leaf still evaluates refusal")

/obj/item/dq_pred_test/proc/native_lit_welder(datum/act/op/A)
	var/datum/entry/part/req/plan = all_of(req(PROC_REF(native_welder)), req(PROC_REF(native_holding)))
	return op_req_check(A, plan)

/datum/unit_test/dq_native_predicate_numeric/empty_identity/Run()
	var/obj/item/dq_pred_test/light = allocate(/obj/item/dq_pred_test)
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = light
	A.target = light
	var/datum/entry/part/req/empty_all = part_make(/datum/entry/part/req/all, null, list())
	var/datum/entry/part/req/empty_any = part_make(/datum/entry/part/req/any, null, list())
	TEST_ASSERT_NULL(op_req_check(A, empty_all), "explicit native empty ALL is the identity true")
	TEST_ASSERT(!isnull(op_req_check(A, empty_any)), "explicit native empty ANY refuses rather than silently allowing")
	TEST_ASSERT_EQUAL(op_req_check(A, req(PROC_REF(native_lit_welder), because = "needs a lit welder")), "needs a lit welder", "whole-plan because overrides ordered child refusal")
	var/datum/entry/part/req/first = req(PROC_REF(native_holding), id = "native_identity_test")
	var/datum/entry/part/req/same = req(PROC_REF(native_holding), id = "native_identity_test")
	var/datum/entry/part/req/other = req(PROC_REF(native_free_hand), id = "native_identity_test")
	TEST_ASSERT_EQUAL(first, same, "same ID and payload share native flyweight")
	TEST_ASSERT_NOTEQUAL(first, other, "same ID with changed payload never returns stale cached requirement")
	TEST_ASSERT_EQUAL(op_req_check(A, first), "needs something in hand", "interned requirement evaluates current context")
	A.release()

/datum/unit_test/dq_native_predicate_numeric/range_validation/Run()
	var/mob/living/dq_pred_test/actor = allocate(/mob/living/dq_pred_test)
	var/turf/start = dq_pred_open_row()
	TEST_ASSERT(start, "five-open-tile fixture exists")
	actor.forceMove(start)
	var/obj/item/dq_pred_test/near = allocate(/obj/item/dq_pred_test, locate(start.x + 1, start.y, start.z))
	var/obj/item/dq_pred_test/far = allocate(/obj/item/dq_pred_test, locate(start.x + 4, start.y, start.z))
	TEST_ASSERT_NULL(reason(req_range(3), actor, near), "actual near tile lies within three")
	TEST_ASSERT_EQUAL(reason(req_range(3), actor, far), "too far away (more than 3 tiles)", "arbitrary reach exact old refusal")
	for(var/kind in list("unknown tag", "measure as tag", "invalid because"))
		var/caught = FALSE
		try
			switch(kind)
				if("unknown tag")
					req_acceptance_tag("dq_nope")
				if("measure as tag")
					req_acceptance_tag(PROP_MASS)
				if("invalid because")
					req_measure(PROP_MASS, SIM_COMPARE_LT, KG(5), because = 42)
		catch(var/exception/E)
			caught = TRUE
			TEST_ASSERT(length(E.name), "[kind] has concrete native diagnostic")
		TEST_ASSERT(caught, "[kind] must be rejected by actual final constructor")


// Applicable final native acceptance boundaries retained from predicate clause tests.
/datum/unit_test/dq_native_requirement_boundaries
	abstract_type = /datum/unit_test/dq_native_requirement_boundaries

/datum/unit_test/dq_native_requirement_boundaries/clauses/Run()
	var/obj/item/paper/P = allocate(/obj/item/paper, test_floor())
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, test_floor())
	var/datum/act/op/acceptance/A = acceptance_act(W, W, P)
	defer_cleanup(null, GLOBAL_PROC_REF(acceptance_act_release), A)
	var/datum/entry/part/req/tagged = req_acceptance_tag(TAG_PAPERWORK)
	TEST_ASSERT_NULL(op_req_check(A, tagged), "Actual paper passes its actual property tag")
	A.target = W
	TEST_ASSERT_NOTNULL(op_req_check(A, tagged), "Actual wrench fails paperwork property")
	var/datum/entry/part/req/only_paper = req_acceptance_type(/obj/item/paper)
	TEST_ASSERT_EQUAL(op_req_check(A, only_paper), "only takes certain things", "Exact original type refusal")
	A.target = P
	TEST_ASSERT_NULL(op_req_check(A, only_paper), "Actual paper type permits")
	TEST_ASSERT_EQUAL(op_req_check(A, req_acceptance_type(/obj/item/paper, exclude = TRUE)), "not that kind of thing", "Exact original excluded-type refusal")
	P.set_w_class(ITEMSIZE_SMALL)
	var/datum/entry/part/req/size = req_acceptance_max_size(SIZE_CLASS(ITEMSIZE_SMALL))
	TEST_ASSERT_NULL(op_req_check(A, size), "Actual exact numeric size boundary is inclusive")
	P.set_w_class(ITEMSIZE_LARGE)
	TEST_ASSERT_EQUAL(op_req_check(A, size), "too big: size [ITEMSIZE_LARGE] > size [ITEMSIZE_SMALL]", "Exact original size refusal")
	P.set_w_class(ITEMSIZE_SMALL)
	TEST_ASSERT_NULL(op_req_check(A, size), "Real setter restores allowance")

/datum/unit_test/dq_native_requirement_boundaries/composition/Run()
	var/obj/item/paper/P = allocate(/obj/item/paper, test_floor())
	P.set_w_class(ITEMSIZE_LARGE)
	var/datum/act/op/acceptance/A = acceptance_act(P, P, P)
	defer_cleanup(null, GLOBAL_PROC_REF(acceptance_act_release), A)
	var/datum/entry/part/req/type = req_acceptance_type(/obj/item/tool/wrench, because = "wrong type first")
	var/datum/entry/part/req/size = req_acceptance_max_size(SIZE_CLASS(ITEMSIZE_SMALL), because = "too large first")
	TEST_ASSERT_EQUAL(reason_text(op_req_check(A, all_of(type, size))), "wrong type first", "First ordered failing requirement wins")
	TEST_ASSERT_EQUAL(reason_text(op_req_check(A, all_of(size, type))), "too large first", "Changing actual order changes first refusal")
	TEST_ASSERT_NULL(op_req_check(A, any_of(type, req_acceptance_type(/obj/item/paper))), "One real branch permits")
	TEST_ASSERT_EQUAL(req_acceptance_type(/obj/item/paper), req_acceptance_type(/obj/item/paper), "Identical native declarations share immutable flyweight")
	TEST_ASSERT_NOTEQUAL(req_acceptance_type(/obj/item/paper), req_acceptance_type(/obj/item/tool/wrench), "Different native declarations do not collide")

/datum/unit_test/dq_native_requirement_boundaries/metadata/Run()
	var/obj/item/paper/P = allocate(/obj/item/paper, test_floor())
	var/datum/act/op/acceptance/A = acceptance_act(P, P, P)
	defer_cleanup(null, GLOBAL_PROC_REF(acceptance_act_release), A)
	var/datum/entry/part/req/size = req_acceptance_max_size(SIZE_CLASS(ITEMSIZE_SMALL))
	var/found = FALSE
	for(var/list/pair as anything in size.read_keys(A))
		if(pair[1] == P && pair[2] == nameof(P.w_class))
			found = TRUE
	TEST_ASSERT(found, "Numeric size requirement publishes its actual model setter dependency")
	TEST_ASSERT_NULL(req_acceptance_type(/obj/item/paper).read_keys(A), "Immutable actual type identity requires no fabricated change key")

/obj/item/dq_pred_test/override_ready

/obj/item/dq_pred_test/override_ready/dq_is_ready(datum/act/op/A)
	return "subtype refuses readiness"

/datum/unit_test/dq_native_predicate_numeric/subject_override/Run()
	var/obj/item/dq_pred_test/base = allocate(/obj/item/dq_pred_test)
	base.set_name("ready")
	var/obj/item/dq_pred_test/override_ready/child = allocate(/obj/item/dq_pred_test/override_ready)
	child.set_name("ready")
	var/datum/entry/part/req/R = req(TYPE_PROC_REF(/obj/item/dq_pred_test, dq_is_ready), of = ON_TARGET)
	TEST_ASSERT_NULL(reason(R, null, base), "absolute declaration still allows base implementation")
	TEST_ASSERT_EQUAL(reason(R, null, child), "subtype refuses readiness", "actual subject override wins with exact refusal")
