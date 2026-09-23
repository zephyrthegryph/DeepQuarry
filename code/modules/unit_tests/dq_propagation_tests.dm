// Behaviour tests for the propagation users (M5, doc/rewrite/simulation.md §8):
// radiation shielding and EMP falloff. They go through radiation_pulse() and
// empulse(), so they describe behaviour, not the implementation behind it.

/datum/unit_test/proc/rad_mouse(turf/where)
	var/mob/living/simple_mob/animal/passive/mouse/white/mouse = allocate(/mob/living/simple_mob/animal/passive/mouse/white, where)
	mouse.ai_brain?.go_sleep()
	mouse.radiation = 0
	return mouse

/// Runs SSradiation until every queued pulse has been applied.
/datum/unit_test/proc/rad_drain()
	var/rounds = 0
	while(length(SSradiation.processing) && rounds++ < 200)
		SSradiation.fire(FALSE)
		if(length(SSradiation.processing))
			stoplag()
	TEST_ASSERT(!length(SSradiation.processing), "radiation pulses should drain")

/// Five open turfs in a row, west to east, on an empty z-level of their own
/// (made once and shared by these tests; world.maxz cannot shrink).
/datum/unit_test/proc/rad_row()
	var/static/rad_z
	if(!rad_z)
		world.increment_max_z()
		rad_z = world.maxz
	. = list()
	for(var/dx in 0 to 4)
		. += locate(20 + dx, 20, rad_z)

/// A wall between the source and a mob stops a pulse that the open side lets through.
/datum/unit_test/dq_radiation_wall_shields

/datum/unit_test/dq_radiation_wall_shields/Run()
	var/list/row = rad_row()
	var/turf/source_turf = row[3]
	var/turf/wall_turf = row[4]
	var/old_type = wall_turf.type
	var/mob/living/shielded = rad_mouse(row[5])
	var/mob/living/open = rad_mouse(row[1])
	var/obj/item/source = allocate(/obj/item/stack/material/steel, source_turf)
	wall_turf.ChangeTurf(/turf/simulated/wall)
	var/insulation = wall_turf.rad_insulation
	TEST_ASSERT(insulation < 1, "a wall should insulate")
	radiation_pulse(source, 4, (1 + insulation) / 2, 100, 0, 50)
	rad_drain()
	wall_turf.ChangeTurf(old_type)
	TEST_ASSERT(open.radiation > 0, "an unshielded mob should be irradiated")
	TEST_ASSERT_EQUAL(shielded.radiation, 0, "a mob behind a wall should be shielded")

/// Closer mobs take a bigger dose than farther ones.
/datum/unit_test/dq_radiation_dose_falls_off

/datum/unit_test/dq_radiation_dose_falls_off/Run()
	var/list/row = rad_row()
	var/obj/item/source = allocate(/obj/item/stack/material/steel, row[1])
	var/mob/living/near = rad_mouse(row[2])
	var/mob/living/far = rad_mouse(row[5])
	// Chance 99 over range 4: the near mob is all but certain to be hit at almost
	// full strength, the far one gets at most about 80% of it.
	radiation_pulse(source, 4, 0, 99, 0, 100)
	rad_drain()
	TEST_ASSERT(near.radiation > far.radiation, "dose should fall off with distance ([near.radiation] near, [far.radiation] far)")

/// An insulating door or movable in the path blocks the pulse, and stops
/// blocking once it moves away.
/datum/unit_test/dq_radiation_insulated_movable_blocks

/datum/unit_test/dq_radiation_insulated_movable_blocks/Run()
	var/list/row = rad_row()
	var/obj/item/source = allocate(/obj/item/stack/material/steel, row[1])
	var/mob/living/target = rad_mouse(row[5])
	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, row[3])
	var/threshold = (1 + door.rad_insulation) / 2
	radiation_pulse(source, 4, threshold, 100, 0, 50)
	rad_drain()
	TEST_ASSERT_EQUAL(target.radiation, 0, "a door in the path should block")
	var/turf/door_turf = row[3]
	door.forceMove(locate(door_turf.x, door_turf.y + 1, door_turf.z))
	radiation_pulse(source, 4, threshold, 100, 0, 50)
	rad_drain()
	TEST_ASSERT(target.radiation > 0, "moving the door out of the path should let radiation through")
	var/obj/structure/window/reinforced/full/shield = allocate(/obj/structure/window/reinforced/full, row[4])
	shield.set_rad_insulation(0)
	target.radiation = 0
	radiation_pulse(source, 4, 0.5, 100, 0, 50)
	rad_drain()
	TEST_ASSERT_EQUAL(target.radiation, 0, "an object set to full insulation should block")

/// Radiation never reaches across a map edge to the far side of the next row.
/datum/unit_test/dq_radiation_does_not_cross_map_edges

/datum/unit_test/dq_radiation_does_not_cross_map_edges/Run()
	var/list/row = rad_row()
	var/turf/corner = row[1]
	var/turf/east_edge = locate(world.maxx, corner.y, corner.z)
	var/turf/west_edge = locate(1, corner.y + 1, corner.z)
	var/mob/living/target = rad_mouse(corner)
	target.forceMove(east_edge)
	var/obj/item/source = allocate(/obj/item/stack/material/steel, corner)
	source.forceMove(west_edge)
	radiation_pulse(source, 5, 0, 100, 0, 50)
	rad_drain()
	TEST_ASSERT_EQUAL(target.radiation, 0, "a pulse on the west edge should not wrap to the east edge of the row below")

/// Records every EMP severity it is hit with.
/obj/dq_emp_probe
	var/list/severities = list()

/obj/dq_emp_probe/emp_act(severity, recursive)
	severities |= severity
	return ..()

/// EMP severity is heavy at the centre and weakens ring by ring, stops at the
/// outer range, and never wraps across a map edge.
/datum/unit_test/dq_emp_severity_rings

/datum/unit_test/dq_emp_severity_rings/Run()
	var/list/row = rad_row()
	var/turf/centre = row[3]
	var/list/obj/dq_emp_probe/probes = list()
	// Probes at distances 0, 1, 2 and 3 from the centre.
	for(var/turf/T as anything in list(row[3], row[2], row[1], locate(centre.x - 3, centre.y, centre.z)))
		probes += allocate(/obj/dq_emp_probe, T)
	// Bands: heavy below 1, heavy/medium at 1, medium/light at 2 (the third band's edge); nothing past 2.
	for(var/i in 1 to 8)
		empulse(centre, 1, 1, 2, 2)
	var/obj/dq_emp_probe/at_centre = probes[1]
	var/obj/dq_emp_probe/ring_one = probes[2]
	var/obj/dq_emp_probe/ring_two = probes[3]
	var/obj/dq_emp_probe/outside = probes[4]
	TEST_ASSERT_EQUAL(jointext(at_centre.severities, ","), "[EMP_HEAVY]", "the centre takes only heavy pulses")
	TEST_ASSERT(!length(ring_one.severities - list(EMP_HEAVY, EMP_MEDIUM)) && length(ring_one.severities), "the first ring is heavy or medium")
	TEST_ASSERT(!length(ring_two.severities - list(EMP_MEDIUM, EMP_LIGHT)) && length(ring_two.severities), "the edge of the third band is medium or light")
	TEST_ASSERT(!length(outside.severities), "nothing past the outer range is pulsed")

	var/obj/dq_emp_probe/wrapped = allocate(/obj/dq_emp_probe, centre)
	wrapped.forceMove(locate(world.maxx, centre.y - 1, centre.z))
	var/obj/dq_emp_probe/edge = allocate(/obj/dq_emp_probe, centre)
	edge.forceMove(locate(1, centre.y, centre.z))
	empulse(locate(1, centre.y, centre.z), 1, 1, 2, 2)
	TEST_ASSERT(length(edge.severities), "an EMP on the west edge hits its own turf")
	TEST_ASSERT(!length(wrapped.severities), "an EMP on the west edge must not wrap to the east edge of the row below")

/// Moving, spawning or changing an insulating atom marks its turfs for the
/// Rust insulation layer; changing nothing marks nothing.
/datum/unit_test/dq_radiation_shielding_tracks_changes

/datum/unit_test/dq_radiation_shielding_tracks_changes/Run()
	var/list/row = rad_row()
	var/obj/item/stack/material/steel/shield = allocate(/obj/item/stack/material/steel, row[1])
	SSradiation.flush_shielding()
	shield.set_rad_insulation(shield.rad_insulation)
	TEST_ASSERT(!SSradiation.dirty_turfs[row[1]], "setting the same insulation should not mark the turf")
	shield.set_rad_insulation(0.5)
	TEST_ASSERT(SSradiation.dirty_turfs[row[1]], "changing insulation should mark the turf")
	SSradiation.flush_shielding()
	shield.forceMove(row[2])
	TEST_ASSERT(SSradiation.dirty_turfs[row[1]] && SSradiation.dirty_turfs[row[2]], "moving an insulating object should mark both turfs")
	SSradiation.flush_shielding()
	TEST_ASSERT(!length(SSradiation.dirty_turfs), "a flush should clear the dirty turfs")
