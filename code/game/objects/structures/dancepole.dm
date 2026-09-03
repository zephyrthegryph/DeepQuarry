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
	playsound(src, O.usesound, 50, 1)
	to_chat(user, span_notice("Now disassembling \the [src]..."))
	if(do_after(user, 3 SECONDS * O.toolspeed, target = src))
		to_chat(user, span_notice("You disassembled \the [src]!"))
		new /obj/item/stack/material/steel(loc, 1)
		qdel(src)
	return TRUE
