/obj/machinery/atmospheric_field_generator
	name = "atmospheric retention field generator"
	desc = "A floor-mounted piece of equipment that generates an atmosphere-retaining energy field when powered and activated. Linked to environmental alarm systems and will automatically activate when hazardous conditions are detected.<br><br>Note: prolonged immersion in active atmospheric retention fields may have negative long-term health consequences."
	icon = 'icons/obj/atm_fieldgen.dmi'
	icon_state = "arfg_off"
	anchored = TRUE
	opacity = FALSE
	density = FALSE
	power_channel = ENVIRON	//so they shut off last
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 2500
	integrity_failure = 0.5
	var/ispowered = TRUE
	var/isactive = FALSE
	var/wasactive = FALSE		//controls automatic reboot after power-loss
	var/alwaysactive = FALSE	//for a special subtype


	var/hatch_open = FALSE
	var/wires_intact = TRUE
	var/list/areas_added
	var/field_type = /obj/structure/atmospheric_retention_field
	circuit = /obj/item/circuitboard/arf_generator
TRACKED(/obj/machinery/atmospheric_field_generator, isactive)
TRACKED(/obj/machinery/atmospheric_field_generator, wires_intact)

/obj/machinery/atmospheric_field_generator/impassable
	desc = "An older model of ARF-G that generates an impassable retention field. Works just as well as the modern variety, but is slightly more energy-efficient.<br><br>Note: prolonged immersion in active atmospheric retention fields may have negative long-term health consequences."
	active_power_usage = 2000
	field_type = /obj/structure/atmospheric_retention_field/impassable

/obj/machinery/atmospheric_field_generator/perma
	name = "static atmospheric retention field generator"
	desc = "A floor-mounted piece of equipment that generates an atmosphere-retaining energy field when powered and activated. This model is designed to always be active, though the field will still drop from loss of power or electromagnetic interference.<br><br>Note: prolonged immersion in active atmospheric retention fields may have negative long-term health consequences."
	alwaysactive = TRUE
	active_power_usage = 2000

/obj/machinery/atmospheric_field_generator/perma/impassable
	active_power_usage = 1500
	field_type = /obj/structure/atmospheric_retention_field/impassable

/obj/machinery/atmospheric_field_generator/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	if(isactive)
		to_chat(user, span_warning("You can't open the ARF-G whilst it's running!"))
		return OP_OK
	to_chat(user, span_notice("You [hatch_open ? "close" : "open"] \the [src]'s access hatch."))
	hatch_open = !hatch_open
	changed(src)
	if(alwaysactive && wires_intact)
		generate_field()
	return OP_OK

/obj/machinery/atmospheric_field_generator/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!hatch_open)
		return OP_OK
	to_chat(user, span_notice("You toggle \the [src]'s activation behavior to [alwaysactive ? "emergency" : "always-on"]."))
	alwaysactive = !alwaysactive
	return OP_OK

/obj/machinery/atmospheric_field_generator/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!hatch_open)
		return OP_OK
	to_chat(user, span_warning("You [wires_intact ? "cut" : "mend"] \the [src]'s wires!"))
	set_wires_intact(!wires_intact)
	return OP_OK

/obj/machinery/atmospheric_field_generator/proc/welder_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!hatch_open)
		return OP_DECLINE
	use_tool(user, tool, src, delay = 1.5 SECONDS, quality = TOOL_WELDER, amount = 5, volume = 50, start_self = "You start to disassemble \the [src].", start_others = "[user] starts to disassemble \the [src].", receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user))
	return OP_OK

/obj/machinery/atmospheric_field_generator/proc/welder_act_tool_done(mob/user)
	to_chat(user, span_notice("You fully disassemble \the [src]. There were no salvageable parts."))
	destroyed(src, user, "deconstructed")

/obj/machinery/atmospheric_field_generator/perma/Initialize(mapload)
	. = ..()
	generate_field()

/obj/machinery/atmospheric_field_generator/proc/appearance_state()
	if(broken_now())
		return "broken"
	if(hatch_open)
		return wires_intact ? "open_wires" : "open_wirescut"
	return isactive ? "on" : "off"

/// The look (the draw sweep: from its template).
/obj/machinery/atmospheric_field_generator/draw(datum/look/look)
	..()
	look.state("arfg_[appearance_state()]")

/obj/machinery/atmospheric_field_generator/power_change()
	. = ..()
	if(operable())
		ispowered = TRUE
		if(alwaysactive || wasactive)	//reboot our field if we were on or are supposed to be always-on
			generate_field()
	if(. && isactive && (!operable()))
		ispowered = FALSE
		disable_field()

CAPABILITIES(/obj/machinery/atmospheric_field_generator)
	emp_disable(7.5 SECONDS)
	on_change(STAT_OPERABLE, ANY, then(PROC_REF(emp_state_changed)))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(field_generator_blast))))
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(crowbar_used)))
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(multitool_used)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wirecutter_used)))
	op("use_welder", tool(TOOL_WELDER), priority(OP_PRIORITY_DEFAULT), wait(0), costs(RES_FUEL, 0), then(PROC_REF(welder_used)))

/// A pulse took it down (the field drops) or its outage ended (the field comes back if it was on, or is always on).
/obj/machinery/atmospheric_field_generator/proc/emp_state_changed(datum/act/A)
	if(emp_disabled(src))
		disable_field() //shutting dowwwwwwn
	else if(alwaysactive || wasactive) //reboot after a short delay if we were online before
		generate_field()

/// A light blast knocks the field generator out like a pulse.
/obj/machinery/atmospheric_field_generator/proc/field_generator_blast(datum/act/hit/explosion/A)
	var/datum/damage_packet/packet = A.packet
	if(packet.severity == 3)
		emp_act(3)
	return HOOK_DECLINE

/obj/machinery/atmospheric_field_generator/atom_break(damage_flag)
	. = ..()
	if(!.)
		return
	visible_message("The ARF-G cracks and shatters!", "You hear an uncomfortable metallic crunch.")
	disable_field()

/obj/machinery/atmospheric_field_generator/proc/generate_field()
	if(!ispowered || hatch_open || !wires_intact || isactive) //if it's not powered, the hatch is open, the wires are busted, or it's already on, don't do anything
		return
	else
		set_isactive(TRUE)
		icon_state = "arfg_on"
		new field_type (src.loc)
		src.visible_message(span_warning("The ARF-G crackles to life!"),span_warning("You hear an ARF-G coming online!"))
		set_use_power(USE_POWER_ACTIVE)
	return

/obj/machinery/atmospheric_field_generator/proc/disable_field()
	if(isactive)
		if(alwaysactive == TRUE && operable()) //If we're not damaged, don't turn off if we're always on.
			return
		else
			icon_state = "arfg_off"
			for(var/obj/structure/atmospheric_retention_field/F in contents_of(loc))
				spent(F)
			src.visible_message("The ARF-G shuts down with a low hum.","You hear an ARF-G powering down.")
			set_use_power(USE_POWER_IDLE)
			set_isactive(FALSE)
	return

/obj/machinery/atmospheric_field_generator/Initialize(mapload)
	. = ..()
	//Delete ourselves if we find extra mapped in arfgs
	for(var/obj/machinery/atmospheric_field_generator/F in contents_of(loc))
		if(F != src)
			log_mapping("Duplicate ARFGS at [x],[y],[z]")
			return INITIALIZE_HINT_QDEL

	var/area/A = get_area(src)
	ASSERT(istype(A))

	LAZYADD(A.all_arfgs, src)
	areas_added = list(A)

	for(var/direction in GLOB.cardinal)
		A = get_area(get_step(src,direction))
		if(istype(A) && !(A in areas_added))
			LAZYADD(A.all_arfgs, src)
			areas_added += A

/obj/structure/atmospheric_retention_field
	resistance_flags = BOMB_PROOF
	name = "atmospheric retention field"
	desc = "A shimmering forcefield that keeps the good air inside and the bad air outside. This field has been modulated so that it doesn't impede movement or projectiles.<br><br>Note: prolonged immersion in active atmospheric retention fields may have negative long-term health consequences."
	icon = 'icons/obj/atm_fieldgen.dmi'
	icon_state = "arfg_field"
	anchored = TRUE
	density = FALSE
	opacity = 0
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	can_atmos_pass = ATMOS_PASS_NO
	var/basestate = "arfg_field"

	light_range = 3
	light_power = 1
	light_color = "#FFFFFF"
	light_on = TRUE
	rad_insulation = RAD_LIGHT_INSULATION

/obj/structure/atmospheric_retention_field/draw(datum/look/look)
	..()
	var/list/dirs = list()
	for(var/obj/structure/atmospheric_retention_field/F in orange(src,1))
		dirs += get_dir(src, F)

	var/list/connections = dirs_to_corner_states(dirs)

	look.state("")
	for(var/i = 1 to 4)
		var/image/I = image(icon, "[basestate][connections[i]]", dir = 1<<(i-1))
		look.overlay(I)

/obj/structure/atmospheric_retention_field/Initialize(mapload)
	. = ..()
	update_nearby_tiles() //Force ZAS update

DESTROY_EFFECTS(/obj/structure/atmospheric_retention_field, new /datum/destroy_effects_data(neighbor_type = /obj/structure/atmospheric_retention_field))

CAPABILITIES(/obj/structure/atmospheric_retention_field)
	smoothing()
	op("hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/structure/atmospheric_retention_field/proc/interaction_hand(datum/act/op/A)
	if(density)
		visible_message("You touch the retention field, and it crackles faintly. Tingly!")
	else
		visible_message("You try to touch the retention field, but pass through it like it isn't even there.")
	return TRUE

/obj/structure/atmospheric_retention_field/impassable
	desc = "A shimmering forcefield that keeps the good air inside and the bad air outside. It seems fairly solid, almost like it's made out of some kind of hardened light.<br><br>Note: prolonged immersion in active atmospheric retention fields may have negative long-term health consequences."
	icon = 'icons/obj/atm_fieldgen.dmi'
	icon_state = "arfg_field"
	density = TRUE

/obj/machinery/atmospheric_field_generator/perma/underdoors
	field_type = /obj/structure/atmospheric_retention_field/underdoors

/obj/structure/atmospheric_retention_field/underdoors
	plane = OBJ_PLANE
	layer = UNDER_JUNK_LAYER

