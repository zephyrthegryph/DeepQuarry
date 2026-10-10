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
	active = 0
	dir = 1
	var/strength_upper_limit = 2
	var/interface_control = 1
	/// The accelerator parts found by part_scan() (relation list).
	var/list/obj/structure/particle_accelerator/connected_parts
	var/assembled = 0
	var/parts = null

TRACKED(/obj/machinery/particle_accelerator/control_box, interface_control)

/obj/machinery/particle_accelerator/control_box/Initialize(mapload)
	. = ..()
	update_active_power_usage(initial(active_power_usage) * (strength + 1))

// a running accelerator powers down.
/obj/machinery/particle_accelerator/control_box/on_destroy(force)
	if(active)
		toggle_power()
	..()

/obj/machinery/particle_accelerator/control_box/update_state()
	if(pa_stage() < 3)
		set_use_power(USE_POWER_OFF)
		assembled = 0
		set_active(0)
		for(var/obj/structure/particle_accelerator/part in connected_parts)
			part.strength = null
			part.powered = 0
		rel_clear(src, nameof(connected_parts))
		return
	if(!part_scan())
		set_use_power(USE_POWER_IDLE)
		set_active(0)
		rel_clear(src, nameof(connected_parts))

/// The control box's sprite: running strength, powered (assembled or not), or construction stage.
/obj/machinery/particle_accelerator/control_box/draw(datum/look/look)
	..()
	if(active)
		look.state("[reference]p[strength]")
	else if(use_power)
		look.state(assembled ? "[reference]p" : "u[reference]p")
	else
		switch(pa_stage())
			if(0, 1)
				look.state("[reference]")
			if(2)
				look.state("[reference]w")
			else
				look.state("[reference]c")

/obj/machinery/particle_accelerator/control_box/proc/strength_change()
	for(var/obj/structure/particle_accelerator/part in connected_parts)
		part.strength = strength

/obj/machinery/particle_accelerator/control_box/proc/add_strength(mob/user, s)
	if(assembled)
		strength++
		if(strength > strength_upper_limit)
			strength = strength_upper_limit
		else
			message_admins("PA Control Computer increased to [strength] by [key_name(user, user?.client)][ADMIN_QUE(user)] in [ADMIN_COORDJMP(src)]")
			log_game("PACCEL([x],[y],[z]) [key_name(user)] increased to [strength]")
			investigate_log("increased to " + span_red("[strength]") + " by [user?.key]","singulo")
		strength_change()

/obj/machinery/particle_accelerator/control_box/proc/remove_strength(mob/user, s)
	if(assembled)
		strength--
		if(strength < 0)
			strength = 0
		else
			message_admins("PA Control Computer decreased to [strength] by [key_name(user, user?.client)][ADMIN_QUE(user)] in [ADMIN_COORDJMP(src)]")
			log_game("PACCEL([x],[y],[z]) [key_name(user)] decreased to [strength]")
			investigate_log("decreased to " + span_green("[strength]") + " by [user?.key]","singulo")
		strength_change()

/obj/machinery/particle_accelerator/control_box/power_change()
	. = ..()
	if(power_lost())
		set_active(0)
		set_use_power(USE_POWER_OFF)
	else if(!has_condition() && pa_stage() == 3)
		set_use_power(USE_POWER_IDLE)

/// Emits every machine service interval while it runs (its every()); off, it does nothing.
/obj/machinery/particle_accelerator/control_box/proc/emit_step(datum/act/timer/A)
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

	rel_clear(src, nameof(connected_parts))
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
		rel_add(src, nameof(connected_parts), PA)
		return 1
	return 0

/obj/machinery/particle_accelerator/control_box/proc/toggle_power(mob/user)
	set_active(!active)
	investigate_log("turned [active? span_red("ON") : span_green("OFF")] by [user ? user.key : "outside forces"]","singulo")
	message_admins("PA Control Computer turned [active ?"ON":"OFF"] by [user ? key_name(user, user.client) : "outside forces"][ADMIN_QUE(user)] in [ADMIN_COORDJMP(src)]")

	log_game("PACCEL([x],[y],[z]) [user ? key_name(user, user.client) : "outside forces"] turned [active?"ON":"OFF"].")
	if(active)
		set_use_power(USE_POWER_ACTIVE)
		for(var/obj/structure/particle_accelerator/part in connected_parts)
			part.strength = src.strength
			part.powered = 1
	else
		set_use_power(USE_POWER_IDLE)
		for(var/obj/structure/particle_accelerator/part in connected_parts)
			part.strength = null
			part.powered = 0
	return 1

/// Its window answers only when it is built and its interface wire is whole.
/obj/machinery/particle_accelerator/control_box/proc/interface_works(datum/act/A)
	return (interface_control && pa_stage() == 3) ? null : MSG(pa_control/timed_out)

/obj/machinery/particle_accelerator/control_box/proc/is_built(datum/act/A)
	return pa_stage() == 3

/obj/machinery/particle_accelerator/control_box/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["assembled"] = assembled
	data["strength"] = strength
	data["power"] = active
	return data

/obj/machinery/particle_accelerator/control_box/proc/ui_act_power(datum/act/op/A)
	var/mob/user = A.actor
	if(wire_is_cut(src, WIRE_POWER))
		return
	toggle_power(user)
	. = TRUE

/obj/machinery/particle_accelerator/control_box/proc/ui_act_scan(datum/act/op/A)
	part_scan()
	. = TRUE

/obj/machinery/particle_accelerator/control_box/proc/ui_act_add_strength(datum/act/op/A)
	var/mob/user = A.actor
	if(wire_is_cut(src, WIRE_PARTICLE_STRENGTH))
		return
	add_strength(user)
	. = TRUE

/obj/machinery/particle_accelerator/control_box/proc/ui_act_remove_strength(datum/act/op/A)
	var/mob/user = A.actor
	if(wire_is_cut(src, WIRE_PARTICLE_STRENGTH))
		return
	remove_strength(user)
	. = TRUE

/obj/machinery/particle_accelerator/control_box/pre_mapped
	assembled = TRUE

CAPABILITIES(/obj/machinery/particle_accelerator/control_box/pre_mapped)
	configure(construction_graph(start = STAGE_PA_CLOSED, via = list(STAGE_PA_BOLTED, STAGE_PA_WIRED)))

// ---- the wires ----

MSG_DEF_SELF(pa_control/timed_out, "ERROR: Request timed out. Check wire contacts.")

// The control box (doc/rewrite/final_api.html section 16): built on the accelerator's ladder, its wires are bare at the wired stage (an empty
// hand opens them) and its window works once it is closed and its interface wire is whole. While it runs it makes every emitter of the
// assembled accelerator emit (emit_step(), every machine service interval) at its strength.
CAPABILITIES(/obj/machinery/particle_accelerator/control_box)
	ref_many(nameof(connected_parts), /obj/structure/particle_accelerator)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(emit_step)), when = nameof(active))
	wires(name = "Particle accelerator control", count = 5, tools = FALSE, at = null, by_hand = TRUE, reach = PROC_REF(wires_exposed_now))
	extend("wires.open", when(PROC_REF(wires_exposed_now)))
	on_wire(WIRE_PARTICLE_POWER, cut = PROC_REF(power_wire_cut), pulse = PROC_REF(power_wire_pulsed))
	on_wire(WIRE_PARTICLE_STRENGTH, cut = PROC_REF(strength_wire_cut), pulse = PROC_REF(strength_wire_pulsed))
	on_wire(WIRE_PARTICLE_INTERFACE, cut = PROC_REF(interface_wire_cut), pulse = PROC_REF(interface_wire_pulsed))
	on_wire(WIRE_PARTICLE_POWER_LIMIT, cut = PROC_REF(limit_wire_cut), pulse = PROC_REF(limit_wire_pulsed))
	interface("ParticleAccelerator")
	extend("ui_open", when(PROC_REF(is_built)), needs(req(PROC_REF(interface_works))))
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("add_strength", ui_act("add_strength"), then(PROC_REF(ui_act_add_strength)))
	op("remove_strength", ui_act("remove_strength"), then(PROC_REF(ui_act_remove_strength)))


/// The wires are bare at the wired construction stage.
/obj/machinery/particle_accelerator/control_box/proc/wires_exposed_now(datum/act/A)
	return pa_stage() == 2

/// The power wire cut switches a running accelerator off; mended, a stopped one on.
/obj/machinery/particle_accelerator/control_box/proc/power_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(active == !N.mended)
		toggle_power(N.user)

/obj/machinery/particle_accelerator/control_box/proc/power_wire_pulsed(datum/act/A)
	var/datum/notice/wire_pulsed/N = A
	toggle_power(N.user)

/// The strength wire cut drops the strength by two.
/obj/machinery/particle_accelerator/control_box/proc/strength_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	for(var/i = 1; i < 3; i++)
		remove_strength(N.user)

/obj/machinery/particle_accelerator/control_box/proc/strength_wire_pulsed(datum/act/A)
	var/datum/notice/wire_pulsed/N = A
	add_strength(N.user)

/obj/machinery/particle_accelerator/control_box/proc/interface_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	set_interface_control(N.mended)

/obj/machinery/particle_accelerator/control_box/proc/interface_wire_pulsed(datum/act/A)
	set_interface_control(!interface_control)

/// The limit wire cut lets the strength go to three; mended, back to two (a stronger beam steps down).
/obj/machinery/particle_accelerator/control_box/proc/limit_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	strength_upper_limit = (N.mended ? 2 : 3)
	if(strength_upper_limit < strength)
		remove_strength(N.user)

/obj/machinery/particle_accelerator/control_box/proc/limit_wire_pulsed(datum/act/A)
	visible_message("[icon2html(src, viewers(src))]<b>[src]</b> makes a large whirring noise.")
