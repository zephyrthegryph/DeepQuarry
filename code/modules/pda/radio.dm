/obj/item/radio/integrated
	name = "\improper PDA radio module"
	desc = "An electronic radio system."
	icon = 'icons/obj/module.dmi'
	icon_state = "power_mod"
	var/obj/item/pda/hostpda

	var/list/botlist = null		// bots that answered (a relation list)
	var/tmp/mob/living/bot/active	// the active bot (a relation view); if null, show bot list
	var/list/botstatus			// the status signal sent by the bot

	var/bot_type				//The type of bot it is.
	var/bot_filter				//Determines which radio filter to use.

	var/control_freq = BOT_FREQ

	on = 0 //Are we currently active??
	var/menu_message = ""

/obj/item/radio/integrated/Initialize(mapload)
	..()
	if(istype(loc?.loc, /obj/item/pda))
		rel_set(src, nameof(hostpda), loc.loc)
	return INITIALIZE_HINT_LATELOAD

/obj/item/radio/integrated/LateInitialize()
	if(bot_filter)
		add_to_radio(bot_filter)

/obj/item/radio/integrated/proc/post_signal(freq, key, value, key2, value2, key3, value3, s_filter)

	var/datum/radio_frequency/frequency = SSradio.return_frequency(freq)

	if(!frequency)
		return

	var/datum/signal/signal = new()
	rel_set(signal, nameof(signal.source), src)
	signal.transmission_method = TRANSMISSION_RADIO
	signal.data[key] = value
	if(key2)
		signal.data[key2] = value2
	if(key3)
		signal.data[key3] = value3

	frequency.post_signal(src, signal, radio_filter = s_filter)


/obj/item/radio/integrated/receive_signal(datum/signal/signal)
	if(bot_type && isbot(signal.source()) && signal.data["type"] == bot_type)
		rel_add(src, nameof(botlist), signal.source())

		if(active() == signal.source())
			var/list/b = signal.data
			botstatus = b.Copy()

/obj/item/radio/integrated/proc/add_to_radio(bot_filter) //Master filter control for bots. Must be placed in the bot's local Initialize(mapload) to support map spawned bots.
	if(SSradio)
		SSradio.add_object(src, control_freq, radio_filter = bot_filter)

/*
 *	Radio Cartridge, essentially a signaler.
 */
/obj/item/radio/integrated/signal
	frequency = RSD_FREQ
	var/code = 30.0

/obj/item/radio/integrated/signal/Initialize(mapload)
	. = ..()
	// Just the data; on_materialize() (C5) registers it with SSradio.
	if(src.frequency < PUBLIC_LOW_FREQ || src.frequency > PUBLIC_HIGH_FREQ)
		src.frequency = sanitize_frequency(src.frequency)

/obj/item/radio/integrated/signal/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency))

/obj/item/radio/integrated/signal/proc/send_signal(message="ACTIVATE", mob/user)
	if(!COOLDOWN_FINISHED(src, transmission_cooldown))
		return
	COOLDOWN_START(src, transmission_cooldown, 0.5 SECONDS)

	var/time = time2text(world.realtime,"hh:mm:ss")
	var/turf/T = get_turf(src)
	GLOB.lastsignalers.Add("[time] <B>:</B> [user?.key] used [src] @ location ([T.x],[T.y],[T.z]) <B>:</B> [format_frequency(frequency)]/[code]")

	var/datum/signal/signal = new
	rel_set(signal, nameof(signal.source), src)
	signal.encryption = code
	signal.data["message"] = message

	radio_connection().post_signal(src, signal)

/// The hostpda this refers to (a relation view: null once that is deleted).
/obj/item/radio/integrated/proc/hostpda() as /obj/item/pda
	return hostpda

/// The active bot; if null, show bot list (a relation view: null once that is deleted).
/obj/item/radio/integrated/proc/active() as /mob/living/bot
	return active
