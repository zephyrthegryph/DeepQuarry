/obj/item/pipe_painter
	name = "pipe painter"
	desc = "Used to apply a even coat of paint to pipes. Atmospheric usage reccomended."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "labeler1"
	var/list/modes
	var/mode
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

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

CAPABILITIES(/obj/item/pipe_painter)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/obj/item/pipe_painter/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	om_ask(user, /datum/om/prompt/choice, PROC_REF(mode_chosen), title = "Pipe painter", message = "Which colour do you want to use?", choices = modes, ask_flags = ASK_CARRIED | ASK_CAPABLE)

/obj/item/pipe_painter/proc/mode_chosen(datum/om/prompt/choice/ask)
	mode = ask.choice

/obj/item/pipe_painter/examine(mob/user)
	. = ..()
	. += "It is in [mode] mode."
