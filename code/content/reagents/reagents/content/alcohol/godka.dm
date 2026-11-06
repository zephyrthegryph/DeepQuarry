/datum/reagent/ethanol/godka
	name = REAGENT_GODKA
	id = REAGENT_ID_GODKA
	description = "Number one drink AND fueling choice for Russians multiverse-wide."
	taste_description = "russian steel and a hint of grain"
	color = "#0064C8"
	strength = 50

	glass_name = REAGENT_GODKA
	glass_desc = "The glass is barely able to contain the wodka. Xynta."
	glass_special = list(DRINK_FIZZ)

	allergen_type = ALLERGEN_GRAINS //Made from vodka(grain)

/datum/reagent/ethanol/godka/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	if(!(HAS_SYNTHETIC_BIOLOGY(M)))
		M.purge_radiation(5 * removed) // purges radiation (P2-F8)
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(H.species.has_organ[O_LIVER])
				var/obj/item/organ/internal/L = H.organ_in(O_LIVER)
				if(!L)
					return
				var/adjust_liver = rand(-3, 2)
				if(prob(L.damage))
					to_chat(M, span_cult("You feel woozy..."))
				if(adjust_liver > 0)
					H.injure(INJURY_TOXIN, adjust_liver * removed, L, src, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
		// A random swing either way: mends or poisons directly.
		var/adjust_tox = rand(-4, 2)
		if(adjust_tox > 0)
			M.injure(INJURY_TOXIN, adjust_tox * removed, source = src)
		else if(adjust_tox < 0)
			M.mend(TREAT_ANTITOXIN, -adjust_tox * removed)
