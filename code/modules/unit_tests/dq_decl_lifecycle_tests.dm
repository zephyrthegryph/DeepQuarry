// Declarative lifecycle primitives (doc/rewrite/declarative_lifecycle.md,
// code/datums/lifecycle/declarations.dm): one test per primitive, plus the documented
// order and the pilot conversions (reagent containers, space heater, floodlight).

#define REGISTRY_DQ_DECL_TEST "dq_decl_test"
REGISTRY_DECLARE_CONDITIONAL(dq_decl_test, REGISTRY_DQ_DECL_TEST)

GLOBAL_LIST_EMPTY(dq_decl_test_log)

// ---- Fixtures ----

/datum/dq_decl_owned_child
	var/datum/owner_ref

/datum/dq_decl_owned_child/New(datum/owner)
	rel_set(src, nameof(owner_ref), owner)


/obj/item/dq_decl_part
	name = "declared part"

/obj/item/dq_decl_part/better
	name = "better declared part"

/datum/decl_binder/dq_decl_test/bind_list(list/atoms)
	GLOB.dq_decl_test_log += "bind:[length(atoms)]"
	return ..()

/datum/decl_binder/dq_decl_test/bind(atom/A)
	var/obj/item/dq_decl_probe/probe = A
	probe.bound = TRUE

/datum/decl_binder/dq_decl_test/unbind(atom/A)
	var/obj/item/dq_decl_probe/probe = A
	if(probe.bound)
		GLOB.dq_decl_test_log += "unbind"
	probe.bound = FALSE

/// Uses every primitive.
/obj/item/dq_decl_probe
	name = "declaration probe"
	icon = 'icons/obj/chemical.dmi'
	icon_state = "beaker"
	var/volume = 40
	var/mode = "off"
	var/lid = FALSE
	var/bound = FALSE
	var/timer_fired = FALSE
	var/datum/dq_decl_owned_child/helper
	var/obj/item/dq_decl_part/part
	var/obj/item/dq_decl_part/mapped_part = /obj/item/dq_decl_part/better
	var/list/spares
	var/datum/gas_mixture/air_contents
	/// What the type's own Initialize() saw after `. = ..()` (the init declarations ran first).
	var/saw_reagents_in_initialize = 0
	var/saw_part_in_initialize = FALSE

/obj/item/dq_decl_probe/ownership()
	. = ..()
	. += owns(nameof(part), policy = OWN_CONTAINED, starts = /obj/item/dq_decl_part)
	. += owns(nameof(mapped_part), policy = OWN_CONTAINED, starts = /obj/item/dq_decl_part)

CAPABILITIES(/obj/item/dq_decl_probe)
	reagents(nameof(volume), starts = list(REAGENT_ID_WATER = 10))
	owns_one(nameof(air_contents), /datum/gas_mixture)
	owns_one(nameof(helper), starts = /datum/dq_decl_owned_child)
	owns_many(nameof(spares), starts = list(/obj/item/dq_decl_part = 2))
	after_init(2 SECONDS, then(PROC_REF(timer_done)))

DECLARE_GAS(/obj/item/dq_decl_probe, "air_contents", 70, T20C, list(GAS_O2 = ONE_ATMOSPHERE))
DECLARE_APPEARANCE(/obj/item/dq_decl_probe, "mode", list("off" = list(APPEARANCE_ICON_STATE = "beaker"), "on" = list(APPEARANCE_ICON_STATE = "beakerlarge", APPEARANCE_OVERLAYS = list("lid_beaker"))))
DECLARE_APPEARANCE(/obj/item/dq_decl_probe, "lid", list("1" = list(APPEARANCE_OVERLAYS = list("lid_beakerlarge"))))
DECLARE_REGISTRY(/obj/item/dq_decl_probe, REGISTRY_DQ_DECL_TEST)
DECLARE_BIND(/obj/item/dq_decl_probe, /datum/decl_binder/dq_decl_test)
DECLARE_PERIODIC(/obj/item/dq_decl_probe, PERIODIC_SLOW)
DESTROY_EFFECTS(/obj/item/dq_decl_probe, new /datum/destroy_effects_data(drop_contents = TRUE, debris = list(/obj/item/dq_decl_part/better = 2)))

/obj/item/dq_decl_probe/Initialize(mapload)
	. = ..()
	saw_reagents_in_initialize = reagents?.total_volume
	saw_part_in_initialize = istype(part)

/obj/item/dq_decl_probe/proc/timer_done(datum/act/A)
	timer_fired = TRUE

/obj/item/dq_decl_probe/periodic_step(delta)
	return

/// Adds to the parent's reagents (the old ..() chain added too) and tints.
/obj/item/dq_decl_probe/sub
CAPABILITIES(/obj/item/dq_decl_probe/sub)
	configure(reagents(volume = 60, add = list(REAGENT_ID_WATER = 5, REAGENT_ID_ETHANOL = 5), tint = TRUE))

/// Starts with no declared reagents at all.
/obj/item/dq_decl_probe/dry
CAPABILITIES(/obj/item/dq_decl_probe/dry)
	without(CAP_REAGENTS)

/// How many of A's overlays show icon state `state` (add_overlay() re-adds priority overlays, so
/// the raw length is no measure).
/proc/dq_decl_overlay_count(atom/A, state)
	. = 0
	for(var/image/overlay as anything in A.overlays)
		if(overlay.icon_state == state)
			.++

/obj/machinery/shower/dq_decl_probe
	reagent_id = REAGENT_ID_ETHANOL
	reaction_volume = 50

// ---- Tests ----

/datum/unit_test/dq_decl_reagents

/datum/unit_test/dq_decl_reagents/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_decl_probe/probe = allocate(/obj/item/dq_decl_probe, T)
	TEST_ASSERT(probe.reagents, "a declared holder exists")
	TEST_ASSERT_EQUAL(probe.reagents.maximum_volume, 40, "volume read from the declared var")
	TEST_ASSERT_EQUAL(probe.reagents.get_reagent_amount(REAGENT_ID_WATER), 10, "declared water")
	TEST_ASSERT_EQUAL(probe.saw_reagents_in_initialize, 10, "the type's Initialize() saw the reagents after ..()")

	var/obj/item/dq_decl_probe/sub/sub = allocate(/obj/item/dq_decl_probe/sub, T)
	TEST_ASSERT_EQUAL(sub.reagents.maximum_volume, 60, "a subtype's volume replaces the parent's")
	TEST_ASSERT_EQUAL(sub.reagents.get_reagent_amount(REAGENT_ID_WATER), 15, "a subtype's contents add to the parent's")
	TEST_ASSERT_EQUAL(sub.reagents.get_reagent_amount(REAGENT_ID_ETHANOL), 5, "and bring their own")
	TEST_ASSERT_EQUAL(uppertext(copytext(sub.color, 1, 8)), uppertext(copytext(sub.reagents.get_color(), 1, 8)), "the tinted form colours from the reagents")

	var/obj/item/dq_decl_probe/dry/dry = allocate(/obj/item/dq_decl_probe/dry, T)
	TEST_ASSERT(isnull(dry.reagents), "without(CAP_REAGENTS) drops the inherited holder")

	var/obj/machinery/shower/dq_decl_probe/shower = allocate(/obj/machinery/shower/dq_decl_probe, T)
	TEST_ASSERT_EQUAL(shower.reagents.maximum_volume, 50, "the shower's holder follows reaction_volume")
	TEST_ASSERT_EQUAL(shower.reagents.get_reagent_amount(REAGENT_ID_ETHANOL), 50, "the shower fills with its reagent_id")
	TEST_ASSERT_EQUAL(shower.reagents.get_reagent_amount(REAGENT_ID_WATER), 0, "and not hardcoded water")


/datum/unit_test/dq_decl_children

/datum/unit_test/dq_decl_children/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_decl_probe/probe = allocate(/obj/item/dq_decl_probe, T)
	TEST_ASSERT(istype(probe.helper, /datum/dq_decl_owned_child), "an owned datum child from the default type")
	TEST_ASSERT_EQUAL(probe.helper.owner_ref, probe, "created with src as its first argument")
	TEST_ASSERT(istype(probe.part, /obj/item/dq_decl_part) && probe.part.loc == probe, "a held child made inside the owner")
	TEST_ASSERT(istype(probe.mapped_part, /obj/item/dq_decl_part/better), "a path in the var beats the declared default")
	TEST_ASSERT_EQUAL(length(probe.spares), 2, "a list default with a count")
	TEST_ASSERT(probe.saw_part_in_initialize, "children exist when the type's Initialize() runs")

	var/datum/dq_decl_owned_child/helper = probe.helper
	var/obj/item/dq_decl_part/spare = probe.spares[1]
	qdel(probe)
	TEST_ASSERT(QDELETED(helper), "an owned declared child dies with its owner (phase 4)")
	TEST_ASSERT(QDELETED(spare), "so does each owned list member")


/datum/unit_test/dq_decl_gas

/datum/unit_test/dq_decl_gas/Run()
	var/obj/item/dq_decl_probe/probe = allocate(/obj/item/dq_decl_probe, dq_containment_floor())
	TEST_ASSERT(probe.air_contents, "a declared gas mixture")
	TEST_ASSERT_EQUAL(probe.air_contents.return_volume(), 70, "at the declared volume")
	var/pressure = probe.air_contents.return_pressure()
	TEST_ASSERT(abs(pressure - ONE_ATMOSPHERE) < 1, "at the declared pressure, got [pressure]")

/datum/unit_test/dq_decl_appearance

/datum/unit_test/dq_decl_appearance/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_decl_probe/probe = allocate(/obj/item/dq_decl_probe, T)
	var/obj/item/dq_decl_probe/twin = allocate(/obj/item/dq_decl_probe, T)
	TEST_ASSERT_EQUAL(probe.icon_state, "beaker", "the row for the initial state")
	TEST_ASSERT_EQUAL(dq_decl_overlay_count(probe, "lid_beaker"), 0, "no row overlay yet")

	probe.mode = "on"
	probe.update_icon()
	TEST_ASSERT_EQUAL(probe.icon_state, "beakerlarge", "update_icon() follows the state var with no override")
	TEST_ASSERT_EQUAL(dq_decl_overlay_count(probe, "lid_beaker"), 1, "the row's overlay was added")

	probe.lid = TRUE
	probe.update_icon()
	TEST_ASSERT_EQUAL(dq_decl_overlay_count(probe, "lid_beakerlarge"), 1, "a second layer adds its overlay")
	TEST_ASSERT_EQUAL(dq_decl_overlay_count(probe, "lid_beaker"), 1, "and keeps the first layer's")

	probe.mode = "off"
	probe.lid = FALSE
	probe.update_icon()
	TEST_ASSERT_EQUAL(probe.icon_state, "beaker", "back to the first row")
	TEST_ASSERT_EQUAL(dq_decl_overlay_count(probe, "lid_beaker") + dq_decl_overlay_count(probe, "lid_beakerlarge"), 0, "the declared overlays were swapped out")

	twin.mode = "on"
	twin.update_icon()
	probe.mode = "on"
	probe.update_icon()
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(probe)
	TEST_ASSERT(decls.appearance_row(probe, decls.appearance_key(probe)) == decls.appearance_row(twin, decls.appearance_key(twin)), "one shared appearance per (type, state)")

/datum/unit_test/dq_decl_registry

/datum/unit_test/dq_decl_registry/Run()
	var/obj/item/dq_decl_probe/probe = allocate(/obj/item/dq_decl_probe, dq_containment_floor())
	TEST_ASSERT(probe in REGISTRY_MEMBERS(REGISTRY_DQ_DECL_TEST), "a conditional registry joined at materialize")
	probe.dematerialize()
	TEST_ASSERT(!(probe in REGISTRY_MEMBERS(REGISTRY_DQ_DECL_TEST)), "left at dematerialize")
	probe.materialize()
	TEST_ASSERT(probe in REGISTRY_MEMBERS(REGISTRY_DQ_DECL_TEST), "and joined again")
	qdel(probe)
	TEST_ASSERT(!(probe in REGISTRY_MEMBERS(REGISTRY_DQ_DECL_TEST)), "left at destroy")

/datum/unit_test/dq_decl_binds

/datum/unit_test/dq_decl_binds/Run()
	var/turf/T = dq_containment_floor()
	set_global("dq_decl_test_log", list())
	var/obj/item/dq_decl_probe/single = allocate(/obj/item/dq_decl_probe, T)
	TEST_ASSERT(single.bound, "bound at materialize outside a batch")
	TEST_ASSERT_EQUAL(jointext(GLOB.dq_decl_test_log, ","), "bind:1", "one bind_list() call for it")

	// A batch: SSatoms owns deferred_decl_binds for the length of InitializeAtoms().
	set_global("dq_decl_test_log", list())
	var/list/saved = SSatoms.deferred_decl_binds
	SSatoms.deferred_decl_binds = list()
	var/list/probes = list()
	for(var/i in 1 to 3)
		probes += allocate(/obj/item/dq_decl_probe, T)
	var/obj/item/dq_decl_probe/first = probes[1]
	TEST_ASSERT(!first.bound, "not bound until the batch ends")
	qdel(probes[3]) // gone before the flush: never bound, dropped from the queue
	SSatoms.flush_decl_binds()
	SSatoms.deferred_decl_binds = saved
	TEST_ASSERT(first.bound, "bound when the batch flushed")
	TEST_ASSERT_EQUAL(jointext(GLOB.dq_decl_test_log, ","), "bind:2", "one bind_list() for the whole batch")

	set_global("dq_decl_test_log", list())
	qdel(single)
	TEST_ASSERT_EQUAL(jointext(GLOB.dq_decl_test_log, ","), "unbind", "released once, in destroy phase 1")

/datum/unit_test/dq_decl_scheduling

/datum/unit_test/dq_decl_scheduling/Run()
	scheduler_test_begin()
	var/obj/item/dq_decl_probe/probe = new(dq_containment_floor())
	TEST_ASSERT(probe.periodic_pipe == PERIODIC_SLOW, "periodic work started at materialize")
	TEST_ASSERT(!probe.timer_fired, "the timer waits")
	scheduler_advance(3)
	TEST_ASSERT(probe.timer_fired, "the declared timer fired")
	probe.dematerialize()
	TEST_ASSERT(isnull(probe.periodic_pipe), "periodic work stopped at dematerialize")
	qdel(probe)
	scheduler_test_end()

/datum/unit_test/dq_decl_destroy_effects

/datum/unit_test/dq_decl_destroy_effects/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_decl_probe/probe = new(T)
	var/obj/item/dq_decl_part/loose = new(probe) // no slot, no declaration: a leftover in contents
	var/before = length(contents_of(T, /obj/item/dq_decl_part/better))
	qdel(probe)
	TEST_ASSERT_EQUAL(loose.loc, T, "drop_contents moved the leftover to the turf")
	// Two declared debris (the contained mapped_part, also a /better, may be dropped too).
	TEST_ASSERT(length(contents_of(T, /obj/item/dq_decl_part/better)) - before >= 2, "the declared debris list spawned")
	for(var/obj/item/dq_decl_part/P in contents_of(T))
		qdel(P)

/// The documented order: init declarations inside Initialize() (before the type's own code after
/// ..()), materialize ones after. A sandboxed object has the first and not the second.
/datum/unit_test/dq_decl_order

/datum/unit_test/dq_decl_order/Run()
	var/obj/item/dq_decl_probe/probe = new_unmaterialized(/obj/item/dq_decl_probe, dq_containment_floor())
	TEST_ASSERT(probe.reagents && probe.part && probe.air_contents, "init declarations ran in a sandbox")
	TEST_ASSERT(!(probe in REGISTRY_MEMBERS(REGISTRY_DQ_DECL_TEST)) && !probe.bound, "materialize declarations did not")
	probe.materialize()
	TEST_ASSERT((probe in REGISTRY_MEMBERS(REGISTRY_DQ_DECL_TEST)) && probe.bound, "they run when it goes live")
	qdel(probe)

// ---- Pilot conversions ----

/datum/unit_test/dq_decl_pilot_reagent_containers

/datum/unit_test/dq_decl_pilot_reagent_containers/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/reagent_containers/glass/beaker/beaker = allocate(/obj/item/reagent_containers/glass/beaker, T)
	TEST_ASSERT_EQUAL(beaker.reagents?.maximum_volume, beaker.volume, "every container gets a holder of its volume")
	var/obj/item/reagent_containers/pill/antitox/pill = allocate(/obj/item/reagent_containers/pill/antitox, T)
	TEST_ASSERT_EQUAL(pill.reagents.get_reagent_amount(REAGENT_ID_ANTITOXIN), 30, "a converted pill keeps its contents")
	TEST_ASSERT_EQUAL(uppertext(copytext(pill.color, 1, 8)), uppertext(copytext(pill.reagents.get_color(), 1, 8)), "and its reagent colour")

/datum/unit_test/dq_decl_pilot_space_heater

/datum/unit_test/dq_decl_pilot_space_heater/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/space_heater/heater = allocate(/obj/machinery/space_heater, T)
	TEST_ASSERT(istype(heater.cell, heater.cell_type) && heater.cell.loc == heater, "the cell comes from cell_type")
	TEST_ASSERT_EQUAL(heater.icon_state, "sheater0", "icon_state follows state")
	TEST_ASSERT_EQUAL(dq_decl_overlay_count(heater, "sheater-open"), 0, "hatch closed")
	heater.set_panel_open(TRUE)
	heater.update_icon()
	TEST_ASSERT_EQUAL(dq_decl_overlay_count(heater, "sheater-open"), 1, "the hatch overlay follows panel_open")
	heater.set_panel_open(FALSE)
	heater.update_icon()
	TEST_ASSERT_EQUAL(dq_decl_overlay_count(heater, "sheater-open"), 0, "and goes again")

	var/obj/machinery/floodlight/light = allocate(/obj/machinery/floodlight, T)
	TEST_ASSERT(istype(light.cell, /obj/item/cell), "the floodlight's declared default cell")

#undef REGISTRY_DQ_DECL_TEST
