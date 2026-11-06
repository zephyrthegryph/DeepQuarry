// The right-click Menu shows only what makes sense for the actor: an op refused for who the actor is or what the target is (FAILS_HIDDEN) is left out,
// an op refused for the state of things is listed greyed with the reason, and an op that asked (menu(hint_tool = TRUE)) is listed greyed
// "needs a <tool>" while the tool is not held.

/// A target with one op of each kind.
/obj/dq_menu_probe
	name = "menu probe"
	var/ready = FALSE

CAPABILITIES(/obj/dq_menu_probe)
	op("probe_plain", tool(TOOL_WRENCH), label("Probe plain"), then(PROC_REF(probe_done)))
	op("probe_hinted", tool(TOOL_WELDER), menu(hint_tool = TRUE), label("Probe hinted"), then(PROC_REF(probe_done)))
	op("probe_kind", menu(), label("Probe kind"), needs(req_actor_kind(/mob/living/silicon/robot)), then(PROC_REF(probe_done)))
	op("probe_rights", menu(), label("Probe rights"), needs(req_rights(R_ADMIN)), then(PROC_REF(probe_done)))
	op("probe_state", menu(), label("Probe state"), needs(req_is(nameof(ready))), then(PROC_REF(probe_done)))
	op("probe_override", menu(), label("Probe override"), needs(req_actor_kind(/mob/living/silicon/robot, fails = FAILS_GREYED)), then(PROC_REF(probe_done)))

/obj/dq_menu_probe/proc/probe_done(datum/act/op/A)
	return OP_OK

/// The row of `key` in the Menu rows, or null.
/proc/dq_menu_row(list/rows, key)
	for(var/list/row as anything in rows)
		if(row["key"] == key)
			return row
	return null

/// The hidden record of `key`, or null.
/proc/dq_menu_hidden_row(list/hidden, key)
	for(var/list/row as anything in hidden)
		if(row["key"] == key)
			return row
	return null

/// Identity and kind requirements are FAILS_HIDDEN, state requirements FAILS_GREYED, `fails =` overrides, and a combination derives it from the branch that failed.
/datum/unit_test/dq_menu_requirement_fails_kinds

/datum/unit_test/dq_menu_requirement_fails_kinds/Run()
	for(var/datum/entry/part/req/hidden_kind as anything in list(req_actor_kind(/mob/living/silicon), req_rights(R_ADMIN), req_self(), req_on_origin(ORIGIN_CLICK), req_on_authority(AUTH_ADMIN), req(/obj/item, of = ON_HELD), req(PROC_REF(dq_menu_probe_nothing), silent = TRUE)))
		TEST_ASSERT_EQUAL(hidden_kind.fails_as(), FAILS_HIDDEN, "[hidden_kind.part_name] is about who or what, so it hides")
	for(var/datum/entry/part/req/greyed_kind as anything in list(req_adjacent(), req_capable(), req_conscious(), req_alive(), req_is("ready"), req_at_least("ready", 1), req(PROC_REF(dq_menu_probe_nothing))))
		TEST_ASSERT_EQUAL(greyed_kind.fails_as(), FAILS_GREYED, "[greyed_kind.part_name] is about state, so it greys")
	var/datum/entry/part/req/forced_hidden = req_adjacent(fails = FAILS_HIDDEN)
	TEST_ASSERT_EQUAL(forced_hidden.fails_as(), FAILS_HIDDEN, "fails = overrides a greyed kind")
	var/datum/entry/part/req/forced_greyed = req_actor_kind(/mob/living/silicon, fails = FAILS_GREYED)
	TEST_ASSERT_EQUAL(forced_greyed.fails_as(), FAILS_GREYED, "fails = overrides a hidden kind")
	TEST_ASSERT(req_actor_kind(/mob/living/silicon).sig != forced_greyed.sig, "the override is part of the interned part")
	TEST_ASSERT_EQUAL(with_fails(all_of(req_adjacent(), req_capable()), FAILS_HIDDEN).fails_as(), FAILS_HIDDEN, "with_fails() declares it on a combination")

	// A combination is hidden by the branch that failed.
	var/turf/T = test_floor()
	var/turf/far = locate(T.x + 10, T.y, T.z)
	TEST_ASSERT(far, "a tile far from the test floor")
	var/obj/dq_menu_probe/probe = allocate(/obj/dq_menu_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, far)
	var/datum/act/op/A = pooled_op_context(probe, probe, H)
	var/datum/entry/part/req/kind_first = all_of(req_actor_kind(/mob/living/silicon/robot), req_adjacent())
	var/datum/entry/part/req/state_first = all_of(req_adjacent(), req_actor_kind(/mob/living/silicon/robot))
	var/datum/entry/part/req/either = any_of(req_actor_kind(/mob/living/silicon/robot), req_adjacent())
	var/datum/entry/part/req/both_identity = any_of(req_actor_kind(/mob/living/silicon/robot), req_rights(R_ADMIN))
	var/datum/entry/part/req/negated = req_not(req_actor_kind(/mob/living/carbon/human))
	var/kind_first_hides = kind_first.hides_when_failed(A)
	var/state_first_hides = state_first.hides_when_failed(A)
	var/either_hides = either.hides_when_failed(A)
	var/both_hides = both_identity.hides_when_failed(A)
	var/negated_hides = negated.hides_when_failed(A)
	A.release()
	TEST_ASSERT(kind_first_hides, "all_of: the failing branch is the identity one, so it hides")
	TEST_ASSERT(!state_first_hides, "all_of: the failing branch is the state one (the far tile), so it greys")
	TEST_ASSERT(!either_hides, "any_of: one branch (adjacent) is a state, so the row stays listed")
	TEST_ASSERT(both_hides, "any_of of identity branches hides")
	TEST_ASSERT(negated_hides, "req_not of an identity test hides")

/datum/unit_test/dq_menu_requirement_fails_kinds/proc/dq_menu_probe_nothing(datum/act/op/A)
	return null

/// The probe's Menu: tool lines hidden without the tool, the hinted one greyed "needs a welder", kinds and rights hidden, state greyed; the hidden view says why.
/datum/unit_test/dq_menu_applicability_probe

/datum/unit_test/dq_menu_applicability_probe/Run()
	var/turf/T = test_floor()
	var/obj/dq_menu_probe/probe = allocate(/obj/dq_menu_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/list/hidden = list()
	var/list/rows = op_menu(H, probe, null, hidden)
	TEST_ASSERT(!dq_menu_row(rows, "probe_plain"), "a tool line without the tool is not listed")
	var/list/hinted = dq_menu_row(rows, "probe_hinted")
	TEST_ASSERT(hinted, "the hinted tool line is listed: [json_encode(rows)]")
	TEST_ASSERT(!hinted["enabled"], "greyed")
	TEST_ASSERT(findtext(hinted["reason"], "welder"), "with the tool it needs: [hinted["reason"]]")
	TEST_ASSERT(!dq_menu_row(rows, "probe_kind"), "an op for another kind of actor is not listed")
	TEST_ASSERT(!dq_menu_row(rows, "probe_rights"), "an op for staff is not listed for a player")
	var/list/state = dq_menu_row(rows, "probe_state")
	TEST_ASSERT(state && !state["enabled"], "a state requirement greys the row: [json_encode(rows)]")
	var/list/overridden = dq_menu_row(rows, "probe_override")
	TEST_ASSERT(overridden && !overridden["enabled"], "fails = FAILS_GREYED lists the kind requirement greyed")
	TEST_ASSERT_EQUAL(dq_menu_hidden_row(hidden, "probe_kind")?["hidden_by"], "req_actor_kind", "the hidden view names the requirement: [json_encode(hidden)]")
	TEST_ASSERT_EQUAL(dq_menu_hidden_row(hidden, "probe_rights")?["hidden_by"], "req_rights", "the hidden view names the rights requirement")
	// the same menu read again (a cache hit) tells the same story
	var/list/hidden_again = list()
	var/list/rows_again = op_menu(H, probe, null, hidden_again)
	TEST_ASSERT_EQUAL(length(rows_again), length(rows), "the cached read lists the same rows")
	TEST_ASSERT_EQUAL(length(hidden_again), length(hidden), "the cached read keeps the hidden record")
	// a state change opens the greyed row
	probe.set_ready(TRUE)
	var/list/after = dq_menu_row(op_menu(H, probe, null), "probe_state")
	TEST_ASSERT(after?["enabled"], "the row opens when the state does")
	// the data the window gets: no staff view for a mob with no client
	var/list/data = interaction_menu_data(H, probe)
	TEST_ASSERT_NULL(data["hidden"], "a player gets no hidden view")
	// a cyborg is the kind probe_kind is for
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	TEST_ASSERT(dq_menu_row(op_menu(R, probe, null), "probe_kind")?["enabled"], "a cyborg is offered the cyborg op")

/// No kind of actor sees a row greyed only because of who it is: the "That isn't something you can do" and rights refusals are gone from the Menu.
/datum/unit_test/dq_menu_no_identity_refusals

/datum/unit_test/dq_menu_no_identity_refusals/Run()
	var/turf/T = test_floor()
	var/turf/side = get_step(T, EAST)
	var/mob/living/carbon/human/human = allocate(/mob/living/carbon/human, T)
	var/mob/living/silicon/robot/cyborg = allocate(/mob/living/silicon/robot, T)
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE)
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	var/list/actors = list(human, cyborg, AI, ghost)
	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, side)
	var/obj/machinery/vending/snack/vending = allocate(/obj/machinery/vending/snack, side)
	var/obj/machinery/power/apc/apc = allocate(/obj/machinery/power/apc, side)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, side)
	var/mob/living/silicon/robot/other_cyborg = allocate(/mob/living/silicon/robot, side)
	var/obj/item/tool/crowbar/item = allocate(/obj/item/tool/crowbar, side)
	var/list/targets = list(door, vending, apc, other, other_cyborg, item)
	var/wrong_actor = reason_text(/datum/msg/op/wrong_actor)
	var/no_rights = reason_text(/datum/msg/req_no_rights)
	var/checked = 0
	for(var/mob/actor as anything in actors)
		for(var/atom/target as anything in targets)
			for(var/list/row as anything in op_menu(actor, target, actor.get_active_hand()))
				checked++
				if(row["enabled"])
					continue
				TEST_ASSERT(row["reason"] != wrong_actor, "[actor.type] on [target.type]: \"[row["label"]]\" is not greyed for being the wrong kind of actor")
				TEST_ASSERT(row["reason"] != no_rights, "[actor.type] on [target.type]: \"[row["label"]]\" is not greyed for lacking admin rights")
	TEST_ASSERT(checked, "the menus had rows to look at")
