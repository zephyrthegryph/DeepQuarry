/obj/item/pipe_painter
	name = "pipe painter"
	desc = "Used to apply a even coat of paint to pipes. Atmospheric usage reccomended."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "labeler1"
	var/list/modes
	var/mode
	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/obj/item/pipe_painter/Initialize(mapload)
	. = ..()
	modes = new()
	for(var/C in GLOB.pipe_colors)
		modes += "[C]"
	mode = pick(modes)

/obj/item/pipe_painter/afterattack(atom/A, mob/user as mob, proximity)
	if(!proximity)
		return

	if(!istype(A,/obj/machinery/atmospherics/pipe) || istype(A,/obj/machinery/atmospherics/pipe/tank) || istype(A,/obj/machinery/atmospherics/pipe/vent) || istype(A,/obj/machinery/atmospherics/pipe/simple/heat_exchanging) || istype(A,/obj/machinery/atmospherics/pipe/simple/insulated) || !in_range(user, A))
		return
	var/obj/machinery/atmospherics/pipe/P = A

	P.change_color(GLOB.pipe_colors[mode])

/obj/item/pipe_painter/get_interactions()
	var/static/list/L = list(INTERACT_USE(null, PROC_REF(interaction_self)))
	return L

/obj/item/pipe_painter/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(mode_chosen), title = "Pipe painter", message = "Which colour do you want to use?", choices = modes, ask_flags = ASK_CARRIED | ASK_CAPABLE)

/obj/item/pipe_painter/proc/mode_chosen(datum/om/prompt/choice/ask)
	mode = ask.choice

/obj/item/pipe_painter/examine(mob/user)
	. = ..()
	. += "It is in [mode] mode."
