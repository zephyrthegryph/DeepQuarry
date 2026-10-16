/mob/living/carbon/human/dummy
	real_name = "Test Dummy"
	status_flags = CANPUSH
	has_huds = FALSE
	no_vore = TRUE //Dummies don't need bellies.

/mob/living/carbon/human/dummy/proc/dummy_godmode_ready(datum/act/timer/A)
	enable_godmode()

/// Preview dummies are in no mob registry.
/mob/living/carbon/human/dummy/skips_registry(registry_id)
	return TRUE

/mob/living/carbon/human/dummy
	life_set = LIFE_SET_DELIST

/// A dummy is a mannequin for previews and look pins, never a crowd: its name is rolled at make, so seeding the tail loop from it would
/// draw a different idle frame state on every run. Every dummy plays loop 0.
/mob/living/carbon/human/dummy/tail_idle_variant()
	return 0


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

CAPABILITIES(/mob/living/carbon/human/dummy/mannequin/autoequip/tajaran)
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Tajaran Ears"))
/mob/living/carbon/human/dummy/mannequin/autoequip/tajaran
	species_at_make = SPECIES_TAJARAN
/mob/living/carbon/human/dummy/mannequin/autoequip/tajaran

/mob/living/carbon/human/dummy/mannequin/autoequip/unathi
	icon = 'icons/mob/human_races/r_lizard.dmi'

CAPABILITIES(/mob/living/carbon/human/dummy/mannequin/autoequip/unathi)
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Unathi Horns"))
/mob/living/carbon/human/dummy/mannequin/autoequip/unathi
	species_at_make = SPECIES_UNATHI
/mob/living/carbon/human/dummy/mannequin/autoequip/unathi

/mob/living/carbon/human/dummy/mannequin/autoequip/sergal
	icon = 'icons/mob/human_races/r_sergal.dmi' // our icons

CAPABILITIES(/mob/living/carbon/human/dummy/mannequin/autoequip/sergal)
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Sergal Ears"))
/mob/living/carbon/human/dummy/mannequin/autoequip/sergal
	species_at_make = SPECIES_SERGAL
/mob/living/carbon/human/dummy/mannequin/autoequip/sergal

/mob/living/carbon/human/dummy/mannequin/autoequip/vulpkanin
	icon = 'icons/mob/human_races/r_vulpkanin.dmi'

CAPABILITIES(/mob/living/carbon/human/dummy/mannequin/autoequip/vulpkanin)
	profile(nameof(looks), /datum/record/appearance, fields = list())
/mob/living/carbon/human/dummy/mannequin/autoequip/vulpkanin
	species_at_make = SPECIES_VULPKANIN
/mob/living/carbon/human/dummy/mannequin/autoequip/vulpkanin

/mob/living/carbon/human/dummy/mannequin/autoequip/teshari
	icon = 'icons/mob/human_races/r_teshari.dmi'
/mob/living/carbon/human/dummy/mannequin/autoequip/teshari
	species_at_make = SPECIES_TESHARI

/mob/living/carbon/human/skrell
	species_at_make = SPECIES_SKRELL

CAPABILITIES(/mob/living/carbon/human/skrell)
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Skrell Short Tentacles"))
/mob/living/carbon/human/skrell

/mob/living/carbon/human/tajaran
	species_at_make = SPECIES_TAJARAN

CAPABILITIES(/mob/living/carbon/human/tajaran)
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Tajaran Ears"))
/mob/living/carbon/human/tajaran

/mob/living/carbon/human/unathi
	species_at_make = SPECIES_UNATHI

CAPABILITIES(/mob/living/carbon/human/unathi)
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Unathi Horns"))
/mob/living/carbon/human/unathi

/mob/living/carbon/human/vox
	species_at_make = SPECIES_VOX

CAPABILITIES(/mob/living/carbon/human/vox)
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Short Vox Quills"))
/mob/living/carbon/human/vox

/mob/living/carbon/human/diona
	species_at_make = SPECIES_DIONA

/mob/living/carbon/human/teshari
	species_at_make = SPECIES_TESHARI

CAPABILITIES(/mob/living/carbon/human/teshari)
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Teshari Default"))
/mob/living/carbon/human/teshari

/mob/living/carbon/human/promethean
	species_at_make = SPECIES_PROMETHEAN

/mob/living/carbon/human/zaddat
	species_at_make = SPECIES_ZADDAT

/mob/living/carbon/human/monkey
	low_sorting_priority = TRUE

/mob/living/carbon/human/monkey
	species_at_make = SPECIES_MONKEY
TYPE_TABLE(/mob/living/carbon/human/monkey, initial_species_copy, TRUE)

/mob/living/carbon/human/farwa
	low_sorting_priority = TRUE

/mob/living/carbon/human/farwa
	species_at_make = SPECIES_MONKEY_TAJ
TYPE_TABLE(/mob/living/carbon/human/farwa, initial_species_copy, TRUE)

/mob/living/carbon/human/neaera
	low_sorting_priority = TRUE

/mob/living/carbon/human/neaera
	species_at_make = SPECIES_MONKEY_SKRELL
TYPE_TABLE(/mob/living/carbon/human/neaera, initial_species_copy, TRUE)

/mob/living/carbon/human/stok
	low_sorting_priority = TRUE

/mob/living/carbon/human/stok
	species_at_make = SPECIES_MONKEY_UNATHI
TYPE_TABLE(/mob/living/carbon/human/stok, initial_species_copy, TRUE)

/mob/living/carbon/human/sergal
	species_at_make = SPECIES_SERGAL

CAPABILITIES(/mob/living/carbon/human/sergal)
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Sergal Plain"))
/mob/living/carbon/human/sergal

/mob/living/carbon/human/akula
	species_at_make = SPECIES_AKULA

/mob/living/carbon/human/nevrean
	species_at_make = SPECIES_NEVREAN

/mob/living/carbon/human/xenochimera
	species_at_make = SPECIES_XENOCHIMERA

/mob/living/carbon/human/spider
	species_at_make = SPECIES_VASILISSAN

/mob/living/carbon/human/vulpkanin
	species_at_make = SPECIES_VULPKANIN

/mob/living/carbon/human/protean
	species_at_make = SPECIES_PROTEAN

/mob/living/carbon/human/alraune
	species_at_make = SPECIES_ALRAUNE

/mob/living/carbon/human/shadekin
	species_at_make = SPECIES_SHADEKIN

/mob/living/carbon/human/altevian
	species_at_make = SPECIES_ALTEVIAN

/mob/living/carbon/human/lleill
	species_at_make = SPECIES_LLEILL

/mob/living/carbon/human/hanner
	species_at_make = SPECIES_HANNER

/mob/living/carbon/human/sparkledog
	species_at_make = SPECIES_SPARKLE

/// Immune to incapacitation by nature (stun, weakness, paralysis).
CAPABILITIES(/mob/living/carbon/human/dummy)
	configure(lighting_config(emissive = EMISSIVE_BLOCK_NONE))
	after_init(0, then(PROC_REF(dummy_godmode_ready)))
	immune_to_incapacitation()
