/**
 * Possible 'state' options for change_state(state) are:
 * idle: The default look
 * active: Glowy lights in the center
 * panel_open: Opened panel (wiring)
 * panel_closed: Closed panel
 */
// trade beacon from Eris
/obj/structure/prop/machine/tradebeacon
	icon_state = "tradebeacon"

/// The look: the open panel.
/obj/structure/prop/machine/tradebeacon/draw(datum/look/look)
	..()
	look.overlay("tradebeacon_panel", when = panel_shown)

/obj/structure/prop/machine/tradebeacon/change_state(state)
	. = ..()
	switch(state)
		if("idle")
			set_icon_state("tradebeacon")
		if("active")
			set_icon_state("tradebeacon_active")
		if("panel_open")
			set_panel_shown(TRUE)
		if("panel_closed")
			set_panel_shown(FALSE)

/obj/structure/prop/machine/tradebeacon/starts_active
	icon_state = "tradebeacon_active"
