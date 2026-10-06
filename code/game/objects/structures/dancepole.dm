//Dance pole
/obj/structure/dancepole
	name = "dance pole"
	desc = "Engineered for your entertainment"
	icon = 'icons/obj/objects_vr.dmi'
	icon_state = "dancepole"
	density = FALSE
	anchored = TRUE

/obj/structure/dancepole/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	set_anchored(!anchored)
	playsound(src, O.usesound, 50, 1)
	to_chat(user, span_blue("You [anchored ? "secure" : "unsecure"] \the [src]."))
	return OP_OK

CAPABILITIES(/obj/structure/dancepole)
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))

/obj/structure/dancepole/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	use_tool(user, O, src, delay = 3 SECONDS, quality = TOOL_WRENCH, volume = 50, start_self = "Now disassembling \the [src]...", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return OP_OK

/obj/structure/dancepole/proc/wrench_act_tool_done(mob/user)
	to_chat(user, span_notice("You disassembled \the [src]!"))
	replace_with(src, /obj/item/stack/material/steel, 1)
