/obj/item/integrated_circuit/input/numberpad
	name = "number pad"
	desc = "This small number pad allows someone to input a number into the system."
	icon_state = "numberpad"
	complexity = 2
	can_be_asked_input = 1
	inputs = list()
	outputs = list("number entered" = IC_PINTYPE_NUMBER)
	activators = list("on entered" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	power_draw_per_use = 4

/obj/item/integrated_circuit/input/numberpad/ask_for_input(mob/user)
	var/original_client_ckey
	if(istype(user, /client))
		var/client/C = user
		original_client_ckey = C.ckey
		user = C.mob
	if(!ismob(user) || QDELETED(user))
		return
	open_request(src, /datum/prompt/number/circuit_numberpad, PROC_REF(input_entered), answerer = user, original_client_ckey = original_client_ckey, question = "Enter a number, please.", title = "Number pad", default = get_pin_data(IC_OUTPUT, 1), timeout = 0, min_value = 0, max_value = INFINITY, step = 1)

/obj/item/integrated_circuit/input/numberpad/proc/input_entered(datum/act/request/A)
	if(!A.answer)
		return
	apply_input(A)
	SStgui.update_uis(src)

/obj/item/integrated_circuit/input/numberpad/proc/apply_input(datum/act/request/A)
	var/datum/prompt/number/circuit_numberpad/request = A.request
	var/mob/user = request.original_client_ckey ? GLOB.directory[request.original_client_ckey] : request.answerer
	if(!user)
		return
	var/new_input = A.answer.value
	if(isnum(new_input) && CanInteract(user, GLOB.tgui_physical_state))
		set_pin_data(IC_OUTPUT, 1, new_input)
		push_data()
		activate_pin(1)
