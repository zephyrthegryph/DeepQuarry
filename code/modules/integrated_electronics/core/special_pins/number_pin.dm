// These pins can only contain numbers (int and floating point) or null.
/datum/integrated_io/number
	name = "number pin"

/datum/prompt/number/typed_pin_number
	var/original_client_ckey

/datum/prompt/number/typed_pin_number/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, !isnull(step), GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/integrated_io/number/ask_for_pin_data(mob/user)
	var/original_client_ckey
	if(istype(user, /client))
		var/client/C = user
		original_client_ckey = C.ckey
		user = C.mob
	if(!ismob(user) || QDELETED(user))
		return
	open_request(src, /datum/prompt/number/typed_pin_number, PROC_REF(pin_input_entered), answerer = user, original_client_ckey = original_client_ckey, timeout = 0, question = "Please type in a number.", title = "[src] number writing", min_value = 0, max_value = INFINITY, step = 1)

/datum/integrated_io/number/proc/pin_input_entered(datum/act/request/A)
	if(!A.answer)
		return
	apply_pin_input(A)
	SStgui.update_uis(src)

/datum/integrated_io/number/proc/apply_pin_input(datum/act/request/A)
	var/datum/prompt/number/typed_pin_number/request = A.request
	var/mob/user = request.original_client_ckey ? GLOB.directory[request.original_client_ckey] : request.answerer
	if(!user)
		return
	var/new_data = A.answer.answer_value
	if(isnum(new_data) && holder().check_interactivity(user) )
		to_chat(user, span_notice("You input [new_data] into the pin."))
		write_data_to_pin(new_data)

/datum/integrated_io/number/write_data_to_pin(new_data)
	if(isnull(new_data) || isnum(new_data))
		data = new_data
		holder().on_data_written()

/datum/integrated_io/number/display_pin_type()
	return IC_FORMAT_NUMBER
