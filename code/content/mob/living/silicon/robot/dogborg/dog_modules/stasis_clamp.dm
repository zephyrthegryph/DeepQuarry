/obj/item/dogborg/stasis_clamp
	name = "stasis clamp"
	desc = "A magnetic clamp which can halt the flow of gas in a pipe, via a localised stasis field."
	icon = 'icons/atmos/clamp.dmi'
	icon_state = "pclamp0"

/// Projects a /obj/machinery/clamp onto a simple pipe, or takes one back off (its on_destroy reopens the pipe).
/obj/item/dogborg/stasis_clamp/afterattack(atom/A, mob/user as mob, proximity)
	if(!proximity)
		return

	if(istype(A, /obj/machinery/clamp))
		to_chat(user, span_notice("You dissipate \the [A]."))
		dissolved(A, user)
		return

	if(!istype(A, /obj/machinery/atmospherics/pipe/simple))
		return
	if(locate_within(get_turf(A), /obj/machinery/clamp))
		to_chat(user, span_warning("A clamp is already attached to the pipe there!"))
		return
	new /obj/machinery/clamp(A.loc, A)
	to_chat(user, span_notice("You attach a stasis clamp to \the [A]."))
