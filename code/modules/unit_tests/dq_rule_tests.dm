// Rules (doc/rewrite/rules.md §4, roadmap P4): compilation to reactor
// triggers, the generated threshold tests, and parity for the rules that
// replace old code.

/obj/item/dq_rule_test
	name = "rule test item"
	w_class = ITEMSIZE_SMALL

/// Needs its temperature above 400 K for two seconds in total, then grows.
/datum/rule/dq_test_hold
	name = "test hold"
	test_only = TRUE
	condition = list(REQ_AT_LEAST(PRED_TARGET, PROP_TEMPERATURE, KELVIN(400)))
	effect_kind = RULE_EFFECT_DATA
	transform = list(RULE_SET_STATE("w_class", ITEMSIZE_HUGE))
	hold_for = 2 SECONDS

/datum/rule/dq_test_band
	name = "test band"
	test_only = TRUE
	condition = list(REQ_BETWEEN(PRED_TARGET, PROP_TEMPERATURE, KELVIN(300), KELVIN(350)))
	effect_kind = RULE_EFFECT_DATA
	transform = list(RULE_SET_STATE("w_class", ITEMSIZE_TINY))

/datum/rule/dq_test_static_only
	name = "test static only"
	test_only = TRUE
	condition = list(REQ_ABOVE(PRED_TARGET, PROP_SIZE_CLASS, SIZE_CLASS(1)))
	effect_kind = RULE_EFFECT_DATA
	transform = list(RULE_REMOVE)

/datum/rule/dq_test_actor
	name = "test actor"
	test_only = TRUE
	condition = list(REQ_ABOVE(PRED_ACTOR, PROP_TEMPERATURE, KELVIN(300)))
	effect_kind = RULE_EFFECT_DATA
	transform = list(RULE_REMOVE)

/// Let SSreactor step and dispatch.
/proc/dq_rx_flush()
	react_test_ticks(2)

/// Let `ds` deciseconds of reactor time pass, then dispatch.
/proc/dq_rx_test_advance(ds)
	sleep(ds)
	react_test_ticks(2)

/// Writes `value` into property `id` of `thing` through its base provider.
/proc/dq_rule_test_write(datum/thing, id, value)
	var/datum/property_registry/registry = dq_property_registry()
	var/datum/property_provider/provider = registry.base_provider(thing.type, id)
	return provider ? provider.test_write(thing, value) : FALSE

// ---- Compilation ----

/datum/unit_test/dq_rule_compile

/datum/unit_test/dq_rule_compile/Run()
	var/list/errors = dq_rules_validate()
	TEST_ASSERT(!length(errors), "declared rules compile: [jointext(errors, "; ")]")

	var/list/rules = dq_rules()
	var/datum/rule/paper = rules[/datum/rule/paper_ignition]
	TEST_ASSERT(paper, "the paper rule is registered")
	TEST_ASSERT_EQUAL(length(paper.triggers), 1, "paper has one trigger")
	var/datum/rule_trigger/ignite = paper.triggers[1]
	TEST_ASSERT_EQUAL(ignite.kind, RULE_TRIGGER_THRESHOLD, "temperature vs ignition point is a Threshold watch")
	TEST_ASSERT_EQUAL(ignite.value_property, PROP_IGNITION_POINT, "its level is the ignition point")
	TEST_ASSERT(ignite.fires_above(), "it fires above the level")

	var/datum/rule/grille = rules[/datum/rule/integrity_breaks]
	var/list/grille_thresholds = grille.thresholds()
	TEST_ASSERT_EQUAL(length(grille_thresholds), 1, "the grille rule has one threshold")
	var/datum/rule_trigger/breaks = grille_thresholds[1]
	TEST_ASSERT_EQUAL(breaks.kind, RULE_TRIGGER_KEY, "integrity is DM-owned: a key trigger")
	TEST_ASSERT_EQUAL(breaks.key_kind, RULE_KEY_INTEGRITY, "on the integrity key")
	TEST_ASSERT(!breaks.fires_above(), "it fires at or below the breaking point")

	var/datum/rule/band = dq_rule_fixture(/datum/rule/dq_test_band)
	var/datum/rule_trigger/band_trigger = band.triggers[1]
	TEST_ASSERT_EQUAL(band_trigger.kind, RULE_TRIGGER_BAND, "REQ_BETWEEN on temperature is a Band watch")

	var/datum/rule/static_only = new /datum/rule/dq_test_static_only
	TEST_ASSERT(!static_only.compile(), "a rule over static properties only is rejected")
	var/datum/rule/actor = new /datum/rule/dq_test_actor
	TEST_ASSERT(!actor.compile(), "a rule reading the actor is rejected")

	// Per-type index: inherited by subtypes, nothing for unrelated types.
	TEST_ASSERT(paper in dq_rules_for_type(/obj/item/paper/card), "paper subtypes inherit the rule")
	TEST_ASSERT_NULL(dq_rules_for_type(/obj/item/dq_rule_test), "a type without rules has none")
	TEST_ASSERT(RULES_REPLACE(/obj/item/paper, RULE_REPLACES_IGNITION), "paper's ignition is rule-driven")
	TEST_ASSERT(!RULES_REPLACE(/obj/item/dq_rule_test, RULE_REPLACES_IGNITION), "other objects keep fire_act ignition")

// ---- Generated threshold tests ----

/// Every declared threshold, on every type a rule names: the input just on the
/// quiet side does nothing; just across fires the effect exactly once; further
/// across does not fire it again.
/datum/unit_test/dq_rule_thresholds

/datum/unit_test/dq_rule_thresholds/Run()
	GLOB.dq_rule_recording = TRUE
	GLOB.dq_rule_fire_log.Cut()
	var/declared = 0
	var/passed = 0
	var/list/rules = dq_rules()
	for(var/rule_path in rules)
		var/datum/rule/rule = rules[rule_path]
		for(var/root in rule.applies_to)
			for(var/declaring in dq_rule_declaring_types(rule, root))
				for(var/datum/rule_trigger/trigger as anything in rule.thresholds())
					declared++
					if(run_case(rule, declaring, trigger))
						passed++
	GLOB.dq_rule_recording = FALSE
	TEST_NOTICE(src, "[passed]/[declared] generated rule threshold tests passed")
	TEST_ASSERT(declared > 0, "some thresholds are declared")
	TEST_ASSERT_EQUAL(passed, declared, "every declared threshold passes its generated test")

/datum/unit_test/dq_rule_thresholds/proc/run_case(datum/rule/rule, root, datum/rule_trigger/trigger)
	// Fresh log per case: a deleted object's ref can be reused by the next one.
	GLOB.dq_rule_fire_log.Cut()
	var/atom/thing = ispath(root, /atom/movable) ? allocate(root, test_floor()) : allocate(root)
	. = check_case(rule, root, trigger, thing)
	// Some types allow one per turf (tables); clear the case's object and drops.
	if(ismovable(thing) && !QDELETED(thing))
		var/turf/T = get_turf(thing)
		qdel(thing)
		for(var/obj/item/stack/rods/R in T)
			qdel(R)

/datum/unit_test/dq_rule_thresholds/proc/check_case(datum/rule/rule, root, datum/rule_trigger/trigger, atom/thing)
	var/label = "[rule.type] on [root]: [trigger.describe()]"
	var/datum/rule_binding/binding = dq_rule_binding_of(thing)
	if(!binding)
		TEST_FAIL("[label]: did not subscribe when it materialized")
		return FALSE
	var/level = trigger.level_for(thing)
	if(isnull(level))
		TEST_FAIL("[label]: has no level")
		return FALSE
	var/step = dq_rule_epsilon(level) * 10
	var/direction = trigger.fires_above() ? 1 : -1
	var/quiet = level - direction * step
	var/across = level + direction * step
	var/further = max(0, level + direction * step * 10)
	if(!dq_rule_test_write(thing, trigger.property, quiet))
		TEST_FAIL("[label]: [trigger.property] has no test writer")
		return FALSE
	dq_rx_flush()
	if(dq_rule_fire_count(thing, rule) != 0)
		TEST_FAIL("[label]: fired at [quiet], on the quiet side of [level]")
		return FALSE
	dq_rule_test_write(thing, trigger.property, across)
	dq_rx_flush()
	if(dq_rule_fire_count(thing, rule) != 1)
		TEST_FAIL("[label]: fired [dq_rule_fire_count(thing, rule)] times at [across], expected once")
		return FALSE
	if(!QDELETED(thing))
		dq_rule_test_write(thing, trigger.property, further)
		dq_rx_flush()
		if(dq_rule_fire_count(thing, rule) != 1)
			TEST_FAIL("[label]: fired again at [further]")
			return FALSE
	return TRUE

/// The types a generated test instantiates for `rule` under `root`: the root
/// itself when the rule's per-type filter takes it, otherwise every topmost
/// subtype the filter takes (the types that declare the breakpoint).
/proc/dq_rule_declaring_types(datum/rule/rule, root)
	if(dq_rule_applies(rule, root))
		return list(root)
	. = list()
	for(var/path in subtypesof(root))
		if(!dq_rule_applies(rule, path))
			continue
		var/parent = path
		var/topmost = TRUE
		while(parent != root)
			parent = type2parent(parent)
			if(parent != root && dq_rule_applies(rule, parent))
				topmost = FALSE
				break
		if(topmost)
			. += path

// ---- Subscription lifecycle ----

/datum/unit_test/dq_rule_subscription

/datum/unit_test/dq_rule_subscription/Run()
	var/obj/item/dq_rule_test/plain = allocate(/obj/item/dq_rule_test)
	TEST_ASSERT_NULL(dq_rule_binding_of(plain), "an object without rules has no binding")
	var/obj/item/paper/paper = allocate(/obj/item/paper)
	var/datum/rule_binding/binding = dq_rule_binding_of(paper)
	TEST_ASSERT(binding, "paper subscribes when it materializes")
	TEST_ASSERT(!isnull(binding.nodes[PROP_TEMPERATURE]), "its ignition watch made a heat node")
	TEST_ASSERT_EQUAL(PROPERTY(paper, PROP_TEMPERATURE), T20C, "the node starts at room temperature")
	TEST_ASSERT(!dq_rx_node_in_rust(binding.nodes[PROP_TEMPERATURE]), "at rest it holds no probe cell")
	qdel(paper)
	TEST_ASSERT_NULL(dq_rule_binding_of(paper), "deleting the object drops its binding")
	TEST_ASSERT(QDELETED(binding), "and the binding is deleted")

	// A rule whose level the object lacks does not subscribe: a cooler bottle
	// with no material has no melting point.
	var/obj/item/reagent_containers/glass/cooler_bottle/bare = allocate(/obj/item/reagent_containers/glass/cooler_bottle)
	var/datum/rule_binding/bare_binding = dq_rule_binding_of(bare)
	TEST_ASSERT(bare_binding, "a cooler bottle subscribes")
	bare.dematerialize()
	TEST_ASSERT(QDELETED(bare_binding), "dematerializing drops the subscriptions")
	bare.material_template = null
	TEST_ASSERT_NULL(dq_rules_on_materialize(bare), "without a melting point there is nothing to watch")

// ---- Time above threshold, bands, data transforms ----

/datum/unit_test/dq_rule_hold_and_band

/datum/unit_test/dq_rule_hold_and_band/Run()
	GLOB.dq_rule_recording = TRUE
	var/datum/rule/hold = dq_rule_fixture(/datum/rule/dq_test_hold)
	var/obj/item/dq_rule_test/item = allocate(/obj/item/dq_rule_test)
	var/datum/rule_binding/binding = new(item, list(hold))
	var/handle = binding.nodes[PROP_TEMPERATURE]
	TEST_ASSERT(!isnull(handle), "the hold rule watches a heat node")

	dq_rx_node_write(handle, DQ_RX_CH_TEMPERATURE, 450)
	TEST_ASSERT(dq_rx_node_in_rust(handle), "a hot node borrows a probe cell: its watch is a Rust REACT_WHEN watch")
	dq_rx_test_advance(0.8 SECONDS)
	TEST_ASSERT_EQUAL(dq_rule_fire_count(item, hold), 0, "under a second above is not enough")
	dq_rx_node_write(handle, DQ_RX_CH_TEMPERATURE, 300)
	dq_rx_test_advance(1.5 SECONDS)
	TEST_ASSERT_EQUAL(dq_rule_fire_count(item, hold), 0, "time below the threshold does not count")
	dq_rx_node_write(handle, DQ_RX_CH_TEMPERATURE, 450)
	dq_rx_test_advance(0.5 SECONDS)
	TEST_ASSERT_EQUAL(dq_rule_fire_count(item, hold), 0, "about 1.5 seconds in total is not enough")
	dq_rx_test_advance(1 SECONDS)
	TEST_ASSERT_EQUAL(dq_rule_fire_count(item, hold), 1, "two seconds in total fires it, from a rate model watch, not polling")
	TEST_ASSERT_EQUAL(item.w_class, ITEMSIZE_HUGE, "the data transform set the state")
	TEST_ASSERT_EQUAL(PROPERTY(item, PROP_SIZE_CLASS), ITEMSIZE_HUGE, "which overrides the property")
	TEST_ASSERT(QDELETED(binding), "a once rule drops its binding after firing")

	var/datum/rule/band = dq_rule_fixture(/datum/rule/dq_test_band)
	var/obj/item/dq_rule_test/banded = allocate(/obj/item/dq_rule_test)
	var/datum/rule_binding/band_binding = new(banded, list(band))
	var/band_handle = band_binding.nodes[PROP_TEMPERATURE]
	dq_rx_node_write(band_handle, DQ_RX_CH_TEMPERATURE, 280)
	dq_rx_flush()
	TEST_ASSERT_EQUAL(dq_rule_fire_count(banded, band), 0, "below the band")
	dq_rx_node_write(band_handle, DQ_RX_CH_TEMPERATURE, 320)
	dq_rx_flush()
	TEST_ASSERT_EQUAL(dq_rule_fire_count(banded, band), 1, "entering the band fires")
	TEST_ASSERT_EQUAL(banded.w_class, ITEMSIZE_TINY, "band transform applied")
	GLOB.dq_rule_recording = FALSE

// ---- Parity: paper ignition ----

/datum/unit_test/dq_rule_paper_ignition

/datum/unit_test/dq_rule_paper_ignition/Run()
	var/obj/item/paper/hot = allocate(/obj/item/paper)
	var/ignition = PROPERTY(hot, PROP_IGNITION_POINT)
	TEST_ASSERT(ignition > T20C, "paper has an ignition point")
	// Before: any fire_act caught it at once. After: the exposure heats the node,
	// and the rule catches it on the next dispatch, for any exposure at or above
	// the ignition point.
	hot.fire_act(1000, 100)
	TEST_ASSERT(!(hot.resistance_flags & ON_FIRE), "fire_act no longer ignites paper directly")
	dq_rx_flush()
	TEST_ASSERT(hot.resistance_flags & ON_FIRE, "the rule ignites paper exposed above its ignition point")
	TEST_ASSERT(hot.GetComponent(/datum/component/burning), "with the same burning component as before")

	var/obj/item/paper/warm = allocate(/obj/item/paper)
	warm.fire_act(ignition - 50, 100)
	dq_rx_flush()
	TEST_ASSERT(!(warm.resistance_flags & ON_FIRE), "an exposure below the ignition point does not ignite it")
	dq_rx_test_advance(RULE_HEAT_EXPOSURE_HOLD + 1)
	TEST_ASSERT(abs(PROPERTY(warm, PROP_TEMPERATURE) - dq_ambient_temperature(warm)) < 0.01, "the node relaxes to the air once exposure stops")

	var/obj/item/paper/proofed = allocate(/obj/item/paper)
	proofed.resistance_flags |= FIRE_PROOF
	proofed.fire_act(1000, 100)
	dq_rx_flush()
	TEST_ASSERT(!(proofed.resistance_flags & ON_FIRE), "fireproof paper still does not burn")

// ---- Melting ----

/datum/unit_test/dq_rule_plastic_melts

/datum/unit_test/dq_rule_plastic_melts/Run()
	var/turf/T = test_floor()
	var/obj/item/reagent_containers/glass/cooler_bottle/bottle = allocate(/obj/item/reagent_containers/glass/cooler_bottle, T)
	var/datum/material/plastic = GLOB.name_to_material[MAT_PLASTIC]
	TEST_ASSERT_EQUAL(PROPERTY(bottle, PROP_MELTING_POINT), plastic.melting_point, "the bottle's melting point is its plastic's, through PROPERTY()")
	var/obj/item/dq_rule_test/inside = new(bottle)
	bottle.fire_act(plastic.melting_point - 10, 100)
	dq_rx_flush()
	TEST_ASSERT(!QDELETED(bottle), "below the melting point it keeps its shape")
	bottle.fire_act(plastic.melting_point + 10, 100)
	dq_rx_flush()
	TEST_ASSERT(QDELETED(bottle), "at the melting point it is replaced")
	TEST_ASSERT(locate(/obj/effect/decal/cleanable/molten_item) in T, "by a molten mass")
	TEST_ASSERT_EQUAL(inside.loc, T, "and what was inside drops out")
	qdel(inside)
	for(var/obj/effect/decal/cleanable/molten_item/goo in T)
		qdel(goo)

// ---- Parity: grille breaking point ----

/datum/unit_test/dq_rule_grille_parity

/datum/unit_test/dq_rule_grille_parity/Run()
	var/turf/T = test_floor()
	var/obj/structure/grille/grille = allocate(/obj/structure/grille, T)
	TEST_ASSERT(dq_rule_binding_of(grille), "grilles subscribe their breaking point")
	var/rods_before = count_rods(T)
	// Old behaviour: 10 damage crosses integrity_failure (0.375 of 16) and breaks it at once.
	grille.take_damage(10, BRUTE, MELEE, FALSE)
	TEST_ASSERT(grille.destroyed, "10 damage breaks it in the same call, as before")
	TEST_ASSERT(!grille.density, "a broken grille is passable")
	TEST_ASSERT_EQUAL(count_rods(T) - rods_before, 1, "breaking drops one rod")
	dq_rx_flush()
	TEST_ASSERT_EQUAL(count_rods(T) - rods_before, 1, "the later key wake does not break it again")

	// One hit that both breaks and destroys: break first, then destruction.
	var/obj/structure/grille/second = allocate(/obj/structure/grille, T)
	var/rods_mid = count_rods(T)
	second.take_damage(20, BRUTE, MELEE, FALSE)
	TEST_ASSERT(QDELETED(second), "20 damage destroys it")
	TEST_ASSERT_EQUAL(count_rods(T) - rods_mid, 2, "break then destruction each drop a rod, as before")

	// Repair above the breaking point re-arms the rule (atom_fix), and it breaks again.
	var/obj/structure/grille/third = allocate(/obj/structure/grille, T)
	third.take_damage(10, BRUTE, MELEE, FALSE)
	var/datum/rule_binding/binding = dq_rule_binding_of(third)
	var/break_index = binding.rules.Find(dq_rules()[/datum/rule/integrity_breaks])
	TEST_ASSERT(break_index, "grilles have the breaking-point rule")
	TEST_ASSERT(binding.holding[break_index], "broken: the rule holds")
	third.repair_damage(10)
	TEST_ASSERT(!binding.holding[break_index], "repaired above the breaking point: the rule is re-armed")
	for(var/obj/item/stack/rods/R in T)
		qdel(R)

/datum/unit_test/dq_rule_grille_parity/proc/count_rods(turf/T)
	. = 0
	for(var/obj/item/stack/rods/R in T)
		. += R.get_amount()
