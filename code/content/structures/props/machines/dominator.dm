/**
 * Possible 'state' options for change_state(state) are:
 * blue, red, orange, yellow, green, purple: Set that color
 * damaged: add damage overlay
 * undamaged: remove damage overlay
 * broken: become damaged
 * plain: undamaged white version, otherwise use a color
 */
// dominator console from /tg/
/obj/structure/prop/dominator
	icon = 'icons/obj/props/decor.dmi'
	icon_state = "dominator"
	/// The damage overlay is shown.
	var/dominator_damaged = FALSE

/// The look: the damage overlay.
/obj/structure/prop/dominator/draw(datum/look/look)
	..()
	look.overlay("dom_damage", when = dominator_damaged)

/obj/structure/prop/dominator/change_state(state)
	. = ..()
	switch(state)
		if("blue")
			set_icon_state("dominator-blue")
		if("red")
			set_icon_state("dominator-red")
		if("orange")
			set_icon_state("dominator-orange")
		if("yellow")
			set_icon_state("dominator-yellow")
		if("green")
			set_icon_state("dominator-green")
		if("purple")
			set_icon_state("dominator-purple")
		if("damaged")
			set_dominator_damaged(TRUE)
		if("undamaged")
			set_dominator_damaged(FALSE)
		if("broken")
			set_icon_state("dominator-broken")
		if("plain")
			set_icon_state("dominator")

/obj/structure/prop/dominator/blue
	icon_state = "dominator-blue"

/obj/structure/prop/dominator/red
	icon_state = "dominator-red"

/obj/structure/prop/dominator/orange
	icon_state = "dominator-orange"

/obj/structure/prop/dominator/yellow
	icon_state = "dominator-yellow"

/obj/structure/prop/dominator/green
	icon_state = "dominator-green"

/obj/structure/prop/dominator/purple
	icon_state = "dominator-purple"
