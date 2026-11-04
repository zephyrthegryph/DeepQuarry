/**
 * Possible 'state' options for change_state(state) are:
 * panel_open: The panel is opened
 * panel_closed: The panel is closed
 */
// neotheology cloning biocan from Eris
/obj/structure/prop/machine/nt_biocan
	icon = 'icons/obj/props/decor.dmi'
	icon_state = "nt_biocan"

/// The look: the open panel.
/obj/structure/prop/machine/nt_biocan/draw(datum/look/look)
	..()
	look.overlay("nt_biocan_panel", when = panel_shown)

/obj/structure/prop/machine/nt_biocan/change_state(state)
	. = ..()
	switch(state)
		if("panel_open")
			set_panel_shown(TRUE)
		if("panel_closed")
			set_panel_shown(FALSE)
