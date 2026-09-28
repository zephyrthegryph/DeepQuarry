/obj/item/radio/integrated
	name = "\improper PDA radio module"
	desc = "An electronic radio system."
	icon = 'icons/obj/module.dmi'
	icon_state = "power_mod"
	var/hostpda_handle

	var/list/botlist = null		// list of bots
	// ALLOW(state_ref): baseline when CI was wired (2026-09-26); convert or give a real reason
	var/tmp/active_handle	// the active bot; if null, show bot list
	var/list/botstatus			// the status signal sent by the bot

	var/bot_type				//The type of bot it is.
	var/bot_filter				//Determines which radio filter to use.

	var/control_freq = BOT_FREQ

	on = 0 //Are we currently active??
	var/menu_message = ""

/obj/item/radio/integrated/Initialize(mapload)
	..()
	if(istype(loc?.loc, /obj/item/pda))
		hostpda_handle = om_handle(loc.loc)
	return INITIALIZE_HINT_LATELOAD

/obj/item/radio/integrated/LateInitialize()
	if(bot_filter)
		add_to_radio(bot_filter)

/obj/item/radio/integrated/proc/post_signal(freq, key, value, key2, value2, key3, value3, s_filter)

	var/datum/radio_frequency/frequency = GLOB.radio_service.return_frequency(freq)

	if(!frequency)
		return

	var/datum/signal/signal = new()
	signal.source_handle = om_handle(src)
	signal.transmission_method = TRANSMISSION_RADIO
	signal.data[key] = value
	if(key2)
		signal.data[key2] = value2
	if(key3)
		signal.data[key3] = value3

	frequency.post_signal(src, signal, radio_filter = s_filter)

/obj/item/radio/integrated/Topic(href, href_list)
	..()
	switch(href_list["op"])
		if("control")
			active_handle = om_handle(locate(href_list["bot"]))
			post_signal(control_freq, "command", "bot_status", "active", active(), s_filter = bot_filter)

		if("scanbots")		// find all bots
			botlist = null
			post_signal(control_freq, "command", "bot_status", s_filter = bot_filter)

		if("botlist")
			active_handle = null

		if("stop", "go", "home")
			post_signal(control_freq, "command", href_list["op"], "active", active(), s_filter = bot_filter)
			post_signal(control_freq, "command", "bot_status", "active", active(), s_filter = bot_filter)

		if("summon")
			post_signal(control_freq, "command", "summon", "active", active(), "target", get_turf(hostpda()), "useraccess", hostpda().GetAccess(), "user", usr, s_filter = bot_filter)
			post_signal(control_freq, "command", "bot_status", "active", active(), s_filter = bot_filter)

/obj/item/radio/integrated/receive_signal(datum/signal/signal)
	if(bot_type && isbot(signal.source()) && signal.data["type"] == bot_type)
		if(!botlist)
			botlist = new()

		botlist |= signal.source()

		if(active() == signal.source())
			var/list/b = signal.data
			botstatus = b.Copy()

/obj/item/radio/integrated/proc/add_to_radio(bot_filter) //Master filter control for bots. Must be placed in the bot's local Initialize(mapload) to support map spawned bots.
	if(GLOB.radio_service)
		GLOB.radio_service.add_object(src, control_freq, radio_filter = bot_filter)

/*
 *	Radio Cartridge, essentially a signaler.
 */
/obj/item/radio/integrated/signal
	frequency = RSD_FREQ
	var/code = 30.0

/obj/item/radio/integrated/signal/Initialize(mapload)
	. = ..()
	// Just the data; on_materialize() (C5) registers it with GLOB.radio_service.
	if(src.frequency < PUBLIC_LOW_FREQ || src.frequency > PUBLIC_HIGH_FREQ)
		src.frequency = sanitize_frequency(src.frequency)

/obj/item/radio/integrated/signal/set_frequency(new_frequency)
	GLOB.radio_service.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection_handle = om_handle(GLOB.radio_service.add_object(src, frequency))

/obj/item/radio/integrated/signal/proc/send_signal(message="ACTIVATE")
	if(!COOLDOWN_FINISHED(src, transmission_cooldown))
		return
	COOLDOWN_START(src, transmission_cooldown, 0.5 SECONDS)

	var/time = time2text(world.realtime,"hh:mm:ss")
	var/turf/T = get_turf(src)
	GLOB.lastsignalers.Add("[time] <B>:</B> [usr.key] used [src] @ location ([T.x],[T.y],[T.z]) <B>:</B> [format_frequency(frequency)]/[code]")

	var/datum/signal/signal = new
	signal.source_handle = om_handle(src)
	signal.encryption = code
	signal.data["message"] = message

	radio_connection().post_signal(src, signal)

/// LC-refs: the hostpda this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/radio/integrated/proc/hostpda() as /obj/item/pda
	return om_resolve(hostpda_handle)

/// LC-refs: the active bot; if null, show bot list -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/radio/integrated/proc/active() as /mob/living/bot
	return om_resolve(active_handle)
