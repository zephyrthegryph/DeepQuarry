/obj/machinery/appliance/cooker/fryer
	name = "deep fryer"
	desc = "Deep fried <i>everything</i>."
	icon_state = "fryer_off"
	can_cook_mobs = 1
	cook_type = "deep fried"
	on_icon = "fryer_on"
	off_icon = "fryer_off"
	food_color = "#FFAD33"
	cooked_sound = SFX_MACHINES_DING
	var/datum/looping_sound/deep_fryer/fry_loop
	circuit = /obj/item/circuitboard/fryer
	appliancetype = FRYER
	active_power_usage = 12 KILOWATTS
	heating_power = 12 KILOWATTS

	light_y = 15

	min_temp = 140 + T0C	// Same as above, increasing this to just under 2x to make the % increase on efficiency not quite so painful as it would be at 80.
	optimal_temp = 400 + T0C // Increasing this to be 2x Oven to allow for a much higher/realistic frying temperatures. Doesn't really do anything but make heating the fryer take a bit longer.
	optimal_power = 0.95 // .35 higher than the default to give fryers faster cooking speed.

	idle_power_usage = 3.6 KILOWATTS
	// Power used to maintain temperature once it's heated.
	// Going with 25% of the active power. This is a somewhat arbitrary value.

	resistance = 2 KILOWATTS	// Approx. 2 minutes to heat up.

	max_contents = 2
	container_type = /obj/item/reagent_containers/cooking_container/fryer

	starts_off = TRUE

	tgui_id = "CookingFryer"

	var/datum/reagents/oil_reagents/oil
	var/optimal_oil = 2500 //25 litres of cooking oil

CAPABILITIES(/obj/machinery/appliance/cooker/fryer)
	owns_one(nameof(fry_loop), /datum/looping_sound/deep_fryer)
	owns_one(nameof(oil), /datum/reagents/oil_reagents)
	op("fryer_interaction_oil", item(/obj/item), then(PROC_REF(fryer_interaction_oil)))

///Reagent subtype for the fryer.
/datum/reagents/oil_reagents
	var/optimal_oil = 2500 //Overridden during init of the fryer.

/obj/machinery/appliance/cooker/fryer/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(fry_loop), new /datum/looping_sound/deep_fryer(list(src), FALSE))

	rel_set(src, nameof(oil), new/datum/reagents/oil_reagents(optimal_oil * 1.25, src))
	oil.optimal_oil = optimal_oil
	var/variance = rand()*0.15
	// Fryer is always a little below full, but its usually negligible

	if(prob(20))
		// Sometimes the fryer will start with much less than full oil, significantly impacting efficiency until filled
		variance = rand()*0.5
	oil.add_reagent(REAGENT_ID_COOKINGOIL, optimal_oil*(1 - variance))
	add_hose_connector(/datum/hose_connector/input/fryer)


/obj/machinery/appliance/cooker/fryer/examine(mob/user)
	. = ..()
	var/oil_level = oil.total_volume/optimal_oil
	if(Adjacent(user))
		var/message = span_notice("Oil Level: [oil.total_volume] / [optimal_oil]")
		if(oil_level <= 0.9)
			message += span_warning(" UNDERFILLED")
		else if(oil_level > 1.05) //A little bit of wiggle room
			message += span_warning(" OVERFILLED")
		to_chat(user, message)

/obj/machinery/appliance/cooker/fryer/ui_data(datum/act/eval/A)
	var/list/data = ..()
	var/list/merged_1 = ui_data_obj_machinery_appliance_cooker_fryer(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/appliance/cooker/fryer's window data.
/obj/machinery/appliance/cooker/fryer/proc/ui_data_obj_machinery_appliance_cooker_fryer(mob/user, datum/tgui/ui, datum/tgui_state/state)
	. = list()
	.["reagents"] = list("name" = oil.get_master_reagent_name(), "volume" = oil.total_volume, "max" = oil.maximum_volume)

/obj/machinery/appliance/cooker/fryer/heat_up()
	if (..())
		//Set temperature of oil reagent
		var/datum/reagent/nutriment/triglyceride/oil/OL = oil.get_master_reagent()
		if (OL && istype(OL))
			OL.data["temperature"] = get_temperature()

/obj/machinery/appliance/cooker/fryer/equalize_temperature()
	if (..())
		//Set temperature of oil reagent
		var/datum/reagent/nutriment/triglyceride/oil/OL = oil.get_master_reagent()
		if (OL && istype(OL))
			OL.data["temperature"] = get_temperature()

/obj/machinery/appliance/cooker/fryer/update_cooking_power()
	..()//In addition to parent temperature calculation
	//Fryer efficiency also drops when oil levels arent optimal
	var/oil_level = 0
	var/datum/reagent/nutriment/triglyceride/oil/OL = oil.get_master_reagent()
	if(OL && istype(OL))
		oil_level = OL.volume

	var/oil_efficiency = 0
	if(oil_level)
		oil_efficiency = oil_level / optimal_oil

		if(oil_efficiency > 1)
			//We're above optimal, efficiency goes down as we pass too much over it
			oil_efficiency = 1 - (oil_efficiency - 1)

	cooking_power *= oil_efficiency

DECLARE_APPEARANCE_PROC(/obj/machinery/appliance/cooker/fryer, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/appliance/cooker/fryer/appearance_overlays() // We add our own version of the proc to use the special fryer double-lights.
	. = list()
	if(!has_condition())
		. += ..()
		if(cooking == TRUE)
			icon_state = on_icon
			if(fry_loop)
				fry_loop.start(src)
		else
			icon_state = off_icon
			if(fry_loop)
				fry_loop.stop(src)
	else
		icon_state = off_icon
		if(fry_loop)
			fry_loop.stop(src)

	// Special fryer double-lights overlay.
	var/image/light
	if(use_power == 1 && !has_condition())
		light = image(icon, "fryer_light_idle")
	else if(use_power == 2 && !has_condition())
		light = image(icon, "fryer_light_preheating")
	else
		light = image(icon, "fryer_light_off")
	light.pixel_x = light_x
	light.pixel_y = light_y
	. += light

//Fryer gradually infuses any cooked food with oil. Moar calories
//This causes a slow drop in oil levels, encouraging refill after extended use
/obj/machinery/appliance/cooker/fryer/do_cooking_tick(datum/cooking_item/CI)
	if(..() && (CI.oil < CI.max_oil) && prob(20))
		var/datum/reagents/buffer = new /datum/reagents(2)
		oil.trans_to_holder(buffer, min(0.5, CI.max_oil - CI.oil))
		CI.oil += buffer.total_volume
		CI.container().soak_reagent(buffer)

//To solve any odd logic problems with results having oil as part of their compiletime ingredients.
//Upon finishing a recipe the fryer will analyse any oils in the result, and replace them with our oil
//As well as capping the total to the max oil
/obj/machinery/appliance/cooker/fryer/finish_cooking(datum/cooking_item/CI)
	..()
	var/total_oil = 0
	var/total_our_oil = 0
	var/total_removed = 0
	var/datum/reagent/our_oil = oil.get_master_reagent()
	if(!our_oil)
		return

	for (var/obj/item/I in CI.container())
		if (I.reagents && I.reagents.total_volume)
			for (var/datum/reagent/R in I.reagents.reagent_list)
				if (istype(R, /datum/reagent/nutriment/triglyceride/oil))
					total_oil += R.volume
					if (R.id != our_oil.id)
						total_removed += R.volume
						I.reagents.remove_reagent(R.id, R.volume)
					else
						total_our_oil += R.volume

	if (total_removed > 0 || total_oil != CI.max_oil)
		total_oil = min(total_oil, CI.max_oil)

		if (total_our_oil < total_oil)
			//If we have less than the combined total, then top up from our reservoir
			var/datum/reagents/buffer = new /datum/reagents(INFINITY)
			oil.trans_to_holder(buffer, total_oil - total_our_oil)
			CI.container().soak_reagent(buffer)
		else if (total_our_oil > total_oil)

			//If we have more than the maximum allowed then we delete some.
			//This could only happen if one of the objects spawns with the same type of oil as ours
			var/portion = 1 - (total_oil / total_our_oil) //find the percentage to remove
			for (var/obj/item/I in CI.container())
				if (I.reagents && I.reagents.total_volume)
					for (var/datum/reagent/R in I.reagents.reagent_list)
						if (R.id == our_oil.id)
							I.reagents.remove_reagent(R.id, R.volume*portion)

/obj/machinery/appliance/cooker/fryer/cook_mob(mob/living/victim, mob/user)

	if(!istype(victim))
		return


	//Removed delay on this action in favour of a cooldown after it
	//If you can lure someone close to the fryer and grab them then you deserve success.
	//And a delay on this kind of niche action just ensures it never happens
	//Cooldown ensures it can't be spammed to instakill someone
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN*3)

	fry_loop.start(src)

	task_timed(user, 2 SECONDS, victim, src, PROC_REF(cook_mob_done), list(victim, user), on_fail = PROC_REF(cook_mob_stopped))

/obj/machinery/appliance/cooker/fryer/proc/cook_mob_stopped()
	set_cooking(FALSE)
	icon_state = off_icon
	fry_loop.stop(src)

/obj/machinery/appliance/cooker/fryer/proc/cook_mob_done(mob/living/victim, mob/user)
	if(!victim || !victim.Adjacent(user))
		to_chat(user, span_danger("Your victim slipped free!"))
		set_cooking(FALSE)
		icon_state = off_icon
		fry_loop.stop(src)
		return

	var/damage = rand(7,13) // Though this damage seems reduced, some hot oil is transferred to the victim and will burn them for a while after

	var/datum/reagent/nutriment/triglyceride/oil/OL = oil.get_master_reagent()
	damage *= OL.heatdamage(victim)

	var/obj/item/organ/external/E
	var/nopain
	if(ishuman(victim) && user.zone_sel.selecting != BP_GROIN && user.zone_sel.selecting != BP_TORSO)
		var/mob/living/carbon/human/H = victim
		E = H.get_organ(user.zone_sel.selecting)
		if(!E)
			nopain = 2
		else if(E.is_robotic())
			nopain = 1
		else if(!H.can_feel_pain(E))
			nopain = 2

	act_message(user, victim, others = span_danger("%U% shoves %T%[E ? "'s [E.name]" : ""] into \the [src]!"))
	if (damage > 0)
		if(E)
			if(E.children && E.children.len)
				for(var/obj/item/organ/external/child in E.children)
					if(nopain && nopain < 2 && !(child.is_robotic()))
						nopain = 0
					victim.injure(INJURY_BURN, damage, child.organ_tag, source = src)
					damage -= (damage*0.5)//IF someone's arm is plunged in, the hand should take most of it
			victim.injure(INJURY_BURN, damage, E.organ_tag, source = src)
		else
			victim.injure(INJURY_BURN, damage, user.zone_sel.selecting, source = src)

		if(!nopain)
			to_chat(victim, span_danger("Agony consumes you as searing hot oil scorches your [E ? E.name : "flesh"] horribly!"))
			victim.emote("scream")
		else
			to_chat(victim, span_danger("Searing hot oil scorches your [E ? E.name : "flesh"]!"))

		add_attack_logs(user, victim, "has been [cook_type] with [src]")
		msg_admin_attack("[key_name_admin(user)] [cook_type] \the [victim] ([victim.ckey]) in \a [src]. (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[user.x];Y=[user.y];Z=[user.z]'>JMP</a>)")

	//Coat the victim in some oil
	oil.trans_to(victim, 40)

	fry_loop.stop()

/// Old attackby: scooping or pouring oil, else the appliance's own handling.
/obj/machinery/appliance/cooker/fryer/proc/fryer_interaction_oil(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/reagent_containers) && !istype(I, /obj/item/reagent_containers/food) && I.reagents)
		if(istype(I, /obj/item/reagent_containers/glass)) //Scooping stuff out with a glass.
			if(I.reagents.total_volume <= 0 && oil)
				//Its empty, handle scooping some hot oil out of the fryer
				oil.trans_to(I, I.reagents.maximum_volume)
				act_message(user, src, MSG_SELF(span_notice("You scoop some oil out of %T%.")), \
					MSG_OTHERS(span_filter_notice("%U% scoops some oil out of %T%.")))
				return TRUE
	//It contains stuff, handle pouring any oil into the fryer
	//Possibly in future allow pouring non-oil reagents in, in  order to sabotage it and poison food.
	//That would really require coding some sort of filter or better replacement mechanism first
	//So for now, restrict to oil only
		var/amount = 0
		for(var/datum/reagent/R in I.reagents.reagent_list)
			if(istype(R, /datum/reagent/nutriment/triglyceride/oil))
				var/delta = oil.get_free_space()
				delta = min(delta, R.volume)
				oil.add_reagent(R.id, delta)
				I.reagents.remove_reagent(R.id, delta)
				amount += delta
		if(amount > 0)
			act_message(user, src, MSG_SELF(span_notice("You pour [amount]u of oil into %T%.")), \
				MSG_OTHERS(span_filter_notice("%U% pours some oil into %T%.")), \
				MSG_BLIND(span_notice("You hear something viscous being poured into a metal container.")))
			return TRUE
	//If neither of the above returned, then call parent as normal
	return OP_DECLINE
