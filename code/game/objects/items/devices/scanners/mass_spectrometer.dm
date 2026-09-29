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
	reagents = R
	R.my_atom = src

/obj/item/mass_spectrometer/on_reagent_change()
	if(reagents.total_volume)
		icon_state = initial(icon_state) + "_s"
	else
		icon_state = initial(icon_state)

DECLARE_INTERACTIONS(/obj/item/mass_spectrometer, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/mass_spectrometer/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if (user.stat)
		return
	if (!user.IsAdvancedToolUser())
		to_chat(user, span_warning("You don't have the dexterity to do this!"))
		return
	if(reagents.total_volume)
		var/list/blood_traces = list()
		for(var/datum/reagent/R in reagents.reagent_list)
			if(R.id != REAGENT_ID_BLOOD)
				reagents.clear_reagents()
				to_chat(user, span_warning("The sample was contaminated! Please insert another sample"))
				return
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
	return

/obj/item/mass_spectrometer/adv
	name = "advanced mass spectrometer"
	icon_state = "adv_spectrometer"
	details = 1
