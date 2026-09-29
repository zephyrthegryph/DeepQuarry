MATERIAL_MIX(/obj/item/assembly/signaler, list(MAT_STEEL = 1000, MAT_GLASS = 200))
/obj/item/assembly/signaler
	name = "remote signaling device"
	desc = "Used to remotely activate devices.  Tap against another secured signaler to transfer configuration."
	icon_state = "signaller"
	item_state = "signaler"
	wires_type = WIRE_RECEIVE | WIRE_PULSE | WIRE_RADIO_PULSE | WIRE_RADIO_RECEIVE

	secured = TRUE

	var/code = 30
	var/frequency = RSD_FREQ
	var/delay = 0
	var/airlock_wire = null
	var/tmp/connected_handle
	var/tmp/radio_connection_handle
	var/deadman = FALSE

/obj/item/assembly/signaler/Initialize(mapload)
	. = ..()
	set_frequency(frequency)

/obj/item/assembly/signaler/activate()
	if(!COOLDOWN_FINISHED(src, next_activate))
		return FALSE
	signal()
	return TRUE

DECLARE_APPEARANCE_PROC(/obj/item/assembly/signaler, PROC_REF(appearance_overlays), list())
/obj/item/assembly/signaler/appearance_overlays()
	. = list()
	if(holder())
		holder().update_icon()

/obj/item/assembly/signaler/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Signaler", name)
		ui.open()

/obj/item/assembly/signaler/tgui_data(mob/user)
	var/list/data = list()
	data["frequency"] = frequency
	data["code"] = code
	data["minFrequency"] = RADIO_LOW_FREQ
	data["maxFrequency"] = RADIO_HIGH_FREQ
	return data

/obj/item/assembly/signaler/tgui_act(action, params)
	if(..())
		return TRUE

	switch(action)
		if("signal")
			signal()
			. = TRUE
		if("freq")
			frequency = unformat_frequency(params["freq"])
			frequency = sanitize_frequency(frequency, RADIO_LOW_FREQ, RADIO_HIGH_FREQ)
			set_frequency(frequency)
			. = TRUE
		if("code")
			code = text2num(params["code"])
			code = clamp(round(code), 1, 100)
			. = TRUE
		if("reset")
			if(params["reset"] == "freq")
				set_frequency(initial(frequency))
			else
				code = initial(code)
			. = TRUE

	update_icon()

/// A subtype adding to an ancestor's compact specs uses declare_interactions() (the proven
/// chain, ..() and all) and builds its own entry directly with dq_interaction_from_spec() -
/// see doc/rewrite/interactions.md §5a for why get_interactions() itself doesn't chain here.
/obj/item/assembly/signaler/declare_interactions(list/into)
	into += dq_interaction_from_spec(type, INTERACT_ITEM("Transfer", PROC_REF(interaction_transfer)))
	into += dq_interaction_from_spec(type, INTERACT_VERB("Threaten to push the button!", PROC_REF(deadman_it_effect), REQ_IN_INVENTORY))
	..()

/// Old attackby: tap two secured signalers together to copy frequency/code.
/obj/item/assembly/signaler/proc/interaction_transfer(mob/user, obj/item/W, datum/interaction/interaction)
	if(issignaler(W))
		var/obj/item/assembly/signaler/signaler2 = W
		if(secured && signaler2.secured)
			code = signaler2.code
			set_frequency(signaler2.frequency)
			to_chat(user, "You transfer the frequency and code of [signaler2] to [src].")
		return TRUE
	return FALSE

/obj/item/assembly/signaler/proc/signal()
	if(!COOLDOWN_FINISHED(src, next_activate))
		return FALSE
	if(!radio_connection())
		return
	if(is_jammed(src))
		return

	var/datum/signal/signal = new
	signal.source_handle = om_handle(src)
	signal.encryption = code
	signal.data["message"] = "ACTIVATE"
	radio_connection().post_signal(src, signal)
	COOLDOWN_START(src, next_activate, activation_cooldown)

/obj/item/assembly/signaler/pulse(radio = 0)
	if(is_jammed(src))
		return FALSE
	if(connected() && wires)
		connected().pulse_assembly(src)
	else if(holder())
		holder().process_activation(src, 1, 0)
	else
		..(radio)
	return TRUE

/obj/item/assembly/signaler/receive_signal(datum/signal/signal)
	if(!signal)
		return FALSE
	if(signal.encryption != code)
		return FALSE
	if(!(src.wires & WIRE_RADIO_RECEIVE))
		return FALSE
	if(is_jammed(src))
		return FALSE
	pulse(1)

	if(!holder())
		for(var/mob/O in hearers(1, src.loc))
			O.show_message("[icon2html(src, O.client)] *beep* *beep*", 3, "*beep* *beep*", 2)

/obj/item/assembly/signaler/proc/set_frequency(new_frequency)
	if(!frequency)
		return
	if(!GLOB.radio_service)
		om_after(src, 2 SECONDS, PROC_REF(radio_checkup), new_frequency)
		return
	set_radio(new_frequency)

/obj/item/assembly/signaler/proc/radio_checkup(new_frequency)
	PROTECTED_PROC(TRUE)
	if(!GLOB.radio_service)
		return
	set_radio(new_frequency)

/obj/item/assembly/signaler/proc/set_radio(new_frequency)
	PROTECTED_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	GLOB.radio_service.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection_handle = om_handle(GLOB.radio_service.add_object(src, frequency, RADIO_CHAT))
// BEGIN re-adds stealth removal
/obj/item/assembly/signaler/periodic_step()
	if(!deadman)
		om_task_periodic_stop(src)
	var/mob/M = src.loc
	if(!M || !ismob(M))
		if(prob(5))
			signal()
		deadman = FALSE
		om_task_periodic_stop(src)
	else if(prob(5))
		M.visible_message("[M]'s finger twitches a bit over [src]'s signal button!")

/obj/item/assembly/signaler/proc/deadman_it_effect(mob/user, obj/item/held, datum/interaction/interaction)
	deadman = TRUE
	om_task_periodic(src, PERIODIC_SLOW)
	log_and_message_admins("is threatening to trigger a signaler deadman's switch", user)
	user.visible_message("<font color='red'>[user] moves their finger over [src]'s signal button...</font>")
// end


/// LC-refs: the connected this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/assembly/signaler/proc/connected() as /datum/wires
	return om_resolve(connected_handle)

/// LC-refs: the radio_connection this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/assembly/signaler/proc/radio_connection() as /datum/radio_frequency
	return om_resolve(radio_connection_handle)
