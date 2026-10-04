/*
	Pins both hold data for circuits, as well move data between them.  Some also cause circuits to do their function.  DATA_CHANNEL pins are the data holding/moving kind,
where as PULSE_CHANNEL causes circuits to work() when their pulse hits them.

A visualization of how pins work is below.  Imagine the below image involves an addition circuit.
When the bottom pin, the activator, receives a pulse, all the numbers on the left (input) get added, and the answer goes on the right side (output).

Inputs      Outputs

A [2]\      /[8] result
B [1]-\|++|/
C [4]-/|++|
D [1]/  ||
		||
	Activator

*/
/datum/integrated_io
	var/name = "input/output"
	var/tmp/obj/item/integrated_circuit/holder
	var/data = null // A reference is an IC ref (ic_ref(), an OM handle in a text wrapper), to reduce typecasts.  Note that oftentimes numbers and text may also occupy this.
	var/list/linked // Lazy: most pins are never wired.
	var/io_type = DATA_CHANNEL

/datum/integrated_io/New(newloc, name, new_data)
	..()
	src.name = name
	if(!isnull(new_data))
		src.data = new_data
	rel_set(src, nameof(holder), newloc)
	if(!istype(holder(), /obj/item/integrated_circuit))
		message_admins("ERROR: An integrated_io ([src.name]) spawned without a valid holder!  This is a bug.")

// a pin disconnects from its linked pins.
/datum/integrated_io/on_destroy(force)
	disconnect()
	..()

/datum/integrated_io/tgui_host()
	return holder().tgui_host()

/datum/integrated_io/proc/data_as_type(as_type)
	if(!ic_is_ref(data))
		return
	var/w = data
	var/output = ic_ref_resolve(w)
	return istype(output, as_type) ? output : null

/datum/integrated_io/proc/display_data(input)
	if(isnull(input))
		return "(null)" // Empty data means nothing to show.

	if(ic_is_ref(input))
		var/atom/A = ic_ref_resolve(input)
		return A ? "(\ref[A] \[Ref\])" : "(null)"

	if(istext(input))
		return "(\"[input]\")" // Wraps the 'string' in escaped quotes, so that people know it's a 'string'.

/*
list[](
	"A",
	"B",
	"C"
)
*/

	if(islist(input))
		var/list/my_list = input
		var/result = "list\[[my_list.len]\]("
		if(my_list.len)
			result += "<br>"
			var/pos = 0
			for(var/line in my_list)
				result += "[display_data(line)]"
				pos++
				if(pos != my_list.len)
					result += ",<br>"
			result += "<br>"
		result += ")"
		return result

	return "([input])" // Nothing special needed for numbers or other stuff.

/datum/integrated_io/activate/display_data()
	return "(\[pulse\])"

/datum/integrated_io/proc/display_pin_type()
	return IC_FORMAT_ANY

/datum/integrated_io/activate/display_pin_type()
	return IC_FORMAT_PULSE

/datum/integrated_io/proc/scramble()
	if(isnull(data))
		return
	if(isnum(data))
		write_data_to_pin(rand(-10000, 10000))
	if(istext(data) && !ic_is_ref(data))
		write_data_to_pin("ERROR")
	push_data()

/datum/integrated_io/activate/scramble()
	push_data()

/datum/integrated_io/proc/write_data_to_pin(new_data)
	if(isnull(new_data) || isnum(new_data) || istext(new_data) || ic_is_ref(new_data)) // Anything else is a type we don't want.
		if(istext(new_data) && !ic_is_ref(new_data))
			new_data = sanitizeSafe(new_data, MAX_MESSAGE_LEN, 0, 0)
		data = new_data
		holder().on_data_written()

/datum/integrated_io/proc/push_data()
	for(var/datum/integrated_io/io in linked)
		io.write_data_to_pin(data)

/datum/integrated_io/activate/push_data(work_left = IC_MAX_PULSE_CIRCUITS)
	for(var/datum/integrated_io/io in linked)
		io.holder().check_then_do_work(work_left = work_left)

/datum/integrated_io/proc/pull_data()
	for(var/datum/integrated_io/io in linked)
		write_data_to_pin(io.data)

/datum/integrated_io/proc/get_linked_to_desc()
	if(LAZYLEN(linked))
		return "the [english_list(linked)]"
	return "nothing"

/datum/integrated_io/proc/disconnect()
	//First we iterate over everything we are linked to.
	for(var/datum/integrated_io/their_io in linked)
		//While doing that, we iterate them as well, and disconnect ourselves from them.
		for(var/datum/integrated_io/their_linked_io in their_io.linked)
			if(their_linked_io == src)
				rel_remove(their_io, nameof(their_io.linked), src)
			else
				continue
		//Now that we're removed from them, we gotta remove them from us.
		rel_remove(src, nameof(linked), their_io)

/// A pin's type/value questions keep the pin and actor weak while preserving arbitrary defaults.
/datum/pin_value_review
	var/mob/actor
	var/datum/integrated_io/pin
	var/type_name
	var/value
	var/default_scalar
	var/datum/default_entity
	var/default_entity_selected = FALSE
	var/default_client_ckey
	var/default_client_selected = FALSE
	var/on_value

CAPABILITIES(/datum/pin_value_review)
	ref_one(nameof(actor), /mob)
	ref_one(nameof(pin), /datum/integrated_io)
	ref_one(nameof(default_entity), /datum)

/datum/prompt/choice/pin_type
	timeout = 0
	question = "Please choose a type to use."

/datum/prompt/choice/pin_type/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/pin_value_review/review = owner
	return review.why_not()

/datum/prompt/text/pin_value
	timeout = 0
	question = "Now type in a string."
	max_len = MAX_NAME_LEN
	name_text = TRUE
	encode = FALSE

/datum/prompt/text/pin_value/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/pin_value_review/review = owner
	return review.why_not()

/datum/prompt/number/pin_value
	timeout = 0
	question = "Now type in a number."
	max_value = INFINITY
	min_value = -INFINITY

/datum/prompt/number/pin_value/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, !isnull(step), GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/number/pin_value/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/pin_value_review/review = owner
	return review.why_not()

/datum/pin_value_review/proc/capture_default(default)
	if(istype(default, /client))
		var/client/C = default
		default_client_ckey = C.ckey
		default_client_selected = TRUE
	else if(isdatum(default))
		default_entity_selected = TRUE
		rel_set(src, nameof(default_entity), default)
	else
		default_scalar = default

/datum/pin_value_review/proc/default_value()
	if(default_client_selected)
		return GLOB.directory[default_client_ckey]
	return default_entity_selected ? default_entity : default_scalar

/datum/pin_value_review/proc/retire()
	qdel(src) // ALLOW(lifecycle): Finished nonspatial pin edit state has no inventory release contract.

/datum/pin_value_review/proc/why_not()
	if(QDELETED(actor) || QDELETED(pin) || (default_entity_selected && QDELETED(default_entity)))
		return "gone"
	if(default_client_selected && !default_value())
		return "gone"

/datum/pin_value_review/proc/start(list/allowed_data_types)
	if(why_not())
		retire()
		return
	start_step(allowed_data_types)
		retire()

/datum/pin_value_review/proc/start_step(list/allowed_data_types)
	open_request(src, /datum/prompt/choice/pin_type, PROC_REF(type_entered), answerer = actor, asker = actor, title = "[pin] type setting", choices = allowed_data_types)

/datum/pin_value_review/proc/run_step(step, datum/act/request/A)
	if(!A.answer || why_not())
		retire()
		return
	var/datum/result/result = safe_call(step, A)
	if(!result.ok)
		stack_trace("Pin value step [step]: [result.error]")
		retire()

/datum/pin_value_review/proc/type_entered(datum/act/request/A)
	run_step(PROC_REF(type_step), A)

/datum/pin_value_review/proc/type_step(datum/act/request/A)
	type_name = A.answer.answer_value
	var/default = default_value()
	switch(type_name)
		if("string")
			open_request(src, /datum/prompt/text/pin_value, PROC_REF(value_entered), answerer = actor, asker = actor, title = "[pin] string writing", default = istext(default) ? default : null)
			return
		if("number")
			open_request(src, /datum/prompt/number/pin_value, PROC_REF(value_entered), answerer = actor, asker = actor, title = "[pin] number writing", default = isnum(default) ? default : 0)
			return
	pin.typed_value_entered(src)
	retire()

/datum/pin_value_review/proc/value_entered(datum/act/request/A)
	run_step(PROC_REF(value_step), A)

/datum/pin_value_review/proc/value_step(datum/act/request/A)
	value = A.answer.answer_value
	pin.typed_value_entered(src)
	retire()

/// Asks for a type and value; a caller may supply a specialized native review carrying its state.
/datum/integrated_io/proc/ask_for_data_type(mob/user, default, list/allowed_data_types = list("string","number","null"), on_value, datum/pin_value_review/sequence)
	if(istype(user, /client))
		var/client/C = user
		user = C.mob
	var/datum/pin_value_review/review = sequence || new /datum/pin_value_review
	rel_set(review, nameof(review.actor), user)
	rel_set(review, nameof(review.pin), src)
	review.on_value = on_value
	review.capture_default(default)
	review.start(allowed_data_types)

/datum/integrated_io/proc/typed_value_entered(datum/pin_value_review/seq)
	var/mob/user = seq.actor
	if(!holder()?.check_interactivity(user))
		return
	var/new_data = null
	switch(seq.type_name)
		if("string")
			new_data = sanitizeSafe(seq.value, MAX_NAME_LEN, 0, 0)
			if(!istext(new_data))
				return
			to_chat(user, span_notice("You input [new_data] into the pin."))
		if("number")
			new_data = seq.value
			if(!isnum(new_data))
				return
			to_chat(user, span_notice("You input [new_data] into the pin."))
		if("null")
			to_chat(user, span_notice("You clear the pin's memory."))
		else
			return
	call(src, seq.on_value)(user, new_data, seq)

// Basically a null check
/datum/integrated_io/proc/is_valid()
	return !isnull(data)

// This proc asks for the data to write, then writes it.
/datum/integrated_io/proc/ask_for_pin_data(mob/user, obj/item/I)
	ask_for_data_type(user, on_value = PROC_REF(pin_data_chosen))

/datum/integrated_io/proc/pin_data_chosen(mob/user, new_data, datum/pin_value_review/seq)
	write_data_to_pin(new_data)

/datum/integrated_io/activate/ask_for_pin_data(mob/user) // This just pulses the pin.
	holder().check_then_do_work(ignore_power = TRUE)
	to_chat(user, span_notice("You pulse \the [holder()]'s [src] pin."))

/datum/integrated_io/activate
	name = "activation pin"
	io_type = PULSE_CHANNEL

/datum/integrated_io/activate/out // All this does is just make the UI say 'out' instead of 'in'
	data = 1

/// The holder this refers to (a relation view: null once that is deleted).
/datum/integrated_io/proc/holder() as /obj/item/integrated_circuit
	return holder
