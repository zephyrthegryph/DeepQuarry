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
	playsound(src, sounds_of(O).use, 50, 1)
	to_chat(user, span_blue("You [anchored ? "secure" : "unsecure"] \the [src]."))
	return OP_OK

CAPABILITIES(/obj/structure/dancepole)
	op("use_wrench", tool(TOOL_WRENCH), starts(PROC_REF(wrench_started)), begins(PROC_REF(wrench_begins)), wait(3 SECONDS), then(PROC_REF(wrench_act_tool_done)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))

/obj/structure/dancepole/proc/wrench_started(datum/act/op/A)
	playsound(src, sounds_of(A.held).use, 50, TRUE)

/obj/structure/dancepole/proc/wrench_begins(datum/act/op/A)
	return msg_text("Now disassembling \the [src]...", null)

/obj/structure/dancepole/proc/wrench_act_tool_done(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You disassembled \the [src]!"))
	replace_with(src, /obj/item/stack/material/steel, 1)
