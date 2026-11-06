/mob/living/simple_mob/slime/xenobio/emerald/get_mechanics_info(list/additional_information)
	return ..(list("This slime will make everything around it, and itself, faster for a few seconds, if close by.") + additional_information)

/mob/living/simple_mob/slime/xenobio/emerald
	desc ="This slime is faster than usual, even more so than the red slimes."
	color = "#22FF22"
	shiny = TRUE
	glow_toggle = TRUE
	slime_color = "emerald"
	coretype = /obj/item/slime_extract/emerald

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/green,
		/mob/living/simple_mob/slime/xenobio/green,
		/mob/living/simple_mob/slime/xenobio/emerald,
		/mob/living/simple_mob/slime/xenobio/emerald
	)

/mob/living/simple_mob/slime/xenobio/emerald/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.zoom_aura()
	..()

/mob/living/simple_mob/slime/xenobio/emerald/proc/zoom_aura()
	for(var/mob/living/L in view(src, 2))
		if(L.stat == DEAD || !IIsAlly(L))
			continue
		L.apply_body_effect(/datum/body_effect/technomancer/haste, 5 SECONDS, src)
