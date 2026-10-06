#define SERVER_NOMINAL_TEXT "Nominal"

/obj/machinery/rnd/server
	name = "\improper R&D Server"
	desc = "A computer system running a deep neural network that processes arbitrary information to produce data useable in the development of new technologies. In layman's terms, it makes research points."
	icon = 'icons/obj/machines/research_vr.dmi'
	icon_state = "RD-server-on"
	var/base_icon_state = "RD-server"
	circuit = /obj/item/circuitboard/machine/rdserver
	req_access = list(ACCESS_RD)
	/// Declared machine heat (heat_objects.dm): watts dumped into the room while working.
	heat_output = 500
	heat_dissipation = 150

	/// if TRUE, we are currently operational and giving out research points.
	var/working = TRUE
	/// if TRUE, someone manually disabled us via console.
	var/research_disabled = FALSE

CAPABILITIES(/obj/machinery/rnd/server)
	emp_disable(60 SECONDS)
	on_change(STAT_OPERABLE, ANY, then(PROC_REF(emp_state_changed)))

/obj/machinery/rnd/server/Initialize(mapload)
	. = ..()
	//servers handle techwebs differently as we are expected to be there to connect
	//every other machinery on-station.
	if(!stored_research)
		var/datum/techweb/science_web = locate_in_list(SSresearch.techwebs, /datum/techweb/science)
		connect_techweb(science_web)
	rel_add(stored_research, nameof(stored_research.techweb_servers), src)
	name += " [num2hex(rand(1,65535), -1)]" //gives us a random four-digit hex number as part of the name. Y'know, for fluff.
	refresh_working()

/// A server moving to another web leaves the old web's server list.
/obj/machinery/rnd/server/connect_techweb(datum/techweb/new_techweb)
	if(stored_research && stored_research != new_techweb)
		rel_remove(stored_research, nameof(stored_research.techweb_servers), src)
	. = ..()
	if(stored_research)
		rel_add(stored_research, nameof(stored_research.techweb_servers), src)

/// The look (the draw sweep: from its template).
/obj/machinery/rnd/server/draw(datum/look/look)
	..()
	look.state("[base_icon_state]-[appearance_suffix()]")

/// "off" without power; otherwise "on" while working ("halt" covers EMP-ed, disabled or broken).
/obj/machinery/rnd/server/proc/appearance_suffix()
	if(power_lost())
		return "off"
	return working ? "on" : "halt"

/obj/machinery/rnd/server/power_change()
	. = ..()
	refresh_working()

/// Checks if we should be working or not, and updates accordingly.
/obj/machinery/rnd/server/proc/refresh_working()
	if(power_lost() || emp_disabled(src) || research_disabled)
		working = FALSE
	else
		working = TRUE

	// update_current_power_usage()
	update_heat_output()
	changed(src)

/// Only a working server runs hot; halted or EMP'd it emits nothing.
/obj/machinery/rnd/server/current_heat_output()
	if(!working)
		return 0
	return ..()

/// Halted while EMP'd, working again once the outage lapses.
/obj/machinery/rnd/server/proc/emp_state_changed(datum/act/A)
	refresh_working()

/// Toggles whether or not researched_disabled is, yknow, disabled
/obj/machinery/rnd/server/proc/toggle_disable(mob/user)
	research_disabled = !research_disabled
	log_game("[key_name(user)] [research_disabled ? "shut off" : "turned on"] [src]")
	refresh_working()

/// Gets status text based on this server's status for the computer.
/obj/machinery/rnd/server/proc/get_status_text()
	if(emp_disabled(src))
		return "O&F@I*$ - R3*&O$T R@U!R%D"
	else if(power_lost())
		return "Offline - Server Unpowered"
	else if(research_disabled)
		return "Offline - Server Control Disabled"
	else if(!working)
		// If, for some reason, working is FALSE even though we're not emp'd or powerless,
		// We need something to update our working state - such as rebooting the server
		return "Offline - Reboot Required"

	return SERVER_NOMINAL_TEXT

/// Master R&D server. As long as this still exists and still holds the HDD for the theft objective, research points generate at normal speed. Destroy it or an antag steals the HDD? Half research speed.
/obj/machinery/rnd/server/master
	// max_integrity = 1800 //takes roughly ~15s longer to break then full deconstruction.
	circuit = null

/obj/machinery/rnd/server/master/Initialize(mapload)
	. = ..()
	name = "\improper Master " + name
	add_overlay("RD-server-objective-stripes")

CAPABILITIES(/obj/machinery/rnd/server/master)
	op("block", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_block)))

/obj/machinery/rnd/server/master/proc/interaction_block(datum/act/op/A)
	// No doing anything to the master server
	return TRUE

#undef SERVER_NOMINAL_TEXT
