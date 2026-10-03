#ifndef T_BOARD
#error T_BOARD macro is not defined but we need it!
#endif

/obj/item/circuitboard/supplycomp
	name = T_BOARD("supply ordering console")
	build_path = /obj/machinery/computer/supplycomp
	var/contraband_enabled = 0

TRACKED(/obj/item/circuitboard/supplycomp, contraband_enabled)

/obj/item/circuitboard/supplycomp/control
	name = T_BOARD("supply ordering console")
	build_path = /obj/machinery/computer/supplycomp/control

/obj/item/circuitboard/supplycomp/construct(obj/machinery/computer/supplycomp/SC)
	if (..(SC))
		SC.can_order_contraband = contraband_enabled

/obj/item/circuitboard/supplycomp/atom_deconstruct(disassembled = TRUE, obj/machinery/computer/supplycomp/SC)
	if (..(SC))
		set_contraband_enabled(SC.can_order_contraband)

CAPABILITIES(/obj/item/circuitboard/supplycomp)
	op("spectrum", tool(TOOL_MULTITOOL), needs(req_adjacent(), req_capable()), label("Configure receiver spectrum"), wait(0),
		asks(/datum/prompt/choice, keeps = 0, fields = list("question" = computed(PROC_REF(spectrum_question)), "title" = "Multitool-Circuitboard interface", "choices" = computed(PROC_REF(spectrum_choices)), "buttons" = TRUE, "timeout" = 0)), then(PROC_REF(spectrum_chosen)), passes())

/obj/item/circuitboard/supplycomp/proc/spectrum_question(datum/act/op/A)
	return "Current receiver spectrum is set to: [contraband_enabled ? "BROAD" : "STANDARD"]"

/obj/item/circuitboard/supplycomp/proc/spectrum_choices(datum/act/op/A)
	return list("Switch to [contraband_enabled ? "STANDARD" : "BROAD"]", "Cancel")

/obj/item/circuitboard/supplycomp/proc/spectrum_chosen(datum/act/op/A)
	var/datum/prompt/choice/R = A.answer
	if(R.value != "Cancel")
		set_contraband_enabled(!contraband_enabled)
	return OP_OK
