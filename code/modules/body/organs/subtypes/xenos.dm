//XENOMORPH ORGANS
/obj/item/organ/internal/xenos
	name = "xeno organ"
	icon = 'icons/obj/surgery.dmi'
	desc = "It smells like an accident in a chemical factory."
	supply_conversion_value = 50 // Selling engineered organs

/obj/item/organ/internal/xenos/eggsac
	name = "egg sac"
	parent_organ = BP_GROIN
	icon_state = "sac"
	organ_tag = O_EGG

/obj/item/organ/internal/xenos/eggsac/grey
	icon_state = "sac_grey"


CAPABILITIES(/obj/item/organ/internal/xenos/eggsac/grey/colormatch)
	after_init(0, then(PROC_REF(match_blood_color)))

/// Takes its owner's blood colour, once the body has placed it.
/obj/item/organ/internal/xenos/eggsac/grey/colormatch/proc/match_blood_color(datum/act/timer/A)
	if(ishuman(owner)) // placed in its limb by now
		var/mob/living/carbon/human/H = owner
		color = H.species.blood_color

/obj/item/organ/internal/xenos/plasmavessel
	name = "plasma vessel"
	parent_organ = BP_TORSO
	icon_state = "plasma"
	organ_tag = O_PLASMA
	var/stored_plasma = 0
	var/max_plasma = 500
	/// Plasma generated every organ tick regardless of phoron intake.
	var/passive_plasma = 1

	organ_verbs = list(
		/mob/living/carbon/human/proc/transfer_plasma
		)

/obj/item/organ/internal/xenos/plasmavessel/handle_organ_proc_special(cycles)
	if(!istype(owner))
		return

	var/modifier = 1 - 0.5 * is_bruised()

	if(owner.bloodstr.has_reagent(REAGENT_ID_PHORON))
		adjust_plasma(round(4 * modifier))

	if(owner.ingested.has_reagent(REAGENT_ID_PHORON))
		adjust_plasma(round(2 * modifier))

	adjust_plasma(passive_plasma)

/obj/item/organ/internal/xenos/plasmavessel/proc/adjust_plasma(amount = 0)
	stored_plasma = CLAMP(stored_plasma + amount, 0, max_plasma)

/obj/item/organ/internal/xenos/plasmavessel/grey
	icon_state = "plasma_grey"
	stored_plasma = 200


CAPABILITIES(/obj/item/organ/internal/xenos/plasmavessel/grey/colormatch)
	after_init(0, then(PROC_REF(match_blood_color)))

/// Takes its owner's blood colour, once the body has placed it.
/obj/item/organ/internal/xenos/plasmavessel/grey/colormatch/proc/match_blood_color(datum/act/timer/A)
	if(ishuman(owner)) // placed in its limb by now
		var/mob/living/carbon/human/H = owner
		color = H.species.blood_color

/obj/item/organ/internal/xenos/plasmavessel/queen
	name = "bloated plasma vessel"
	stored_plasma = 200
	max_plasma = 500

/obj/item/organ/internal/xenos/plasmavessel/sentinel
	stored_plasma = 100
	max_plasma = 250

/obj/item/organ/internal/xenos/plasmavessel/hunter
	name = "tiny plasma vessel"
	stored_plasma = 100
	max_plasma = 150

/obj/item/organ/internal/xenos/acidgland
	name = "acid gland"
	parent_organ = BP_HEAD
	icon_state = "acidgland"
	organ_tag = O_ACID

	organ_verbs = list(
		/mob/living/carbon/human/proc/corrosive_acid,
		/mob/living/carbon/human/proc/neurotoxin,
		/mob/living/carbon/human/proc/acidspit
		)

/obj/item/organ/internal/xenos/acidgland/grey
	icon_state = "acidgland_grey"


CAPABILITIES(/obj/item/organ/internal/xenos/acidgland/grey/colormatch)
	after_init(0, then(PROC_REF(match_blood_color)))

/// Takes its owner's blood colour, once the body has placed it.
/obj/item/organ/internal/xenos/acidgland/grey/colormatch/proc/match_blood_color(datum/act/timer/A)
	if(ishuman(owner)) // placed in its limb by now
		var/mob/living/carbon/human/H = owner
		color = H.species.blood_color

/obj/item/organ/internal/xenos/hivenode
	name = "hive node"
	parent_organ = BP_TORSO
	icon_state = "xenode"
	organ_tag = O_HIVE

/obj/item/organ/internal/xenos/hivenode/replaced(mob/living/carbon/human/target,obj/item/organ/external/affected)
	..()
	target.add_language(LANGUAGE_HIVEMIND) //You need this to speak the language, so...

/obj/item/organ/internal/xenos/hivenode/removed(mob/living/user)
	if(ishuman(user))
		var/mob/living/carbon/human/human = user
		human.remove_language(LANGUAGE_HIVEMIND)
	..()

/obj/item/organ/internal/xenos/hivenode/grey
	icon_state = "xenode_grey"


CAPABILITIES(/obj/item/organ/internal/xenos/hivenode/grey/colormatch)
	after_init(0, then(PROC_REF(match_blood_color)))

/// Takes its owner's blood colour, once the body has placed it.
/obj/item/organ/internal/xenos/hivenode/grey/colormatch/proc/match_blood_color(datum/act/timer/A)
	if(ishuman(owner)) // placed in its limb by now
		var/mob/living/carbon/human/H = owner
		color = H.species.blood_color

/obj/item/organ/internal/xenos/resinspinner
	name = "resin spinner"
	parent_organ = BP_HEAD
	icon_state = "xenode"
	organ_tag = O_RESIN

	organ_verbs = list(
		/mob/living/carbon/human/proc/resin,
		/mob/living/carbon/human/proc/plant
		)

/obj/item/organ/internal/xenos/resinspinner/grey
	icon_state = "xenode_grey"


CAPABILITIES(/obj/item/organ/internal/xenos/resinspinner/grey/colormatch)
	after_init(0, then(PROC_REF(match_blood_color)))

/// Takes its owner's blood colour, once the body has placed it.
/obj/item/organ/internal/xenos/resinspinner/grey/colormatch/proc/match_blood_color(datum/act/timer/A)
	if(ishuman(owner)) // placed in its limb by now
		var/mob/living/carbon/human/H = owner
		color = H.species.blood_color


// XENOMORPH EXTERNAL ORGANS

/obj/item/organ/external/chest/unseverable/xeno
	cannot_gib = 1
	cannot_amputate = 1

/obj/item/organ/external/groin/unseverable/xeno
	cannot_gib = 1
	cannot_amputate = 1
	encased = TRUE

/obj/item/organ/external/arm/unseverable/xeno
	cannot_gib = 1
	cannot_amputate = 1
	stapled_nerves = TRUE
	encased = TRUE

/obj/item/organ/external/arm/right/unseverable/xeno
	cannot_gib = 1
	cannot_amputate = 1
	stapled_nerves = TRUE
	encased = TRUE

/obj/item/organ/external/leg/unseverable/xeno
	cannot_gib = 1
	cannot_amputate = 1
	stapled_nerves = TRUE
	encased = TRUE

/obj/item/organ/external/leg/right/unseverable/xeno
	cannot_gib = 1
	cannot_amputate = 1
	stapled_nerves = TRUE
	encased = TRUE

/obj/item/organ/external/foot/unseverable/xeno
	cannot_gib = 1
	cannot_amputate = 1
	stapled_nerves = TRUE
	encased = TRUE

/obj/item/organ/external/foot/right/unseverable/xeno
	cannot_gib = 1
	cannot_amputate = 1
	stapled_nerves = TRUE
	encased = TRUE

/obj/item/organ/external/hand/unseverable/xeno
	cannot_gib = 1
	cannot_amputate = 1
	stapled_nerves = TRUE
	encased = TRUE

/obj/item/organ/external/hand/right/unseverable/xeno
	cannot_gib = 1
	cannot_amputate = 1
	stapled_nerves = TRUE
	encased = TRUE

/obj/item/organ/external/head/unseverable/xeno
	cannot_gib = 1
	cannot_amputate = 1
	eye_icon = "blank_eyes"

// This organ has work every organ_tick(), so the body's organ clock stays running for it.
/obj/item/organ/internal/xenos/plasmavessel/life_step_idle()
	return FALSE

