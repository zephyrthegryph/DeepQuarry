/datum/species/zaddat
	name = SPECIES_ZADDAT
	name_plural = "Zaddat"
	icobase = 'icons/mob/human_races/r_zaddat.dmi'
	deform = 'icons/mob/human_races/r_zaddat.dmi'
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/punch)
	flash_mod = 2
	flash_burn = 15 //flashing a zaddat probably counts as police brutality
	// did u know if your ancestors starved ur body will actually start in starvation mode?
	factor_baseline = alist(STAT_METABOLISM_MULT = 0.7, STAT_INCOMING_PHYSICAL = 1.15, STAT_INCOMING_THERMAL = 1.15, STAT_INCOMING_TOXIC = 0.5)
	item_slowdown_mod = 0.30
	taste_sensitivity = TASTE_SENSITIVE
	num_alternate_languages = 3
	secondary_langs = list(LANGUAGE_ZADDAT, LANGUAGE_UNATHI)
	assisted_langs = list(LANGUAGE_EAL, LANGUAGE_ROOTLOCAL, LANGUAGE_ROOTGLOBAL, LANGUAGE_VOX, LANGUAGE_PROMETHEAN) //limited vocal range; can talk Unathi and magical Galcom but not much else
	name_language = LANGUAGE_ZADDAT
	species_language = LANGUAGE_ZADDAT
	health_hud_intensity = 2.5
	throwforce_absorb_threshold = 5

	minimum_breath_pressure = 20 //have fun with underpressures. any higher than this and they'll be even less suitible for life on the station

	economic_modifier = 3

	min_age = 18
	max_age = 90

	blurb = "The Zaddat are an Unathi client race only recently introduced to SolGov space. Having evolved on \
	the high-pressure and post-apocalyptic world of Xohok, Zaddat require an environmental suit called a Shroud \
	to survive in usual planetary and station atmospheres. Despite these restrictions, worsening conditions on \
	Xohok and the blessing of the Moghes Hegemony have lead the Zaddat to enter human space in search of work \
	and living space."
	wikilink="https://wiki.chompstation13.net/index.php?title=Zaddat" // link to our wiki
	catalogue_data = list(/datum/category_item/catalogue/fauna/zaddat)

	hazard_high_pressure = HAZARD_HIGH_PRESSURE + 500  // Dangerously high pressure.
	warning_high_pressure = WARNING_HIGH_PRESSURE + 500 // High pressure warning.
	warning_low_pressure = 300   // Low pressure warning.
	hazard_low_pressure = 220     // Dangerously low pressure.
	safe_pressure = 400
	poison_type = GAS_N2      // technically it's a partial pressure thing but IDK if we can emulate that
	ideal_air_type = /datum/gas_mixture/belly_air/zaddat

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	spawn_flags = SPECIES_CAN_JOIN
	appearance_flags = null

	flesh_color = "#AFA59E"
	base_color = "#e2e4a6"
	blood_color = "#FFCC00" //a gross sort of orange color

	reagent_tag = IS_ZADDAT

	species_component = list(/datum/trait_state/burninlight) // Until a parent component like xenochimera have is needed, only handles burning in light.

	heat_discomfort_strings = list(
		"Your joints itch.",
		"You feel uncomfortably warm.",
		"Your carapace feels like a stove."
		)

	cold_discomfort_strings = list(
		"You feel chilly.",
		"You shiver suddenly.",
		"Your antenna ache."
		)

	has_organ = list(    //No appendix.
	O_HEART =		/obj/item/organ/internal/heart,
	O_LUNGS =		/obj/item/organ/internal/lungs,
	O_VOICE =		/obj/item/organ/internal/voicebox,
	O_LIVER =		/obj/item/organ/internal/liver,
	O_KIDNEYS =		/obj/item/organ/internal/kidneys,
	O_SPLEEN =		/obj/item/organ/internal/spleen,
	O_BRAIN =		/obj/item/organ/internal/brain,
	O_EYES =		/obj/item/organ/internal/eyes,
	O_STOMACH =		/obj/item/organ/internal/stomach,
	O_INTESTINE =	/obj/item/organ/internal/intestine
	)


	default_emotes = list(
		/datum/decl/emote/audible/chirp
	)
	inherent_verbs = list(/mob/living/carbon/human/proc/tie_hair)

/datum/species/zaddat/equip_survival_gear(mob/living/carbon/human/H)
	. = ..()
	if(H.get_equipped_item(SLOT_ID_SUIT)) //get rid of job labcoats so they don't stop us from equipping the Shroud
		H.slot_clear(SLOT_ID_SUIT) //if you know how to gently set it in like, their backpack or whatever, be my guest
	if(H.get_equipped_item(SLOT_ID_MASK))
		H.slot_clear(SLOT_ID_MASK)
	if(H.get_equipped_item(SLOT_ID_HEAD))
		H.slot_clear(SLOT_ID_HEAD)

	H.equip_to_slot_or_del(new /obj/item/clothing/mask/gas/zaddat/(H), SLOT_ID_MASK) // mask has to come first or Shroud helmet will get in the way
	H.equip_to_slot_or_del(new /obj/item/clothing/suit/space/void/zaddat/(H), SLOT_ID_SUIT)

	var/obj/item/storage/toolbox/lunchbox/survival/zaddat/L = new(get_turf(H))
	if(H.bio.backbag == 1)
		H.equip_to_slot_or_del(L, SLOT_ID_HAND_R)
	else
		H.equip_to_slot_or_del(L, SLOT_ID_IN_BACKPACK)

// === merged from station_ch.dm during hard-fork de-suffix (manually verified: all-new types/defines, no base re-open) ===
//There is already a station file, but feels wrong to put zaddat balancing changes with the restriction file, and feels wrong to lump them in with a modular station_vr so hello station_ch file

/datum/species/zaddat
	//toxins rarely come into play, and zaddat just has negatives. Along with their parasite letting them survive in their polluted planet, this seems reasonable. (toxins)
