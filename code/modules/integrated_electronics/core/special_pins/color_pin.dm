// These pins can only contain a color (in the form of #FFFFFF) or null.
/datum/integrated_io/color
	name = "color pin"

/datum/integrated_io/color/ask_for_pin_data(mob/user)
	open_request(src, /datum/prompt/color/circuit, PROC_REF(color_chosen), answerer = user, title = "[src] color writing", question = "Please select a color.", default = data ? data : "#000000", subject = holder())

/// A colour typed into a circuit (subject). Re-checked on the answer: the circuit can still be
/// worked by hand (tgui physical state).
/datum/prompt/color/circuit
	usable_state = "physical"
	timeout = 0

/datum/integrated_io/color/proc/color_chosen(datum/act/request/A)
	if(!A.answer)
		return
	to_chat(A.request.answerer, span_notice("You input a <font color='[A.answer.answer_value]'>new color</font> into the pin."))
	write_data_to_pin(A.answer.answer_value)

/datum/integrated_io/color/write_data_to_pin(new_data)
	// Since this is storing the color as a string hex color code, we need to make sure it's actually one.
	if(isnull(new_data) || (istext(new_data) && !ic_is_ref(new_data)))
		if(istext(new_data))
			new_data = uppertext(new_data)
			if(length(new_data) != 7)						// We can hex if we want to, we can leave your strings behind
				return 										// Cause your strings don't hex and if they don't hex
			var/friends = copytext(new_data, 2, 8)			// Well they're are no strings of mine
			// I say, we can go where we want to, a place where they will never find
			var/safety_dance = 1
			while(safety_dance <= 6)									// And we can act like we come from out of this world.log
				var/hex = copytext(friends, safety_dance, safety_dance+1)
				if(!(hex in list("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F")))
					return									// Leave the fake one far behind,
				safety_dance++

		data = new_data										// And we can hex
		holder().on_data_written()

// This randomizes the color.
/datum/integrated_io/color/scramble()
	if(!is_valid())
		return
	var/new_data = get_random_colour(simple = FALSE, lower = 0, upper = 255)
	data = new_data
	push_data()

/datum/integrated_io/color/display_pin_type()
	return IC_FORMAT_COLOR

/datum/integrated_io/color/display_data(input)
	if(!isnull(data))
		return "(<font color='[data]'>[data]</font>)"
	return ..()
