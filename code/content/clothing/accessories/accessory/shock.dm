/obj/item/clothing/accessory/collar/shock
	name = "Shock collar"
	desc = "A collar used to ease hungry predators."
	icon_state = "collar_shk0"
	item_state = "collar_shk"
	overlay_state = "collar_shk"
	var/on = FALSE // 0 for off, 1 for on, starts off to encourage people to set non-default frequencies and codes.
	var/frequency = AMAG_ELE_FREQ
	var/code = 2
	var/tmp/datum/radio_frequency/radio_connection
	special_collar = TRUE

/obj/item/clothing/accessory/collar/shock/proc/connect_collar_radio()
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_CHAT)) // Makes it so you don't need to change the frequency off of default for it to work.

/obj/item/clothing/accessory/collar/shock/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	tracked_changed(src, nameof(frequency))
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_CHAT))

SETTER(/obj/item/clothing/accessory/collar/shock, frequency)

CAPABILITIES(/obj/item/clothing/accessory/collar/shock)
	setup(PROC_REF(connect_collar_radio))
	ref_one(nameof(radio_connection), /datum/radio_frequency)
	op("controls", in_hand(), label("Open shock collar controls"), then(PROC_REF(shock_collar_controls_opened)))
	interface("ShockCollar")
	without("ui_open")
	op("freq", ui_act("freq", arg("freq", schema_text(4096))), then(PROC_REF(ui_act_freq)))
	op("code", ui_act("code", arg("code", num())), then(PROC_REF(ui_act_code)))
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("tag", ui_act("tag"), asks(/datum/prompt/text/shock_collar_ui_tag, step = "tag"), then(PROC_REF(ui_act_tag)))

/obj/item/clothing/accessory/collar/shock/proc/shock_collar_controls_opened(datum/act/op/A)
	if(!ishuman(A.actor))
		return OP_OK
	tgui_interact(A.actor)
	return OP_OK

/obj/item/clothing/accessory/collar/shock/tgui_static_data(mob/user)
	var/list/data = ..()

	data["freq_min"] = PUBLIC_LOW_FREQ
	data["freq_max"] = PUBLIC_HIGH_FREQ

	data["code_min"] = 0
	data["code_max"] = 100

	return data

/obj/item/clothing/accessory/collar/shock/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["on"] = on
	data["frequency"] = frequency
	data["code"] = code
	return data

/obj/item/clothing/accessory/collar/shock/proc/ui_act_freq(datum/act/op/A, freq)
	var/new_freq = sanitize_frequency(freq)
	set_frequency(new_freq)
	. = TRUE

/obj/item/clothing/accessory/collar/shock/proc/ui_act_code(datum/act/op/A, code_arg)
	set_code(CLAMP(code_arg, 1, 100))
	. = TRUE

/obj/item/clothing/accessory/collar/shock/proc/ui_act_power(datum/act/op/A)
	set_on(!on)
	if(!istype(src, /obj/item/clothing/accessory/collar/shock/bluespace))
		set_icon_state("collar_shk[on]")
	. = TRUE

/obj/item/clothing/accessory/collar/shock/proc/ui_act_tag(datum/act/op/A)
	return apply_ui_tag(A.actor, A.step_value("tag"))

/obj/item/clothing/accessory/collar/shock/proc/apply_ui_tag(mob/user, sanitized)
	if(!length(sanitized))
		to_chat(user, span_notice("[src]'s tag set to blank."))
		name = initial(name)
		desc = initial(desc)
	else
		to_chat(user, span_notice("[src]'s tag set to '[sanitized]'."))
		name = initial(name) + " ([sanitized])"
		desc = initial(desc) + " The tag says \"[sanitized]\"."
	. = TRUE

/obj/item/clothing/accessory/collar/shock/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption != code)
		return

	if(on)
		var/mob/M = null
		if(ismob(loc))
			M = loc
		if(ismob(loc.loc))
			M = loc.loc // This is about as terse as I can make my solution to the whole 'collar won't work when attached as accessory' thing.
		if(!M)
			return
		to_chat(M,span_danger("You feel a sharp shock!"))
		fx_sparks(M, 3)
		M.status_at_least(STAT_WEAKENED, 10)

/// the radio_connection this refers to (a relation view: null once it is deleted).
/obj/item/clothing/accessory/collar/shock/proc/radio_connection() as /datum/radio_frequency
	return radio_connection
