// watched() (code/modules/heat/watched.dm): a draw that reads Rust-owned heat as a band redraws when Rust reports a band change.

/obj/dq_watched_probe
	name = "watched probe"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/watch_level = 400

/obj/dq_watched_probe/draw(datum/look/look)
	..()
	look.overlay("band-[watched(src, WATCH_HEAT, list(watch_level))]")

/datum/unit_test/dq_watched_band_redraws_on_a_crossing

/datum/unit_test/dq_watched_band_redraws_on_a_crossing/Run()
	var/turf/T = test_floor()
	var/obj/dq_watched_probe/P = allocate(/obj/dq_watched_probe, T)
	TEST_ASSERT(P.create_heat_body(TRUE), "the probe got no heat body")
	P.set_watch_level(P.get_temperature() + 50)
	state_changed(P)
	refresh_flush()
	TEST_ASSERT(("band-0" in P.rx?.look_overlays), "below the level it reads band 0: [json_encode(P.rx?.look_overlays)]")
	SSwatched.arm_pending(0)
	TEST_ASSERT(watched_armed(P, WATCH_HEAT, list(P.watch_level)), "the read armed a band watch after the draw")
	vg_world_run_steps(2)
	native_system().drain()
	refresh_flush()
	heat_set(P, P.watch_level + 100)
	vg_world_run_steps(2)
	native_system().drain()
	refresh_flush()
	TEST_ASSERT(P.get_temperature() >= P.watch_level, "the heat did not raise the body past the level: [P.get_temperature()]")
	TEST_ASSERT(("band-1" in P.rx?.look_overlays), "a crossing Rust reported redrew it: [json_encode(P.rx?.look_overlays)]")
