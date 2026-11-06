/mob/living/simple_mob/slime/xenobio/amber/get_mechanics_info(list/additional_information)
	return ..(list("This slime feeds nearby entities passively while it is alive. This can cause uncontrollable \
	slime growth and reproduction if not kept in check. The amber slime cannot feed itself, but can be fed by other amber slimes.") + additional_information)

/mob/living/simple_mob/slime/xenobio/amber
	desc ="This slime seems to be an expert in the culinary arts, as they create their own food to share with others.  \
	They would probably be very important to other slimes, if the other colors didn't try to kill them."
	color = "#FFBB00"
	slime_color = "amber"
	shiny = TRUE
	glow_toggle = TRUE
	coretype = /obj/item/slime_extract/amber
	player_msg = "You <b>passively provide nutrition</b> to nearby entities."

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/silver,
		/mob/living/simple_mob/slime/xenobio/silver,
		/mob/living/simple_mob/slime/xenobio/amber,
		/mob/living/simple_mob/slime/xenobio/amber
	)

/mob/living/simple_mob/slime/xenobio/amber/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.feed_aura()
	..()

/mob/living/simple_mob/slime/xenobio/amber/proc/feed_aura()
	for(var/mob/living/L in view(1, src))
		if(L.stat == DEAD || !IIsAlly(L))
			continue
		if(L == src || istype(L, /mob/living/simple_mob/slime/xenobio/amber)) // Don't feed themselves, or it is impossible to stop infinite slimes without killing all of the ambers.
			continue
		if(istype(L, /mob/living/simple_mob/slime/xenobio))
			var/mob/living/simple_mob/slime/xenobio/X = L
			X.adjust_nutrition(rand(15, 25), 0)
		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			if(HAS_SYNTHETIC_BIOLOGY(H))
				continue
			H.set_nutrition(between(0, nutrition_of(H) + rand(15, 25), 800))
