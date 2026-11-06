/// A pipe draws nothing, so it carries no has_power reading: an APC flipping its area's channels marks every machine that draws power and no pipe.
/datum/unit_test/pipe_carries_no_has_power

/datum/unit_test/pipe_carries_no_has_power/Run()
	var/obj/machinery/atmospherics/pipe/simple/hidden/supply/pipe = allocate(/obj/machinery/atmospherics/pipe/simple/hidden/supply, run_loc_floor_bottom_left)
	var/obj/machinery/vending/cigarette/vendor = allocate(/obj/machinery/vending/cigarette, run_loc_floor_bottom_left)
	var/area/served = get_area(vendor)
	TEST_ASSERT_EQUAL(get_area(pipe), served, "the pipe and the vendor share an area")
	TEST_ASSERT(vendor.power_area == served, "the vendor reads its area's channels")
	served.set_channels(TRUE, TRUE, TRUE, notify = FALSE)
	stat_drain_marked()
	served.set_channels(FALSE, FALSE, FALSE, notify = FALSE)
	var/pipes_marked = 0
	var/vendor_marked = FALSE
	for(var/list/row as anything in GLOB.stat_marked)
		var/datum/stat_def/def = row[2]
		if(!def || def.name != "has_power")
			continue
		if(row[1] == pipe)
			pipes_marked++
		if(row[1] == vendor)
			vendor_marked = TRUE
	TEST_ASSERT(vendor_marked, "a machine that draws power is re-read when its area's channels flip")
	TEST_ASSERT_EQUAL(pipes_marked, 0, "a pipe is not re-read when its area's channels flip")
	served.set_channels(TRUE, TRUE, TRUE, notify = FALSE)
	stat_drain_marked()
