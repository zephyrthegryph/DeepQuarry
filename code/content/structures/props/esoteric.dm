/obj/structure/prop/esoteric
	name = "some esoteric thing"
	desc = "Perhaps it's of ritual significance?"
	icon = 'icons/obj/props/decor.dmi'

/obj/structure/prop/esoteric/nt_pedestal0_old
	name = "pedestal"
	desc = "A pedestal with a mysterious slot at its center."
	icon_state = "nt_pedestal0_old"

/obj/structure/prop/esoteric/nt_pedestal1_old
	name = "pedestal"
	desc = "A pedestal with some kind of sword slotted securely in the center."
	icon_state = "nt_pedestal1_old"

// eye of the protector from Eris
/obj/structure/prop/esoteric/eotp
	icon = 'icons/obj/props/decor32x64.dmi'
	icon_state = "eotp"

/**
 * Possible 'state' options for change_state(state) are:
 * off: Looks boring and off
 * on: candles lit and stuff
 * no_cruciform: No cruciform (the little triangle thing) inserted
 * red_cruciform: Red light cruciform inserted
 * green_cruciform: Green light cruciform inserted
 * panel_open: The panel is open (wiring)
 * panel_closed: The panel is closed
 */
// neotheology cruciform reader from Eris
/obj/structure/prop/esoteric/reader
	name = "electronic altar"
	desc = "It looks like you're meant to scan something here."
	icon = 'icons/obj/props/decor.dmi'
	icon_state = "nt_reader_off"
	/// The colour of the cruciform's light, or null with no cruciform inserted.
	var/cruciform_light = null

/// The look: the inserted cruciform's light and the open panel.
/obj/structure/prop/esoteric/reader/draw(datum/look/look)
	..()
	look.overlay("nt_reader_c_[cruciform_light]", when = cruciform_light)
	look.overlay("nt_reader_panel", when = panel_shown)

/obj/structure/prop/esoteric/reader/change_state(state)
	. = ..()
	switch(state)
		if("off")
			set_icon_state("nt_reader_off")
		if("on")
			set_icon_state("nt_reader_on")
		if("no_cruciform")
			set_cruciform_light(null)
		if("red_cruciform")
			set_cruciform_light("red")
		if("green_cruciform")
			set_cruciform_light("green")
		if("panel_open")
			set_panel_shown(TRUE)
		if("panel_closed")
			set_panel_shown(FALSE)
