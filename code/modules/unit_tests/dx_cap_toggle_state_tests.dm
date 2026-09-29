// cap_toggle_state() (code/datums/capabilities/library/toggle_state.dm).

/obj/item/cap_fixture/hoodie
	var/stuck = FALSE
	var/has_hood = TRUE
	var/applied

/obj/item/cap_fixture/hoodie/capabilities()
	. = ..()
	. += cap_toggle_state("hood", on_suffix = "_t", verb_name = "Toggle Hood", apply = PROC_REF(fx_apply), available = PROC_REF(fx_available), else_say = "it has no hood", self_on = "You raise the hood of %T%.", self_off = "You lower the hood of %T%.", examine_on = "Its hood is up.", examine_off = "Its hood is down.", log = LOG_GAME)

/obj/item/cap_fixture/hoodie/proc/fx_apply(on, mob/user)
	if(stuck)
		return "the hood is stuck"
	applied = on
	return TRUE

/obj/item/cap_fixture/hoodie/proc/fx_available()
	return has_hood

/obj/item/cap_fixture/jacket/capabilities()
	. = ..()
	. += cap_toggle_state("buttons", on_state = "open", off_state = "closed", bit = CAP_TOGGLE_2)

/// The verb in A.verbs named `name`, or null.
/proc/dx_verb_named(atom/A, name)
	for(var/procpath/V as anything in A.verbs)
		if(V.name == name)
			return V
	return null

/datum/unit_test/dx_cap_toggle_state

/datum/unit_test/dx_cap_toggle_state/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/cap_fixture/hoodie/F = allocate(/obj/item/cap_fixture/hoodie, T)

	var/datum/interaction/capability/E = dx_cap_entry(F, "Toggle Hood")
	TEST_ASSERT_NOTNULL(E, "cap_toggle_state() offers its entry, named verb_name")
	TEST_ASSERT_EQUAL(E.entry, INTERACTION_ENTRY_SELF, "a self-use entry")
	TEST_ASSERT_EQUAL(E.why_not(H, F, F), "you need to be carrying it", "only while carried")
	TEST_ASSERT_NOTNULL(dx_verb_named(F, "Toggle Hood"), "the native verb, renamed")
	TEST_ASSERT_EQUAL(toggle_is_on(F, "hood"), FALSE, "starts off")
	TEST_ASSERT("Its hood is down." in F.caps_examine(H), "examine off")

	TEST_ASSERT(H.put_in_r_hand(F), "held")
	TEST_ASSERT(F.attack_self(H), "self-use toggles")
	TEST_ASSERT(cap_has(F, CAP_TOGGLE_1), "the bit is set")
	TEST_ASSERT_EQUAL(toggle_is_on(F, "hood"), TRUE, "on")
	TEST_ASSERT_EQUAL(F.applied, TRUE, "apply() ran with on")
	TEST_ASSERT_EQUAL(F.icon_state, "fixture_t", "drawn at once (the worn sprite reads it)")
	TEST_ASSERT_EQUAL(GLOB.dispatch_last_record["log"], LOG_GAME, "the declared log level")
	TEST_ASSERT("Its hood is up." in F.caps_examine(H), "examine on")
	var/list/data = list()
	F.caps_ui_data(H, data)
	TEST_ASSERT(data["hood"], "UI data")

	// apply() refuses: the state stays.
	F.stuck = TRUE
	F.attack_self(H)
	TEST_ASSERT(cap_has(F, CAP_TOGGLE_1), "a refused apply() leaves it on")
	F.stuck = FALSE

	// The verb runs the same entry.
	F.cap_toggle_verb_run(H, CAP_TOGGLE_1)
	TEST_ASSERT(!cap_has(F, CAP_TOGGLE_1), "the verb toggles it off")
	TEST_ASSERT_EQUAL(F.applied, FALSE, "apply() ran with off")
	refresh_flush()
	TEST_ASSERT_EQUAL(F.icon_state, "fixture", "drawn off: the initial icon_state")

	// Unavailable: refused with else_say, and the verb is hidden until it comes back.
	F.has_hood = FALSE
	changed(F)
	refresh_flush()
	TEST_ASSERT_EQUAL(E.why_not(H, F, F), "it has no hood", "unavailable refuses with else_say")
	TEST_ASSERT_NULL(dx_verb_named(F, "Toggle Hood"), "the verb is hidden")
	F.has_hood = TRUE
	changed(F)
	refresh_flush()
	TEST_ASSERT_NULL(E.why_not(H, F, F), "available again")
	TEST_ASSERT_NOTNULL(dx_verb_named(F, "Toggle Hood"), "the verb is back, with its name")

	// A second toggle on its own bit, with literal states and the default verb name.
	var/obj/item/cap_fixture/jacket/J = allocate(/obj/item/cap_fixture/jacket, T)
	TEST_ASSERT_NOTNULL(dx_cap_entry(J, "Toggle buttons"), "the default verb name")
	TEST_ASSERT_NOTNULL(dx_verb_named(J, "Toggle buttons"), "the verb for its bit")
	refresh_flush()
	TEST_ASSERT_EQUAL(J.icon_state, "closed", "off_state drawn")
	TEST_ASSERT(H.put_in_l_hand(J), "held")
	J.cap_toggle_verb_run(H, CAP_TOGGLE_2)
	TEST_ASSERT(cap_has(J, CAP_TOGGLE_2), "its own bit")
	TEST_ASSERT(!cap_has(J, CAP_TOGGLE_1), "not the first toggle's bit")
	TEST_ASSERT_EQUAL(J.icon_state, "open", "on_state drawn")
	H.drop_from_inventory(F, T)
	H.drop_from_inventory(J, T)
