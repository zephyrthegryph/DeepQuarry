// The appearance cache (code/engine/present/look_cache.dm) and the per-type draw cost it is measured by.

/obj/dq_cache_probe
	name = "cache probe"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/mode = 0
	var/tint = "none"

/obj/dq_cache_probe/draw(datum/look/look)
	..()
	look.overlay("mode-[mode]")
	look.overlay("tint-[tint]")

/// A draw that reads another atom: the key cannot see what it reads, so the cache never serves it.
/obj/dq_cache_reader
	name = "cache reader"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/obj/other

/obj/dq_cache_reader/draw(datum/look/look)
	..()
	look.overlay("reader-[other ? other.name : "none"]")

/// A cache of its own and the switches set for the test (what the world held is put back when the test ends).
/datum/unit_test/proc/look_cache_clean(verify = FALSE, on = TRUE)
	set_global(nameof(GLOB.look_cache), alist())
	set_global(nameof(GLOB.look_cache_on), on)
	set_global(nameof(GLOB.look_cache_verify), verify)

/datum/unit_test/dq_look_cache_serves_equal_inputs

/datum/unit_test/dq_look_cache_serves_equal_inputs/Run()
	var/turf/T = test_floor()
	refresh_flush()
	look_cache_clean()
	var/misses = GLOB.look_cache_misses
	var/obj/dq_cache_probe/first = allocate(/obj/dq_cache_probe, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(GLOB.look_cache_misses - misses, 1, "the first draw of a set of inputs builds its look and holds it")
	TEST_ASSERT(("mode-0" in first.rx?.look_overlays), "and applies it: [json_encode(first.rx?.look_overlays)]")
	var/builds = GLOB.look_builds
	var/hits = GLOB.look_cache_hits
	var/obj/dq_cache_probe/second = allocate(/obj/dq_cache_probe, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(GLOB.look_cache_hits - hits, 1, "an atom with the same inputs is served the held look")
	TEST_ASSERT_EQUAL(GLOB.look_builds, builds, "a hit runs no draw and builds no look")
	TEST_ASSERT_EQUAL(second.rx?.look_key, first.rx?.look_key, "it holds the same look key")
	TEST_ASSERT_EQUAL(json_encode(second.rx?.look_overlays), json_encode(first.rx?.look_overlays), "and shows the same layers")
	// Different inputs build their own look.
	second.set_mode(2)
	refresh_flush()
	TEST_ASSERT(GLOB.look_builds > builds, "a changed input builds a look")
	TEST_ASSERT(("mode-2" in second.rx?.look_overlays) && !("mode-0" in second.rx?.look_overlays), "and shows it, with nothing of the old one: [json_encode(second.rx?.look_overlays)]")
	// A third atom that comes to the same inputs is served the second's look.
	var/obj/dq_cache_probe/third = allocate(/obj/dq_cache_probe, T)
	refresh_flush()
	builds = GLOB.look_builds
	hits = GLOB.look_cache_hits
	third.set_mode(2)
	refresh_flush()
	TEST_ASSERT_EQUAL(GLOB.look_cache_hits - hits, 1, "an atom that reaches held inputs is served by the cache")
	TEST_ASSERT_EQUAL(GLOB.look_builds, builds, "with no look built")
	TEST_ASSERT_EQUAL(third.rx?.look_key, second.rx?.look_key, "to the same look")
	// Served again with nothing changed: the look is the one it shows.
	var/applied = third.rx?.look_key
	refresh_mark(third, DEP_DRAW)
	refresh_flush()
	TEST_ASSERT_EQUAL(third.rx?.look_key, applied, "a redraw that finds the look it shows changes nothing")

/datum/unit_test/dq_look_cache_skips_what_its_key_cannot_see

/datum/unit_test/dq_look_cache_skips_what_its_key_cannot_see/Run()
	var/turf/T = test_floor()
	refresh_flush()
	look_cache_clean()
	var/obj/dq_cache_probe/target = allocate(/obj/dq_cache_probe, T)
	var/obj/dq_cache_reader/A = allocate(/obj/dq_cache_reader, T)
	A.set_other(target)
	refresh_flush()
	TEST_ASSERT_NULL(look_cache_key(A), "a draw that reads another atom has no key")
	TEST_ASSERT(("reader-cache probe" in A.rx?.look_overlays), "and draws as it always did: [json_encode(A.rx?.look_overlays)]")

/// What the cache holds for equal inputs is what a fresh draw makes: real types are drawn twice, once served and once built.
/datum/unit_test/dq_look_cache_matches_a_fresh_draw

/datum/unit_test/dq_look_cache_matches_a_fresh_draw/Run()
	var/turf/T = test_floor()
	refresh_flush()
	look_cache_clean(verify = TRUE) // every hit below is compared with a fresh draw: a mismatch is a runtime
	var/list/kinds = list(/obj/structure/closet, /obj/structure/lightpost, /obj/machinery/light, /obj/item/pen, /obj/machinery/vending/coffee)
	for(var/kind in kinds)
		for(var/n in 1 to 3)
			allocate(kind, T)
	refresh_flush()
	var/hits = GLOB.look_cache_hits
	for(var/kind in kinds)
		var/obj/A = allocate(kind, T)
		refresh_mark(A, DEP_DRAW)
	refresh_flush()
	log_world("look cache real types: [GLOB.look_cache_hits - hits] hits of [length(kinds)] extra atoms; [look_cache_text()]")

// ---- the measurement ----

/// Draws `count` atoms of each type with the cache off, then on, and logs what a draw costs by type (mean and p95) and the totals. The numbers
/// the cache is judged by; the test asserts only that the served draws built nothing.
/datum/unit_test/dq_look_cache_draw_cost

/datum/unit_test/dq_look_cache_draw_cost/Run()
	var/turf/T = test_floor()
	refresh_flush()
	var/count = 150
	var/list/kinds = list(/obj/dq_cache_probe, /obj/structure/closet, /obj/structure/lightpost, /obj/machinery/light, /obj/item/pen, /obj/machinery/vending/coffee)
	var/list/atoms = list()
	for(var/kind in kinds)
		for(var/n in 1 to count)
			atoms += allocate(kind, T)
	refresh_flush()
	for(var/mode in list(FALSE, TRUE))
		look_cache_clean(on = mode)
		set_global(nameof(GLOB.look_cost), alist())
		set_global(nameof(GLOB.look_cost_all_draws), 0)
		set_global(nameof(GLOB.look_cost_all_ms), 0)
		set_global(nameof(GLOB.look_cost_hit_ms), 0)
		set_global(nameof(GLOB.look_cost_built_ms), 0)
		var/builds = GLOB.look_builds
		for(var/atom/A as anything in atoms)
			var/datum/rx_state/S = rx_of(A)
			S.look_key = null // the look is applied afresh: the draw runs, or the cache serves it
			refresh_look(A)
		log_world("LOOK COST ([mode ? "cache on" : "cache off"]): [look_cost_text(10)]; looks built [GLOB.look_builds - builds] of [length(atoms)] draws; [look_cache_text()]")
		if(mode)
			TEST_ASSERT(GLOB.look_builds - builds < length(atoms), "with the cache on some draws are served without a look")
