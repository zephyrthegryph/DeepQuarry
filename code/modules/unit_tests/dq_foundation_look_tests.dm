// Standard-part validation uses test-owned capabilities; gameplay panel/breakage behavior is tested separately.
/datum/capability/dq_standard_parts_fixture/look_parts()
	return list(LOOK_PANEL_OPEN, LOOK_BROKEN)

/proc/dq_standard_parts_fixture()
	return new /datum/capability/dq_standard_parts_fixture

// The look naming convention (variants, parts, glows), the missing-parts check, the construction
// primitives / joints / presets and their round-trip conservation, and the pooled base
// (code/datums/capabilities/look.dm, construction_primitives.dm, code/datums/lifecycle/pool.dm).

// ---- look: variants, parts, glows ----

/// An icon of the test holder's own making: it has the states a convention test names.
/datum/unit_test/proc/look_test_icon(list/state_names)
	var/icon/made = icon('icons/obj/stock_parts.dmi')
	var/list/have = icon_states('icons/obj/stock_parts.dmi')
	var/icon/source = icon('icons/obj/stock_parts.dmi', have[1])
	for(var/state in state_names)
		made.Insert(source, state)
	return made

/obj/cap_fixture/look_probe
	name = "look probe"
	icon_state = "fix"

CAPABILITIES(/obj/cap_fixture/look_probe)
	dq_standard_parts_fixture()

/datum/unit_test/dq_look_convention

/datum/unit_test/dq_look_convention/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/look_probe/A = allocate(/obj/cap_fixture/look_probe, T)
	A.icon = look_test_icon(list("fix", "fix-lit", "panel-open", "charge-3", "legacy_thing", "fix-shell"))
	var/datum/look/look = new
	look.variant("lit")
	look.variant("absent")
	look.part("panel", "open")
	look.part("charge", 3)
	look.part("legacy-thing")
	look.part("nothere")
	look.part("off", FALSE)
	look.glow("panel", "open")
	look.apply_to(A)
	TEST_ASSERT_EQUAL(A.icon_state, "fix-lit", "the base takes the variant the icon has and ignores the one it lacks")
	TEST_ASSERT(("panel-open" in A.rx?.look_overlays), "part(name, value) resolves name-value: [json_encode(A.rx?.look_overlays)]")
	TEST_ASSERT(("charge-3" in A.rx?.look_overlays), "a numeric value resolves")
	TEST_ASSERT(!("legacy_thing" in A.rx?.look_overlays), "names are exact: an underscore state is not found")
	TEST_ASSERT(!("nothere" in A.rx?.look_overlays), "a part with no state draws nothing")
	TEST_ASSERT_EQUAL(length(A.rx?.look_overlays), 3, "two parts and the emissive of the glowing one")
	TEST_ASSERT(length(GLOB.look_missing_parts["[A.type]"]), "the missing part is recorded in test builds")

	// A base-prefixed part wins over the shared one.
	var/obj/cap_fixture/look_probe/B = allocate(/obj/cap_fixture/look_probe, T)
	B.icon = look_test_icon(list("fix", "fix-panel-open", "panel-open"))
	var/datum/look/second = new
	second.part("panel", "open")
	second.apply_to(B)
	TEST_ASSERT(("fix-panel-open" in B.rx?.look_overlays) && !("panel-open" in B.rx?.look_overlays), "<base>-part wins over the shared part")

	// hide() is exact; glow() with no part of that name adds the part, glowing.
	var/datum/look/third = new
	third.part("panel", "open")
	third.hide("panel-open")
	TEST_ASSERT_NULL(third.parts, "hide() removes a part by its full name")
	third.part("panel", "open")
	third.hide("panel")
	TEST_ASSERT_NULL(third.parts, "or every value of it by its name")
	third.glow("plain")
	TEST_ASSERT_EQUAL(length(third.parts), 1, "glow() with no part adds the part")
	var/list/plain = third.parts[1]
	TEST_ASSERT(plain[1] == "plain" && plain[3], "the added part glows")

	// The change key sees parts, values and variants.
	var/datum/look/one = new
	one.part("panel", "open")
	var/datum/look/two = new
	two.part("panel", "shut")
	TEST_ASSERT(one.change_key() != two.change_key(), "different part values give different keys")
	var/datum/look/four = new
	four.part("panel", "open")
	four.variant("lit")
	TEST_ASSERT(one.change_key() != four.change_key(), "a variant changes the key")

/datum/unit_test/dq_look_state_cache

/datum/unit_test/dq_look_state_cache/Run()
	var/list/first = look_states_of('icons/obj/stock_parts.dmi')
	TEST_ASSERT(length(first), "the icon's states are read")
	TEST_ASSERT(look_states_of('icons/obj/stock_parts.dmi') == first, "the set is cached per icon file")
	TEST_ASSERT(!look_icon_has_state('icons/obj/stock_parts.dmi', "no-such-state-anywhere"), "a missing state is not present")

// ---- the missing-parts check ----

/obj/cap_fixture/look_lacking
	name = "lacking probe"
	icon_state = "fix"

CAPABILITIES(/obj/cap_fixture/look_lacking)
	dq_standard_parts_fixture()

/obj/cap_fixture/look_lacking/look_lacks()
	return list(LOOK_BROKEN)

/datum/unit_test/dq_look_missing_parts

/datum/unit_test/dq_look_missing_parts/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/look_probe/bare = allocate(/obj/cap_fixture/look_probe, T)
	bare.icon = look_test_icon(list("fix"))
	var/list/missing = look_missing_standard_parts(bare)
	TEST_ASSERT((LOOK_PANEL_OPEN in missing), "a panel with no sprite is listed: [json_encode(missing)]")
	TEST_ASSERT((LOOK_BROKEN in missing), "a broken layer with no sprite is listed")
	var/obj/cap_fixture/look_lacking/allowed = allocate(/obj/cap_fixture/look_lacking, T)
	allowed.icon = look_test_icon(list("fix"))
	missing = look_missing_standard_parts(allowed)
	TEST_ASSERT(!(LOOK_BROKEN in missing), "look_lacks() allowlists a part")
	TEST_ASSERT((LOOK_PANEL_OPEN in missing), "what it does not allow is still listed")
	var/obj/cap_fixture/look_probe/full = allocate(/obj/cap_fixture/look_probe, T)
	full.icon = look_test_icon(list("fix", "panel-open", "broken"))
	TEST_ASSERT_EQUAL(length(look_missing_standard_parts(full)), 0, "an icon with every standard part lists nothing")
	var/obj/cap_fixture/look_probe/legacy = allocate(/obj/cap_fixture/look_probe, T)
	legacy.icon = look_test_icon(list("fix", "panel_open", "broken"))
	TEST_ASSERT((LOOK_PANEL_OPEN in look_missing_standard_parts(legacy)), "an old underscore state is listed until it is renamed")
	// Types that opted in (look_checked()) must have every standard part or say they lack it.
	var/list/failures = list()
	var/checked = 0
	for(var/atom/movable/M in world)
		if(!look_checked(M))
			continue
		checked++
		var/list/lacking = look_missing_standard_parts(M)
		if(length(lacking))
			failures["[M.type]"] = lacking
	TEST_ASSERT(!length(failures), "checked types missing standard parts (of [checked]): [json_encode(failures)]")

// ---- construction: primitives, joints, presets ----

/obj/cap_fixture/prim_probe
	name = "primitive probe"
	icon_state = "prim_base"

/obj/cap_fixture/prim_probe/capabilities()
	. = ..()
	// The bay its steps work at (ladder steps are ops, and an op at a bay the holder never declares fails closed).
	. += legacy_compartment("test_bay")
	. += cap_construction(
		ladder_options(at = "test_bay", sprite = "prim_", undo_delay = 1 SECONDS, dismantle = ladder_dismantle(tool = TOOL_WRENCH, becomes = /obj/item/stack/material/steel, amount = 2)),
		stage("frame", desc = "A bare frame."),
		build_insert(/obj/item/stock_parts/capacitor),
		build_wire(3),
		build_fasten(TOOL_SCREWDRIVER, name = "closed"),
		build_plate(/obj/item/stack/material/steel, 2, name = "plated"),
	)

/obj/cap_fixture/prim_mech/capabilities()
	. = ..()
	. += cap_construction(mech_chassis(/obj/item/stack/material/steel, sprite = "chassis_", parts = list(/obj/item/stock_parts/capacitor, /obj/item/stock_parts/capacitor),
		steps = list(build_weld(name = "reinforced"))))

/obj/cap_fixture/prim_machine/capabilities()
	. = ..()
	. += cap_construction(machine_frame(/obj/item/circuitboard))

/obj/cap_fixture/prim_computer/capabilities()
	. = ..()
	. += cap_construction(computer_frame(/obj/item/circuitboard))

/obj/cap_fixture/prim_wall/capabilities()
	. = ..()
	. += cap_construction(wall_frame(/obj/item/circuitboard))

/obj/cap_fixture/prim_girder/capabilities()
	. = ..()
	. += cap_construction(girder())

/// The step of `ladder` from stage `from` to `to` (a stage name or LADDER_DONE).
/datum/unit_test/proc/prim_step(datum/construction_ladder/ladder, from, destination)
	for(var/datum/interaction/capability/construction_step/step as anything in ladder.edges)
		if(step.from_state == from && step.to_state == destination)
			return step
	return null

/datum/unit_test/dq_construction_primitives

/datum/unit_test/dq_construction_primitives/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/prim_probe/probe = allocate(/obj/cap_fixture/prim_probe, T)
	var/datum/construction_ladder/ladder = ladder_of(probe)
	var/list/problems = ladder.validate()
	TEST_ASSERT(!length(problems), "valid: [jointext(problems, "; ")]")
	TEST_ASSERT_EQUAL(jointext(ladder.states, ","), "frame,capacitor,wired,closed,plated", "stage names come from the parts and tools")
	var/datum/ladder_stage/wired_stage = ladder.stage_named("wired")
	var/datum/ladder_stage/plated_stage = ladder.stage_named("plated")
	TEST_ASSERT_EQUAL(wired_stage.icon, "prim_3", "icons are the sprite prefix and the stage's position")
	TEST_ASSERT_EQUAL(plated_stage.icon, "prim_5", "for every stage")

	var/datum/interaction/capability/construction_step/unwire = prim_step(ladder, "wired", "capacitor")
	TEST_ASSERT_EQUAL(unwire.tool, TOOL_WIRECUTTER, "build_wire() is undone with wirecutters")
	TEST_ASSERT_EQUAL(unwire.duration, 1 SECONDS, "undo_delay overrides an undo's wait")
	TEST_ASSERT_EQUAL(unwire.refund_amount, 3, "the refund is what the build consumed")
	var/datum/interaction/capability/construction_step/screw = prim_step(ladder, "wired", "closed")
	TEST_ASSERT_EQUAL(screw.tool, TOOL_SCREWDRIVER, "build_fasten() builds with its tool")
	TEST_ASSERT_EQUAL(screw.duration, ladder_tool_delay(TOOL_SCREWDRIVER), "a build takes its tool's default delay")
	TEST_ASSERT_EQUAL(screw.at, "test_bay", "ladder_options(at =) is stored on every step entry")
	TEST_ASSERT_NULL(op_at_reason(probe, screw.at, null), "a holder that declares no such bay lets a context-less entry through")
	TEST_ASSERT_EQUAL(screw.phrase, "screw %T% shut", "the message comes from the verb table")
	var/datum/interaction/capability/construction_step/unscrew = prim_step(ladder, "closed", "wired")
	TEST_ASSERT_EQUAL(unscrew.tool, TOOL_SCREWDRIVER, "the fastener table undoes a screw with a screwdriver")
	var/datum/interaction/capability/construction_step/uninsert = prim_step(ladder, "capacitor", "frame")
	TEST_ASSERT(uninsert.by_hand, "build_insert() is taken back out by hand")
	var/datum/interaction/capability/construction_step/unplate = prim_step(ladder, "plated", "closed")
	TEST_ASSERT_EQUAL(unplate.tool, TOOL_WELDER, "a plate is cut off with the welder")
	TEST_ASSERT_EQUAL(unplate.refund_amount, 2, "and gives its sheets back")
	TEST_ASSERT(prim_step(ladder, "frame", LADDER_DONE), "dismantle adds a branch out of the first stage")

	TEST_ASSERT(!built_past(probe, "capacitor"), "on the first stage nothing is built past")
	ladder_set_stage(probe, "closed")
	TEST_ASSERT(built_past(probe, "wired"), "a later stage is built past an earlier one")
	TEST_ASSERT(!built_past(probe, "closed"), "not past its own stage")
	TEST_ASSERT(!built_past(probe, "plated"), "nor past a later one")
	TEST_ASSERT(!built_past(probe, "no such stage"), "an unknown stage is never built past")
	TEST_ASSERT(!built_past(T, "frame"), "a holder with no ladder is never built past")

/datum/unit_test/dq_construction_presets

/datum/unit_test/dq_construction_presets/Run()
	var/turf/T = test_floor()
	for(var/path in list(/obj/cap_fixture/prim_mech, /obj/cap_fixture/prim_machine, /obj/cap_fixture/prim_computer, /obj/cap_fixture/prim_wall, /obj/cap_fixture/prim_girder))
		var/atom/A = allocate(path, T)
		var/datum/construction_ladder/ladder = ladder_of(A)
		TEST_ASSERT(ladder, "[path] has a ladder")
		if(!ladder)
			continue
		var/list/problems = ladder.validate()
		TEST_ASSERT(!length(problems), "[path] is valid: [jointext(problems, "; ")]")
		TEST_ASSERT(length(ladder.states) >= 4, "[path] has its stages")
	TEST_ASSERT_EQUAL(jointext(ladder_of(allocate(/obj/cap_fixture/prim_machine, T)).states, ","), "loose,anchored,board in,wired,closed", "machine frame stages")
	var/atom/mech = allocate(/obj/cap_fixture/prim_mech, T)
	var/datum/construction_ladder/chassis = ladder_of(mech)
	TEST_ASSERT(chassis.stage_named("capacitor"), "the first like part keeps its plain name")
	TEST_ASSERT(chassis.stage_named("capacitor 2"), "a second like part is numbered")
	TEST_ASSERT(chassis.stage_named("reinforced"), "steps are placed before the final fastening")
	TEST_ASSERT(prim_step(chassis, "finished", LADDER_DONE), "the chassis turns into its result")

// ---- round trip conservation ----

/// Every undo on every ladder alive gives back what its build took.
/datum/unit_test/dq_construction_conservation

/datum/unit_test/dq_construction_conservation/Run()
	var/turf/T = test_floor()
	for(var/path in list(/obj/cap_fixture/prim_probe, /obj/cap_fixture/prim_mech, /obj/cap_fixture/prim_machine, /obj/cap_fixture/prim_computer, /obj/cap_fixture/prim_wall, /obj/cap_fixture/prim_girder, /obj/cap_fixture/ladder_probe))
		allocate(path, T)
	var/list/ladders = list()
	for(var/obj/O in world)
		var/datum/construction_ladder/ladder = ladder_of(O)
		if(ladder && !(ladder in ladders))
			ladders += ladder
	TEST_ASSERT(length(ladders) >= 7, "the ladders alive are found ([length(ladders)])")
	for(var/datum/construction_ladder/ladder as anything in ladders)
		for(var/datum/interaction/capability/construction_step/undo as anything in ladder.edges)
			if(undo.forward || undo.refund_use == LADDER_ITEM_KEEP)
				continue
			var/datum/interaction/capability/construction_step/build = prim_step(ladder, undo.to_state, undo.from_state)
			TEST_ASSERT(build, "[ladder.id]: the undo [undo.from_state] -> [undo.to_state] has a build")
			if(!build)
				continue
			TEST_ASSERT_EQUAL(undo.refund_type, build.item_type, "[ladder.id]: [undo.from_state] gives back the type its build took")
			TEST_ASSERT_EQUAL(undo.refund_amount, build.item_amount, "[ladder.id]: [undo.from_state] gives back the amount its build took")
			TEST_ASSERT(build.item_use != LADDER_ITEM_KEEP, "[ladder.id]: [undo.from_state] refunds something its build consumed")

/// Build and undo the primitives on a real holder: no sheet, cable or part is created or lost.
/datum/unit_test/dq_construction_round_trip

/datum/unit_test/dq_construction_round_trip/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/prim_probe/probe = allocate(/obj/cap_fixture/prim_probe, T)
	var/datum/construction_ladder/ladder = ladder_of(probe)
	var/obj/item/stock_parts/capacitor/part = allocate(/obj/item/stock_parts/capacitor, T)
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 5)
	var/obj/item/stack/material/steel/sheets = allocate(/obj/item/stack/material/steel, T, 5)
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/obj/item/tool/wirecutters/cutters = dq_fast_tool(/obj/item/tool/wirecutters, T)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)

	TEST_ASSERT(ladder_walk(H, probe, prim_step(ladder, "frame", "capacitor"), part), "the part goes in")
	TEST_ASSERT_EQUAL(part.loc, probe, "held by the holder")
	TEST_ASSERT(ladder_walk(H, probe, prim_step(ladder, "capacitor", "wired"), coil), "cable goes on")
	TEST_ASSERT(ladder_walk(H, probe, prim_step(ladder, "wired", "closed"), screwdriver), "it is closed")
	TEST_ASSERT(ladder_walk(H, probe, prim_step(ladder, "closed", "plated"), sheets), "plated")
	TEST_ASSERT_EQUAL(ladder.state_of(probe), "plated", "the ladder owns the stage")
	TEST_ASSERT(built_past(probe, "wired"), "built_past reads the ladder")
	TEST_ASSERT_EQUAL(sheets.get_amount(), 3, "two sheets were used")

	TEST_ASSERT(ladder_walk(H, probe, prim_step(ladder, "plated", "closed"), welder), "the plate is cut off")
	TEST_ASSERT(ladder_walk(H, probe, prim_step(ladder, "closed", "wired"), screwdriver), "opened")
	TEST_ASSERT(ladder_walk(H, probe, prim_step(ladder, "wired", "capacitor"), cutters), "the cable is cut out")
	TEST_ASSERT(ladder_walk(H, probe, prim_step(ladder, "capacitor", "frame"), null), "the part comes out by hand")
	TEST_ASSERT_EQUAL(ladder.state_of(probe), "frame", "back on the first stage")
	TEST_ASSERT_EQUAL(part.loc, T, "the part is back on the floor")
	var/cable = coil.get_amount()
	var/steel = sheets.get_amount()
	for(var/obj/item/stack/cable_coil/other in T)
		if(other != coil)
			cable += other.get_amount()
	for(var/obj/item/stack/material/steel/other in T)
		if(other != sheets)
			steel += other.get_amount()
	TEST_ASSERT_EQUAL(cable, 5, "no cable was created or lost")
	TEST_ASSERT_EQUAL(steel, 5, "no steel was created or lost")
	own_turf_contents(T)

// ---- pools ----

/datum/pool_probe
	parent_type = /datum/pooled
	pool_max_free = 2
	var/count = 4
	var/label = "fresh"
	var/datum/held
	var/list/bucket
	var/list/made_in_new
	var/list/preset = list(1, 2)
	var/resets = 0

/datum/pool_probe/New()
	..()
	made_in_new = list()

/datum/pool_probe/reset()
	..()
	resets++

/datum/unit_test/dq_pool_pooled

/datum/unit_test/dq_pool_pooled/Run()
	var/was_poison = pool_set_poison(FALSE)
	var/datum/pool_probe/probe = take(/datum/pool_probe)
	var/list/allocated = probe.made_in_new
	probe.count = 9
	probe.label = "used"
	probe.held = new /datum
	probe.bucket = list(1, 2)
	probe.made_in_new += "x"
	probe.preset += 3
	probe.release()
	TEST_ASSERT_EQUAL(probe.count, 4, "fields go back to their initial values")
	TEST_ASSERT_EQUAL(probe.label, "fresh", "strings too")
	TEST_ASSERT_NULL(probe.held, "references are cleared")
	TEST_ASSERT_NULL(probe.bucket, "a list the type never allocated is nulled")
	TEST_ASSERT(probe.made_in_new == allocated && !length(probe.made_in_new), "a list New() allocated is kept and emptied")
	TEST_ASSERT_EQUAL(probe.resets, 1, "reset() runs after the automatic reset")
	TEST_ASSERT_EQUAL(length(probe.preset), 2, "a list with a declared initial value goes back to a copy of it")
	var/datum/pool_probe/fresh_one = new
	TEST_ASSERT(probe.preset != fresh_one.preset || length(fresh_one.preset) == 2, "and the declared list itself was not changed")
	var/list/after = probe.snapshot()
	TEST_ASSERT_EQUAL(after["count"], 4, "snapshot() lists the reset fields")
	var/datum/pool_probe/again = take(/datum/pool_probe)
	TEST_ASSERT(again == probe, "the released object is reused")
	// pool_max_free: extras past the cap are destroyed, not kept.
	var/datum/pool_probe/b = take(/datum/pool_probe)
	var/datum/pool_probe/c = take(/datum/pool_probe)
	var/datum/pool_probe/d = take(/datum/pool_probe)
	again.release()
	b.release()
	c.release()
	d.release()
	var/datum/object_pool/pool = GLOB.object_pools[/datum/pool_probe]
	TEST_ASSERT_EQUAL(length(pool.free), 2, "the pool keeps at most pool_max_free")
	TEST_ASSERT_EQUAL(pool.dropped, 2, "the rest are dropped and counted")
	while(length(pool.free))
		var/datum/pool_probe/spare = pool.free[length(pool.free)]
		pool.free.len--
		qdel(spare, TRUE)
	pool_set_poison(was_poison)

/datum/unit_test/dq_pool_poison_default

/datum/unit_test/dq_pool_poison_default/Run()
	// The default in a test build is poison on: a holder that keeps a packet past its release crashes.
	var/datum/damage_packet/packet = damage_packet()
	packet.release()
	TEST_ASSERT(GLOB.pool_poison, "poison is on by default in a test build")
	TEST_ASSERT_EQUAL(packet.pool_state, POOL_STATE_POISONED, "a released packet is poisoned")
	var/crashed = FALSE
	try
		packet.add(DAMAGE_BLUNT, 1)
	catch
		crashed = TRUE
	TEST_ASSERT(crashed, "using a released packet crashes")

/// A stage named like one of stage()'s own named arguments keeps its name.
/datum/unit_test/dq_construction_stage_named_anchored

/datum/unit_test/dq_construction_stage_named_anchored/Run()
	var/datum/ladder_stage/built = build_fasten(TOOL_WRENCH, name = "anchored", anchored = TRUE)
	TEST_ASSERT_EQUAL(built.name, "anchored", "a stage named anchored, with anchored set, keeps its name")
	TEST_ASSERT(built.anchored, "and its anchoring")
	var/datum/ladder_stage/plain = build_insert(/obj/item/stock_parts/capacitor, name = "icon", icon = "x")
	TEST_ASSERT_EQUAL(plain.name, "icon", "a part named like an argument keeps its name")

/obj/dq_look_cache_empty/draw(look)
	return ..()

/datum/unit_test/dq_look_cache_lifetime/Run()
	var/obj/dq_look_cache_empty/A = allocate(/obj/dq_look_cache_empty)
	TEST_ASSERT(isnull(A.rx), "A plain atom starts without an allocated reaction cache")
	refresh_look(A, FALSE)
	refresh_verbs(A, FALSE)
	refresh_granted_verbs(A, FALSE)
	refresh_sweep_track(A)
	TEST_ASSERT(isnull(A.rx), "Read-only empty look and verb probes leave reaction storage unallocated")
	var/obj/visible = allocate(/obj)
	var/datum/look/L = allocate(/datum/look)
	L.alpha = 111
	L.overlay("cache-probe")
	L.add_look_filter("cache-filter", list("type" = "blur", "size" = 1))
	L.vis = list(visible)
	L.apply_to(A)
	TEST_ASSERT_EQUAL(A.alpha, 111, "Applying a look writes its actual base appearance")
	TEST_ASSERT(A.rx?.look_set_bits && ("cache-probe" in A.rx?.look_overlays), "Applied appearance records the set properties and overlays in reaction state")
	TEST_ASSERT(("cache-filter" in A.rx?.look_filters), "The actual applied filter is recorded for later removal")
	TEST_ASSERT((visible in A.vis_contents) && (visible in A.rx?.look_vis), "Visible contents and their removal cache agree")
	L.reset()
	L.apply_to(A)
	TEST_ASSERT_EQUAL(A.alpha, initial(A.alpha), "Removing the look restores the base appearance")
	TEST_ASSERT_EQUAL(A.rx?.look_set_bits, 0, "The removed look leaves no recorded base property")
	TEST_ASSERT(isnull(A.rx?.look_overlays) && isnull(A.rx?.look_filters) && isnull(A.rx?.look_vis), "The removed look clears every owned appearance cache")
	TEST_ASSERT(!(visible in A.vis_contents), "Removing the look removes its actual visible contents")
