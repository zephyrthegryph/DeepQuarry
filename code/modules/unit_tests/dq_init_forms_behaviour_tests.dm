// What the types whose post-init work moved from LateInitialize() to after_init() do once they are made
// (code/engine/actions/after_init.dm). Written against the old form first; each holds under both.

/datum/unit_test/dq_init_forms_behaviour
	abstract_type = /datum/unit_test/dq_init_forms_behaviour

/// A closed closet made on a turf takes in the loose items lying there.
/datum/unit_test/dq_init_forms_behaviour/closet_takes_loose_items

/datum/unit_test/dq_init_forms_behaviour/closet_takes_loose_items/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/paper/P = allocate(/obj/item/paper, T)
	var/obj/structure/closet/C = allocate(/obj/structure/closet, T)
	TEST_ASSERT_EQUAL(P.loc, C, "the closet took in the paper on its turf")

/// A safe made on a turf takes in the items lying there, as space allows.
/datum/unit_test/dq_init_forms_behaviour/safe_takes_loose_items

/datum/unit_test/dq_init_forms_behaviour/safe_takes_loose_items/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/paper/P = allocate(/obj/item/paper, T)
	var/obj/structure/safe/S = allocate(/obj/structure/safe, T)
	TEST_ASSERT_EQUAL(P.loc, S, "the safe took in the paper on its turf")

/// A hydroponics tray made over a seed packet plants it.
/datum/unit_test/dq_init_forms_behaviour/tray_plants_seeds_on_its_turf

/datum/unit_test/dq_init_forms_behaviour/tray_plants_seeds_on_its_turf/Run()
	var/turf/T = dq_containment_floor()
	allocate(/obj/item/seeds/chiliseed, T)
	var/obj/machinery/portable_atmospherics/hydroponics/tray = allocate(/obj/machinery/portable_atmospherics/hydroponics, T)
	TEST_ASSERT_NOTNULL(tray.seed, "the tray planted the seeds lying under it")

/// A breaker box made in its activated form is on.
/datum/unit_test/dq_init_forms_behaviour/activated_breaker_starts_on

/datum/unit_test/dq_init_forms_behaviour/activated_breaker_starts_on/Run()
	var/obj/machinery/power/breakerbox/activated/B = allocate(/obj/machinery/power/breakerbox/activated, dq_containment_floor())
	TEST_ASSERT(B.on, "the activated breaker box is on")

/// A brig door timer finds the brig lockers that share its id.
/datum/unit_test/dq_init_forms_behaviour/door_timer_finds_its_lockers

/datum/unit_test/dq_init_forms_behaviour/door_timer_finds_its_lockers/Run()
	var/turf/T = dq_containment_floor()
	var/obj/structure/closet/secure_closet/brig/locker = allocate(/obj/structure/closet/secure_closet/brig, T)
	locker.id = "Cell 1"
	var/obj/machinery/door_timer/cell_1/timer = allocate(/obj/machinery/door_timer/cell_1, get_step(T, EAST))
	TEST_ASSERT(locker in timer.targets, "the timer linked the locker with its id")

/// A broken wooden floor made at runtime comes out broken.
/datum/unit_test/dq_init_forms_behaviour/broken_wood_floor_is_broken

/datum/unit_test/dq_init_forms_behaviour/broken_wood_floor_is_broken/Run()
	var/turf/T = dq_containment_floor()
	var/old_type = T.type
	var/turf/simulated/floor/wood/broken/W = T.ChangeTurf(/turf/simulated/floor/wood/broken)
	TEST_ASSERT(istype(W) && !isnull(W.broken), "the floor broke its tile after init")
	W.ChangeTurf(old_type)
