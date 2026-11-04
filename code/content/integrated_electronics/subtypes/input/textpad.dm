/obj/item/integrated_circuit/input/textpad
	name = "text pad"
	desc = "This small text pad allows someone to input a string into the system."
	icon_state = "textpad"
	complexity = 1
	can_be_asked_input = 1
	inputs = list()
	outputs = list("string entered" = IC_PINTYPE_STRING)
	activators = list("on entered" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	power_draw_per_use = 4

/obj/item/integrated_circuit/input/textpad/ask_for_input(mob/user)
	var/original_client_ckey
	if(istype(user, /client))
		var/client/C = user
		original_client_ckey = C.ckey
		user = C.mob
	if(!ismob(user) || QDELETED(user))
		return
	open_request(src, /datum/prompt/text/circuit_textpad, PROC_REF(input_entered), answerer = user, original_client_ckey = original_client_ckey, question = "Enter some words, please.", title = "Text pad", default = get_pin_data(IC_OUTPUT, 1), timeout = 0, max_len = MAX_KEYPAD_INPUT_LEN, name_text = FALSE, encode = FALSE, multiline = FALSE)

/obj/item/integrated_circuit/input/textpad/proc/input_entered(datum/act/request/A)
	if(!A.answer)
		return
	apply_input(A)
	SStgui.update_uis(src)

/obj/item/integrated_circuit/input/textpad/proc/apply_input(datum/act/request/A)
	var/datum/prompt/text/circuit_textpad/request = A.request
	var/mob/user = request.original_client_ckey ? GLOB.directory[request.original_client_ckey] : request.answerer
	if(!user)
		return
	var/new_input = sanitizeSafe(A.answer.value, MAX_KEYPAD_INPUT_LEN, 0, 0)
	if(istext(new_input) && CanInteract(user, GLOB.tgui_physical_state))
		set_pin_data(IC_OUTPUT, 1, new_input)
		push_data()
		activate_pin(1)
