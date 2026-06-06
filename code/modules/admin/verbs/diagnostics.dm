// DQEdit — rewrote off ZAS zones. SSair.zones / SSair.tiles_to_update /
// /datum/zone don't exist under LINDA. Report LINDA's real stats instead:
// active_turfs (turfs SSair is currently sharing), excited_groups (groups of
// turfs converging on equilibrium), hotspot count from SSair.hotspots, and
// the high-pressure delta queue (spacewind).
ADMIN_VERB(air_report, R_DEBUG, "Show Air Report", "Displays the current atmos stats.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	if(!SSair.initialized)
		tgui_alert_async(user, "SSair not ready.", "Air Report")
		return

	var/active_turfs_total = length(SSair.active_turfs)
	var/active_on_main_station = 0
	for(var/turf/T as anything in SSair.active_turfs)
		if(T.z in using_map.station_levels)
			active_on_main_station++

	var/hotspots = 0
	for(var/obj/effect/hotspot/H in world)
		if(!QDELETED(H))
			hotspots++

	var/output = {"<B>AIR SYSTEMS REPORT</B><HR>
<B>General Processing Data</B><BR>
	Cycle: [SSair.times_fired]<BR>
	Active turfs: [active_turfs_total]<BR>
	&nbsp;&nbsp;on station: [active_on_main_station]<BR>
	Excited groups: [length(SSair.excited_groups)]<BR>
<BR>
<B>Special Processing Data</B><BR>
	Hotspots (active fires): [hotspots]<BR>
	High-pressure delta queue: [length(SSair.high_pressure_delta)]<BR>
<BR>
<B>Pipenets</B><BR>
	Networks: [length(SSair.networks)]<BR>
"}

	var/datum/browser/popup = new(user, "airreport", "Airreport")
	popup.set_content(output)
	popup.open()

ADMIN_VERB(radio_report, R_DEBUG, "Radio report", "Displays a radio report.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	var/output = "<b>Radio Report</b><hr>"
	for (var/fq in SSradio.frequencies)
		output += "<b>Freq: [fq]</b><br>"
		var/datum/radio_frequency/fqs = SSradio.frequencies[fq]
		if (!fqs)
			output += "&nbsp;&nbsp;<b>ERROR</b><br>"
			continue
		for (var/radio_filter, device_list in fqs.devices)
			var/list/f = device_list
			if (!f)
				output += "&nbsp;&nbsp;[radio_filter]: ERROR<br>"
				continue
			output += "&nbsp;&nbsp;[radio_filter]: [f.len]<br>"
			for (var/device in f)
				if (isobj(device))
					output += "&nbsp;&nbsp;&nbsp;&nbsp;[device] ([device:x],[device:y],[device:z] in area [get_area(device:loc)])<br>"
					continue
				output += "&nbsp;&nbsp;&nbsp;&nbsp;[device]<br>"

	var/datum/browser/popup = new(user, "radioreport", "Radioreport")
	popup.set_content(output)
	popup.open()
	feedback_add_details("admin_verb","RR") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(reload_admins, R_SERVER, "Reload Admins", "Reloads admins from the file or database.", ADMIN_CATEGORY_DEBUG_SERVER)
	message_admins("[user] manually reloaded admins")
	load_admins()
	feedback_add_details("admin_verb","RLDA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(print_jobban_old, R_ADMIN|R_MOD, "Print Jobban Log", "This spams all the active jobban entries for the current round to standard output.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	to_chat(user, span_debug_info(span_bold("Jobbans active in this round.")))
	for(var/t in GLOB.jobban_keylist)
		to_chat(user, span_debug_info("[t]"))

ADMIN_VERB(print_jobban_old_filter, R_ADMIN|R_MOD, "Search Jobban Log", "This searches all the active jobban entries for the current round and outputs the results to standard output.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	var/job_filter = tgui_input_text(user, "Contains what?","Job Filter")
	if(!job_filter)
		return

	to_chat(user, span_debug_info(span_bold("Jobbans active in this round.")))
	for(var/t in GLOB.jobban_keylist)
		if(findtext(t, job_filter))
			to_chat(user, span_debug_info("[t]"))
