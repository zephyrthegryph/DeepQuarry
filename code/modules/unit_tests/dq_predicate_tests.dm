// Consumer coverage retained after retiring the old predicate grammar.
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

/obj/item/dq_pred_test/override_ready

/obj/item/dq_pred_test/override_ready/dq_is_ready(datum/act/op/A)
	return "subtype refuses readiness"

/// The native context carries each participant independently.
/datum/unit_test/proc/dq_native_requirement_reason(datum/entry/part/req/R, datum/holder, mob/actor, atom/target, obj/item/held = null)
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = holder
	A.actor = actor
	A.target = target
	A.held = held
	var/result = R.check(A)
	A.release()
	return result

/proc/dq_native_test_weld_tier(datum/act/op/A)
	return A.held && dq_tool_tier(A.held, TOOL_WELDER) >= 2 ? null : "needs a welder (tier 2)"

/proc/dq_native_test_light_mass(datum/act/op/A)
	return dq_property(A.target, PROP_MASS) < 5 ? null : "too heavy: 12 kg > 5 kg"

/proc/dq_native_test_held_sharp(datum/act/op/A)
	return A.held && dq_has_tag(A.held, TAG_SHARP) ? null : "needs something sharp in hand"

/proc/dq_native_test_adjacent(datum/act/op/A)
	return A.actor?.Adjacent(A.target) ? null : "too far away"

/datum/unit_test/dq_predicate_clauses

/datum/unit_test/dq_predicate_clauses/Run()
	var/obj/item/dq_pred_test/light = allocate(/obj/item/dq_pred_test)
	var/obj/item/dq_pred_test/heavy/heavy = allocate(/obj/item/dq_pred_test/heavy)
	var/obj/item/dq_pred_test/knife/knife = allocate(/obj/item/dq_pred_test/knife)
	var/obj/item/dq_pred_test/welder/welder = allocate(/obj/item/dq_pred_test/welder)
	var/obj/item/dq_pred_test/welder/advanced/advanced = allocate(/obj/item/dq_pred_test/welder/advanced)
	var/datum/entry/part/req/sharp = req_acceptance_tag(TAG_SHARP)
	TEST_ASSERT_NULL(dq_native_requirement_reason(sharp, light, null, knife), "Actual sharp item allows")
	TEST_ASSERT_EQUAL(dq_native_requirement_reason(sharp, light, null, light), "must be sharp", "Tag refusal remains exact")
	var/datum/entry/part/req/blunt = req_acceptance_tag(TAG_SHARP, exclude = TRUE)
	TEST_ASSERT_NULL(dq_native_requirement_reason(blunt, light, null, light), "Blunt item permits excluded sharp tag")
	TEST_ASSERT_EQUAL(dq_native_requirement_reason(blunt, light, null, knife), "must not be sharp", "Excluded tag refuses actual knife")
	var/datum/entry/part/req/size = req_acceptance_max_size(ITEMSIZE_SMALL, PROP_UNIT_SIZE_CLASS)
	TEST_ASSERT_NULL(dq_native_requirement_reason(size, light, null, light), "Numeric size admits equality")
	TEST_ASSERT_NOTNULL(dq_native_requirement_reason(size, light, null, heavy), "Numeric size rejects a real larger item")
	var/datum/entry/part/req/tier = req(GLOBAL_PROC_REF(dq_native_test_weld_tier))
	TEST_ASSERT_NOTNULL(dq_native_requirement_reason(tier, light, null, light, welder), "Tier one does not satisfy tier two")
	TEST_ASSERT_NULL(dq_native_requirement_reason(tier, light, null, light, advanced), "Actual advanced tool satisfies its tier")
	TEST_ASSERT_EQUAL(dq_native_requirement_reason(tier, light, null, light, knife), "needs a welder (tier 2)", "Wrong held item retains tool refusal")

/datum/unit_test/dq_predicate_combinators

/datum/unit_test/dq_predicate_combinators/Run()
	var/obj/item/dq_pred_test/light = allocate(/obj/item/dq_pred_test)
	var/obj/item/dq_pred_test/heavy/heavy = allocate(/obj/item/dq_pred_test/heavy)
	var/obj/item/dq_pred_test/knife/knife = allocate(/obj/item/dq_pred_test/knife)
	var/obj/item/dq_pred_test/welder/advanced/advanced = allocate(/obj/item/dq_pred_test/welder/advanced)
	var/datum/entry/part/req/tier = req(GLOBAL_PROC_REF(dq_native_test_weld_tier))
	var/datum/entry/part/req/mass = req(GLOBAL_PROC_REF(dq_native_test_light_mass))
	var/datum/entry/part/req/all = all_of(tier, mass)
	TEST_ASSERT_EQUAL(dq_native_requirement_reason(all, light, null, heavy, knife), "needs a welder (tier 2)", "Ordered native refusal checks tool first")
	TEST_ASSERT_EQUAL(dq_native_requirement_reason(all, light, null, heavy, advanced), "too heavy: 12 kg > 5 kg", "Next actual refusal wins after tool allows")
	TEST_ASSERT_NULL(dq_native_requirement_reason(all, light, null, light, advanced), "Both actual requirements permit")
	var/datum/entry/part/req/any = any_of(tier, req(GLOBAL_PROC_REF(dq_native_test_held_sharp)))
	TEST_ASSERT_NULL(dq_native_requirement_reason(any, light, null, light, advanced), "First alternative allows")
	TEST_ASSERT_NULL(dq_native_requirement_reason(any, light, null, light, knife), "Second alternative allows")
	TEST_ASSERT_EQUAL(dq_native_requirement_reason(any, light, null, light), "needs a welder (tier 2) or needs something sharp in hand", "Native alternatives retain both actual reasons")
	var/datum/entry/part/req/overridden = req_acceptance_tag(TAG_SHARP, because = "too dull")
	TEST_ASSERT_EQUAL(dq_native_requirement_reason(overridden, light, null, light), "too dull", "Explicit native reason overrides leaf reason")

/datum/unit_test/dq_predicate_subject_override

/datum/unit_test/dq_predicate_subject_override/Run()
	var/obj/item/dq_pred_test/base = allocate(/obj/item/dq_pred_test)
	var/obj/item/dq_pred_test/override_ready/child = allocate(/obj/item/dq_pred_test/override_ready)
	base.set_name("ready")
	child.set_name("ready")
	var/datum/entry/part/req/R = req(TYPE_PROC_REF(/obj/item/dq_pred_test, dq_is_ready))
	TEST_ASSERT_NULL(dq_native_requirement_reason(R, base, null, base), "Declared base callback permits actual ready holder")
	TEST_ASSERT_EQUAL(dq_native_requirement_reason(R, child, null, child), "subtype refuses readiness", "Native virtual dispatch preserves real subtype refusal")

/datum/unit_test/dq_predicate_table

/datum/unit_test/dq_predicate_table/Run()
	var/turf/start = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, start)
	var/obj/item/dq_pred_test/light = allocate(/obj/item/dq_pred_test, start)
	var/obj/item/dq_pred_test/heavy/heavy = allocate(/obj/item/dq_pred_test/heavy, start)
	var/obj/item/dq_pred_test/welder/welder = allocate(/obj/item/dq_pred_test/welder)
	var/obj/item/dq_pred_test/welder/advanced/advanced = allocate(/obj/item/dq_pred_test/welder/advanced)
	var/obj/item/dq_pred_test/knife/knife = allocate(/obj/item/dq_pred_test/knife)
	var/datum/entry/part/req/R = all_of(req(GLOBAL_PROC_REF(dq_native_test_adjacent)), req(GLOBAL_PROC_REF(dq_native_test_weld_tier)), req(GLOBAL_PROC_REF(dq_native_test_light_mass)))
	var/list/rows = list(list(light, advanced, null), list(light, welder, "needs a welder (tier 2)"), list(light, knife, "needs a welder (tier 2)"), list(light, null, "needs a welder (tier 2)"), list(heavy, advanced, "too heavy: 12 kg > 5 kg"), list(heavy, knife, "needs a welder (tier 2)"))
	for(var/list/row as anything in rows)
		TEST_ASSERT_EQUAL(dq_native_requirement_reason(R, row[1], actor, row[1], row[2]), row[3], "Actual held-tool/target matrix preserves ordered refusal")

/proc/dq_native_test_free_hand(datum/act/op/A)
	return A.actor && (!A.actor.get_equipped_item(SLOT_ID_HAND_L) || !A.actor.get_equipped_item(SLOT_ID_HAND_R)) ? null : "needs a free hand"

/proc/dq_native_test_target_held(datum/act/op/A)
	return A.actor && (A.actor.get_active_hand() == A.target || A.actor.get_inactive_hand() == A.target) ? null : "must be held in hand"

/proc/dq_native_test_holding(datum/act/op/A)
	return A.held ? null : "needs something in hand"

/proc/dq_native_test_empty_handed(datum/act/op/A)
	return !A.held ? null : "needs an empty hand"

/datum/unit_test/dq_native_requirement_hands

/datum/unit_test/dq_native_requirement_hands/Run()
	var/turf/floor = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, floor)
	var/obj/item/pen/right = allocate(/obj/item/pen, floor)
	var/obj/item/tool/wrench/left = allocate(/obj/item/tool/wrench, floor)
	var/obj/item/paper/unheld = allocate(/obj/item/paper, floor)
	var/datum/entry/part/req/free = req(GLOBAL_PROC_REF(dq_native_test_free_hand))
	var/datum/entry/part/req/held = req(GLOBAL_PROC_REF(dq_native_test_target_held))
	TEST_ASSERT_NULL(dq_native_requirement_reason(free, unheld, H, unheld), "Real empty human hands permit")
	TEST_ASSERT(H.put_in_r_hand(right), "Real right-hand insertion succeeds")
	TEST_ASSERT(H.put_in_l_hand(left), "Real left-hand insertion succeeds")
	TEST_ASSERT_EQUAL(dq_native_requirement_reason(free, unheld, H, unheld, right), "needs a free hand", "Actual two occupied slots refuse")
	TEST_ASSERT_NULL(dq_native_requirement_reason(held, left, H, left, right), "Actual offhand item is held independently of input held participant")
	TEST_ASSERT_EQUAL(dq_native_requirement_reason(held, unheld, H, unheld, right), "must be held in hand", "Actual floor item is not silently treated as held")
	TEST_ASSERT_EQUAL(dq_native_requirement_reason(req(GLOBAL_PROC_REF(dq_native_test_holding)), unheld, H, unheld), "needs something in hand", "Missing input held participant refuses")
	TEST_ASSERT_NULL(dq_native_requirement_reason(req(GLOBAL_PROC_REF(dq_native_test_holding)), unheld, H, unheld, right), "Real held input participant allows")
	TEST_ASSERT_EQUAL(dq_native_requirement_reason(req(GLOBAL_PROC_REF(dq_native_test_empty_handed)), unheld, H, unheld, right), "needs an empty hand", "Nonempty input participant refuses empty-hand condition")
	TEST_ASSERT(H.unEquip(left, target = floor), "Actual offhand removal succeeds")
	TEST_ASSERT_NULL(dq_native_requirement_reason(free, unheld, H, unheld, right), "Real removal recovers free-hand admission")

/datum/unit_test/dq_native_requirement_validation

/datum/unit_test/dq_native_requirement_validation/Run()
	var/rejected_null = FALSE
	try
		req_acceptance_type(list(null))
	catch(var/exception/null_fault)
		rejected_null = TRUE
		TEST_ASSERT(findtext(null_fault.name, "acceptance type list contains a non-type path"), "Actual native type factory identifies malformed null path")
	TEST_ASSERT(rejected_null, "Native type lists never silently ignore the old middle-null defect")
	var/rejected_text = FALSE
	try
		req_acceptance_type(list("/obj/item/pen"))
	catch(var/exception/text_fault)
		rejected_text = TRUE
		TEST_ASSERT(findtext(text_fault.name, "non-type path"), "The real factory identifies a textual pseudo-path")
	TEST_ASSERT(rejected_text, "A path-looking string is not a declared type path")
	var/rejected_unit = FALSE
	try
		req_acceptance_max_size(ITEMSIZE_SMALL, PROP_UNIT_KELVIN)
	catch(var/exception/unit_fault)
		rejected_unit = TRUE
		TEST_ASSERT(findtext(unit_fault.name, "numeric unit"), "The real factory identifies the incompatible unit")
	TEST_ASSERT(rejected_unit, "Numeric native size requirements reject an incompatible real unit")
	var/obj/item/pen/P = allocate(/obj/item/pen)
	var/datum/entry/part/req/empty = req_acceptance_type(list(), because = "it can't be worn")
	TEST_ASSERT_EQUAL(dq_native_requirement_reason(empty, P, null, P), "it can't be worn", "Intentional empty type lists remain valid always-refusing requirements")
