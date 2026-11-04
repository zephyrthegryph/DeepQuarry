//Boop //New and improved, now a simple reagent sniffer.
/obj/item/boop_module
	name = "boop module"
	icon = 'icons/mob/dogborg_vr.dmi'
	icon_state = "nose"
	desc = "The BOOP module, a simple reagent and atmosphere scanner."
	w_class = ITEMSIZE_TINY
	flags = NOBLUDGEON //No more attack messages

CAPABILITIES(/obj/item/boop_module)
	configure(item_thrown(force = 0))
	configure(item_combat(force = 0, attack_verbs = list("nuzzled", "nosed", "booped")))
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/boop_module/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if (!( istype(user.loc, /turf) ))
		return TRUE

	var/datum/gas_mixture/environment = user.loc.return_air()

	var/pressure = environment.return_pressure()
	var/total_moles = environment.total_moles()

	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	act_message(user, null, MSG_SELF(span_notice("You scan the air...")), MSG_OTHERS(span_notice("%U% scans the air.")))

	to_chat(user, span_boldnotice("Scan results:"))
	if(abs(pressure - ONE_ATMOSPHERE) < 10)
		to_chat(user, span_notice("Pressure: [round(pressure,0.1)] kPa"))
	else
		to_chat(user, span_warning("Pressure: [round(pressure,0.1)] kPa"))
	if(total_moles)
		// was XGM env.gas[g] iteration; under LINDA, env.gases keys are
		// /datum/gas type paths and the moles live at gases[g][MOLES].
		for(var/datum/gas/g as anything in environment.get_gases())
			var/moles = environment.get_moles(g)
			to_chat(user, span_notice("[initial(g.name)]: [round((moles / total_moles) * 100)]%"))
		var/environment_temperature = environment.return_temperature()
		to_chat(user, span_notice("Temperature: [round(environment_temperature-T0C,0.1)]&deg;C ([round(environment_temperature,0.1)]K)"))
	return TRUE

/obj/item/boop_module/afterattack(obj/O, mob/user as mob, proximity)
	if(!proximity)
		return
	if (user.stat)
		return
	if(!istype(O))
		return

	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	act_message(user, null, MSG_SELF(span_notice("You scan \the [O.name]...")), MSG_OTHERS(span_notice("%U% scan at \the [O.name].")))

	if(!isnull(O.reagents))
		var/dat = ""
		if(O.reagents.reagent_list.len > 0)
			for (var/datum/reagent/R in O.reagents.reagent_list)
				dat += "\n \t " + span_notice("[R]")

		if(dat)
			to_chat(user, span_notice("Your BOOP module indicates: [dat]"))
		else
			to_chat(user, span_notice("No active chemical agents detected in [O]."))
	else
		to_chat(user, span_notice("No significant chemical agents detected in [O]."))

	return
