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
	for(var/C in GLOB.pipe_colors)
		LAZYADD(modes, "[C]")
	set_mode(pick(modes))

TRACKED(/obj/item/pipe_painter, mode)

CAPABILITIES(/obj/item/pipe_painter)
	op("choose_mode", in_hand(), label("Choose paint colour"), needs(carried()),
		asks(/datum/prompt/choice/pipe_painter_mode, fields = list("timeout" = 0), keeps = 0), then(PROC_REF(mode_picked)))
	op("paint", at_target(/obj/machinery/atmospherics/pipe), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Paint pipe"),
		needs(req_adjacent(), req(PROC_REF(paintable_pipe))), then(PROC_REF(pipe_painted)))

/datum/prompt/choice/pipe_painter_mode
	title = "Pipe painter"
	question = "Which colour do you want to use?"

/datum/prompt/choice/pipe_painter_mode/prepare(datum/act/A)
	. = ..()
	if(istype(A, /datum/act/op))
		var/datum/act/op/asking = A
		var/obj/item/pipe_painter/painter = asking.holder // ALLOW(check_grep): the operation holder is the paint device whose colours populate this prompt, not an admin credential
		if(istype(painter))
			choices = painter.modes.Copy()

/obj/item/pipe_painter/proc/mode_picked(datum/act/op/A)
	var/datum/prompt/choice/picked = A.answer
	set_mode(picked.value)
	return OP_OK

/obj/item/pipe_painter/proc/paintable_pipe(datum/act/op/A)
	return (!istype(A.target, /obj/machinery/atmospherics/pipe/tank) && !istype(A.target, /obj/machinery/atmospherics/pipe/vent) && !istype(A.target, /obj/machinery/atmospherics/pipe/simple/heat_exchanging) && !istype(A.target, /obj/machinery/atmospherics/pipe/simple/insulated)) ? null : MSG(op/not_available)

/obj/item/pipe_painter/proc/pipe_painted(datum/act/op/A)
	var/obj/machinery/atmospherics/pipe/P = A.target
	P.change_color(GLOB.pipe_colors[mode])
	return OP_OK

/obj/item/pipe_painter/examine(mob/user)
	. = ..()
	. += "It is in [mode] mode."
