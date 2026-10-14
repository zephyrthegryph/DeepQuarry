/// Rebuilds the pin list var `io_var` (a spec list of names/types) into owned pin datums.
/obj/item/integrated_circuit/proc/setup_io(io_var, io_type, list/io_default_list)
	var/list/io_list = vars[io_var]
	var/list/io_list_copy = io_list ? io_list.Copy() : list()
	io_list?.Cut()
	var/i = 1

	for(var/io_entry in io_list_copy)
		var/default_data = null
		var/io_type_override = null
		// Override the default data.
		if(io_default_list && io_default_list.len) // List containing special pin types that need to be added.
			default_data = io_default_list["[i]"] // This is deliberately text because the index is a number in text form.
		// Override the pin type.
		if(io_list_copy[io_entry])
			io_type_override = io_list_copy[io_entry]

		if(io_type_override)
			rel_add(src, io_var, new io_type_override(src, io_entry, default_data))
		else
			rel_add(src, io_var, new io_type(src, io_entry, default_data))
		i++

/// Prefix of an IC ref. Pin text is sanitized (html-encoded), so no string a
/// player writes can start with it and forge a reference.
#define IC_REF_PREFIX "<ic-ref "

/// An IC ref: the OM handle of `D` in that wrapper. Null for a deleted datum.
/proc/ic_ref(datum/D)
	var/h = entity_handle(D)
	return h && "[IC_REF_PREFIX][h]>"

/// TRUE if `x` is an IC ref (ic_ref()), whether or not it still resolves.
/proc/ic_is_ref(x)
	return istext(x) && findtext(x, IC_REF_PREFIX, 1, length(IC_REF_PREFIX) + 1)

/// The datum an IC ref names, or null once it has been deleted.
/proc/ic_ref_resolve(x)
	if(!ic_is_ref(x))
		return null
	return resolve_handle(copytext(x, length(IC_REF_PREFIX) + 1, -1))

/obj/item/integrated_circuit/proc/set_pin_data(pin_type, pin_number, datum/new_data)
	if (istype(new_data) && !ic_is_ref(new_data))
		new_data = ic_ref(new_data)
	var/datum/integrated_io/pin = get_pin_ref(pin_type, pin_number)
	return pin.write_data_to_pin(new_data)

/obj/item/integrated_circuit/proc/get_pin_data(pin_type, pin_number)
	var/datum/integrated_io/pin = get_pin_ref(pin_type, pin_number)
	return pin.get_data()

/obj/item/integrated_circuit/proc/get_pin_data_as_type(pin_type, pin_number, as_type)
	var/datum/integrated_io/pin = get_pin_ref(pin_type, pin_number)
	return pin.data_as_type(as_type)

/obj/item/integrated_circuit/proc/activate_pin(pin_number)
	var/datum/integrated_io/activate/A = activators[pin_number]
	// Forward the remaining per-propagation work budget so a chain of activations
	// can't exceed IC_MAX_PULSE_CIRCUITS in a single synchronous pulse.
	A.push_data(ic_work_budget)

/datum/integrated_io/proc/get_data()
	if(isnull(data))
		return
	if(ic_is_ref(data))
		return ic_ref_resolve(data)
	return data

/obj/item/integrated_circuit/proc/get_pin_ref(pin_type, pin_number)
	switch(pin_type)
		if(IC_INPUT)
			if(pin_number > inputs.len)
				return null
			return inputs[pin_number]
		if(IC_OUTPUT)
			if(pin_number > outputs.len)
				return null
			return outputs[pin_number]
		if(IC_ACTIVATOR)
			if(pin_number > activators.len)
				return null
			return activators[pin_number]
	return null
