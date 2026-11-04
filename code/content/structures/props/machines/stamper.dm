/**
 * Possible 'state' options for change_state(state) are:
 * off: Not doing much
 * on: Stamping mysterious substances
 */
// sheetizer from /tg/
/obj/structure/prop/machine/stamper
	icon = 'icons/obj/props/decor.dmi'
	icon_state = "stamper"
	/// Stamping mysterious substances (change_state "on").
	var/stamper_running = FALSE

/// The look: the running stamper's processing lights.
/obj/structure/prop/machine/stamper/draw(datum/look/look)
	..()
	look.overlay("stamper_proc", when = stamper_running)
	look.overlay("stamper_but", when = stamper_running)

/obj/structure/prop/machine/stamper/change_state(state)
	. = ..()
	switch(state)
		if("off")
			set_stamper_running(FALSE)
		if("on")
			set_stamper_running(TRUE)

/obj/structure/prop/machine/stamper/starts_on
	icon_state = "stamper_on"

/obj/structure/prop/machine/stamper/starts_on/draw(datum/look/look)
	..()
	look.overlay("stamper_proc", when = isnull(state)) // until a state is set, then the base draw takes over
	look.overlay("stamper_but")
