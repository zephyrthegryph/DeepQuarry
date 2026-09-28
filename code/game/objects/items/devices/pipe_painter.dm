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

DECLARE_INTERACTIONS(/obj/item/pipe_painter, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/pipe_painter/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	om_prompt(src, user, list("kind" = "list", "message" = "Which colour do you want to use?", "title" = "Pipe painter", "choices" = modes, "requires" = PROMPT_HELD), PROC_REF(mode_chosen))

/obj/item/pipe_painter/proc/mode_chosen(mob/user, new_mode, datum/om/prompt/ask)
	mode = new_mode

/obj/item/pipe_painter/examine(mob/user)
	. = ..()
	. += "It is in [mode] mode."
