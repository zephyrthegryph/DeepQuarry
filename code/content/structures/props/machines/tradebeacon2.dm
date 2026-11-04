/**
 * Possible 'state' options for change_state(state) are:
 * idle: The default look
 * active: Glowy lights in the center
 * panel_open: Opened panel (wiring)
 * panel_closed: Closed panel
 */
// another trade beacon from Eris
/obj/structure/prop/machine/tradebeacon2
	icon_state = "tradebeacon"

/// The look: the open panel.
/obj/structure/prop/machine/tradebeacon2/draw(datum/look/look)
	..()
	look.overlay("tradebeacon_sending_panel", when = panel_shown)

/obj/structure/prop/machine/tradebeacon2/change_state(state)
	. = ..()
	switch(state)
		if("idle")
			set_icon_state("tradebeacon_sending")
		if("active")
			set_icon_state("tradebeacon_sending_active")
		if("panel_open")
			set_panel_shown(TRUE)
		if("panel_closed")
			set_panel_shown(FALSE)

/obj/structure/prop/machine/tradebeacon2/starts_active
	icon_state = "tradebeacon_sending_active"
