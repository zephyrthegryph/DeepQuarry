/obj/machinery/computer/looking_glass
	name = "looking glass control"
	desc = "Controls the looking glass displays in this room. Provided courtesy of NT's Advanced Spatial Imaging Division."

	icon_keyboard = "tech_key"
	icon_screen = "holocontrol"

	var/static/list/supported_programs = list()
	var/static/list/secret_programs = list()

	use_power = USE_POWER_IDLE
	active_power_usage = 8000

	var/current_program = "Off"
	var/tmp/my_area_handle
	/// Two-tier gravity toggle throttle: ignore inside the short window, warn inside the long one.
	COOLDOWN_DECLARE(gravity_short_cooldown)
	COOLDOWN_DECLARE(gravity_long_cooldown)
	COOLDOWN_DECLARE(ready)
	var/immersion = FALSE

	var/lg_id = "change_me"

/obj/machinery/computer/looking_glass/Initialize(mapload)
	. = ..()
	for(var/area/looking_glass/lga in world)
		if(lga.lg_id == lg_id)
			my_area_handle = om_handle(lga)
			break
	if(!istype(my_area(), /area/looking_glass))
		log_mapping("Looking glass console [x],[y],[x] not in a looking glass area.")
	if(!supported_programs.len)
		supported_programs["Off"] = null
		supported_programs["Diagnostics"] = image(icon = 'icons/skybox/skybox.dmi', icon_state = "diagnostic")
		supported_programs["Space 1"] = image(icon = 'icons/skybox/skybox.dmi', icon_state = "space1")
		supported_programs["Space 2"] = image(icon = 'icons/skybox/skybox.dmi', icon_state = "space2")
		supported_programs["Space 3"] = image(icon = 'icons/skybox/skybox.dmi', icon_state = "space3")
		supported_programs["Space 4"] = image(icon = 'icons/skybox/skybox.dmi', icon_state = "space4")
		supported_programs["Space 5"] = image(icon = 'icons/skybox/skybox.dmi', icon_state = "space5")
		supported_programs["Space 6"] = image(icon = 'icons/skybox/skybox.dmi', icon_state = "space6")

		secret_programs["Maw"] = image(icon = 'icons/skybox/skybox_vr.dmi', icon_state = "maw")
		secret_programs["Flesh"] = image(icon = 'icons/skybox/skybox_vr.dmi', icon_state = "flesh")
		secret_programs["Synth Int"] = image(icon = 'icons/skybox/skybox_vr.dmi', icon_state = "synthinsides")
		secret_programs["Synth Int 2"] = image(icon = 'icons/skybox/skybox_vr.dmi', icon_state = "synthinsides_active")
		secret_programs["Two Teshari"] = image(icon = 'icons/skybox/skybox_vr.dmi', icon_state = "doubletesh")
		secret_programs["Teshari 1"] = image(icon = 'icons/skybox/skybox_vr.dmi', icon_state = "sca")
		secret_programs["Teshari 2"] = image(icon = 'icons/skybox/skybox_vr.dmi', icon_state = "eis")

/obj/machinery/computer/looking_glass/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/open_ui,
	)
	..()

DECLARE_UI(/obj/machinery/computer/looking_glass, "LookingGlass")

UI_DATA(/obj/machinery/computer/looking_glass, "currentProgram=current_program:text", "immersion:num", "merge:ui_data_obj_machinery_computer_looking_glass{supportedPrograms:list,gravity:num}")

/// The computed part of /obj/machinery/computer/looking_glass's window data (declared on its UI_DATA row).
/obj/machinery/computer/looking_glass/proc/ui_data_obj_machinery_computer_looking_glass(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/list/program_list = list()
	for(var/P in supported_programs)
		program_list.Add(P)

	if(emagged)
		for(var/P in secret_programs)
			program_list.Add(P)

	data["supportedPrograms"] = program_list
	if(my_area()?.get_gravity())
		data["gravity"] = 1
	else
		data["gravity"] = 0

	return data

UI_ACT(/obj/machinery/computer/looking_glass, "program", ui_act_program, UI_ARG_TEXT("program"))
UI_ACT_PROC(/obj/machinery/computer/looking_glass, ui_act_program)
	if(COOLDOWN_FINISHED(src, ready))
		var/prog = params["program"]
		if(prog == "Off")
			current_program = "Off"
			unload_program()
		else if((prog in supported_programs) || (emagged && (prog in secret_programs)))
			current_program = prog
			load_program(prog)
	else
		visible_message(span_warning("ERROR. Recalibrating displays."))
	return TRUE

UI_ACT(/obj/machinery/computer/looking_glass, "gravity", ui_act_gravity)
UI_ACT_PROC(/obj/machinery/computer/looking_glass, ui_act_gravity)
	toggle_gravity(my_area())
	return TRUE

UI_ACT(/obj/machinery/computer/looking_glass, "immersion", ui_act_immersion)
UI_ACT_PROC(/obj/machinery/computer/looking_glass, ui_act_immersion)
	immersion = !immersion
	my_area()?.toggle_optional(immersion)
	return TRUE

/obj/machinery/computer/looking_glass/emag_act(remaining_charges, mob/user as mob)
	if (!emagged)
		play_sfx(src, SFX_EFFECTS_SPARKS4)
		set_emagged(1)
		to_chat(user, span_notice("You unlock several programs that were hidden somewhere in memory."))
		log_game("[key_name(user)] emagged the [name]")
		return 1
	return

/obj/machinery/computer/looking_glass/proc/load_program(prog_name)
	COOLDOWN_START(src, ready, 10 SECONDS)

	if(prog_name in supported_programs)
		my_area()?.begin_program(supported_programs[prog_name])
	else if(prog_name in secret_programs)
		my_area()?.begin_program(secret_programs[prog_name])

/obj/machinery/computer/looking_glass/proc/unload_program()
	COOLDOWN_START(src, ready, 10 SECONDS)

	my_area()?.end_program()

/obj/machinery/computer/looking_glass/proc/toggle_gravity(area/A)
	if(COOLDOWN_TIMELEFT(src, gravity_long_cooldown))
		if(COOLDOWN_TIMELEFT(src, gravity_short_cooldown))
			return
		visible_message(span_warning("ERROR. Recalibrating gravity field."))
		return

	COOLDOWN_START(src, gravity_short_cooldown, 1 SECOND)
	COOLDOWN_START(src, gravity_long_cooldown, 3 SECONDS)

	if(A.get_gravity())
		A.gravitychange(0)
	else
		A.gravitychange(1)

//This could all be done better, but it works for now.
// the looking glass unloads its program.
/obj/machinery/computer/looking_glass/on_destroy(force)
	unload_program()
	..()

/obj/machinery/computer/looking_glass/ex_act(severity)
	unload_program()
	..()

/obj/machinery/computer/looking_glass/power_change()
	. = ..()
	if (. && (has_stat(NOPOWER)))
		unload_program()

/// LC-refs: the my_area this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/computer/looking_glass/proc/my_area() as /area/looking_glass
	return om_resolve(my_area_handle)
