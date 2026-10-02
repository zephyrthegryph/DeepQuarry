// E2's resolver on the paths the design gates (doc/rewrite/final_api.html, section 8 "Resolution cost"; section 19 "Bench scenarios"):
//
//   click_resolve_30  clicks on a target whose candidate stack has 30 entries (one op per held key type, plus the hand): cost per click
//   hover_60          the menu and the screentip of 60 atoms in turn (cost per hover) with the menu cache warm and cold
//
// Run: tools/build/build.sh bench --scenario=click_resolve_30,hover_60 [--bench_clicks=2000]
// There is no pinned old-path number for either (the legacy resolver has no 30-candidate equivalent): the figures are this engine's own.

#if defined(BENCHMARK) || defined(SPACEMAN_DMM)
/datum/benchmark/click_resolve_30
	id = "click_resolve_30"
	description = "Clicks on a target with a 30-candidate stack: the resolver and a no-op effect"

/datum/benchmark/click_resolve_30/Run()
	var/clicks = param("clicks", 2000)
	var/turf/where = locate(10, 10, 1)
	var/mob/living/simple_mob/e0_fixture/M = new(where)
	var/obj/e2_bench_stack/S = new(where)
	var/list/keys = list()
	for(var/i in 1 to 30)
		var/key_type = text2path("/obj/item/e2_bench_key[i]")
		keys += new key_type(where)
	// warm: the table, the plans and the type indexes are built
	op_resolve_click(M, S, keys[1], GESTURE_CLICK, ORIGIN_CLICK, TRUE)
	begin_window()
	var/start = REALTIMEOFDAY
	for(var/c in 1 to clicks)
		op_resolve_click(M, S, keys[(c % 30) + 1], GESTURE_CLICK, ORIGIN_CLICK, TRUE)
	var/ms = (REALTIMEOFDAY - start) * 100
	end_window("click")
	metric("ms_per_click", ms / clicks, "ms")
	count_metric("ran", S.uses, "ops")
	for(var/obj/item/K as anything in keys)
		qdel(K)
	qdel(S)
	qdel(M)

/datum/benchmark/hover_60
	id = "hover_60"
	description = "The menu and the screentip of 60 atoms in turn, the menu cache cold and warm"

/datum/benchmark/hover_60/Run()
	var/rounds = param("rounds", 40)
	var/turf/origin = locate(10, 10, 1)
	var/mob/living/simple_mob/e0_fixture/M = new(origin)
	var/obj/item/held = new /obj/item/e2_bench_key7(origin)
	var/list/atoms = list()
	for(var/i in 1 to 60)
		atoms += new /obj/e2_bench_stack(locate(origin.x + (i % 20), origin.y + round(i / 20), origin.z))
	var/hovers = 0
	begin_window()
	var/cold_start = REALTIMEOFDAY
	for(var/r in 1 to rounds)
		GLOB.op_epoch++ // a state change since the last round: the cached menus are stale
		for(var/atom/A as anything in atoms)
			action_options(M, A, held)
			screentip_for(M, A, held, GESTURE_CLICK)
			hovers++
	var/cold_ms = (REALTIMEOFDAY - cold_start) * 100
	end_window("cold")
	var/warm_start = REALTIMEOFDAY
	for(var/r in 1 to rounds)
		for(var/atom/A as anything in atoms)
			action_options(M, A, held)
	var/warm_ms = (REALTIMEOFDAY - warm_start) * 100
	metric("cold_ms_per_hover", cold_ms / hovers, "ms")
	metric("warm_ms_per_menu", warm_ms / (rounds * length(atoms)), "ms")
	count_metric("hovers", hovers, "atoms")
	for(var/atom/A as anything in atoms)
		qdel(A)
	qdel(held)
	qdel(M)

#endif
