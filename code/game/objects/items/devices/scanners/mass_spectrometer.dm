MATERIAL_MIX(/obj/item/mass_spectrometer, list(MAT_STEEL = 30,MAT_GLASS = 20))
/obj/item/mass_spectrometer
	name = "mass spectrometer"
	desc = "A hand-held mass spectrometer which identifies trace chemicals in a blood sample."
	icon = 'icons/obj/device.dmi'
	icon_state = "spectrometer"
	w_class = ITEMSIZE_SMALL
	flags = OPENCONTAINER
	slot_flags = SLOT_BELT
	throwforce = 5
	throw_speed = 4
	throw_range = 20


	var/details = 0
	var/recent_fail = 0

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

/obj/item/mass_spectrometer/Initialize(mapload)
	. = ..()
	var/datum/reagents/R = new/datum/reagents(5)
	rel_set(src, nameof(reagents), R)
	rel_set(R, nameof(R.my_atom), src)

/obj/item/mass_spectrometer/on_reagent_change()
	if(reagents.total_volume)
		icon_state = initial(icon_state) + "_s"
	else
		icon_state = initial(icon_state)

CAPABILITIES(/obj/item/mass_spectrometer)
	op("analyze", in_hand(), needs(req(PROC_REF(can_analyze), because = MSG(spectrometer/clumsy))), then(PROC_REF(analyzed)))

MSG_DEF_SELF(spectrometer/clumsy, "you don't have the dexterity to do this")

/// Requirement: only a dexterous user can work the spectrometer (one who is out cold is let through: the effect declines silently).
/obj/item/mass_spectrometer/proc/can_analyze(datum/act/op/A)
	var/mob/user = A.actor
	if(user.stat)
		return TRUE
	return user.IsAdvancedToolUser()

/obj/item/mass_spectrometer/proc/analyzed(datum/act/op/A)
	var/mob/user = A.actor
	if (user.stat)
		return OP_OK
	if(reagents.total_volume)
		var/list/blood_traces = list()
		for(var/datum/reagent/R in reagents.reagent_list)
			if(R.id != REAGENT_ID_BLOOD)
				reagents.clear_reagents()
				to_chat(user, span_warning("The sample was contaminated! Please insert another sample"))
				return OP_OK
			else
				blood_traces = params2list(R.data["trace_chem"])
				break
		var/dat = "Trace Chemicals Found: "
		for(var/R in blood_traces)
			if(details)
				dat += "[R] ([blood_traces[R]] units) "
			else
				dat += "[R] "
		to_chat(user, "[dat]")
		reagents.clear_reagents()
	return OP_OK

/obj/item/mass_spectrometer/adv
	name = "advanced mass spectrometer"
	icon_state = "adv_spectrometer"
	details = 1
