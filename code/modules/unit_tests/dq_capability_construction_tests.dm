// The construction and deconstruct capabilities and the standard frame ladder
// (code/datums/capabilities/construction.dm, frame_ladder.dm).

/// Runs `step` on `target` with no wait. Returns what perform() returned.
/datum/unit_test/proc/ladder_walk(mob/actor, atom/target, datum/interaction/capability/construction_step/step, obj/item/held)
	GLOB.dq_ladder_instant = TRUE
	. = step.perform(actor, target, held)
	GLOB.dq_ladder_instant = FALSE

/// The step leaving `target`'s stage toward `destination` (a stage name or LADDER_DONE).
/datum/unit_test/proc/ladder_step(atom/target, from, destination)
	for(var/datum/interaction/capability/construction_step/step as anything in ladder_steps_for(target))
		if(step.from_state == from && step.to_state == destination)
			return step
	return null

/// A test holder whose capabilities use every kind of stage and step.
/obj/item/dq_ladder_probe
	name = "ladder probe"
	var/marker
	var/hot = FALSE

/obj/item/dq_ladder_probe/capabilities()
	. = ..()
	. += construction(
		ladder_options(anywhere = list(branch("start", with_tool(TOOL_CROWBAR), say = "reset %T%", when = PROC_REF(probe_can_reset)))),
		stage("start", desc = "A probe at the start."),
		stage("wired", build = using(/obj/item/stack/cable_coil, amount = 3), undo = with_tool(TOOL_WIRECUTTER), anchored = TRUE, on_enter = PROC_REF(probe_marked)),
		stage("boarded", build = insert(null, /obj/item/stock_parts/capacitor), undo = hand(null)),
		stage("finished", build = tool(null, TOOL_WRENCH, delay = 3 SECONDS),
			also = list(branch(LADDER_DONE, with_tool(TOOL_SCREWDRIVER), say = "melt %T% down", become = /obj/item/stack/material/steel, amount = 2,
				needs = PROC_REF(probe_cool), else_say = "it is too hot"))),
	)

/obj/item/dq_ladder_probe/proc/probe_marked(mob/user, obj/item/held, from)
	marker = "wired"

/obj/item/dq_ladder_probe/proc/probe_cool(mob/user, obj/item/held)
	return !hot

/obj/item/dq_ladder_probe/proc/probe_can_reset()
	return ladder_stage_index(src) > 1

/// Every ladder a capability list declares is valid, and the probe's steps run through the capability.
/datum/unit_test/dq_capability_construction

/datum/unit_test/dq_capability_construction/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/dq_ladder_probe/probe = allocate(/obj/item/dq_ladder_probe, T)
	var/datum/construction_ladder/ladder = ladder_of(probe)
	TEST_ASSERT(ladder, "the probe's capabilities give it a ladder")
	var/list/problems = ladder?.validate()
	TEST_ASSERT(!length(problems), "valid: [jointext(problems, "; ")]")
	TEST_ASSERT_EQUAL(ladder.state_of(probe), "start", "a new holder is on the first stage")
	TEST_ASSERT(length(cap_interactions(probe)) >= 5, "the steps are the capability's interactions")
	var/text = jointext(probe.caps_examine(H), "\n")
	TEST_ASSERT(findtext(text, "A probe at the start."), "examine comes from the capability: [text]")

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

	TEST_ASSERT(ladder_set_stage(probe, "finished"), "set from outside a step")
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/datum/interaction/capability/construction_step/melt = ladder_step(probe, "finished", LADDER_DONE)
	probe.hot = TRUE
	TEST_ASSERT_EQUAL(melt.why_not(H, probe, screwdriver), "it is too hot", "needs refuses with else_say")
	probe.hot = FALSE
	TEST_ASSERT(ladder_walk(H, probe, melt, screwdriver), "the finishing branch runs")
	TEST_ASSERT(QDELETED(probe), "become replaced the probe")
	own_turf_contents(T)

/// The standard frame ladder is valid on a real frame.
/datum/unit_test/dq_capability_frame_ladder

/datum/unit_test/dq_capability_frame_ladder/Run()
	var/turf/T = test_floor()
	var/obj/structure/frame/frame = allocate(/obj/structure/frame, T)
	var/datum/capability/construction/C = standard_frame_ladder()
	var/datum/construction_ladder/ladder = C.ladder_for(frame)
	var/list/problems = ladder.validate()
	TEST_ASSERT(!length(problems), "valid: [jointext(problems, "; ")]")
	TEST_ASSERT_EQUAL(ladder.state_of(frame), frame.anchored ? "placed" : "loose", "the stage is read from the frame's state")

/// deconstructible() offers a crowbar Dismantle behind the panel.
/datum/unit_test/dq_capability_deconstruct

/datum/unit_test/dq_capability_deconstruct/Run()
	var/datum/capability/deconstruct/C = deconstructible(board = /obj/item/circuitboard)
	var/list/entries = C.interactions(null)
	TEST_ASSERT_EQUAL(length(entries), 1, "one entry")
	var/datum/interaction/capability/entry = entries[1]
	TEST_ASSERT_EQUAL(entry.tool, TOOL_CROWBAR, "a crowbar")
	TEST_ASSERT_EQUAL(entry.behind, PANEL, "behind the panel")
	TEST_ASSERT(entry.works_broken && entry.works_unpowered, "works broken and unpowered")
