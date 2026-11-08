// The gate of E2, parts (doc/rewrite/final_api.html, section 19 "The seven workers", "E2, parts"). The fixtures are code/tests/engine/e2_fixtures.dm.
// Each test drives the engine through the test driver (test_click, test_ui, test_menu, test_answer, test_time) and reads the plain /datum/op_result
// it returns, as the E0 proofs do.

/// Base: the kernel on its injected clock around the test, a clean driver after.
/datum/unit_test/dq_e2
	abstract_type = /datum/unit_test/dq_e2

/datum/unit_test/dq_e2/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_e2/proc/run_gate()
	return

/// A fixture actor with hands.
/datum/unit_test/dq_e2/proc/actor()
	return allocate(/mob/living/simple_mob/e0_fixture)

// ---------------------------------------------------------------------------------------------------------------------
// One op through each input kind resolves to its intended winner.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e2/input_kinds

/datum/unit_test/dq_e2/input_kinds/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture/e2_topic_actor)
	var/obj/e2_box/B = allocate(/obj/e2_box)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar)
	var/obj/item/e2_key/key = allocate(/obj/item/e2_key)
	var/obj/item/e2_cloth/cloth = allocate(/obj/item/e2_cloth)
	// hand: an empty-handed click
	var/datum/op_result/by_hand = test_click(M, B, null)
	TEST_ASSERT_NOTNULL(by_hand, "an empty-handed click resolves")
	TEST_ASSERT_EQUAL(by_hand.key, "open", "an empty hand's click is the hand() op")
	TEST_ASSERT_EQUAL(by_hand.outcome, ACT_COMMITTED, "and it commits")
	TEST_ASSERT_EQUAL(B.opened, TRUE, "the toggle landed")
	// tool: the held crowbar's quality wins over the hand (tier PART over NORMAL)
	var/datum/op_result/by_tool = test_click(M, B, crowbar)
	TEST_ASSERT_EQUAL(by_tool?.key, "pry", "a crowbar click is the tool() op, which outranks the empty-hand use")
	TEST_ASSERT_NULL(by_tool?.outcome, "the tool profile's wait is pending")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(by_tool?.outcome, ACT_COMMITTED, "the wait ends and the op commits")
	TEST_ASSERT_EQUAL(B.pried, 1, "the pry ran")
	// item: the named held item
	var/datum/op_result/by_item = test_click(M, B, key)
	TEST_ASSERT_EQUAL(by_item?.key, "insert_key", "a key click is the item(T) op")
	TEST_ASSERT_EQUAL(B.keys, 1, "the key was used")
	TEST_ASSERT(QDELETED(key), "and consumes() used it up at commit")
	// drag: the dragged cloth dropped onto the box answers INTENT_DROP_ONTO
	var/datum/op_result/by_drag = test_click(M, B, cloth, GESTURE_DRAG)
	TEST_ASSERT_EQUAL(by_drag?.key, "slide_in", "a drag is the op that answers INTENT_DROP_ONTO")
	TEST_ASSERT_EQUAL(B.slid, 1, "the drop ran")
	// in hand: the held item on itself
	var/datum/op_result/in_hand = test_click(M, cloth, cloth, GESTURE_SELF)
	TEST_ASSERT_EQUAL(in_hand?.key, "polish", "an item used on itself is its in_hand() op")
	TEST_ASSERT_EQUAL(cloth.polished, 1, "the polish ran")
	// menu: a pick by key, origin ORIGIN_MENU
	var/datum/op_result/by_menu = test_menu(M, B, "peek")
	TEST_ASSERT_EQUAL(by_menu?.key, "peek", "a menu pick is the op named by key")
	TEST_ASSERT_EQUAL(by_menu?.origin, ORIGIN_MENU, "with the menu's origin")
	TEST_ASSERT_EQUAL(B.peeked, 1, "the peek ran")
	// UI: a window button; the argument crosses its schema
	var/datum/op_result/by_ui = test_ui(M, B, "set_label", list("text" = "hello"))
	TEST_ASSERT_EQUAL(by_ui?.key, "set_label", "a window button is the op with that ui_act() binding")
	TEST_ASSERT_EQUAL(by_ui?.origin, ORIGIN_UI, "with the UI origin")
	TEST_ASSERT_EQUAL(B.label_text, "hello", "the validated argument arrived as a typed parameter")
	var/datum/op_result/too_long = test_ui(M, B, "set_label", list("text" = "this is far too long"))
	TEST_ASSERT_EQUAL(too_long?.outcome, ACT_REFUSED, "a value that fails its schema refuses the press")
	TEST_ASSERT_EQUAL(B.label_text, "hello", "and the handler never ran")
	// topic: a link
	var/datum/op_result/by_topic = op_topic(M, B, "ping", list("n" = 3))
	TEST_ASSERT_EQUAL(by_topic?.key, "ping", "a topic link is the op with that topic() binding")
	TEST_ASSERT_EQUAL(by_topic?.outcome, ACT_COMMITTED, "the real topic admission gate permits this interactive actor")
	TEST_ASSERT_EQUAL(B.last_ping, 3, "its argument arrived")
	var/datum/op_result/bad_topic = op_topic(M, B, "ping", list("n" = 12))
	TEST_ASSERT_EQUAL(B.last_ping, 9, "an out-of-range number is clamped to the schema's ceiling, by the schema, never by the handler")
	TEST_ASSERT_EQUAL(bad_topic?.outcome, ACT_COMMITTED, "the schema-clamped topic still commits")
	var/turf/nearby = get_turf(B)
	var/turf/far_away = locate(nearby.x + 4, nearby.y, nearby.z)
	TEST_ASSERT(far_away, "the fixture has a real distant turf for topic admission")
	M.forceMove(far_away)
	var/datum/op_result/distant_topic = op_topic(M, B, "ping", list("n" = 4))
	TEST_ASSERT_EQUAL(distant_topic?.outcome, ACT_REFUSED, "the actual obj topic gate refuses a distant interactive actor")
	TEST_ASSERT_EQUAL(B.last_ping, 9, "refused topic admission leaves the previous real argument unchanged")
	M.forceMove(nearby)
	// inside: acting on the container the actor is in
	var/obj/e2_box/inner = allocate(/obj/e2_box)
	M.forceMove(inner)
	var/datum/op_result/by_inside = test_click(M, inner, null)
	TEST_ASSERT_EQUAL(by_inside?.key, "escape", "inside the box a click is the inside() op")
	TEST_ASSERT_EQUAL(inner.escaped, 1, "the escape ran")
	TEST_ASSERT(assert_resolves(M, inner, null, GESTURE_CLICK, "escape"), "assert_resolves names the same winner")
	M.forceMove(get_turf(B))
	TEST_ASSERT(assert_resolves(M, B, null, GESTURE_CLICK, "open"), "back outside, a click is the hand() op again")

// ---------------------------------------------------------------------------------------------------------------------
// A refusal shows its reason.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e2/refusal_shows_reason

/datum/unit_test/dq_e2/refusal_shows_reason/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/e2_vault/V = allocate(/obj/e2_vault)
	var/datum/op_result/refused = test_click(M, V, null)
	TEST_ASSERT_NOTNULL(refused, "the click reached the op: a Require refusal never falls through to nothing")
	TEST_ASSERT_EQUAL(refused.outcome, ACT_REFUSED, "a failed requirement refuses")
	TEST_ASSERT_EQUAL(refused.reason, MSG(e2/locked), "with the requirement's reason")
	TEST_ASSERT_EQUAL(reason_text(refused.reason), "It is locked.", "which reads as text")
	TEST_ASSERT_EQUAL(V.opened, FALSE, "and nothing happened")
	var/list/menu = action_options(M, V, null)
	var/found = FALSE
	for(var/list/row in menu)
		if(row["key"] == "open")
			found = TRUE
			TEST_ASSERT_EQUAL(row["enabled"], FALSE, "the menu greys the op out")
			TEST_ASSERT_EQUAL(row["reason"], "It is locked.", "and says why")
	TEST_ASSERT(found, "a refused op is still listed")
	V.set_locked(FALSE)
	var/datum/op_result/opened = test_click(M, V, null)
	TEST_ASSERT_EQUAL(opened?.outcome, ACT_COMMITTED, "unlocked, the same click commits")
	TEST_ASSERT_EQUAL(V.opened, TRUE, "and the effect ran")

// ---------------------------------------------------------------------------------------------------------------------
// asks() cancel leaves costs unspent; an effect written above an asks() is a build error.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e2/asks_cancel_unspent

/datum/unit_test/dq_e2/asks_cancel_unspent/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/e2_machine/machine = allocate(/obj/e2_machine)
	M.dark_energy = 50
	test_record(M, machine)
	var/datum/op_result/waiting = test_ui(M, machine, "rename", list())
	TEST_ASSERT_NOTNULL(waiting, "the press returns a result")
	TEST_ASSERT_NULL(waiting.outcome, "the op waits on the prompt: no outcome yet")
	TEST_ASSERT_EQUAL(M.dark_energy, 50, "nothing is spent while it waits")
	var/datum/op_result/cancelled = test_answer(M, null, REQ_CANCELLED)
	var/list/cancelled_events = test_recorded()
	TEST_ASSERT_EQUAL(cancelled?.outcome, ACT_REFUSED, "cancelling the prompt refuses the op")
	TEST_ASSERT(cancelled == waiting, "through the same result the press returned")
	TEST_ASSERT_EQUAL(M.dark_energy, 50, "no cost was spent")
	TEST_ASSERT_EQUAL(test_events_count(cancelled_events, TEST_EVENT_RESERVE), 0, "none was even reserved: costs are reserved after the last answer")
	TEST_ASSERT_NULL(machine.label_text, "and nothing was renamed")
	// answered: the cost is reserved after the answer and committed after the effect
	test_record(M, machine)
	var/datum/op_result/second = test_ui(M, machine, "rename", list())
	TEST_ASSERT_NULL(second?.outcome, "asked again")
	var/datum/op_result/answered = test_answer(M, "Bob")
	var/list/answered_events = test_recorded()
	TEST_ASSERT_EQUAL(answered?.outcome, ACT_COMMITTED, "an answer commits")
	TEST_ASSERT_EQUAL(machine.label_text, "Bob", "the effect read the answer")
	TEST_ASSERT_EQUAL(M.dark_energy, 45, "the cost was spent once, after the effect")
	TEST_ASSERT_EQUAL(test_events_count(answered_events, TEST_EVENT_RESERVE), 1, "one reservation")
	TEST_ASSERT_EQUAL(test_events_count(answered_events, TEST_EVENT_COMMIT), 1, "committed once")
	TEST_ASSERT_EQUAL(test_events_count(answered_events, TEST_EVENT_RELEASE), 0, "and none released")

/datum/unit_test/dq_e2/effect_above_asks_is_a_build_error

/datum/unit_test/dq_e2/effect_above_asks_is_a_build_error/run_gate()
	GLOB.declare_report_capture = list()
	table_compile(/obj/e2_machine, null, list(op("bad", hand(), then("note_pry"), asks(/datum/prompt/text, fields = list("question" = "x")))), "test:1")
	var/list/reports = GLOB.declare_report_capture
	GLOB.declare_report_capture = null
	var/matched = FALSE
	for(var/report in reports)
		if(findtext(report, "[RULE_OP_ORDER]") && findtext(report, "then() is written above asks()"))
			matched = TRUE
	TEST_ASSERT(matched, "an effect written above an asks() is reported with its rule: [jointext(reports, " | ")]")
	GLOB.declare_report_capture = list()
	table_compile(/obj/e2_machine, null, list(op("fine", hand(), confirms("sure?"), then("note_pry"))), "test:2")
	var/list/clean = GLOB.declare_report_capture
	GLOB.declare_report_capture = null
	TEST_ASSERT_EQUAL(length(clean), 0, "the effect below its asks() is fine: [jointext(clean, " | ")]")

// ---------------------------------------------------------------------------------------------------------------------
// wait() is cancelled with feedback when the target is deleted.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e2/wait_cancelled_when_target_deleted

/datum/unit_test/dq_e2/wait_cancelled_when_target_deleted/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/e2_lever/L = allocate(/obj/e2_lever)
	var/datum/op_result/waiting = test_click(M, L, null)
	TEST_ASSERT_NOTNULL(waiting, "the click started a wait")
	TEST_ASSERT_NULL(waiting.outcome, "no outcome while it waits")
	TEST_ASSERT_NOTNULL(op_pending_of(M), "the actor has a pending op")
	qdel(L)
	TEST_ASSERT_EQUAL(waiting.outcome, ACT_REFUSED, "deleting the target cancels the op")
	TEST_ASSERT_EQUAL(waiting.reason, /datum/msg/op/target_gone, "with the reason")
	TEST_ASSERT_NULL(op_pending_of(M), "and the actor is free again")
	var/found_line = FALSE
	for(var/datum/test_log/line in test_logs())
		if(line.key == "pull_slow" && line.outcome == ACT_REFUSED)
			found_line = TRUE
	TEST_ASSERT(found_line, "the cancellation is logged with its key chain")
	// the keeps: dropping what the op was started with, or the target leaving, cancels it too
	var/obj/e2_lever/L2 = allocate(/obj/e2_lever)
	var/datum/op_result/second = test_click(M, L2, null)
	TEST_ASSERT_NULL(second?.outcome, "a second wait")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(second?.outcome, ACT_COMMITTED, "left alone, the wait ends and the op commits")
	TEST_ASSERT_EQUAL(L2.pulled, TRUE, "its effect ran after the wait")

// ---------------------------------------------------------------------------------------------------------------------
// Two ops with the same input, intent and tier are a build error.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e2/same_input_is_a_build_error

/datum/unit_test/dq_e2/same_input_is_a_build_error/run_gate()
	GLOB.declare_report_capture = list()
	table_compile(/obj/e2_box, null, list(op("one", hand(), then("note_pry")), op("two", hand(), then("note_key"))), "test:1")
	var/list/clash = GLOB.declare_report_capture
	GLOB.declare_report_capture = null
	var/matched = FALSE
	for(var/report in clash)
		if(findtext(report, "[RULE_OP_CLASH]") && findtext(report, "\"one\"") && findtext(report, "\"two\""))
			matched = TRUE
	TEST_ASSERT(matched, "two hand() ops at one tier name both: [jointext(clash, " | ")]")
	// the ways out: a different tier, a different input, passes(), mutually exclusive when() parts
	GLOB.declare_report_capture = list()
	table_compile(/obj/e2_box, null, list( \
		op("a", hand(), priority(OP_PRIORITY_PART), then("note_pry")), \
		op("b", hand(), then("note_key")), \
		op("c", tool(TOOL_CROWBAR), then("note_slide")), \
		op("d", hand(), answers(INTENT_EXAMINE), then("note_peek")), \
		op("e", ui_act("e"), then("note_peek")), \
		op("f", ui_act("f"), then("note_peek"))), "test:2")
	var/list/fine = GLOB.declare_report_capture
	GLOB.declare_report_capture = null
	TEST_ASSERT_EQUAL(length(fine), 0, "a different tier, input or intent is not a clash: [jointext(fine, " | ")]")
	GLOB.declare_report_capture = list()
	table_compile(/obj/e2_box, null, list( \
		op("g", hand(), when("opened"), then("note_pry")), \
		op("h", hand(), when(not("opened")), then("note_key"))), "test:3")
	var/list/exclusive = GLOB.declare_report_capture
	GLOB.declare_report_capture = null
	TEST_ASSERT_EQUAL(length(exclusive), 0, "mutually exclusive when() parts do not clash: [jointext(exclusive, " | ")]")
	GLOB.declare_report_capture = list()
	table_compile(/obj/e2_box, null, list(op("i", ui_act("same"), then("note_pry")), op("j", ui_act("same"), then("note_key"))), "test:4")
	var/list/ui_clash = GLOB.declare_report_capture
	GLOB.declare_report_capture = null
	TEST_ASSERT(length(ui_clash) > 0, "two ops answering one window action clash")

// ---------------------------------------------------------------------------------------------------------------------
// any_of / all_of over req_is() conditions: the clash check sees when they can never both hold.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e2/any_all_of_req_is_exclusive

/datum/unit_test/dq_e2/any_all_of_req_is_exclusive/run_gate()
	// any_of(a, b) against all_of(not a, not b): when one holds the other cannot
	GLOB.declare_report_capture = list()
	table_compile(/obj/e2_box, null, list( 		op("g", hand(), when(any_of(req_is("opened"), req_is("sealed"))), then("note_pry")), 		op("h", hand(), when(all_of(req_is("opened", FALSE), req_is("sealed", FALSE))), then("note_key"))), "test:any_all:1")
	var/list/exclusive = GLOB.declare_report_capture
	GLOB.declare_report_capture = null
	TEST_ASSERT_EQUAL(length(exclusive), 0, "any_of(a, b) and all_of(!a, !b) never both hold, so they do not clash: [jointext(exclusive, " | ")]")
	// the same pair the other way round
	GLOB.declare_report_capture = list()
	table_compile(/obj/e2_box, null, list( 		op("g", hand(), when(all_of(req_is("opened", FALSE), req_is("sealed", FALSE))), then("note_pry")), 		op("h", hand(), when(any_of(req_is("opened"), req_is("sealed"))), then("note_key"))), "test:any_all:2")
	var/list/reversed = GLOB.declare_report_capture
	GLOB.declare_report_capture = null
	TEST_ASSERT_EQUAL(length(reversed), 0, "and in the other order: [jointext(reversed, " | ")]")
	// any_of(a, b) against not a alone: b can hold with a false, so they can both hold
	GLOB.declare_report_capture = list()
	table_compile(/obj/e2_box, null, list( 		op("g", hand(), when(any_of(req_is("opened"), req_is("sealed"))), then("note_pry")), 		op("h", hand(), when(req_is("opened", FALSE)), then("note_key"))), "test:any_all:3")
	var/list/overlap = GLOB.declare_report_capture
	GLOB.declare_report_capture = null
	var/matched = FALSE
	for(var/report in overlap)
		if(findtext(report, "[RULE_OP_CLASH]") && findtext(report, "\"g\"") && findtext(report, "\"h\""))
			matched = TRUE
	TEST_ASSERT(matched, "any_of(a, b) against !a can both hold (b alone), so it still clashes: [jointext(overlap, " | ")]")
	// all_of(a, c) against not a: one conjunct is enough
	GLOB.declare_report_capture = list()
	table_compile(/obj/e2_box, null, list( 		op("g", hand(), when(all_of(req_is("opened"), req_is("sealed"))), then("note_pry")), 		op("h", hand(), when(req_is("opened", FALSE)), then("note_key"))), "test:any_all:4")
	var/list/conjunct = GLOB.declare_report_capture
	GLOB.declare_report_capture = null
	TEST_ASSERT_EQUAL(length(conjunct), 0, "all_of(a, b) against !a cannot both hold: [jointext(conjunct, " | ")]")

// ---------------------------------------------------------------------------------------------------------------------
// explain_click matches a golden.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e2/explain_click_golden

/datum/unit_test/dq_e2/explain_click_golden/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/e2_box/B = allocate(/obj/e2_box)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar)
	var/text = explain_click(M, B, crowbar, GESTURE_CLICK)
	// Every type's topic links (View Variables, the stat panel) are candidates too, dropped by origin on a click: the golden is the fixture's,
	// the engine's and the mob's own, so those lines are left out, the rest renumbered, and the winner's declared index (a count of all) ignored.
	var/regex/numbered = regex(@"^(\s+)\d+\. ")
	var/regex/declared = regex(@"declared \d+\)")
	var/list/lines = list()
	var/kept = 0
	for(var/line in splittext(text, "\n"))
		if(findtext(line, " topic(") && !findtext(line, "code/tests/engine/e2_fixtures.dm"))
			continue
		if(numbered.Find(line))
			kept++
			line = numbered.Replace(line, "$1[kept]. ")
		line = declared.Replace(line, "declared N)")
		lines += line
	for(var/i in 1 to length(lines))
		if(findtext(lines[i], "candidates ("))
			lines[i] = "  candidates ([kept]):"
	var/list/golden = list(
		"explain: actor /mob/living/simple_mob/e0_fixture target /obj/e2_box held /obj/item/tool/crowbar origin click gesture click",
		"  intents: use",
		"  candidates (93):",
		"    1. drag_buckle item(/mob/living) tier=default claims=none (derived) side=target @ code/domains/world_model/atom/atoms_movable.dm:936 section lazy_state -> dropped by match",
		"    2. disconnect_hose menu(Quickly disconnect a hose from all machines it is attached to.) tier=normal claims=none (derived) side=target @ code/domains/world_model/atom/atoms_movable.dm:937 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    3. micro_interact menu(Micros can enter, or move between objects with this! Non-micros can reach into objects to search for micros!) tier=normal claims=none (derived) side=target @ code/domains/world_model/obj/objs.dm:289 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    4. micro_interact_inside menu(Exit, or move to another micro-enterable object.) tier=normal claims=none (derived) side=target @ code/domains/world_model/obj/objs.dm:290 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    5. melee_hit item(/obj/item) tier=-2009 claims=none (derived) side=target @ code/domains/world_model/obj/objs.dm:291 section lazy_state -> dropped by match",
		"    6. open hand tier=normal claims=none (derived) side=target @ code/tests/engine/e2_fixtures.dm:57 -> survives, after the winner",
		"    7. pry tool(crowbar) tier=part claims=hands+body (derived) side=target @ code/tests/engine/e2_fixtures.dm:58 -> WINNER (placed: intent rank 1, tier part, side target, declared N)",
		"    8. insert_key item(/obj/item/e2_key) tier=part claims=none (derived) side=target @ code/tests/engine/e2_fixtures.dm:59 -> dropped by match",
		"    9. slide_in item(/obj/item/e2_cloth) tier=part claims=none (derived) side=target @ code/tests/engine/e2_fixtures.dm:60 -> dropped by match",
		"    10. peek menu tier=normal claims=none (derived) side=target @ code/tests/engine/e2_fixtures.dm:61 -> dropped by origin (You can't do that that way.)",
		"    11. set_label ui_act(set_label) tier=normal claims=none (derived) side=target @ code/tests/engine/e2_fixtures.dm:62 -> dropped by origin (You can't do that that way.)",
		"    12. ping topic(ping) tier=normal claims=none (derived) side=target @ code/tests/engine/e2_fixtures.dm:63 -> dropped by origin (You can't do that that way.)",
		"    13. escape inside tier=normal claims=none (derived) side=target @ code/tests/engine/e2_fixtures.dm:64 -> dropped by reach (You can't reach that.)",
		"    14. drag_buckle item(/mob/living) tier=default claims=none (derived) side=held @ code/domains/world_model/atom/atoms_movable.dm:936 section lazy_state -> dropped by match",
		"    15. disconnect_hose menu(Quickly disconnect a hose from all machines it is attached to.) tier=normal claims=none (derived) side=held @ code/domains/world_model/atom/atoms_movable.dm:937 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    16. micro_interact menu(Micros can enter, or move between objects with this! Non-micros can reach into objects to search for micros!) tier=normal claims=none (derived) side=held @ code/domains/world_model/obj/objs.dm:289 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    17. micro_interact_inside menu(Exit, or move to another micro-enterable object.) tier=normal claims=none (derived) side=held @ code/domains/world_model/obj/objs.dm:290 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    18. kit_customize item(/obj/item/kit) tier=part claims=none (derived) side=held @ code/domains/world_model/obj/items.dm:1245 section lazy_state -> dropped by match",
		"    19. kit_customize_last item(/obj/item/kit) tier=-2001 claims=none (derived) side=held @ code/domains/world_model/obj/items.dm:1246 section lazy_state -> dropped by match",
		"    20. move_to_top menu tier=normal claims=none (derived) side=held @ code/domains/world_model/obj/items.dm:1247 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    21. toggle_digestable menu tier=normal claims=none (derived) side=held @ code/domains/world_model/obj/items.dm:1248 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    22. pick_up_item hand tier=-2010 claims=none (derived) side=held @ code/domains/world_model/obj/items.dm:1249 section lazy_state -> dropped by match",
		"    23. collect_item item(/obj/item/storage) tier=default claims=none (derived) side=held @ code/domains/world_model/obj/items.dm:1250 section lazy_state -> dropped by match",
		"    24. gen_silicon_item_silicon_equip_module remote tier=-2050 claims=none (derived) side=held @ code/domains/world_model/obj/items.dm:1251 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    25. drag_buckle item(/mob/living) tier=default claims=none (derived) side=actor @ code/domains/world_model/atom/atoms_movable.dm:936 section lazy_state -> dropped by match",
		"    26. disconnect_hose menu(Quickly disconnect a hose from all machines it is attached to.) tier=normal claims=none (derived) side=actor @ code/domains/world_model/atom/atoms_movable.dm:937 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    27. yank_out_object menu(Remove an embedded item at the cost of bleeding and pain.) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/mob_defines.dm:166 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    28. yank_out ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/mob_defines.dm:193 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    29. zmove ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/mob_defines.dm:195 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    30. spin ai tier=normal claims=none (claims()) side=actor @ code/domains/world_model/mob/mob_defines.dm:197 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    31. hardsuit_interface menu(Open the interface of the hardsuit you are loaded into.) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:150 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    32. combat_move menu(Trigger one of your AI mob's special moves.) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:151 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    33. abilities_panel menu(Every ability your species, traits and form give you, in one window.) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:152 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    34. ling_evolution menu(Adapt yourself carefully.) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:153 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    35. ling_respec menu(Forget your adaptations and choose again.) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:154 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    36. ling_hive_channel menu(Channel DNA in the airwaves to allow other changelings to absorb it.) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:155 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    37. ling_hive_absorb menu(Absorb a single DNA from the airwaves.) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:156 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    38. toggle_self_surgery menu(Toggles the 'safeties' on self-surgery, allowing you to do so.) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:157 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    39. activate_held menu(Use the item in your active hand.) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:158 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    40. mob_sleep menu tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:159 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    41. check_default_language menu tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:160 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    42. give menu tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:161 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    43. lick menu(Lick someone nearby!) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:162 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    44. smell menu(Smell someone nearby!) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:163 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    45. look_up menu(Look above you, and hope there's no ceiling spiders.) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:164 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    46. attack_variants.disarm menu tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:176 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    47. attack_variants.grab menu tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:176 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    48. touch_help hand tier=-2010 claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:177 section lazy_state -> dropped by match",
		"    49. touch_disarm hand tier=-2010 claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:178 section lazy_state -> dropped by match",
		"    50. touch_grab hand tier=-2010 claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:179 section lazy_state -> dropped by match",
		"    51. touch_hurt hand tier=-2010 claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:180 section lazy_state -> dropped by match",
		"    52. hit_help item(/obj/item) tier=-2010 claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:181 section lazy_state -> dropped by match",
		"    53. hit_disarm item(/obj/item) tier=-2010 claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:182 section lazy_state -> dropped by match",
		"    54. hit_grab item(/obj/item) tier=-2010 claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:183 section lazy_state -> dropped by match",
		"    55. hit_hurt item(/obj/item) tier=-2010 claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:184 section lazy_state -> dropped by match",
		"    56. healing_rainbows ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    57. injection ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    58. succubus_bite ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    59. absorb_devour ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    60. dominate_predator ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    61. dominate_prey ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    62. lend_prey_control ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    63. shred_limb ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    64. beacon_insert ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    65. body_writing ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    66. eat_minerals ai tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    67. harvest ai tier=normal claims=target (claims()) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    68. butcher ai tier=normal claims=target (claims()) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    69. melee_swing ai tier=normal claims=none (claims()) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    70. climb_wall ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    71. climb_down ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    72. ventcrawl_in ai tier=normal claims=target (claims()) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    73. egg_laying ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    74. vertical_nom ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    75. revert_beast_form ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    76. polymorph ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/living_defines.dm:188 section lazy_state -> dropped by origin (You can't do that that way.)",
		"    77. vore_check_nutrition menu(Check your current nutrition level.) tier=normal claims=none (derived) side=actor @ code/content/vore/eating/living.dm:2064 -> dropped by origin (You can't do that that way.)",
		"    78. print_healthbars menu tier=normal claims=none (derived) side=actor @ code/content/vore/eating/living.dm:2065 -> dropped by origin (You can't do that that way.)",
		"    79. devour ai tier=normal claims=body (derived) side=actor @ code/content/vore/eating/living.dm:2067 -> dropped by origin (You can't do that that way.)",
		"    80. toggle_vore_icons menu(Toggle visibility of changed mob sprite when you have eaten other things.) tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:162 -> dropped by origin (You can't do that that way.)",
		"    81. reload ai tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:174 -> dropped by origin (You can't do that that way.)",
		"    82. mob_attacks.melee ai tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:175 -> dropped by origin (You can't do that that way.)",
		"    83. mob_attacks.shoot ai tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:175 -> dropped by origin (You can't do that that way.)",
		"    84. mob_attacks.step ai tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:175 -> dropped by origin (You can't do that that way.)",
		"    85. mob_attacks.special ai tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:175 -> dropped by origin (You can't do that that way.)",
		"    86. mob_attacks.fire ai tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:175 -> dropped by origin (You can't do that that way.)",
		"    87. mob_attacks.throw ai tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:175 -> dropped by origin (You can't do that that way.)",
		"    88. mob_attacks.pickup ai tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:175 -> dropped by origin (You can't do that that way.)",
		"    89. mob_attacks.alarm ai tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:175 -> dropped by origin (You can't do that that way.)",
		"    90. mob_attacks.charge ai tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:175 -> dropped by origin (You can't do that that way.)",
		"    91. mob_attacks.slam ai tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:175 -> dropped by origin (You can't do that that way.)",
		"    92. nutrition_heal menu(Nutrition Heal) tier=normal claims=body (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:195 -> dropped by origin (You can't do that that way.)",
		"    93. ghost_join observe tier=normal claims=none (derived) side=actor @ code/domains/world_model/mob/simple_mob.dm:206 -> dropped by match",
		"  winner: pry (tier part)")
	TEST_ASSERT_EQUAL(length(lines), length(golden), "the explanation has the golden's lines (other types' topic links left out):\n[jointext(lines, "\n")]")
	// An origin's line number moves whenever its file is edited above it: the file and the entry are what the golden pins.
	var/regex/origin_line = regex(@"\.dm:[0-9]+ ->")
	for(var/i in 1 to min(length(lines), length(golden)))
		TEST_ASSERT_EQUAL(origin_line.Replace(lines[i], ".dm ->"), origin_line.Replace(golden[i], ".dm ->"),"line [i] of the explanation differs from the golden, whole text follows:\n[text]")

