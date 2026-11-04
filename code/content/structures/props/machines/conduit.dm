/**
 * Possible 'state' options for change_state(state) are:
 * off: Boring, round
 * on: Spinny glowy
 */
// conduit of soul from Eris
/obj/structure/prop/machine/conduit
	icon_state = "conduit_off"

/obj/structure/prop/machine/conduit/change_state(state)
	. = ..()
	switch(state)
		if("on")
			set_icon_state("conduit_spin")
			flick("conduit_starting", src)
		if("off")
			set_icon_state("conduit_off")
			flick("conduit_stopping", src)

/obj/structure/prop/machine/conduit/starts_on
	icon_state = "conduit_spin"
