/datum/reagent/firefighting_foam
	name = REAGENT_FIREFOAM
	id = REAGENT_ID_FIREFOAM
	description = "A historical fire suppressant. Originally believed to simply displace oxygen to starve fires, it actually interferes with the combustion reaction itself. Vastly superior to the cheap water-based extinguishers found on most NT vessels."
	reagent_state = LIQUID
	dermal_absorption = 0 //Custom touch handling. As funny as PFAS poisoning is.
	color = "#A6FAFF"
	scannable = SCANNABLE_ADVANCED
	taste_description = "the inside of a fire extinguisher"
	supply_conversion_value = REFINERYEXPORT_VALUE_UNWANTED
	industrial_use = REFINERYEXPORT_REASON_INDUSTRY

/datum/reagent/firefighting_foam/touch_turf(turf/T, reac_volume)
	if(reac_volume >= 1)
		var/obj/effect/effect/foam/firefighting/F = (locate_on(T, /obj/effect/effect/foam/firefighting))
		if(!F)
			F = new(T)
		else if(istype(F))
			F.lifetime = initial(F.lifetime) //reduce object churn a little bit when using smoke by keeping existing foam alive a bit longer

	// Foam is water-based: the same quench and the same latent heat as water.
	reagent_quench_hotspot(T)
	if(reagent_boil_off(T, volume))
		if(prob(5))
			T.visible_message(span_warning("The foam sizzles as it lands on \the [T]!"))

	T.apply_fire_protection() // Apply fire protection to the turf

/datum/reagent/firefighting_foam/touch_obj(obj/O, reac_volume)
	O.water_act(reac_volume / 5)

/datum/reagent/firefighting_foam/touch_mob(mob/living/M, reac_volume)
	if(istype(M, /mob/living/simple_mob/slime)) //I'm sure foam is water-based!
		var/mob/living/simple_mob/slime/S = M
		S.injure(INJURY_CORROSIVE, 15 * reac_volume, source = src)
		act_message(S, null, MSG_SELF(span_danger("Your flesh burns in the foam!")), MSG_OTHERS(span_warning("%U%'s flesh sizzles where the foam touches it!")))
	if(istype(M))
		M.adjust_fire_stacks(-reac_volume)
		M.extinguish_mob()
