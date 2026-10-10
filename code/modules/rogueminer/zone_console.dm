//////////////////////////////
// The zone control console, fluffed ingame as
// a scanner console for the asteroid belt
//////////////////////////////
#define OUTPOST_Z 2
#define TRANSIT_Z 3
#define BELT_Z 10

/obj/machinery/computer/roguezones
	name = "asteroid belt scanning computer"
	desc = "Used to monitor the nearby asteroid belt and detect new areas."
	icon_keyboard = "tech_key"
	icon_screen = "request"
	light_color = "#315ab4"
	use_power = USE_POWER_IDLE
	idle_power_usage = 250
	active_power_usage = 500
	circuit = /obj/item/circuitboard/roguezones

	var/debug = 0
	var/debug_scans = 0
	var/scanning = 0
	var/legacy_zone = 0 //Disable scanning and whatnot.
	var/tmp/obj/machinery/computer/shuttle_control/belter/shuttle_control

/obj/machinery/computer/roguezones/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(shuttle_control), locate(/obj/machinery/computer/shuttle_control/belter))

/// Makes the rogue controller the first console needs.
/obj/machinery/computer/roguezones/proc/make_controller(datum/act/timer/A)
	if(!GLOB.rm_controller)
		GLOB.rm_controller = new /datum/controller/rogue()

/obj/machinery/computer/roguezones/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(!operable())
		return TRUE
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/machinery/computer/roguezones)
	after_init(0, then(PROC_REF(make_controller)))
	interface("RogueZones")
	op("scan_for_new", ui_act("scan_for_new"), then(PROC_REF(ui_act_scan_for_new)))
	op("recall_shuttle", ui_act("recall_shuttle"), then(PROC_REF(ui_act_recall_shuttle)))
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_use)))

/obj/machinery/computer/roguezones/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["scanning"] = scanning
	data["debug"] = debug
	var/list/merged_1 = ui_data_obj_machinery_computer_roguezones(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/computer/roguezones's window data.
/obj/machinery/computer/roguezones/proc/ui_data_obj_machinery_computer_roguezones(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/chargePercent = min(100, ((((world.time - GLOB.rm_controller.last_scan) / 10) / 60) / GLOB.rm_controller.scan_wait) * 100)
	var/curZoneOccupied = GLOB.rm_controller.current_zone() ? GLOB.rm_controller.current_zone().is_occupied() : 0

	var/list/data = list()
	data["timeout_percent"] = chargePercent
	data["diffstep"] = GLOB.rm_controller.diffstep
	data["difficulty"] = GLOB.rm_controller.diffstep_strs[GLOB.rm_controller.diffstep]
	data["occupied"] = curZoneOccupied
	data["updated"] = ELAPSED(GLOB.rm_controller, last_scan, CLOCK_WORLD) < 20 SECONDS //Very recently scanned (20 seconds)

	if(!shuttle_control())
		data["shuttle_location"] = "Unknown"
		data["shuttle_at_station"] = 0
	else if(shuttle_control().z in using_map.belter_docked_z)
		data["shuttle_location"] = "Landed"
		data["shuttle_at_station"] = 1
	else if(shuttle_control().z == using_map.belter_transit_z)
		data["shuttle_location"] = "In-transit"
		data["shuttle_at_station"] = 0
	else if(shuttle_control().z == using_map.belter_belt_z)
		data["shuttle_location"] = "Belt"
		data["shuttle_at_station"] = 0

	var/can_scan = 0
	if(chargePercent >= 100) //Keep having weird problems with these in one 'if' statement
		if(shuttle_control() && (shuttle_control().z in using_map.belter_docked_z)) //Even though I put them all in parens to avoid OoO problems...
			if(!curZoneOccupied) //Not sure why.
				if(!scanning)
					can_scan = 1

	if(debug_scans) can_scan = 1
	data["scan_ready"] = can_scan

	// Permit emergency recall of the shuttle if its stranded in a zone with just dead people.
	data["can_recall_shuttle"] = (shuttle_control() && (shuttle_control().z in using_map.belter_belt_z) && !curZoneOccupied)
	return data

/obj/machinery/computer/roguezones/proc/ui_act_scan_for_new(datum/act/op/A)
	var/mob/user = A.actor
	scan_for_new_zone()
	. = TRUE
	add_fingerprint(user)

/obj/machinery/computer/roguezones/proc/ui_act_recall_shuttle(datum/act/op/A)
	var/mob/user = A.actor
	failsafe_shuttle_recall(user)
	. = TRUE
	add_fingerprint(user)

/obj/machinery/computer/roguezones/proc/scan_for_new_zone()
	if(scanning)
		return

	//Set some kinda scanning var to pause UI input on console
	EXPIRY_STAMP(GLOB.rm_controller, last_scan, CLOCK_WORLD)
	scanning = 1
	after(src, 6 SECONDS, PROC_REF(finish_scan))

/obj/machinery/computer/roguezones/proc/finish_scan()
	//Break the shuttle temporarily.
	shuttle_control().shuttle_tag = null

	//Build and get a new zone.
	var/datum/rogue/zonemaster/ZM_target = GLOB.rm_controller.prepare_new_zone()
	if(!ZM_target)
		return

	//Update shuttle destination.
	var/datum/shuttle/autodock/ferry/S = shuttles_shuttles()["Belter"]
	rel_set(S, nameof(S.landmark_offsite), ZM_target.myshuttle_landmark())
	rel_set(S, nameof(S.next_location), S.get_location_waypoint(!S.location))

	//Re-enable shuttle.
	shuttle_control().shuttle_tag = "Belter"

	//Update rm_previous
	rel_set(GLOB.rm_controller, nameof(/datum/controller/rogue::previous_zone), GLOB.rm_controller.current_zone())

	//Update rm_current
	rel_set(GLOB.rm_controller, nameof(/datum/controller/rogue::current_zone), ZM_target)

	//Unset scanning
	scanning = 0

	return


/obj/machinery/computer/roguezones/proc/failsafe_shuttle_recall(mob/user)
	if(!shuttle_control())
		return // Shuttle computer has been destroyed
	if (!(shuttle_control().z in using_map.belter_belt_z))
		return // Usable only when shuttle is away
	if(GLOB.rm_controller.current_zone() && GLOB.rm_controller.current_zone().is_occupied())
		return // Not usable if shuttle is in occupied zone
	// Okay do it
	var/datum/shuttle/autodock/ferry/S = shuttles_shuttles()["Belter"]
	S.launch(user)

/obj/item/circuitboard/roguezones
	name = T_BOARD("asteroid belt scanning computer")
	build_path = /obj/machinery/computer/roguezones
	hidden = TRUE // Might have issues on maps without belters?

/obj/item/paper/rogueminer
	name = "R-38 Scanner Console Guide"
	info = {"<h4>Getting Started</h4>
	Congratulations, your station has purchased the R-38 industrial asteroid belt scanner!<br>
	Using the R-38 is almost as simple as brain surgery! Simply press the scan button to scan for a new mineral-rich asteroid belt location!<br>
	<b>That's all there is to it!</b><br>
	Notice, scan may cause extreme brain damage to those present in asteroid belt, so scanning will be disabled in that case.<br>
	Existing minerals and living creatures interfere with the scans, so the more minerals extracted and creatures 'removed'/made-not-living in the belt, the more accurate future scans will be.<br>
	<h4>Traveling to the belt</h4>
	When a new zone has been scanned, your station's shuttle destination will be updated to direct it to the newly discovered area automatically.<br>
	You can then travel to the new area to mine in that location.<br>
	<br>
	<br> "} + span_small("This technology produced under license from Thinktronic Systems, LTD.")


#undef OUTPOST_Z
#undef TRANSIT_Z
#undef BELT_Z

/// Accessor for the shuttle_control var.
/obj/machinery/computer/roguezones/proc/shuttle_control() as /obj/machinery/computer/shuttle_control/belter
	return shuttle_control
