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

		om_prompt(src, user, list("message" = "Current receiver spectrum is set to: [catastasis]", "title" = "Multitool-Circuitboard interface", "choices" = list("Switch to [opposite_catastasis]","Cancel"), "requires" = PROMPT_ADJACENT), PROC_REF(spectrum_chosen))
	return

/obj/item/circuitboard/supplycomp/proc/spectrum_chosen(mob/user, choice, datum/om/prompt/ask)
	if(choice == "Switch to STANDARD" || choice == "Switch to BROAD")
		src.contraband_enabled = !src.contraband_enabled
