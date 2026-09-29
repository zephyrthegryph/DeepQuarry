//Dance pole
/obj/structure/dancepole
	name = "dance pole"
	desc = "Engineered for your entertainment"
	icon = 'icons/obj/objects_vr.dmi'
	icon_state = "dancepole"
	density = FALSE
	anchored = TRUE

/obj/structure/dancepole/screwdriver_act(mob/user, obj/item/O)
	set_anchored(!anchored)
	playsound(src, O.usesound, 50, 1)
	to_chat(user, span_blue("You [anchored ? "secure" : "unsecure"] \the [src]."))
	return TRUE

/obj/structure/dancepole/wrench_act(mob/user, obj/item/O)
	use_tool(user, O, src, delay = 3 SECONDS, quality = TOOL_WRENCH, volume = 50, message_self = "Now disassembling \the [src]...", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return TRUE

/obj/structure/dancepole/proc/wrench_act_tool_done(mob/user)
	to_chat(user, span_notice("You disassembled \the [src]!"))
	replace_with(src, /obj/item/stack/material/steel, 1)
