// Standard-part validation uses test-owned capabilities; gameplay panel/breakage behavior is tested separately.
/datum/capability/dq_standard_parts_fixture/look_parts()
	return list(LOOK_PANEL_OPEN, LOOK_BROKEN)

/proc/dq_standard_parts_fixture()
	return new /datum/capability/dq_standard_parts_fixture

// The look naming convention (variants, parts, glows), the missing-parts check
// and the pooled base
// (code/datums/capabilities/look.dm, code/datums/lifecycle/pool.dm).

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

CAPABILITY(/obj/cap_fixture/look_probe, dq_standard_parts_fixture())

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

CAPABILITY(/obj/cap_fixture/look_lacking, dq_standard_parts_fixture())

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
