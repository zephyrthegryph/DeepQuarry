// These pins can only contain numbers (int and floating point) or null.
/datum/integrated_io/number
	name = "number pin"
//	data = 0

/datum/integrated_io/number/ask_for_pin_data(mob/user)
	var/new_data = rerun_prompt(user, "k7", list("kind" = "number", "message" = "Please type in a number.", "title" = "[src] number writing"), PROC_REF(ask_for_pin_data), args)
	if(isnull(new_data))
		return
	if(isnum(new_data) && holder().check_interactivity(user) )
		to_chat(user, span_notice("You input [new_data] into the pin."))
		write_data_to_pin(new_data)

/datum/integrated_io/number/write_data_to_pin(new_data)
	if(isnull(new_data) || isnum(new_data))
		data = new_data
		holder().on_data_written()

/datum/integrated_io/number/display_pin_type()
	return IC_FORMAT_NUMBER
