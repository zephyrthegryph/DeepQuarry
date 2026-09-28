#ifndef T_BOARD
#error T_BOARD macro is not defined but we need it!
#endif

/obj/item/circuitboard/supplycomp
	name = T_BOARD("supply ordering console")
	build_path = /obj/machinery/computer/supplycomp
	var/contraband_enabled = 0

/obj/item/circuitboard/supplycomp/control
	name = T_BOARD("supply ordering console")
	build_path = /obj/machinery/computer/supplycomp/control

/obj/item/circuitboard/supplycomp/construct(obj/machinery/computer/supplycomp/SC)
	if (..(SC))
		SC.can_order_contraband = contraband_enabled

/obj/item/circuitboard/supplycomp/atom_deconstruct(disassembled = TRUE, obj/machinery/computer/supplycomp/SC)
	if (..(SC))
		contraband_enabled = SC.can_order_contraband

/obj/item/circuitboard/supplycomp/attackby(obj/item/I as obj, mob/user as mob)
	if(I.has_tool_quality(TOOL_MULTITOOL))
		var/catastasis = src.contraband_enabled
		var/opposite_catastasis
		if(catastasis)
			opposite_catastasis = "STANDARD"
			catastasis = "BROAD"
		else
			opposite_catastasis = "BROAD"
			catastasis = "STANDARD"

		om_ask(user, /datum/om/prompt/confirm, PROC_REF(spectrum_chosen), title = "Multitool-Circuitboard interface", message = "Current receiver spectrum is set to: [catastasis]", yes_text = "Switch to [opposite_catastasis]", no_text = "Cancel", ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)
	return

/obj/item/circuitboard/supplycomp/proc/spectrum_chosen(datum/om/prompt/confirm/ask)
	if(ask.yes)
		src.contraband_enabled = !src.contraband_enabled
