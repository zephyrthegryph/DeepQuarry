// Real constructors for the object-only native setup cohort.
/datum/unit_test/dq_init_objects_nonitems
	abstract_type = /datum/unit_test/dq_init_objects_nonitems

/datum/unit_test/dq_init_objects_nonitems/mine_and_countdown
/datum/unit_test/dq_init_objects_nonitems/mine_and_countdown/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/effect/mine/M = allocate(/obj/effect/mine, T)
	TEST_ASSERT(!QDELETED(M), "the actual mine survives construction")
	TEST_ASSERT((entity_handle_of(M) in T.dangerous_objects), "native setup registers the exact real mine on its turf")
	var/obj/item/host = allocate(/obj/item, T)
	var/obj/effect/countdown/C = allocate(/obj/effect/countdown, host)
	TEST_ASSERT_EQUAL(C.attached_to, host, "countdown setup preserves its exact supplied containing atom")
	TEST_ASSERT_EQUAL(C.loc, T, "the real countdown moves to its host's turf")
	TEST_ASSERT(!C.started, "construction does not invent an active countdown")

/obj/structure/micro_tunnel/dq_init_mapped_offset
	pixel_x = 7
	pixel_y = 9
	dir = NORTH

/datum/unit_test/dq_init_objects_nonitems/tunnel_and_tube
/datum/unit_test/dq_init_objects_nonitems/tunnel_and_tube/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/structure/micro_tunnel/ordinary = allocate(/obj/structure/micro_tunnel, T)
	TEST_ASSERT_EQUAL(ordinary.pixel_x, 0, "an ordinary south-facing tunnel has no horizontal offset")
	TEST_ASSERT_EQUAL(ordinary.pixel_y, -32, "native setup applies the actual default south-facing offset")
	var/obj/structure/micro_tunnel/mapped = allocate(/obj/structure/micro_tunnel/dq_init_mapped_offset, T)
	TEST_ASSERT_EQUAL(mapped.pixel_x, 7, "setup preserves a mapper's horizontal offset")
	TEST_ASSERT_EQUAL(mapped.pixel_y, 9, "setup preserves a mapper's vertical offset")
	var/obj/structure/transit_tube/tube = allocate(/obj/structure/transit_tube, T)
	TEST_ASSERT_EQUAL(length(tube.tube_dirs), 2, "the actual E-W tube builds both connection directions")
	TEST_ASSERT((EAST in tube.tube_dirs) && (WEST in tube.tube_dirs), "both exact directions survive native construction")
	var/obj/structure/transit_tube/station/station = allocate(/obj/structure/transit_tube/station, T)
	TEST_ASSERT((EAST in station.tube_dirs) && (WEST in station.tube_dirs), "the station's virtual init_dirs still selects the sides of its south-facing exit")

/datum/unit_test/dq_init_objects_nonitems/pillow_and_salvage
/datum/unit_test/dq_init_objects_nonitems/pillow_and_salvage/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/structure/bed/pillowpile/pile = allocate(/obj/structure/bed/pillowpile, T)
	var/obj/structure/bed/pillowpilefront/front = pile.front
	TEST_ASSERT_NOTNULL(front, "the actual owned front exists before its setup link")
	TEST_ASSERT_EQUAL(front.pile, pile, "setup links the real initialized front back to its exact pile")
	TEST_ASSERT_EQUAL(owner_of(front), pile, "the existing ownership declaration still owns the front")
	qdel(pile)
	TEST_ASSERT(QDELETED(front), "the owned front is still deleted with its pile")
	var/list/previous = list()
	for(var/obj/structure/table/reinforced/table in T)
		previous += table
	var/obj/structure/salvageable/personal/terminal = allocate(/obj/structure/salvageable/personal, T)
	TEST_ASSERT(!QDELETED(terminal), "the actual salvage terminal survives construction")
	var/list/created = list()
	for(var/obj/structure/table/reinforced/table in T)
		if(!(table in previous))
			created += table
			own(table)
	TEST_ASSERT_EQUAL(length(created), 1, "native setup creates exactly one actual reinforced support table")
	var/obj/structure/table/reinforced/support = created[1]
	TEST_ASSERT_EQUAL(support.loc, T, "the new support table is on the terminal's actual turf")

/datum/unit_test/dq_init_objects_nonitems/light_cone_and_mirror
/datum/unit_test/dq_init_objects_nonitems/light_cone_and_mirror/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/effect/overlay/light_cone/C = allocate(/obj/effect/overlay/light_cone, T)
	var/matrix/transform = C.transform
	TEST_ASSERT_EQUAL(transform.c, -32, "the actual light cone applies its horizontal standard translation once")
	TEST_ASSERT_EQUAL(transform.f, -32, "the actual light cone applies its vertical standard translation once")
	qdel(C, TRUE)
	var/obj/structure/mirror/frame = allocate(/obj/structure/mirror, T, NORTH, TRUE)
	TEST_ASSERT(!frame.glass, "constructed mirror setup leaves the real frame empty")
	TEST_ASSERT_EQUAL(frame.icon_state, "mirror_frame", "the constructor's supplied building flag still selects its real frame sprite")
	var/obj/structure/mirror/mapped = allocate(/obj/structure/mirror, T)
	TEST_ASSERT(mapped.glass, "the ordinary mapped mirror keeps its actual glass")

/datum/unit_test/dq_init_objects_nonitems/loose_map_contents
/datum/unit_test/dq_init_objects_nonitems/loose_map_contents/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/item/reagent_containers/food/snacks/food = allocate(/obj/item/reagent_containers/food/snacks/cookie, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	var/obj/structure/foodcart/cart = allocate(/obj/structure/foodcart, T)
	TEST_ASSERT_EQUAL(food.loc, cart, "native foodcart setup adopts the actual loose food already on its map tile")
	TEST_ASSERT_EQUAL(pen.loc, T, "foodcart setup leaves non-food loose items on the tile")
	var/obj/structure/largecrate/crate = allocate(/obj/structure/largecrate, T)
	TEST_ASSERT_EQUAL(pen.loc, crate, "native crate setup gathers the exact eligible loose item")
	TEST_ASSERT_EQUAL(food.loc, cart, "crate setup does not steal another holder's nested food")
	TEST_ASSERT_EQUAL(cart.loc, T, "dense map structures are not gathered into the crate")

/datum/unit_test/dq_init_objects_nonitems/initial_clocks
/datum/unit_test/dq_init_objects_nonitems/initial_clocks/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/structure/timer_door/door = allocate(/obj/structure/timer_door, T)
	TEST_ASSERT_EQUAL(door.start_time, world.time, "the actual timer door stamps its construction clock")
	var/obj/effect/bspawner/spawner = allocate(/obj/effect/bspawner, T)
	TEST_ASSERT_EQUAL(spawner.init_time, world.time, "the actual bluespace spawner stamps its initial world clock")
	var/obj/structure/mob_spawner/nest = allocate(/obj/structure/mob_spawner, T)
	TEST_ASSERT(nest.spawn_cooldown >= world.time + nest.spawn_delay, "the base spawner retains its full initial delay")
	TEST_ASSERT(nest.spawn_cooldown <= world.time + 2 * nest.spawn_delay, "the base spawner retains the old bounded random addition")
	var/obj/structure/mob_spawner/mouse_nest/mice = allocate(/obj/structure/mob_spawner/mouse_nest, T)
	TEST_ASSERT(mice.spawn_cooldown >= world.time, "the child spawner's override never schedules before construction")
	TEST_ASSERT(mice.spawn_cooldown <= world.time + mice.spawn_delay, "the child setup still replaces the parent's longer initial interval")

/datum/unit_test/dq_init_objects_nonitems/constructed_frames
/datum/unit_test/dq_init_objects_nonitems/constructed_frames/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/structure/window/built = allocate(/obj/structure/window, T, EAST, TRUE)
	TEST_ASSERT(!built.anchored, "a constructed actual window remains loose")
	TEST_ASSERT_EQUAL(built.state, 0, "the actual built window starts unfastened")
	TEST_ASSERT_EQUAL(built.ini_dir, EAST, "window setup remembers its actual supplied orientation")
	var/obj/structure/window/mapped = allocate(/obj/structure/window, T)
	TEST_ASSERT(mapped.anchored, "a mapped actual window retains anchoring")
	TEST_ASSERT_EQUAL(mapped.state, 2, "the mapped window keeps its secured default state")
	var/obj/structure/windoor_assembly/assembly = allocate(/obj/structure/windoor_assembly, T, SOUTHEAST, TRUE)
	TEST_ASSERT(!assembly.anchored, "constructed windoor setup leaves the actual frame loose")
	TEST_ASSERT_EQUAL(assembly.dir, NORTH, "a non-cardinal supplied direction preserves the original north fallback")

/datum/unit_test/dq_init_objects_nonitems/coating_and_drip
/datum/unit_test/dq_init_objects_nonitems/coating_and_drip/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/effect/decal/cleanable/chemcoating/old = allocate(/obj/effect/decal/cleanable/chemcoating, T)
	old.reagents.add_reagent(REAGENT_ID_WATER, 7)
	TEST_ASSERT_EQUAL(old.reagents.get_reagent_amount(REAGENT_ID_WATER), 7, "the actual old coating holds the known reagent amount")
	var/obj/effect/decal/cleanable/chemcoating/replacement = allocate(/obj/effect/decal/cleanable/chemcoating, T)
	TEST_ASSERT(QDELETED(old), "native merge setup consumes the exact previous coating")
	TEST_ASSERT_EQUAL(replacement.reagents.get_reagent_amount(REAGENT_ID_WATER), 7, "the real constructor transfers the full old reagent amount")
	var/obj/effect/decal/cleanable/blood/drip/D = allocate(/obj/effect/decal/cleanable/blood/drip, T)
	TEST_ASSERT_EQUAL(length(D.drips), 1, "native drip setup records exactly one actual starting sprite")
	TEST_ASSERT((D.icon_state in D.drips), "the stored starting drip is the actual rolled constructor sprite")

/datum/unit_test/dq_init_objects_nonitems/shared_particles
/datum/unit_test/dq_init_objects_nonitems/shared_particles/Run()
	dq_init_objects_fixture_scope()
	var/obj/effect/abstract/shared_particle_holder/P = allocate(/obj/effect/abstract/shared_particle_holder, test_floor(), /particles/smoke, NONE)
	TEST_ASSERT(!QDELETED(P), "the actual shared particle holder survives its valid constructor")
	TEST_ASSERT_NULL(P.loc, "native setup moves the actual holder off the physical map")
	TEST_ASSERT_EQUAL(P.particle_path, /particles/smoke, "the retained constructor parameter selects the actual particle type")
	TEST_ASSERT_NOTNULL(P.particles, "native setup constructs the actual particle emitter")
	TEST_ASSERT_EQUAL(P.shared_users, 0, "direct construction does not invent pooled users")

/datum/unit_test/dq_init_objects_nonitems/directional_light_child
/datum/unit_test/dq_init_objects_nonitems/directional_light_child/Run()
	dq_init_objects_fixture_scope()
	var/obj/effect/abstract/directional_lighting/L = allocate(/obj/effect/abstract/directional_lighting, test_floor())
	var/obj/effect/abstract/light_spot/spot = L.light_spot
	TEST_ASSERT_NOTNULL(spot, "the actual declared light spot exists before presentation setup")
	TEST_ASSERT((spot in L.vis_contents), "the real owned spot is exposed through its parent's actual vis_contents")
	TEST_ASSERT_EQUAL(owner_of(spot), L, "visual setup preserves the declared child ownership")
	qdel(L)
	TEST_ASSERT(QDELETED(spot), "deleting the real parent still deletes its owned light spot")

/datum/unit_test/dq_init_objects_nonitems/duplicate_catwalk
/datum/unit_test/dq_init_objects_nonitems/duplicate_catwalk/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/structure/catwalk/first = allocate(/obj/structure/catwalk, T)
	TEST_ASSERT(!QDELETED(first), "the first actual catwalk survives its constructor")
	var/obj/structure/catwalk/second = allocate(/obj/structure/catwalk, T)
	TEST_ASSERT(QDELETED(first), "native setup consumes the actual previously initialized duplicate")
	TEST_ASSERT(!QDELETED(second), "the replacing catwalk survives construction")
	var/count = 0
	for(var/obj/structure/catwalk/C in T)
		if(!QDELETED(C))
			count++
			TEST_ASSERT_EQUAL(C, second, "the surviving actual catwalk is the replacement")
	TEST_ASSERT_EQUAL(count, 1, "duplicate initialization leaves exactly one actual live catwalk")

/obj/effect/anomaly/dq_init_immortal
	immortal = TRUE
	countdown_colour = "#123456"

/datum/unit_test/dq_init_objects_nonitems/anomaly_countdown
/datum/unit_test/dq_init_objects_nonitems/anomaly_countdown/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/effect/anomaly/A = allocate(/obj/effect/anomaly, T)
	TEST_ASSERT(!QDELETED(A), "an actual anomaly with an area survives construction")
	TEST_ASSERT_EQUAL(A.impact_area(), get_area(T), "native setup remembers the exact real impact area")
	TEST_ASSERT_NOTNULL(A.anomaly_core, "the actual declared core is initialized before setup")
	TEST_ASSERT_EQUAL(A.anomaly_core.anomaly_type, A.type, "the actual core records its anomaly's exact type")
	TEST_ASSERT(A.anomaly_core.code >= 1 && A.anomaly_core.code <= 100, "core setup preserves the real code's original random bounds")
	TEST_ASSERT(A.countdown.started, "the ordinary real anomaly starts its actual countdown")
	var/obj/effect/anomaly/immortal = allocate(/obj/effect/anomaly/dq_init_immortal, T)
	TEST_ASSERT(!immortal.countdown.started, "immortality still suppresses actual countdown startup")
	TEST_ASSERT_EQUAL(immortal.countdown.color, "#123456", "the supplied countdown color still reaches its actual child")
	var/obj/effect/anomaly/invalid = new /obj/effect/anomaly(null)
	own(invalid)
	TEST_ASSERT(QDELETED(invalid), "native keeps_if discards an anomaly with no actual impact area")

/obj/item/canvas/dq_init_rectangle
	width = 2
	height = 3
	canvas_color = "#123456"

/obj/item/paint_brush/dq_init_color
	selected_color = "#123456"

/datum/unit_test/dq_init_objects_nonitems/art_constructors
/datum/unit_test/dq_init_objects_nonitems/art_constructors/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/canvas/C = allocate(/obj/item/canvas/dq_init_rectangle, test_floor())
	TEST_ASSERT_EQUAL(C.width, 2, "the actual rectangular canvas keeps its declared width")
	TEST_ASSERT_EQUAL(C.height, 3, "the actual rectangular canvas keeps its declared height")
	TEST_ASSERT_EQUAL(length(C.grid), 2, "native setup allocates the real width of the canvas grid")
	for(var/x in 1 to C.width)
		TEST_ASSERT_EQUAL(length(C.grid[x]), 3, "every actual grid column has the declared height")
		for(var/y in 1 to C.height)
			TEST_ASSERT_EQUAL(C.grid[x][y], "#123456", "native setup fills every actual grid pixel with its declared canvas color")
	var/obj/item/canvas/large = allocate(/obj/item/canvas/twentythree_nineteen, test_floor())
	TEST_ASSERT_EQUAL(length(large.grid), 23, "the real content subtype keeps its declared grid width")
	TEST_ASSERT_EQUAL(length(large.grid[23]), 19, "the real content subtype keeps its declared grid height")
	TEST_ASSERT_EQUAL(large.grid[23][19], large.canvas_color, "the last actual pixel is initialized too")
	var/obj/item/paint_brush/B = allocate(/obj/item/paint_brush/dq_init_color, test_floor())
	var/obj/item/paint_brush/other = allocate(/obj/item/paint_brush, test_floor())
	TEST_ASSERT_NOTNULL(B.color_drop, "native setup makes the actual per-instance brush image")
	TEST_ASSERT_NOTNULL(other.color_drop, "each actual brush has a real image")
	TEST_ASSERT(B.color_drop != other.color_drop, "two real brushes do not share their mutable color image")
	TEST_ASSERT_EQUAL(B.color_drop.icon_state, "brush_color", "the real image has the required brush overlay state")
	TEST_ASSERT_EQUAL(lowertext(B.color_drop.color), "#123456", "the initialized image uses its actual brush's selected color")
	B.update_paint("#abcdef")
	TEST_ASSERT_EQUAL(lowertext(B.color_drop.color), "#abcdef", "the existing real brush update still changes its own image")
	TEST_ASSERT_EQUAL(lowertext(other.color_drop.color), "#000000", "changing one image does not recolor the independent brush")
