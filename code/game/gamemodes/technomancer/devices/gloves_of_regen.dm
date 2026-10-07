/datum/technomancer/equipment/gloves_of_regen
	name = "Gloves of Regeneration"
	desc = "It's a pair of black gloves, with a hypodermic needle on the insides, and a small storage of a secret blend of chemicals \
	designed to be slowly fed into a living person's system, increasing their metabolism greatly, resulting in accelerated healing.  \
	A side effect of this healing is that the wearer will generally get hungry a lot faster.  Sliding the gloves on and off also \
	hurts a lot.  As a bonus, the gloves are more resistant to the elements than most.  It should be noted that synthetics will have \
	little use for these."
	cost = 50
	obj_path = /obj/item/clothing/gloves/regen

/obj/item/clothing/gloves/regen
	name = "gloves of regeneration"
	desc = "A pair of gloves with a small storage of green liquid on the outside.  On the inside, a a hypodermic needle can be seen \
	on each glove."
	icon_state = "regen"
	item_state = "graygloves"
	siemens_coefficient = 0
	cold_protection = HANDS
	min_cold_protection_temperature = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE

/obj/item/clothing/gloves/regen/equipped(mob/user)
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.get_equipped_item(SLOT_ID_GLOVES) == src)
			rel_set(src, nameof(wearer), H)
			if(H.can_feel_pain())
				to_chat(H, span_danger("You feel a stabbing sensation in your hands as you slide \the [src] on!"))
				H.custom_pain("You feel a sharp pain in your hands!",1)
	..()

/obj/item/clothing/gloves/regen/dropped(mob/user, equipping, slot)
	if(equipping)
		return ..()

	..()

	if(!ishuman(user))
		return
	var/mob/living/carbon/human/H = user
	if(H.can_feel_pain())
		to_chat(H, span_danger("You feel the hypodermic needles as you slide \the [src] off!"))
		H.custom_pain("Your hands hurt like hell!",1)

/// TRUE while worn (equipped() sets it): the slow step treats the wearer; taken off, it parks.
/obj/item/clothing/gloves/regen/var/tmp/regenerating = FALSE
TRACKED(/obj/item/clothing/gloves/regen, regenerating)

CAPABILITIES(/obj/item/clothing/gloves/regen)
	every(2 SECONDS, then(PROC_REF(regen_step)), when = nameof(regenerating))

/// Works every 2 s while worn.
/obj/item/clothing/gloves/regen/proc/regen_step(datum/act/A)
	var/mob/living/carbon/human/H = ishuman(wearer) ? wearer : null
	if(!H || H.get_equipped_item(SLOT_ID_GLOVES) != src)
		set_regenerating(FALSE)
		return
	if(!ishuman(H) || H.stat == DEAD || H.nutrition <= 10)
		return // Dead people don't have a metabolism.

	// Organic treatment tags: synthetic parts are left alone (and don't cost nutrition).
	if(H.mend(TREAT_TISSUE_REPAIR, 0.1))
		H.set_nutrition(max(H.nutrition - 10, 0))
	if(H.mend(TREAT_BURN_CARE, 0.1))
		H.set_nutrition(max(H.nutrition - 10, 0))
	if(H.mend(TREAT_ANTITOXIN, 0.1))
		H.set_nutrition(max(H.nutrition - 10, 0))
	if(H.mend(TREAT_OXYGENATION, 0.1))
		H.set_nutrition(max(H.nutrition - 10, 0))
	if(H.mend(TREAT_GENETIC_REPAIR, 0.1))
		H.set_nutrition(max(H.nutrition - 20, 0))

/obj/item/clothing/gloves/regen/equipped(mob/user, slot)
	. = ..()
	if(ismob(wearer))
		set_regenerating(TRUE)
