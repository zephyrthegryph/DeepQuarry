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
	var/obj/item/integrated_circuit/holder = null
	var/data = null // A reference is an IC ref (ic_ref(), an OM handle in a text wrapper), to reduce typecasts.  Note that oftentimes numbers and text may also occupy this.
	var/list/linked // Lazy: most pins are never wired.
	var/io_type = DATA_CHANNEL

/datum/integrated_io/New(newloc, name, new_data)
	..()
	src.name = name
	if(!isnull(new_data))
		src.data = new_data
	holder = newloc
	if(!istype(holder))
		message_admins("ERROR: An integrated_io ([src.name]) spawned without a valid holder!  This is a bug.")

/datum/integrated_io/Destroy()
	disconnect()
	data = null
	holder = null
	. = ..()

/datum/integrated_io/tgui_host()
	return holder.tgui_host()


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
		holder.on_data_written()

/datum/integrated_io/proc/push_data()
	for(var/datum/integrated_io/io in linked)
		io.write_data_to_pin(data)

/datum/integrated_io/activate/push_data(work_left = IC_MAX_PULSE_CIRCUITS)
	for(var/datum/integrated_io/io in linked)
		io.holder.check_then_do_work(work_left = work_left)

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
				LAZYREMOVE(their_io.linked, src)
			else
				continue
		//Now that we're removed from them, we gotta remove them from us.
		LAZYREMOVE(linked, their_io)

/// Asks `user` for a value (a type, then the value). When they finish, `on_value` is called on this
/// pin as (user, value, P), with `data` readable from P; "null" gives a null value.
/datum/integrated_io/proc/ask_for_data_type(mob/user, default, list/allowed_data_types = list("string","number","null"), on_value, list/data)
	var/list/all_data = data ? data.Copy() : list()
	all_data["default"] = default
	all_data["on_value"] = on_value
	om_prompt_sequence(src, user, list(
		list("key" = "type", "kind" = "list", "message" = "Please choose a type to use.", "title" = "[src] type setting", "choices" = allowed_data_types),
		PROC_REF(ask_for_typed_value),
	), PROC_REF(typed_value_entered), list("data" = all_data))

/datum/integrated_io/proc/ask_for_typed_value(mob/user, datum/om/prompt/P)
	var/default = P.get("default")
	switch(P.get("type"))
		if("string")
			return list("key" = "value", "kind" = "text", "message" = "Now type in a string.", "title" = "[src] string writing", "default" = istext(default) ? default : null, "max_length" = MAX_NAME_LEN, "encode" = FALSE)
		if("number")
			return list("key" = "value", "kind" = "number", "message" = "Now type in a number.", "title" = "[src] number writing", "default" = isnum(default) ? default : 0, "max" = INFINITY, "min" = -INFINITY, "round" = FALSE)
	return null

/datum/integrated_io/proc/typed_value_entered(mob/user, datum/om/prompt/P)
	if(!holder?.check_interactivity(user))
		return
	var/new_data = null
	switch(P.get("type"))
		if("string")
			new_data = sanitizeSafe(P.get("value"), MAX_NAME_LEN, 0, 0)
			if(!istext(new_data))
				return
			to_chat(user, span_notice("You input [new_data] into the pin."))
		if("number")
			new_data = P.get("value")
			if(!isnum(new_data))
				return
			to_chat(user, span_notice("You input [new_data] into the pin."))
		if("null")
			to_chat(user, span_notice("You clear the pin's memory."))
		else
			return
	call(src, P.get("on_value"))(user, new_data, P)

// Basically a null check
/datum/integrated_io/proc/is_valid()
	return !isnull(data)

// This proc asks for the data to write, then writes it.
/datum/integrated_io/proc/ask_for_pin_data(mob/user, obj/item/I)
	ask_for_data_type(user, on_value = PROC_REF(pin_data_chosen))

/datum/integrated_io/proc/pin_data_chosen(mob/user, new_data, datum/om/prompt/P)
	write_data_to_pin(new_data)

/datum/integrated_io/activate/ask_for_pin_data(mob/user) // This just pulses the pin.
	holder.check_then_do_work(ignore_power = TRUE)
	to_chat(user, span_notice("You pulse \the [holder]'s [src] pin."))

/datum/integrated_io/activate
	name = "activation pin"
	io_type = PULSE_CHANNEL

/datum/integrated_io/activate/out // All this does is just make the UI say 'out' instead of 'in'
	data = 1
