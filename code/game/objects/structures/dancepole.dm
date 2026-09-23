//Dance pole
/obj/structure/dancepole
	name = "dance pole"
	desc = "Engineered for your entertainment"
	icon = 'icons/obj/objects_vr.dmi'
	icon_state = "dancepole"
	density = FALSE
	anchored = TRUE

/obj/structure/dancepole/screwdriver_act(mob/user, obj/item/O)
	anchored = !anchored
	playsound(src, O.usesound, 50, 1)
	to_chat(user, span_blue("You [anchored ? "secure" : "unsecure"] \the [src]."))
	return TRUE

/obj/structure/dancepole/wrench_act(mob/user, obj/item/O)
	if(use_tool(user, O, src, delay = 3 SECONDS, quality = TOOL_WRENCH, volume = 50,
			message_self = "Now disassembling \the [src]..."))
		to_chat(user, span_notice("You disassembled \the [src]!"))
		new /obj/item/stack/material/steel(loc, 1)
		qdel(src)
	return TRUE
