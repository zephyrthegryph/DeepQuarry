// The construction and deconstruct capabilities and the standard frame ladder
// (code/datums/capabilities/construction.dm, frame_ladder.dm).

/// Runs `step` on `target` with no wait. Returns what perform() returned.
/datum/unit_test/proc/ladder_walk(mob/actor, atom/target, datum/interaction/capability/construction_step/step, obj/item/held)
	set_global("dq_ladder_instant", TRUE)
	. = step.perform(actor, target, held)
	set_global("dq_ladder_instant", FALSE)

/// The step leaving `target`'s stage toward `destination` (a stage name or LADDER_DONE).
/datum/unit_test/proc/ladder_step(atom/target, from, destination)
	for(var/datum/interaction/capability/construction_step/step as anything in ladder_steps_for(target))
		if(step.from_state == from && step.to_state == destination)
			return step
	return null

/// What `A` draws now: the icon state its draw(look) sets, or null.
/datum/unit_test/proc/drawn_state(atom/A)
	var/datum/look/look = new
	A.draw(look)
	return look.icon_state

/// A test holder whose capabilities use every kind of stage, cost and step.
/obj/cap_fixture/ladder_probe
	name = "ladder probe"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "probe_base"
	var/marker
	var/hot = FALSE

/obj/cap_fixture/ladder_probe/capabilities()
	. = ..()
	. += cap_construction(
		ladder_options(anywhere = list(branch("start", cap_tool(quality = TOOL_CROWBAR), say = "reset %T%", when = PROC_REF(probe_can_reset)))),
		stage("start", desc = "A probe at the start."),
		stage("wired", build = cap_use_on(held_type = /obj/item/stack/cable_coil), uses = 3, undo = cap_tool(quality = TOOL_WIRECUTTER),
			anchored = TRUE, icon = "probe_wired", on_enter = PROC_REF(probe_marked)),
		stage("boarded", build = cap_insert(held_type = /obj/item/stock_parts/capacitor, needs = PROC_REF(probe_cool), else_say = "it is too hot"),
			undo = cap_hand(), icon = "probe_boarded"),
		stage("finished", build = cap_tool(quality = TOOL_WRENCH, delay = 3 SECONDS, fuel = 2, volume = 10),
			also = list(branch(LADDER_DONE, cap_tool(quality = TOOL_SCREWDRIVER), say = "melt %T% down", become = /obj/item/stack/material/steel, amount = 2,
				needs = PROC_REF(probe_cool), else_say = "it is too hot"))),
	)

/obj/cap_fixture/ladder_probe/proc/probe_marked(mob/user, obj/item/held, from)
	marker = "wired"

/obj/cap_fixture/ladder_probe/proc/probe_cool(mob/user, obj/item/held)
	return !hot

/obj/cap_fixture/ladder_probe/proc/probe_can_reset()
	return ladder_stage_index(src) > 1

/obj/cap_fixture/ladder_probe/proc/probe_hook(mob/user, obj/item/held)
	return TRUE

/// A holder whose ladder keeps its stage in a holder var and whose cost wrongly has a handler.
/obj/cap_fixture/ladder_bad
	name = "bad ladder"
	var/phase = "one"

/obj/cap_fixture/ladder_bad/capabilities()
	. = ..()
	. += cap_construction(
		ladder_options(state_var = nameof(src.phase)),
		stage("one"),
		stage("two", build = cap_tool(quality = TOOL_WRENCH, handler = PROC_REF(bad_handler))),
	)

/obj/cap_fixture/ladder_bad/proc/bad_handler(mob/user, obj/item/held)
	return TRUE

/// The probe's ladder is valid and its steps run through the capability and the dispatch.
/datum/unit_test/dq_capability_construction

/datum/unit_test/dq_capability_construction/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/ladder_probe/probe = allocate(/obj/cap_fixture/ladder_probe, T)
	var/datum/construction_ladder/ladder = ladder_of(probe)
	TEST_ASSERT(ladder, "the probe's capabilities give it a ladder")
	var/list/problems = ladder.validate()
	TEST_ASSERT(!length(problems), "valid: [jointext(problems, "; ")]")
	TEST_ASSERT_EQUAL(ladder.state_of(probe), "start", "a new holder is on the first stage")
	TEST_ASSERT(length(cap_interactions(probe)) >= 5, "the steps are the capability's interactions")
	var/text = jointext(caps_examine(probe, H), "\n")
	TEST_ASSERT(findtext(text, "A probe at the start."), "examine comes from the capability: [text]")
	TEST_ASSERT(findtext(text, "Next: add 3 "), "examine lists the next step: [text]")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 5)
	var/datum/interaction/capability/construction_step/wire = ladder_step(probe, "start", "wired")
	TEST_ASSERT(ladder_walk(H, probe, wire, coil), "building runs through the dispatch")
	TEST_ASSERT_EQUAL(ladder.state_of(probe), "wired", "the stage is kept in the capability's data")
	TEST_ASSERT_EQUAL(coil.get_amount(), 2, "three cable used")
	TEST_ASSERT(probe.anchored, "the stage anchored it")
	TEST_ASSERT_EQUAL(probe.marker, "wired", "on_enter ran")

	var/obj/item/tool/wirecutters/cutters = dq_fast_tool(/obj/item/tool/wirecutters, T)
	TEST_ASSERT(ladder_walk(H, probe, ladder_step(probe, "wired", "start"), cutters), "undo runs")
	TEST_ASSERT(!probe.anchored, "unanchored again")
	TEST_ASSERT(locate(/obj/item/stack/cable_coil) in T.contents - coil, "the undo gave the cable back")

	TEST_ASSERT(ladder_set_stage(probe, "wired"), "set from outside a step")
	var/obj/item/stock_parts/capacitor/part = allocate(/obj/item/stock_parts/capacitor, T)
	var/datum/interaction/capability/construction_step/board = ladder_step(probe, "wired", "boarded")
	probe.hot = TRUE
	TEST_ASSERT_EQUAL(board.why_not(H, probe, part), "it is too hot", "the cost entry's needs / else_say gate the step")
	probe.hot = FALSE
	TEST_ASSERT(ladder_walk(H, probe, board, part), "inserting runs")
	TEST_ASSERT_EQUAL(part.loc, probe, "the part went into the holder")
	TEST_ASSERT(ladder_walk(H, probe, ladder_step(probe, "boarded", "wired"), null), "taking it out by hand runs")
	TEST_ASSERT_EQUAL(part.loc, T, "the hand undo gave the part back")

	TEST_ASSERT(ladder_set_stage(probe, "finished"), "set from outside a step")
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/datum/interaction/capability/construction_step/melt = ladder_step(probe, "finished", LADDER_DONE)
	probe.hot = TRUE
	TEST_ASSERT_EQUAL(melt.why_not(H, probe, screwdriver), "it is too hot", "needs refuses with else_say")
	probe.hot = FALSE
	TEST_ASSERT(ladder_walk(H, probe, melt, screwdriver), "the finishing branch runs")
	TEST_ASSERT(QDELETED(probe), "become replaced the probe")
	own_turf_contents(T)

/// The framework entries are the ladder's costs: each kind maps onto the step it builds.
/datum/unit_test/dq_capability_construction_costs

/datum/unit_test/dq_capability_construction_costs/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ladder_probe/probe = allocate(/obj/cap_fixture/ladder_probe, T)
	var/datum/construction_ladder/ladder = ladder_of(probe)

	var/list/leaving_start = ladder.edges_leaving("start")
	var/datum/interaction/capability/construction_step/wire = leaving_start[1]
	TEST_ASSERT_EQUAL(wire.to_state, "wired", "the first step leaving start is the build")
	TEST_ASSERT_EQUAL(wire.item_use, LADDER_ITEM_USE, "cap_use_on() on a stack with uses is used up")
	TEST_ASSERT_EQUAL(wire.item_amount, 3, "uses is the stack amount")
	TEST_ASSERT_EQUAL(wire.held_type, /obj/item/stack/cable_coil, "the step is meant with the item in hand")

	var/datum/interaction/capability/construction_step/unwire = null
	for(var/datum/interaction/capability/construction_step/step as anything in ladder.edges_leaving("wired"))
		if(step.to_state == "start" && step.tool == TOOL_WIRECUTTER)
			unwire = step
	TEST_ASSERT(unwire, "cap_tool() undo")
	TEST_ASSERT_EQUAL(unwire.refund_use, LADDER_ITEM_USE, "undo gives back the stack")
	TEST_ASSERT_EQUAL(unwire.refund_amount, 3, "all three units")

	var/datum/interaction/capability/construction_step/board = null
	var/datum/interaction/capability/construction_step/unboard = null
	for(var/datum/interaction/capability/construction_step/step as anything in ladder.edges)
		if(step.from_state == "wired" && step.to_state == "boarded")
			board = step
		if(step.from_state == "boarded" && step.to_state == "wired")
			unboard = step
	TEST_ASSERT_EQUAL(board.item_use, LADDER_ITEM_INSERT, "cap_insert() puts the part in")
	TEST_ASSERT_EQUAL(length(board.step_needs), 1, "the entry's needs joined the step's")
	TEST_ASSERT(unboard.by_hand, "cap_hand() is an empty-hand step")
	TEST_ASSERT_EQUAL(unboard.refund_use, LADDER_ITEM_INSERT, "the hand undo takes the part back out")
	TEST_ASSERT(findtext(unboard.phrase, "take the"), "its phrase names the part: [unboard.phrase]")

	var/datum/interaction/capability/construction_step/finish = null
	for(var/datum/interaction/capability/construction_step/step as anything in ladder.edges)
		if(step.to_state == "finished")
			finish = step
	TEST_ASSERT_EQUAL(finish.tool, TOOL_WRENCH, "cap_tool() quality")
	TEST_ASSERT_EQUAL(finish.duration, 3 SECONDS, "cap_tool() delay")
	TEST_ASSERT_EQUAL(finish.tool_amount, 2, "cap_tool() fuel")
	TEST_ASSERT_EQUAL(finish.tool_volume, 10, "cap_tool() volume")
	TEST_ASSERT_EQUAL(finish.requirement_text(), "needs a wrench", "examine names the tool")

	// A plain cap_use_on() without uses is only checked.
	var/datum/capability/entry/tape = cap_use_on(held_type = /obj/item/tape_roll, delay = 1 SECOND)
	TEST_ASSERT_EQUAL(ladder_entry_kind(tape.entry, 0), LADDER_COST_HOLD, "no uses: only checked")
	TEST_ASSERT_EQUAL(tape.entry.duration, 1 SECOND, "cap_use_on() delay")
	qdel(tape)

	// A cost with a handler, and a stage kept in a holder var.
	var/obj/cap_fixture/ladder_bad/bad = allocate(/obj/cap_fixture/ladder_bad, T)
	var/datum/construction_ladder/bad_ladder = ladder_of(bad)
	var/list/problems = bad_ladder.validate()
	TEST_ASSERT(length(problems) && findtext(jointext(problems, ";"), "has a handler"), "a cost with a handler is reported: [jointext(problems, "; ")]")
	TEST_ASSERT_EQUAL(bad_ladder.state_of(bad), "one", "the stage is read from the holder var")
	TEST_ASSERT(!capability_data(bad), "a holder-var ladder keeps no capability data")
	own_turf_contents(T)

/// Stage icons are drawn through draw(look), and the per-instance stage is made at init and dropped at destroy.
/datum/unit_test/dq_capability_construction_look

/datum/unit_test/dq_capability_construction_look/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ladder_probe/probe = allocate(/obj/cap_fixture/ladder_probe, T)
	var/datum/capability/construction/C = cap_of(probe, /datum/capability/construction)
	var/datum/ladder_progress/progress = capability_data(probe)?[C.key]
	TEST_ASSERT(progress, "on_holder_init made the stage data")
	TEST_ASSERT_EQUAL(progress?.stage, "start", "on the start stage")

	TEST_ASSERT_EQUAL(drawn_state(probe), "probe_base", "a stage with no icon draws the type's default")
	ladder_set_stage(probe, "wired")
	TEST_ASSERT_EQUAL(drawn_state(probe), "probe_wired", "the stage's icon is drawn")
	ladder_set_stage(probe, "boarded")
	TEST_ASSERT_EQUAL(drawn_state(probe), "probe_boarded", "the next stage's icon is drawn")
	TEST_ASSERT_EQUAL(probe.icon_state, initial(probe.icon_state), "no step or set writes icon_state; the look applies it")

	C.legacy_holder_destroy(probe)
	TEST_ASSERT(!capability_data(probe)?[C.key], "on_holder_destroy dropped the stage data")
	TEST_ASSERT(QDELETED(progress), "and deleted it")
	TEST_ASSERT_EQUAL(drawn_state(probe), "probe_base", "with no data the holder reads as the start stage")
	own_turf_contents(T)

/// The standard frame ladder is valid on a real frame.
/datum/unit_test/dq_capability_frame_ladder

/datum/unit_test/dq_capability_frame_ladder/Run()
	var/turf/T = test_floor()
	var/obj/structure/frame/frame = allocate(/obj/structure/frame, T)
	var/datum/capability/construction/C = frame.cap_frame_ladder()
	var/datum/construction_ladder/ladder = C.ladder_for(frame)
	var/list/problems = ladder.validate()
	TEST_ASSERT(!length(problems), "valid: [jointext(problems, "; ")]")
	TEST_ASSERT_EQUAL(ladder.state_of(frame), frame.anchored ? "placed" : "loose", "the stage is read from the frame's state")
	var/datum/interaction/capability/construction_step/glass_step = null
	for(var/datum/interaction/capability/construction_step/step as anything in ladder.edges)
		if(step.to_state == "paneled")
			glass_step = step
	TEST_ASSERT(glass_step, "a glass step")
	TEST_ASSERT_EQUAL(glass_step?.item_text(), "2 glass sheets", "the entry's name names the item")
	qdel(C) // a capability made outside capabilities(): its ladder, stages and costs go with it

/// cap_deconstruct() offers a crowbar Dismantle behind the panel.
/datum/unit_test/dq_capability_deconstruct

/datum/unit_test/dq_capability_deconstruct/Run()
	var/datum/capability/deconstruct/C = cap_deconstruct(board = /obj/item/circuitboard, needs = req_set(PANEL))
	var/list/entries = C.interactions(null)
	TEST_ASSERT_EQUAL(length(entries), 1, "one entry")
	var/datum/interaction/capability/entry = entries[1]
	cap_apply_gating(C, entry)
	TEST_ASSERT_EQUAL(entry.tool, TOOL_CROWBAR, "a crowbar")
	TEST_ASSERT_EQUAL(entry.behind, PANEL, "behind the panel")
	TEST_ASSERT(entry.works_broken && entry.works_unpowered, "works broken and unpowered")
	qdel(C)
