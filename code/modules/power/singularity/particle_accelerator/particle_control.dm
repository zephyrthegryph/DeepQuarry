//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:33

/obj/machinery/particle_accelerator/control_box
	name = "Particle Accelerator Control Computer"
	desc = "This controls the density of the particles."
	icon = 'icons/obj/machines/particle_accelerator_vr.dmi'
	icon_state = "control_box"
	reference = "control_box"
	anchored = FALSE
	density = TRUE
	use_power = USE_POWER_OFF
	idle_power_usage = 500
	active_power_usage = 70000 //70 kW per unit of strength
	construction_state = 0
	active = 0
	dir = 1
	var/strength_upper_limit = 2
	var/interface_control = 1
	/// The accelerator parts found by part_scan() (relation list).
	var/list/obj/structure/particle_accelerator/connected_parts
	var/assembled = 0
	var/parts = null

/obj/machinery/particle_accelerator/control_box/Initialize(mapload)
	. = ..()
	set_wires(new /datum/wires/particle_acc/control_box(src))
	update_active_power_usage(initial(active_power_usage) * (strength + 1))

// a running accelerator powers down.
/obj/machinery/particle_accelerator/control_box/on_destroy(force)
	if(active)
		toggle_power()
	..()

/obj/machinery/particle_accelerator/control_box/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/particle_control_use,
	)
	..()

/// Old attack_hand: never called ..().
/datum/interaction/machine_hand/ungated/particle_control_use
	id = "particle_control_use"
	name = "Use"
	effect = /obj/machinery/particle_accelerator/control_box/proc/interaction_use

/obj/machinery/particle_accelerator/control_box/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(construction_state >= 3)
		tgui_interact(user)
	else if(construction_state == 2) // Wires exposed
		wires.Interact(user)
	return TRUE

/obj/machinery/particle_accelerator/control_box/update_state()
	if(construction_state < 3)
		set_use_power(USE_POWER_OFF)
		assembled = 0
		set_active(0)
		for(var/obj/structure/particle_accelerator/part in connected_parts)
			part.strength = null
			part.powered = 0
			part.update_icon()
		rel_clear(src, "connected_parts")
		return
	if(!part_scan())
		set_use_power(USE_POWER_IDLE)
		set_active(0)
		rel_clear(src, "connected_parts")

APPEARANCE_TEMPLATE(/obj/machinery/particle_accelerator/control_box, "{appearance_state}")

/// The icon_state for the control box: running strength, powered (assembled or not), or construction stage.
/obj/machinery/particle_accelerator/control_box/proc/appearance_state()
	if(active)
		return "[reference]p[strength]"
	if(use_power)
		return assembled ? "[reference]p" : "u[reference]p"
	switch(construction_state)
		if(0, 1)
			return "[reference]"
		if(2)
			return "[reference]w"
	return "[reference]c"

/obj/machinery/particle_accelerator/control_box/proc/strength_change()
	for(var/obj/structure/particle_accelerator/part in connected_parts)
		part.strength = strength
		part.update_icon()

/obj/machinery/particle_accelerator/control_box/proc/add_strength(mob/user, s)
	if(assembled)
		strength++
		if(strength > strength_upper_limit)
			strength = strength_upper_limit
		else
			message_admins("PA Control Computer increased to [strength] by [key_name(user, user.client)][ADMIN_QUE(user)] in [ADMIN_COORDJMP(src)]")
			log_game("PACCEL([x],[y],[z]) [key_name(user)] increased to [strength]")
			investigate_log("increased to " + span_red("[strength]") + " by [user.key]","singulo")
		strength_change()

/obj/machinery/particle_accelerator/control_box/proc/remove_strength(mob/user, s)
	if(assembled)
		strength--
		if(strength < 0)
			strength = 0
		else
			message_admins("PA Control Computer decreased to [strength] by [key_name(user, user.client)][ADMIN_QUE(user)] in [ADMIN_COORDJMP(src)]")
			log_game("PACCEL([x],[y],[z]) [key_name(user)] decreased to [strength]")
			investigate_log("decreased to " + span_green("[strength]") + " by [user.key]","singulo")
		strength_change()

/obj/machinery/particle_accelerator/control_box/power_change()
	. = ..()
	if(has_stat(NOPOWER))
		set_active(0)
		set_use_power(USE_POWER_OFF)
	else if(!has_stat(MACHINE_STAT_ANY) && construction_state == 3)
		set_use_power(USE_POWER_IDLE)

/// Emits every machine frame while active; off, it sleeps until toggle_power() turns it on.
/obj/machinery/particle_accelerator/control_box/machine_step()
	if(!active)
		return PROCESS_KILL
	if(src.active)
		//a part is missing!
		if( length(connected_parts) < 6 )
			log_game("PACCEL([x],[y],[z]) Failed due to missing parts.")
			investigate_log("lost a connected part; It " + span_red("powered down") + ".","singulo")
			toggle_power()
			return
		//emit some particles
		for(var/obj/structure/particle_accelerator/particle_emitter/PE in connected_parts)
			if(PE)
				PE.emit_particle(src.strength)

/obj/machinery/particle_accelerator/control_box/proc/part_scan()
	for(var/obj/structure/particle_accelerator/fuel_chamber/F in orange(1,src))
		src.set_dir(F.dir)
		break

	rel_clear(src, "connected_parts")
	assembled = 0
	var/ldir = turn(dir,90)
	var/rdir = turn(dir,-90)
	var/odir = turn(dir,180)
	var/turf/T = src.loc

	T = get_step(T,ldir)
	if(!check_part(T,/obj/structure/particle_accelerator/fuel_chamber))
		return 0

	T = get_step(T,odir)
	if(!check_part(T,/obj/structure/particle_accelerator/end_cap))
		return 0

	T = get_step(T,dir)
	T = get_step(T,dir)
	if(!check_part(T,/obj/structure/particle_accelerator/power_box))
		return 0

	T = get_step(T,dir)
	if(!check_part(T,/obj/structure/particle_accelerator/particle_emitter/center))
		return 0

	T = get_step(T,ldir)
	if(!check_part(T,/obj/structure/particle_accelerator/particle_emitter/left))
		return 0

	T = get_step(T,rdir)
	T = get_step(T,rdir)
	if(!check_part(T,/obj/structure/particle_accelerator/particle_emitter/right))
		return 0

	assembled = 1
	return 1

/obj/machinery/particle_accelerator/control_box/proc/check_part(turf/T, type)
	if(!(T)||!(type))
		return 0

	var/obj/structure/particle_accelerator/PA = locate_on(T, /obj/structure/particle_accelerator)
	if(istype(PA, type) && PA.connect_master(src) && PA.report_ready(src))
		rel_add(src, "connected_parts", PA)
		return 1
	return 0

/obj/machinery/particle_accelerator/control_box/proc/toggle_power(mob/user)
	set_active(!active)
	investigate_log("turned [active? span_red("ON") : span_green("OFF")] by [user ? user.key : "outside forces"]","singulo")
	message_admins("PA Control Computer turned [active ?"ON":"OFF"] by [user ? key_name(user, user.client) : "outside forces"][ADMIN_QUE(user)] in [ADMIN_COORDJMP(src)]")

	log_game("PACCEL([x],[y],[z]) [user ? key_name(user, user.client) : "outside forces"] turned [active?"ON":"OFF"].")
	if(active)
		set_use_power(USE_POWER_ACTIVE)
		MACHINE_WAKE(src)
		for(var/obj/structure/particle_accelerator/part in connected_parts)
			part.strength = src.strength
			part.powered = 1
			part.update_icon()
	else
		set_use_power(USE_POWER_IDLE)
		for(var/obj/structure/particle_accelerator/part in connected_parts)
			part.strength = null
			part.powered = 0
			part.update_icon()
	return 1

/obj/machinery/particle_accelerator/control_box/proc/is_interactive(mob/user)
	if(!interface_control)
		to_chat(user, span_warning("ERROR: Request timed out. Check wire contacts."))
		return FALSE
	if(construction_state != 3)
		return FALSE
	return TRUE

/obj/machinery/particle_accelerator/control_box/tgui_status(mob/user)
	if(is_interactive(user))
		return ..()
	return STATUS_CLOSE

DECLARE_UI(/obj/machinery/particle_accelerator/control_box, "ParticleAccelerator")

UI_DATA_REPLACE(/obj/machinery/particle_accelerator/control_box, "assembled:num", "strength:num", "merge:ui_data_obj_machinery_particle_accelerator_control_box{power:num}")

/// The computed part of /obj/machinery/particle_accelerator/control_box's window data (declared on its UI_DATA row).
/obj/machinery/particle_accelerator/control_box/proc/ui_data_obj_machinery_particle_accelerator_control_box(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["power"] = active
	return data

UI_ACT(/obj/machinery/particle_accelerator/control_box, "power", ui_act_power)
UI_ACT_PROC(/obj/machinery/particle_accelerator/control_box, ui_act_power)
	if(wires.is_cut(WIRE_POWER))
		return
	toggle_power(ui.user)
	. = TRUE
	update_icon()

UI_ACT(/obj/machinery/particle_accelerator/control_box, "scan", ui_act_scan)
UI_ACT_PROC(/obj/machinery/particle_accelerator/control_box, ui_act_scan)
	part_scan()
	. = TRUE
	update_icon()

UI_ACT(/obj/machinery/particle_accelerator/control_box, "add_strength", ui_act_add_strength)
UI_ACT_PROC(/obj/machinery/particle_accelerator/control_box, ui_act_add_strength)
	if(wires.is_cut(WIRE_PARTICLE_STRENGTH))
		return
	add_strength(ui.user)
	. = TRUE
	update_icon()

UI_ACT(/obj/machinery/particle_accelerator/control_box, "remove_strength", ui_act_remove_strength)
UI_ACT_PROC(/obj/machinery/particle_accelerator/control_box, ui_act_remove_strength)
	if(wires.is_cut(WIRE_PARTICLE_STRENGTH))
		return
	remove_strength(ui.user)
	. = TRUE
	update_icon()

/obj/machinery/particle_accelerator/control_box/pre_mapped
	construction_state = 3
	assembled = TRUE

/obj/machinery/particle_accelerator/control_box/pre_mapped/Initialize(mapload)
	. = ..()
	update_icon()

REL_LIST(/obj/machinery/particle_accelerator/control_box, connected_parts)
