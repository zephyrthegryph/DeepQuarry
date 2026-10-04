// These pins can only contain a 1 character string or null.
/datum/integrated_io/char
	name = "char pin"

/datum/prompt/text/typed_pin_char
	var/original_client_ckey

/datum/integrated_io/char/ask_for_pin_data(mob/user)
	var/original_client_ckey
	if(istype(user, /client))
		var/client/C = user
		original_client_ckey = C.ckey
		user = C.mob
	if(!ismob(user) || QDELETED(user))
		return
	open_request(src, /datum/prompt/text/typed_pin_char, PROC_REF(pin_input_entered), answerer = user, original_client_ckey = original_client_ckey, timeout = 0, question = "Please type in one character.", title = "[src] char writing", encode = FALSE, max_len = MAX_MESSAGE_LEN, name_text = FALSE, multiline = FALSE)

/datum/integrated_io/char/proc/pin_input_entered(datum/act/request/A)
	if(!A.answer)
		return
	apply_pin_input(A)
	SStgui.update_uis(src)

/datum/integrated_io/char/proc/apply_pin_input(datum/act/request/A)
	var/datum/prompt/text/typed_pin_char/request = A.request
	var/mob/user = request.original_client_ckey ? GLOB.directory[request.original_client_ckey] : request.answerer
	if(!user)
		return
	var/new_data = sanitizeSafe(A.answer.answer_value, 1, 0, 0)
	if(holder().check_interactivity(user) )
		to_chat(user, span_notice("You input [new_data ? "new_data" : "NULL"] into the pin."))
		write_data_to_pin(new_data)

/datum/integrated_io/char/write_data_to_pin(new_data)
	if(isnull(new_data) || (istext(new_data) && !ic_is_ref(new_data)))
		if(length(new_data) > 1)
			return
		data = new_data
		holder().on_data_written()

// This makes the text go from "A" to "%".
/datum/integrated_io/char/scramble()
	if(!is_valid())
		return
	var/list/options = list("!","@","#","$","%","^","&","*") + GLOB.alphabet_upper
	data = pick(options)
	push_data()

/datum/integrated_io/char/display_pin_type()
	return IC_FORMAT_CHAR
