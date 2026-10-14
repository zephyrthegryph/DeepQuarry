// Real constructors finish their declared structure/effect setup before callers use them.
/datum/unit_test/dq_a3_initialization
	abstract_type = /datum/unit_test/dq_a3_initialization

/datum/unit_test/dq_a3_initialization/New()
	. = ..()
	dview(0, test_floor())

/datum/unit_test/dq_a3_initialization/proc/scope_setup()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.roll_serial), GLOB.roll_serial)

/datum/unit_test/dq_a3_initialization/canvas_grid/Run()
	scope_setup()
	var/obj/item/canvas/C = allocate(/obj/item/canvas, test_floor())
	TEST_ASSERT_EQUAL(length(C.grid), C.width, "The real canvas allocates every column at construction")
	for(var/x = 1 to C.width)
		TEST_ASSERT_EQUAL(length(C.grid[x]), C.height, "Column [x] has every row")
		for(var/y = 1 to C.height)
			TEST_ASSERT_EQUAL(C.grid[x][y], C.canvas_color, "The blank colour fills cell [x],[y]")

/datum/unit_test/dq_a3_initialization/countdown_attachment/Run()
	scope_setup()
	var/obj/structure/prop/O = allocate(/obj/structure/prop, test_floor())
	var/obj/effect/countdown/C = allocate(/obj/effect/countdown, O)
	TEST_ASSERT_EQUAL(C.attached_to, O, "A countdown attaches to the actual constructor owner")
	TEST_ASSERT_EQUAL(C.loc, get_turf(O), "Its display is moved onto the owner's actual turf")
	TEST_ASSERT(!C.started, "Attaching alone does not start the countdown")

/datum/unit_test/dq_a3_initialization/particle_attachment/Run()
	scope_setup()
	var/obj/structure/prop/O = allocate(/obj/structure/prop, test_floor())
	var/obj/effect/abstract/particle_holder/H = allocate(/obj/effect/abstract/particle_holder, O, /particles/smoke)
	TEST_ASSERT_EQUAL(H.get_parent(), O, "The particle holder captures its real constructor owner")
	TEST_ASSERT(isnull(H.loc), "The holder leaves contents for nullspace")
	TEST_ASSERT(H in O.vis_contents, "The owner actually displays its particle holder")
	TEST_ASSERT(istype(H.particles, /particles/smoke), "The configured particle emitter exists when construction returns")

/datum/unit_test/dq_a3_initialization/shared_particles/Run()
	scope_setup()
	var/obj/effect/abstract/shared_particle_holder/H = allocate(/obj/effect/abstract/shared_particle_holder, test_floor(), /particles/smoke)
	TEST_ASSERT(isnull(H.loc), "A shared renderer leaves the map before callers reuse it")
	TEST_ASSERT(istype(H.particles, /particles/smoke), "The shared renderer realizes its durable particle-path parameter")

/datum/unit_test/dq_a3_initialization/tube_directions/Run()
	scope_setup()
	var/obj/structure/transit_tube/T = allocate(/obj/structure/transit_tube, test_floor())
	TEST_ASSERT_EQUAL(length(T.tube_dirs), 2, "The straight tube starts with both entrances")
	TEST_ASSERT((EAST in T.tube_dirs) && (WEST in T.tube_dirs), "Its default E-W sprite defines its two real entrances")

/obj/effect/anomaly/dq_a3_immortal
	immortal = TRUE
	anomaly_core = null

/datum/unit_test/dq_a3_initialization/anomaly_countdown/Run()
	scope_setup()
	var/obj/effect/anomaly/A = allocate(/obj/effect/anomaly, test_floor(), 30 SECONDS)
	TEST_ASSERT_NOTNULL(A.countdown, "The anomaly's declared countdown exists")
	TEST_ASSERT_EQUAL(A.countdown.attached_to, A, "The child countdown attached before the holder configures it")
	TEST_ASSERT(A.countdown.started, "A mortal anomaly starts its countdown when construction completes")
	TEST_ASSERT(A.countdown.get_value() > 0, "Its constructor lifetime is applied before the countdown is read")
	var/obj/effect/anomaly/I = allocate(/obj/effect/anomaly/dq_a3_immortal, test_floor())
	TEST_ASSERT_NOTNULL(I.countdown, "An immortal anomaly still owns its display")
	TEST_ASSERT(!I.countdown.started, "The immortal variant does not start the countdown")
