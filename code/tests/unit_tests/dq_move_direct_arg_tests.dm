// handle_fall() moves a thing with Move(landing, direct = dir): every Move() override must accept that named argument.

/datum/unit_test/dq_move_direct_arg

/datum/unit_test/dq_move_direct_arg/Run()
	var/turf/floor = test_floor()
	var/turf/landing = get_step(floor, NORTH)
	var/list/things = list(
		allocate(/obj/item/pipe/binary/bendable, floor),
		allocate(/obj/structure/window, floor),
		allocate(/obj/structure/easel, floor),
		allocate(/obj/effect/effect/water, floor),
	)
	for(var/atom/movable/thing as anything in things)
		thing.Move(landing, direct = NORTH) // a bad arg name raises a runtime, which fails the test
