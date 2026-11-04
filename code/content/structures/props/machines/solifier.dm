/**
 * Possible 'state' options for change_state(state) are:
 * off: Default, boring
 * on: Pumping or something
 */
// some neotheology thing from Eris
/obj/structure/prop/machine/solifier
	icon_state = "nt_solidifier"

/obj/structure/prop/machine/solifier/change_state(state)
	. = ..()
	switch(state)
		if("off")
			set_icon_state("nt_solidifier")
		if("on")
			set_icon_state("nt_solidifier_on")

/obj/structure/prop/machine/solifier/starts_on
	icon_state = "nt_solidifier_on"
