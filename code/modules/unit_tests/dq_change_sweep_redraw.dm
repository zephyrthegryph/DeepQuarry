// The hand changed() marks of the change sweep are gone: a draw redraws because the state it reads is tracked and written through its setter.

/datum/unit_test/dq_change_sweep_navbeacon_redraws_on_open

/datum/unit_test/dq_change_sweep_navbeacon_redraws_on_open/Run()
	var/turf/T = test_floor()
	var/obj/machinery/navbeacon/N = allocate(/obj/machinery/navbeacon, T)
	refresh_flush()
	var/before = N.icon_state
	N.set_open(TRUE)
	refresh_flush()
	TEST_ASSERT(N.icon_state != before, "opening the beacon's hatch redraws it: [before] -> [N.icon_state]")

/datum/unit_test/dq_change_sweep_floodlight_redraws_on_open

/datum/unit_test/dq_change_sweep_floodlight_redraws_on_open/Run()
	var/turf/T = test_floor()
	var/obj/machinery/floodlight/F = allocate(/obj/machinery/floodlight, T)
	refresh_flush()
	var/before = F.icon_state
	F.set_open(TRUE)
	refresh_flush()
	TEST_ASSERT(F.icon_state != before, "opening the cell hatch redraws the floodlight: [before] -> [F.icon_state]")
