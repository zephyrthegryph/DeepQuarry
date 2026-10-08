// An area's air device (doc/rewrite/final_api.html section 11, "The library"): a device an air alarm drives over the radio, the vent pump and the
// scrubber. One capability owns what each of them used to repeat:
//
//   - its radio tag (the holder's tracked var `tag_var`; a map gives it, else it is made unique when the device initializes). Its setter is the one
//     place a tag changes, and the capability follows it: the area's entries move to the new tag.
//   - its area: it registers in the area under its tag when it initializes (the area names it: "Bar Vent Pump #3", numbered per kind and never
//     reused) and leaves when it goes.
//   - its radio: on the air alarms' frequency (PUMPS_FREQ) it hears and answers only its own area's alarms; on any other it is an ordinary
//     listener. The tracked var `frequency_var`'s setter is the one place the frequency changes; the capability retunes after it.
//   - its commands: a table of packet keys and the holder procs they run, in the order they apply. A command runs when its key carries a value;
//     the handler is x(value, key). "init" (the name the alarm gives) and "status" (report now) are the capability's own.
//   - its status: the common fields (area, tag, device, power, timestamp) and the holder's own (`status`, a proc returning a list), kept by the area
//     for the alarms' windows and posted to them, 0.2 seconds after a command.
//
//   area_air_device(AREA_AIR_VENT, commands = list("power" = PROC_REF(cmd_power), "direction" = PROC_REF(cmd_direction)), status = PROC_REF(status_fields))
//
// The holder routes its radio to the capability: receive_signal() is area_air_receive(src, signal). Its multitool settings go through the same setters.

CAPABILITY_TYPE(area_air_device, CAP_AREA_AIR_DEVICE, /datum/capability/lib/area_air_device, key = NONE, kind = null, commands = null, status = null, tag_var = "id_tag", frequency_var = "frequency")

/datum/capability/lib/area_air_device
	holder_hooks = HOLDER_HOOK_INIT | HOLDER_HOOK_DESTROY

/datum/capability/lib/area_air_device/cap_data_type()
	return /datum/cap_data/area_air_device

/datum/capability/lib/area_air_device/entries()
	return list(
		on_change(tag_var, ANY, then(CAP_PROC(tag_changed))),
		on_change(frequency_var, ANY, then(CAP_PROC(frequency_changed))))

/// The holder's tag was set: the area's entries move from the tag it was registered under.
/datum/capability/lib/area_air_device/proc/tag_changed(datum/act/A)
	area_air_rekey(A.holder)

/// The holder's frequency was set: it retunes.
/datum/capability/lib/area_air_device/proc/frequency_changed(datum/act/A)
	area_air_tune(A.holder)

/// What a device keeps of its place: the area it registered in and its radio filters.
/datum/cap_data/area_air_device
	/// The area it is registered in. Areas are never deleted.
	var/area/area
	/// The tag it is registered under and the frequency it listens on (what a setter changed it from).
	var/device_tag
	var/frequency
	var/filter_in
	var/filter_out

/datum/capability/lib/area_air_device/on_holder_init(datum/act/eval/A)
	var/obj/machinery/holder = A.holder
	if(!holder.vars[tag_var])
		holder.assign_uid()
		call(holder, "set_[tag_var]")(num2text(holder.uid))
	area_air_join(holder, get_area(holder))
	area_air_tune(holder)

/datum/capability/lib/area_air_device/on_holder_destroy(datum/act/eval/A)
	area_air_leave(A.holder)

/// The device record of `holder`, or null.
/proc/area_air_data(datum/holder)
	RETURN_TYPE(/datum/cap_data/area_air_device)
	var/datum/activation/act = cap_activation(holder, CAP_AREA_AIR_DEVICE, null, TRUE)
	return act ? activation_data(act) : null

/// Registers `holder` in area `A` under its tag; the area names it.
/proc/area_air_join(obj/holder, area/A)
	var/datum/capability/lib/area_air_device/def = cap_of(holder, CAP_AREA_AIR_DEVICE)
	var/datum/cap_data/area_air_device/data = area_air_data(holder)
	if(!def || !data)
		return
	area_air_leave(holder)
	data.area = A
	data.device_tag = holder.vars[def.tag_var]
	if(!A)
		return
	holder.name = A.air_device_register(def.kind, data.device_tag)

/// Takes `holder` out of its area's lists.
/proc/area_air_leave(obj/holder)
	var/datum/capability/lib/area_air_device/def = cap_of(holder, CAP_AREA_AIR_DEVICE)
	var/datum/cap_data/area_air_device/data = area_air_data(holder)
	if(!def || !data?.area)
		return
	data.area.air_device_unregister(def.kind, data.device_tag)
	data.area = null

/// The holder's tag changed (its setter): its area's name and status for it move to the new tag.
/proc/area_air_rekey(obj/holder)
	var/datum/capability/lib/area_air_device/def = cap_of(holder, CAP_AREA_AIR_DEVICE)
	var/datum/cap_data/area_air_device/data = area_air_data(holder)
	if(!def || !data)
		return
	var/new_tag = holder.vars[def.tag_var]
	if(new_tag == data.device_tag)
		return
	data.area?.air_device_rekey(def.kind, data.device_tag, new_tag)
	data.device_tag = new_tag
	area_air_status_soon(holder)

/// Tunes `holder` to the frequency its var holds: on the air alarms' frequency it hears and answers only its own area.
/proc/area_air_tune(obj/holder)
	var/datum/capability/lib/area_air_device/def = cap_of(holder, CAP_AREA_AIR_DEVICE)
	var/datum/cap_data/area_air_device/data = area_air_data(holder)
	if(!def || !data)
		return
	var/frequency = holder.vars[def.frequency_var]
	var/uid = data.area?.air_uid()
	data.filter_in = (frequency == PUMPS_FREQ && uid) ? AIRALARM_AREA_FILTER(RADIO_FROM_AIRALARM, uid) : null
	data.filter_out = (frequency == PUMPS_FREQ && uid) ? AIRALARM_AREA_FILTER(RADIO_TO_AIRALARM, uid) : null
	register_radio(holder, data.frequency, frequency, data.filter_in)
	data.frequency = frequency
	area_air_status_soon(holder)

/// A radio packet reached `holder`: a command addressed to its tag runs the holder's handlers, in the table's order, then the device reports.
/proc/area_air_receive(obj/machinery/holder, datum/signal/signal)
	var/datum/capability/lib/area_air_device/def = cap_of(holder, CAP_AREA_AIR_DEVICE)
	if(!def || !signal || !holder.operable())
		return
	var/list/data = signal.data
	if(!data["tag"] || data["tag"] != holder.vars[def.tag_var] || data["sigtype"] != "command")
		return
	for(var/key in def.commands)
		var/value = data[key]
		if(!isnull(value))
			holder_call(holder, def.commands[key], list(value, key))
	if(!isnull(data["init"]))
		holder.name = data["init"]
		return
	area_air_status_soon(holder)

/// The device reports its status in 0.2 seconds (a burst of commands answers once).
/proc/area_air_status_soon(obj/holder)
	after(holder, 0.2 SECONDS, GLOBAL_PROC_REF(area_air_report), key = "area_air_status", with = list(holder))

/// The device reports its status: the area keeps it for the alarms' windows, and it goes out on the radio.
/proc/area_air_report(obj/machinery/holder)
	var/datum/capability/lib/area_air_device/def = cap_of(holder, CAP_AREA_AIR_DEVICE)
	var/datum/cap_data/area_air_device/data = area_air_data(holder)
	if(QDELETED(holder) || !def || !data)
		return
	var/list/fields = def.status ? holder_call(holder, def.status) : list()
	if(!islist(fields))
		fields = list()
	var/tag = holder.vars[def.tag_var]
	fields["area"] = data.area?.air_uid()
	fields["tag"] = tag
	fields["device"] = def.kind
	fields["power"] = holder.use_power
	fields["timestamp"] = EXPIRY_AT(holder, CLOCK_WORLD, 0)
	fields["sigtype"] = "status"
	data.area?.air_device_report(def.kind, tag, fields)
	var/datum/radio_frequency/radio = SSradio.return_frequency(holder.vars[def.frequency_var])
	if(!radio)
		return
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO
	rel_set(signal, nameof(signal.source), holder)
	signal.data = fields
	radio.post_signal(holder, signal, data.filter_out)

// ---- the area's side ----

/area
	/// The air devices of each kind (AREA_AIR_VENT, AREA_AIR_SCRUBBER) the area knows: tag -> name. Lazy: most areas have none.
	var/list/air_vent_names
	var/list/air_scrub_names
	/// Their last status: tag -> the status packet's fields.
	var/list/air_vent_info
	var/list/air_scrub_info
	/// The last number given to a device of each kind (kind -> number): names are numbered from it and never reused.
	var/list/air_device_serials
	/// The area's key on the air alarms' radio (its filters): made once.
	var/tmp/air_uid_text

/// The area's key on the air alarms' radio.
/area/proc/air_uid()
	if(!air_uid_text)
		air_uid_text = REF(src)
	return air_uid_text

/// What a device of `kind` is called in the area's names ("Vent Pump", "Air Scrubber").
/proc/area_air_kind_label(kind)
	switch(kind)
		if(AREA_AIR_VENT)
			return "Vent Pump"
		if(AREA_AIR_SCRUBBER)
			return "Air Scrubber"
	return "Air Device"

/// The names of the devices of `kind`: tag -> name.
/area/proc/air_device_names(kind)
	return kind == AREA_AIR_SCRUBBER ? air_scrub_names : air_vent_names

/// The last status of the devices of `kind`: tag -> fields.
/area/proc/air_device_info(kind)
	return kind == AREA_AIR_SCRUBBER ? air_scrub_info : air_vent_info

/// Registers the device `tag` of `kind` (once) and returns its name: the next number of its kind.
/area/proc/air_device_register(kind, tag)
	var/known = LAZYACCESS(air_device_names(kind), tag)
	if(known)
		return known
	var/number = LAZYACCESS(air_device_serials, kind) + 1
	LAZYSET(air_device_serials, kind, number)
	var/name = "[src.name] [area_air_kind_label(kind)] #[number]"
	if(kind == AREA_AIR_SCRUBBER)
		LAZYSET(air_scrub_names, tag, name)
	else
		LAZYSET(air_vent_names, tag, name)
	return name

/// Forgets the device `tag` of `kind`.
/area/proc/air_device_unregister(kind, tag)
	if(kind == AREA_AIR_SCRUBBER)
		LAZYREMOVE(air_scrub_names, tag)
		LAZYREMOVE(air_scrub_info, tag)
	else
		LAZYREMOVE(air_vent_names, tag)
		LAZYREMOVE(air_vent_info, tag)

/// The device `old_tag` of `kind` is now `new_tag`: its name moves with it; its status waits for its next report.
/area/proc/air_device_rekey(kind, old_tag, new_tag)
	var/name = LAZYACCESS(air_device_names(kind), old_tag)
	air_device_unregister(kind, old_tag)
	if(!name)
		air_device_register(kind, new_tag)
		return
	if(kind == AREA_AIR_SCRUBBER)
		LAZYSET(air_scrub_names, new_tag, name)
	else
		LAZYSET(air_vent_names, new_tag, name)

/// Keeps the status the device `tag` of `kind` reported.
/area/proc/air_device_report(kind, tag, list/fields)
	if(!LAZYACCESS(air_device_names(kind), tag))
		return
	if(kind == AREA_AIR_SCRUBBER)
		LAZYSET(air_scrub_info, tag, fields)
	else
		LAZYSET(air_vent_info, tag, fields)

/// The area was renamed from `oldtitle` to `title` (the blueprints): the names it keeps for its devices follow.
/area/proc/air_devices_retitled(oldtitle, title)
	for(var/tag in air_vent_names)
		air_vent_names[tag] = replacetext(air_vent_names[tag], oldtitle, title)
	for(var/tag in air_scrub_names)
		air_scrub_names[tag] = replacetext(air_scrub_names[tag], oldtitle, title)
