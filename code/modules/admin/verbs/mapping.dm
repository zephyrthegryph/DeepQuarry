//- Are all the floors with or without air, as they should be? (regular or airless)
//- Does the area have an APC?
//- Does the area have an Air Alarm?
//- Does the area have a Request Console?
//- Does the area have lights?
//- Does the area have a light switch?
//- Does the area have enough intercoms?
//- Does the area have enough security cameras? (Use the 'Camera Range Display' verb under Debug)
//- Is the area connected to the scrubbers air loop?
//- Is the area connected to the vent air loop? (vent pumps)
//- Is everything wired properly?
//- Does the area have a fire alarm and firedoors?
//- Do all pod doors work properly?
//- Are accesses set properly on doors, pod buttons, etc.
//- Are all items placed properly? (not below vents, scrubbers, tables)
//- Does the disposal system work properly from all the disposal units in this room and all the units, the pipes of which pass through this room?
//- Check for any misplaced or stacked piece of pipe (air and disposal)
//- Check for any misplaced or stacked piece of wire
//- Identify how hard it is to break into the area and where the weak points are
//- Check if the area has too much empty space. If so, make it smaller and replace the rest with maintenance tunnels.

GLOBAL_VAR_INIT(camera_range_display_status, FALSE)
GLOBAL_VAR_INIT(intercom_range_display_status, FALSE)

GLOBAL_LIST_BOILERPLATE(all_debugging_effects, /obj/effect/debugging)

/obj/effect/debugging/camera_range
	icon = 'icons/480x480.dmi'
	icon_state = "25percent"

/obj/effect/debugging/camera_range/Initialize(mapload, ...)
	. = ..()
	src.pixel_x = -224
	src.pixel_y = -224

/obj/effect/debugging/marker
	icon = 'icons/turf/areas.dmi'
	icon_state = "yellow"

/obj/effect/debugging/marker/Move()
	return 0

ADMIN_VERB_VISIBILITY(camera_view, ADMIN_VERB_VISIBLITY_FLAG_LOCALHOST)
ADMIN_VERB(camera_view, R_DEBUG, "Camera Range Display", "Globally changes the camera view (Only use on a test server).", ADMIN_CATEGORY_MAPPING_TESTS)
	if(GLOB.camera_range_display_status)
		GLOB.camera_range_display_status = FALSE
	else
		GLOB.camera_range_display_status = TRUE

	for(var/obj/effect/debugging/camera_range/C in GLOB.all_debugging_effects)
		qdel(C)

	if(GLOB.camera_range_display_status)
		for(var/obj/machinery/camera/C in GLOB.cameranet.cameras)
			new/obj/effect/debugging/camera_range(C.loc)
	feedback_add_details("admin_verb","mCRD") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_VISIBILITY(sec_camera_report, ADMIN_VERB_VISIBLITY_FLAG_LOCALHOST)
ADMIN_VERB(sec_camera_report, R_DEBUG, "Camera Report", "Gives a report of the camera state (Only use on a test server).", ADMIN_CATEGORY_MAPPING_TESTS)
	if(!SSticker.HasRoundStarted())
		tgui_alert_async(user,"Game init not ready.","Sec Camera Report")
		return 0

	var/list/obj/machinery/camera/CL = list()

	for(var/obj/machinery/camera/C in GLOB.cameranet.cameras)
		CL += C

	var/output = span_bold("CAMERA ANNOMALITIES REPORT") + {"<HR>
"} + span_bold("The following annomalities have been detected. The ones in red need immediate attention: Some of those in black may be intentional.") + {"<BR><ul>"}

	for(var/obj/machinery/camera/C1 in CL)
		for(var/obj/machinery/camera/C2 in CL)
			if(C1 != C2)
				if(C1.c_tag == C2.c_tag)
					output += "<li>" + span_red("c_tag match for sec. cameras at \[[C1.x], [C1.y], [C1.z]\] ([C1.loc.loc]) and \[[C2.x], [C2.y], [C2.z]\] ([C2.loc.loc]) - c_tag is [C1.c_tag]") + "</li>"
				if(C1.loc == C2.loc && C1.dir == C2.dir && C1.pixel_x == C2.pixel_x && C1.pixel_y == C2.pixel_y)
					output += "<li>" + span_red("FULLY overlapping sec. cameras at \[[C1.x], [C1.y], [C1.z]\] ([C1.loc.loc]) Networks: [C1.network] and [C2.network]") + "</li>"
				if(C1.loc == C2.loc)
					output += "<li>overlapping sec. cameras at \[[C1.x], [C1.y], [C1.z]\] ([C1.loc.loc]) Networks: [C1.network] and [C2.network]</li>"
		var/turf/T = get_step(C1,turn(C1.dir,180))
		if(!T || !isturf(T) || !T.density )
			if(!(locate(/obj/structure/grille,T)))
				var/window_check = 0
				for(var/obj/structure/window/W in T)
					if (W.dir == turn(C1.dir,180) || (W.dir in list(5,6,9,10)) )
						window_check = 1
						break
				if(!window_check)
					output += "<li>" + span_red("Camera not connected to wall at \[[C1.x], [C1.y], [C1.z]\] ([C1.loc.loc]) Network: [C1.network]") + "</li>"

	output += "</ul>"

	var/datum/browser/popup = new(user, "airreport", "Airreport", 1000, 500)
	popup.set_content(output)
	popup.open()
	feedback_add_details("admin_verb","mCRP") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_VISIBILITY(intercom_view, ADMIN_VERB_VISIBLITY_FLAG_LOCALHOST)
ADMIN_VERB(intercom_view, R_DEBUG, "Intercom Range Display", "Displays the intercom view as effects (Only use on a test server).", ADMIN_CATEGORY_MAPPING_TESTS)
	if(GLOB.intercom_range_display_status)
		GLOB.intercom_range_display_status = FALSE
	else
		GLOB.intercom_range_display_status = TRUE

	for(var/obj/effect/debugging/marker/M in GLOB.all_debugging_effects)
		qdel(M)

	if(GLOB.intercom_range_display_status)
		for(var/obj/item/radio/intercom/I in GLOB.machines)
			for(var/turf/T in orange(7,I))
				var/obj/effect/debugging/marker/F = new/obj/effect/debugging/marker(T)
				if (!(F in view(7,I.loc)))
					qdel(F)
	feedback_add_details("admin_verb","mIRD") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

// DQEdit — deleted ZAS-only admin debug verbs (testZAScolors / testZAScolors_remove /
// rebootAirMaster) and their /client scratch state. ZAS zones don't exist
// under LINDA; the visualization concepts (zone-adjacency colours, reboot ZAS)
// don't map onto LINDA's excited_groups model. The Air Report verb
// (diagnostics.dm) now reports the LINDA-native stats instead. Port real
// excited-group visualizers here if desired (see /datum/excited_group/proc/
// display_turfs in LINDA_turf_tile.dm — already wired to SSair.display_all_groups).

ADMIN_VERB_VISIBILITY(count_objects_on_z_level, ADMIN_VERB_VISIBLITY_FLAG_LOCALHOST)
ADMIN_VERB(count_objects_on_z_level, R_DEBUG, "Count Objects On Level", "Counts all objects on a Z level (Only use on a test server).", ADMIN_CATEGORY_MAPPING)
	var/level = tgui_input_text(user, "Which z-level?","Level?")
	if(!level)
		return
	var/num_level = text2num(level)
	if(!num_level)
		return
	if(!isnum(num_level))
		return

	var/type_text = tgui_input_text(user, "Which type path?","Path?")
	if(!type_text)
		return
	var/type_path = text2path(type_text)
	if(!type_path)
		return

	var/count = 1

	var/list/atom/atom_list = list()

	for(var/atom/A in world)
		if(istype(A,type_path))
			var/atom/B = A
			while(!(isturf(B.loc)))
				if(B && B.loc)
					B = B.loc
				else
					break
			if(B)
				if(B.z == num_level)
					count++
					atom_list += A
	/*
	var/atom/temp_atom
	for(var/i = 0; i <= (atom_list.len/10); i++)
		var/line = ""
		for(var/j = 1; j <= 10; j++)
			if(i*10+j <= atom_list.len)
				temp_atom = atom_list[i*10+j]
				line += " no.[i+10+j]@\[[temp_atom.x], [temp_atom.y], [temp_atom.z]\]; "
		to_chat(world, line)*/

	to_chat(world, "There are [count] objects of type [type_path] on z-level [num_level]")
	feedback_add_details("admin_verb","mOBJZ") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_VISIBILITY(count_objects_all, ADMIN_VERB_VISIBLITY_FLAG_LOCALHOST)
ADMIN_VERB(count_objects_all, R_DEBUG, "Count Objects All", "Count all objects by type (Only use on a test server).", ADMIN_CATEGORY_MAPPING)
	var/type_text = tgui_input_text(user, "Which type path?","")
	if(!type_text)
		return
	var/type_path = text2path(type_text)
	if(!type_path)
		return

	var/count = 0

	for(var/atom/A in world)
		if(istype(A,type_path))
			count++
	/*
	var/atom/temp_atom
	for(var/i = 0; i <= (atom_list.len/10); i++)
		var/line = ""
		for(var/j = 1; j <= 10; j++)
			if(i*10+j <= atom_list.len)
				temp_atom = atom_list[i*10+j]
				line += " no.[i+10+j]@\[[temp_atom.x], [temp_atom.y], [temp_atom.z]\]; "
		to_chat(world, line)*/

	to_chat(world, "There are [count] objects of type [type_path] in the game world")
	feedback_add_details("admin_verb","mOBJ") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(enable_mapping_verbs, R_DEBUG, "Enable Mapping Verbs", "Enable all mapping verbs.", ADMIN_CATEGORY_MAPPING)
	SSadmin_verbs.update_visibility_flag(user, ADMIN_VERB_VISIBLITY_FLAG_MAPPING_DEBUG, TRUE)
	feedback_add_details("admin_verb","mapDB")

ADMIN_VERB_VISIBILITY(disable_mapping_verbs, ADMIN_VERB_VISIBLITY_FLAG_MAPPING_DEBUG)
ADMIN_VERB(disable_mapping_verbs, R_DEBUG, "Disable Mapping Verbs", "Disable all mapping verbs.", ADMIN_CATEGORY_MAPPING)
	SSadmin_verbs.update_visibility_flag(user, ADMIN_VERB_VISIBLITY_FLAG_MAPPING_DEBUG, FALSE)
