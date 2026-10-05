// These pins can only contain text and null.
/datum/integrated_io/string
	name = "string pin"

/datum/prompt/text/typed_pin_string
	var/original_client_ckey

/datum/integrated_io/string/ask_for_pin_data(mob/user)
	var/original_client_ckey
	if(istype(user, /client))
		var/client/C = user
		original_client_ckey = C.ckey
		user = C.mob
	if(!ismob(user) || QDELETED(user))
		return
	open_request(src, /datum/prompt/text/typed_pin_string, PROC_REF(pin_input_entered), answerer = user, original_client_ckey = original_client_ckey, timeout = 0, question = "Please type in a string.", title = "[src] string writing", encode = FALSE, max_len = MAX_MESSAGE_LEN, name_text = FALSE, multiline = FALSE)

/datum/integrated_io/string/proc/pin_input_entered(datum/act/request/A)
	if(!A.answer)
		return
	apply_pin_input(A)
	SStgui.update_uis(src)

/datum/integrated_io/string/proc/apply_pin_input(datum/act/request/A)
	var/datum/prompt/text/typed_pin_string/request = A.request
	var/mob/user = request.original_client_ckey ? GLOB.directory[request.original_client_ckey] : request.answerer
	if(!user)
		return
	var/new_data = A.answer.value
	new_data = sanitizeSafe(new_data, MAX_MESSAGE_LEN, 0, 0)

	if(new_data && holder().check_interactivity(user) )
		to_chat(user, span_notice("You input [new_data ? "new_data" : "NULL"] into the pin."))
		write_data_to_pin(new_data)

/datum/integrated_io/string/write_data_to_pin(new_data)
	new_data = sanitizeSafe(new_data, MAX_MESSAGE_LEN, 0, 0)
	if(isnull(new_data) || (istext(new_data) && !ic_is_ref(new_data)))
		data = new_data
		holder().on_data_written()

// This makes the text go "from this" to "#G&*!HD$%L"
/datum/integrated_io/string/scramble()
	if(!is_valid())
		return
	var/string_length = length(data)
	var/list/options = list("!","@","#","$","%","^","&","*") + GLOB.alphabet_upper
	var/new_data = ""
	while(string_length)
		new_data += pick(options)
		string_length--
	push_data()

/datum/integrated_io/string/display_pin_type()
	return IC_FORMAT_STRING
