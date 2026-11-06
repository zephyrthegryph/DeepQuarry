/**
 * Possible 'state' options for change_state(state) are:
 * idle: The default look
 * active: Glowy lights underneath
 * panel_open: Opened panel (wiring)
 * panel_closed: Closed panel
 */
// neotheology optable from Eris
/obj/structure/prop/machine/nt_optable
	icon_state = "nt_optable-idle"

/// The look: the open panel.
/obj/structure/prop/machine/nt_optable/draw(datum/look/look)
	..()
	look.overlay("nt_optable_panel", when = panel_shown)

/obj/structure/prop/machine/nt_optable/change_state(state)
	. = ..()
	switch(state)
		if("idle")
			set_icon_state("nt_optable-idle")
		if("active")
			set_icon_state("nt_optable-active")
		if("panel_open")
			set_panel_shown(TRUE)
		if("panel_closed")
			set_panel_shown(FALSE)

/obj/structure/prop/machine/nt_optable/starts_active
	icon_state = "nt_optable-active"
