/obj/item/dogborg/stasis_clamp
	name = "stasis clamp"
	desc = "A magnetic clamp which can halt the flow of gas in a pipe, via a localised stasis field."
	icon = 'icons/atmos/clamp.dmi'
	icon_state = "pclamp0"
	var/list/clamps

/obj/item/dogborg/stasis_clamp/afterattack(atom/A, mob/user as mob, proximity)
	if(!proximity)
		return

	// /obj/machinery/clamp was a ZAS pipe-clamp tool (clamp.dm in atmoalter),
	// deleted with ZAS atmos machinery. Stasis-clamp tool reduced to a polite
	// no-op until LINDA's atmos machinery is wired in.
	if (istype(A, /obj/machinery/atmospherics/pipe))
		to_chat(user, span_warning("Pipe clamping is unavailable until LINDA's atmos machinery is wired in."))
		return
