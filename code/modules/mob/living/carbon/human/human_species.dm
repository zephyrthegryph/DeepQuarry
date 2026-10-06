/mob/living/carbon/human/dummy
	real_name = "Test Dummy"
	status_flags = CANPUSH
	has_huds = FALSE
	blocks_emissive = EMISSIVE_BLOCK_NONE
	no_vore = TRUE //Dummies don't need bellies.

/mob/living/carbon/human/dummy/Initialize(mapload)
	. = ..()
	enable_godmode()

/// Preview dummies are in no mob registry.
/mob/living/carbon/human/dummy/skips_registry(registry_id)
	return TRUE

/mob/living/carbon/human/dummy
	life_set = LIFE_SET_DELIST


/mob/living/carbon/human/dummy/mannequin/Initialize(mapload)
	. = ..()
	delete_inventory()

/mob/living/carbon/human/dummy/mannequin/autoequip
	icon = 'icons/mob/human_races/r_human.dmi'
	icon_state = "preview"
	var/autorotate = TRUE

/mob/living/carbon/human/dummy/mannequin/autoequip/Initialize(mapload)
	icon = null
	icon_state = "" // ALLOW(decl): clears the inherited icon before parent init
	. = ..()

	dress_up()
	if(autorotate)
		turntable()

/mob/living/carbon/human/dummy/mannequin/autoequip/proc/dress_up()

	for(var/obj/item/I in contents_of(loc))
		if(istype(I, /obj/item/clothing))
			var/obj/item/clothing/C = I
			C.restrict_fit(null)
		equip_to_appropriate_slot(I)

	if(istype(get_equipped_item(SLOT_ID_BACK), /obj/item/rig))
		var/obj/item/rig/rig = get_equipped_item(SLOT_ID_BACK)
		rig.toggle_seals(src)

/mob/living/carbon/human/dummy/mannequin/autoequip/proc/turntable()
	turntable_step(SOUTH)

/mob/living/carbon/human/dummy/mannequin/autoequip/proc/turntable_step(facing)
	set_dir(facing)
	after(src, 2 SECONDS, PROC_REF(turntable_step), with = list(turn(facing, 90)))

/mob/living/carbon/human/dummy/mannequin/autoequip/tajaran
	icon = 'icons/mob/human_races/r_tajaran.dmi'
TYPE_TABLE(/mob/living/carbon/human/dummy/mannequin/autoequip/tajaran, forced_initial_species, SPECIES_TAJARAN)
TYPE_TABLE(/mob/living/carbon/human/dummy/mannequin/autoequip/tajaran, forced_initial_hair, "Tajaran Ears")

/mob/living/carbon/human/dummy/mannequin/autoequip/unathi
	icon = 'icons/mob/human_races/r_lizard.dmi'
TYPE_TABLE(/mob/living/carbon/human/dummy/mannequin/autoequip/unathi, forced_initial_species, SPECIES_UNATHI)
TYPE_TABLE(/mob/living/carbon/human/dummy/mannequin/autoequip/unathi, forced_initial_hair, "Unathi Horns")

/mob/living/carbon/human/dummy/mannequin/autoequip/sergal
	icon = 'icons/mob/human_races/r_sergal.dmi' // our icons
TYPE_TABLE(/mob/living/carbon/human/dummy/mannequin/autoequip/sergal, forced_initial_species, SPECIES_SERGAL)
TYPE_TABLE(/mob/living/carbon/human/dummy/mannequin/autoequip/sergal, forced_initial_hair, "Sergal Ears")

/mob/living/carbon/human/dummy/mannequin/autoequip/vulpkanin
	icon = 'icons/mob/human_races/r_vulpkanin.dmi'
TYPE_TABLE(/mob/living/carbon/human/dummy/mannequin/autoequip/vulpkanin, forced_initial_species, SPECIES_VULPKANIN)
TYPE_TABLE(/mob/living/carbon/human/dummy/mannequin/autoequip/vulpkanin, forced_initial_hair, "vulpkanin, dual-color")

/mob/living/carbon/human/dummy/mannequin/autoequip/teshari
	icon = 'icons/mob/human_races/r_teshari.dmi'
TYPE_TABLE(/mob/living/carbon/human/dummy/mannequin/autoequip/teshari, forced_initial_species, SPECIES_TESHARI)

TYPE_TABLE(/mob/living/carbon/human/skrell, forced_initial_species, SPECIES_SKRELL)
TYPE_TABLE(/mob/living/carbon/human/skrell, forced_initial_hair, "Skrell Short Tentacles")

TYPE_TABLE(/mob/living/carbon/human/tajaran, forced_initial_species, SPECIES_TAJARAN)
TYPE_TABLE(/mob/living/carbon/human/tajaran, forced_initial_hair, "Tajaran Ears")

TYPE_TABLE(/mob/living/carbon/human/unathi, forced_initial_species, SPECIES_UNATHI)
TYPE_TABLE(/mob/living/carbon/human/unathi, forced_initial_hair, "Unathi Horns")

TYPE_TABLE(/mob/living/carbon/human/vox, forced_initial_species, SPECIES_VOX)
TYPE_TABLE(/mob/living/carbon/human/vox, forced_initial_hair, "Short Vox Quills")

TYPE_TABLE(/mob/living/carbon/human/diona, forced_initial_species, SPECIES_DIONA)

TYPE_TABLE(/mob/living/carbon/human/teshari, forced_initial_species, SPECIES_TESHARI)
TYPE_TABLE(/mob/living/carbon/human/teshari, forced_initial_hair, "Teshari Default")

TYPE_TABLE(/mob/living/carbon/human/promethean, forced_initial_species, SPECIES_PROMETHEAN)

TYPE_TABLE(/mob/living/carbon/human/zaddat, forced_initial_species, SPECIES_ZADDAT)

/mob/living/carbon/human/monkey
	low_sorting_priority = TRUE

TYPE_TABLE(/mob/living/carbon/human/monkey, forced_initial_species, SPECIES_MONKEY)
TYPE_TABLE(/mob/living/carbon/human/monkey, initial_species_copy, TRUE)

/mob/living/carbon/human/farwa
	low_sorting_priority = TRUE

TYPE_TABLE(/mob/living/carbon/human/farwa, forced_initial_species, SPECIES_MONKEY_TAJ)
TYPE_TABLE(/mob/living/carbon/human/farwa, initial_species_copy, TRUE)

/mob/living/carbon/human/neaera
	low_sorting_priority = TRUE

TYPE_TABLE(/mob/living/carbon/human/neaera, forced_initial_species, SPECIES_MONKEY_SKRELL)
TYPE_TABLE(/mob/living/carbon/human/neaera, initial_species_copy, TRUE)

/mob/living/carbon/human/stok
	low_sorting_priority = TRUE

TYPE_TABLE(/mob/living/carbon/human/stok, forced_initial_species, SPECIES_MONKEY_UNATHI)
TYPE_TABLE(/mob/living/carbon/human/stok, initial_species_copy, TRUE)

TYPE_TABLE(/mob/living/carbon/human/sergal, forced_initial_species, SPECIES_SERGAL)
TYPE_TABLE(/mob/living/carbon/human/sergal, forced_initial_hair, "Sergal Plain")

TYPE_TABLE(/mob/living/carbon/human/akula, forced_initial_species, SPECIES_AKULA)

TYPE_TABLE(/mob/living/carbon/human/nevrean, forced_initial_species, SPECIES_NEVREAN)

TYPE_TABLE(/mob/living/carbon/human/xenochimera, forced_initial_species, SPECIES_XENOCHIMERA)

TYPE_TABLE(/mob/living/carbon/human/spider, forced_initial_species, SPECIES_VASILISSAN)

TYPE_TABLE(/mob/living/carbon/human/vulpkanin, forced_initial_species, SPECIES_VULPKANIN)

TYPE_TABLE(/mob/living/carbon/human/protean, forced_initial_species, SPECIES_PROTEAN)

TYPE_TABLE(/mob/living/carbon/human/alraune, forced_initial_species, SPECIES_ALRAUNE)

TYPE_TABLE(/mob/living/carbon/human/shadekin, forced_initial_species, SPECIES_SHADEKIN)

TYPE_TABLE(/mob/living/carbon/human/altevian, forced_initial_species, SPECIES_ALTEVIAN)

TYPE_TABLE(/mob/living/carbon/human/lleill, forced_initial_species, SPECIES_LLEILL)

TYPE_TABLE(/mob/living/carbon/human/hanner, forced_initial_species, SPECIES_HANNER)

TYPE_TABLE(/mob/living/carbon/human/sparkledog, forced_initial_species, SPECIES_SPARKLE)

/// Immune to incapacitation by nature (stun, weakness, paralysis).
CAPABILITIES(/mob/living/carbon/human/dummy)
	immune_to_incapacitation()
