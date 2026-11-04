/mob/living/simple_mob/slime/xenobio/green/get_mechanics_info(list/additional_information)
	return ..(list("This slime will irradiate anything nearby passively, and will inject radium on attack. \
	A radsuit or other thick and radiation-hardened armor can protect from this. It will only radiate while alive.") + additional_information)

/mob/living/simple_mob/slime/xenobio/green
	desc ="This slime is radioactive."
	color = "#14FF20"
	slime_color = "green"
	coretype = /obj/item/slime_extract/green
	glow_toggle = TRUE
	reagent_injected = REAGENT_ID_RADIUM
	var/rads = 25
	player_msg = "You <b>passively irradiate your surroundings</b>.<br>\
	You also inject radium on attack."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/purple,
			/mob/living/simple_mob/slime/xenobio/green,
			/mob/living/simple_mob/slime/xenobio/emerald,
			/mob/living/simple_mob/slime/xenobio/emerald
		)

/mob/living/simple_mob/slime/xenobio/green/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.irradiate()
	..()

/mob/living/simple_mob/slime/xenobio/green/proc/irradiate()
	radiation_pulse(
		src,
		max_range = 5,
		threshold = RAD_LIGHT_INSULATION,
		chance = rads * 0.5,
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = rads
	)
