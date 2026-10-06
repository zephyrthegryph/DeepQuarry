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
	var/tmp/datum/cap_data/wires/connected
	var/tmp/datum/radio_frequency/radio_connection

/// Someone is threatening to press the button: it may slip while it's not held.
OM_FIELD(/obj/item/assembly/signaler, deadman, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/item/assembly/signaler, PERIODIC_SLOW, "deadman")

/obj/item/assembly/signaler/Initialize(mapload)
	. = ..()
	set_frequency(frequency)

/obj/item/assembly/signaler/activate()
	if(!COOLDOWN_FINISHED(src, next_activate))
		return FALSE
	signal()
	return TRUE

DECLARE_APPEARANCE_PROC(/obj/item/assembly/signaler, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/assembly/signaler/appearance_overlays()
	. = list()
	if(holder())
		holder().update_icon()

CAPABILITIES(/obj/item/assembly/signaler)
	interface("Signaler", state = nameof(GLOB.tgui_deep_inventory_state))
	without("ui_open")
	op("signal", ui_act("signal"), then(PROC_REF(ui_act_signal)))
	op("freq", ui_act("freq", arg("freq", num())), then(PROC_REF(ui_act_freq)))
	op("code", ui_act("code", arg("code", num())), then(PROC_REF(ui_act_code)))
	op("reset", ui_act("reset", arg("reset", schema_text(4096))), then(PROC_REF(ui_act_reset)))

/obj/item/assembly/signaler/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["frequency"] = frequency
	data["code"] = code
	var/list/merged_1 = ui_data_obj_item_assembly_signaler(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/assembly/signaler's window data.
/obj/item/assembly/signaler/proc/ui_data_obj_item_assembly_signaler(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["minFrequency"] = RADIO_LOW_FREQ
	data["maxFrequency"] = RADIO_HIGH_FREQ
	return data

/obj/item/assembly/signaler/proc/ui_act_signal(datum/act/op/A)
	signal()
	. = TRUE
	update_icon()

/obj/item/assembly/signaler/proc/ui_act_freq(datum/act/op/A, freq)
	frequency = unformat_frequency(freq)
	frequency = sanitize_frequency(frequency, RADIO_LOW_FREQ, RADIO_HIGH_FREQ)
	set_frequency(frequency)
	. = TRUE
	update_icon()

/obj/item/assembly/signaler/proc/ui_act_code(datum/act/op/A, code_arg)
	code = code_arg
	code = clamp(round(code), 1, 100)
	. = TRUE
	update_icon()

/obj/item/assembly/signaler/proc/ui_act_reset(datum/act/op/A, reset)
	if(reset == "freq")
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
	rel_set(signal, nameof(signal.source), src)
	signal.encryption = code
	signal.data["message"] = "ACTIVATE"
	radio_connection().post_signal(src, signal)
	COOLDOWN_START(src, next_activate, activation_cooldown)

/obj/item/assembly/signaler/pulse(radio = 0)
	if(is_jammed(src))
		return FALSE
	if(connected())
		connected().signaled(src)
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
	if(!(wires_type & WIRE_RADIO_RECEIVE))
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
	if(!SSradio)
		after(src, 2 SECONDS, PROC_REF(radio_checkup), with = list(new_frequency))
		return
	set_radio(new_frequency)

/obj/item/assembly/signaler/proc/radio_checkup(new_frequency)
	PROTECTED_PROC(TRUE)
	if(!SSradio)
		return
	set_radio(new_frequency)

/obj/item/assembly/signaler/proc/set_radio(new_frequency)
	PROTECTED_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_CHAT))
// BEGIN re-adds stealth removal
/obj/item/assembly/signaler/periodic_step()
	var/mob/M = src.loc
	if(!M || !ismob(M))
		if(prob(5))
			signal()
		set_deadman(FALSE)
	else if(prob(5))
		act_message(M, src, others = "%U%'s finger twitches a bit over %T%'s signal button!")

/obj/item/assembly/signaler/proc/deadman_it_effect(mob/user, obj/item/held, datum/interaction/interaction)
	set_deadman(TRUE)
	log_and_message_admins("is threatening to trigger a signaler deadman's switch", user)
	act_message(user, src, others = "<font color='red'>%U% moves their finger over %T%'s signal button...</font>")
// end


/// the connected this refers to (a relation view: null once it is deleted).
/obj/item/assembly/signaler/proc/connected() as /datum/cap_data/wires
	return connected

/// the radio_connection this refers to (a relation view: null once it is deleted).
/obj/item/assembly/signaler/proc/radio_connection() as /datum/radio_frequency
	return radio_connection
