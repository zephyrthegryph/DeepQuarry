/obj/item/integrated_circuit/input/colorpad
	name = "color pad"
	desc = "This small color pad allows someone to input a hexadecimal color into the system."
	icon_state = "colorpad"
	complexity = 2
	can_be_asked_input = 1
	inputs = list()
	outputs = list("color entered" = IC_PINTYPE_COLOR)
	activators = list("on entered" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	power_draw_per_use = 4

/obj/item/integrated_circuit/input/colorpad/ask_for_input(mob/user)
	open_request(src, /datum/prompt/color/circuit, PROC_REF(color_entered), answerer = user, title = "Color pad", question = "Enter a color, please.", default = get_pin_data(IC_OUTPUT, 1))

/obj/item/integrated_circuit/input/colorpad/proc/color_entered(datum/act/request/A)
	if(!A.answer)
		return
	set_pin_data(IC_OUTPUT, 1, A.answer.value)
	push_data()
	activate_pin(1)
