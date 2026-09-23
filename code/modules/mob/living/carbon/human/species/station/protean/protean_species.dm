/datum/species/protean
	name =             SPECIES_PROTEAN
	name_plural =      "Proteans"
	blurb =            "Sometimes very advanced civilizations will produce the ability to swap into manufactured, robotic bodies. And sometimes \
						" + span_italics("VERY") + " advanced civilizations have the option of 'nanoswarm' bodies. Effectively a single robot body comprised \
						of millions of tiny nanites working in concert to maintain cohesion."
	show_ssd =         "totally quiescent"
	death_message =    "rapidly loses cohesion, retreating into their hardened control module..."
	knockout_message = "collapses inwards, forming a disordered puddle of gray goo."
	remains_type = /obj/effect/decal/cleanable/ash

	selects_bodytype = SELECTS_BODYTYPE_SHAPESHIFTER
	base_species = SPECIES_HUMAN

	blood_color = "#505050" //This is the same as the 80,80,80 below, but in hex
	flesh_color = "#505050"
	base_color = "#FFFFFF" //Color mult, start out with this

	flags =            NO_DNA | NO_SLEEVE | NO_SLIP | NO_MINOR_CUT | NO_HALLUCINATION | NO_INFECT | NO_PAIN
	appearance_flags = HAS_SKIN_COLOR | HAS_EYE_COLOR | HAS_HAIR_COLOR | HAS_UNDERWEAR | HAS_LIPS
	spawn_flags		 = SPECIES_CAN_JOIN | SPECIES_IS_WHITELISTED | SPECIES_WHITELIST_SELECTABLE
	health_hud_intensity = 2
	num_alternate_languages = 3
	species_language = LANGUAGE_EAL
	assisted_langs = list(LANGUAGE_ROOTLOCAL, LANGUAGE_ROOTGLOBAL, LANGUAGE_VOX)
	speech_bubble_appearance = "synthetic"
	color_mult = TRUE

	breath_type = null
	poison_type = null

	// male_scream_sound = null
	// female_scream_sound = null

	virus_immune = 1
	blood_volume = 0
	min_age = 18
	max_age = 200
	factor_baseline = alist(BF_INCOMING_PHYSICAL = 0.8, BF_INCOMING_THERMAL = 1.5, BF_INCOMING_ASPHYXIA = 0)
	//radiation_mod = 0	//Can't be assed with fandangling rad protections while blob formed/suited
	darksight = 10
	siemens_coefficient = 2
	emp_dmg_mod = 0.8
	emp_sensitivity = EMP_BLIND | EMP_DEAFEN | EMP_BRUTE_DMG | EMP_BURN_DMG
	item_slowdown_mod = 1.5	//Gentle encouragement to let others wear you

	hazard_low_pressure = -1 //Space doesn't bother them

	cold_level_1 = -INFINITY
	cold_level_2 = -INFINITY
	cold_level_3 = -INFINITY
	heat_level_1 = 420
	heat_level_2 = 480
	heat_level_3 = 1100

	body_temperature = 290

	rarity_value = 5

	species_sounds = "Robotic"

	crit_mod = 4	//Unable to go crit
	body_plan = /datum/body/humanoid/nanoform
	species_component = list(/datum/component/forms/protean)

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	has_organ = list(
		O_BRAIN = /obj/item/organ/internal/mmi_holder/posibrain/nano,
		O_ORCH = /obj/item/organ/internal/nano/orchestrator,
		O_FACT = /obj/item/organ/internal/nano/refactory,
		)
	has_limbs = list(
		BP_TORSO =  list("path" = /obj/item/organ/external/chest/unbreakable/nano),
		BP_GROIN =  list("path" = /obj/item/organ/external/groin/unbreakable/nano),
		BP_HEAD =   list("path" = /obj/item/organ/external/head/unbreakable/nano),
		BP_L_ARM =  list("path" = /obj/item/organ/external/arm/unbreakable/nano),
		BP_R_ARM =  list("path" = /obj/item/organ/external/arm/right/unbreakable/nano),
		BP_L_LEG =  list("path" = /obj/item/organ/external/leg/unbreakable/nano),
		BP_R_LEG =  list("path" = /obj/item/organ/external/leg/right/unbreakable/nano),
		BP_L_HAND = list("path" = /obj/item/organ/external/hand/unbreakable/nano),
		BP_R_HAND = list("path" = /obj/item/organ/external/hand/right/unbreakable/nano),
		BP_L_FOOT = list("path" = /obj/item/organ/external/foot/unbreakable/nano),
		BP_R_FOOT = list("path" = /obj/item/organ/external/foot/right/unbreakable/nano)
		)

	heat_discomfort_strings = list("WARNING: Temperature exceeding acceptable thresholds!.")
	cold_discomfort_strings = list("You feel too cool.")

	// Power verbs (hotkeys) come from the protean power registry via the forms component.
	inherent_verbs = list(
		/mob/living/proc/set_size,
		/mob/living/carbon/human/proc/nano_change_fitting,
		/mob/living/carbon/human/proc/shapeshifter_select_hair,
		/mob/living/carbon/human/proc/shapeshifter_select_hair_colors,
		/mob/living/carbon/human/proc/shapeshifter_select_colour,
		/mob/living/carbon/human/proc/shapeshifter_select_eye_colour,
		/mob/living/carbon/human/proc/shapeshifter_select_gender,
		/mob/living/carbon/human/proc/shapeshifter_select_wings,
		/mob/living/carbon/human/proc/shapeshifter_select_tail,
		/mob/living/carbon/human/proc/shapeshifter_select_ears,
		/mob/living/carbon/human/proc/shapeshifter_select_secondary_ears,
		/mob/living/proc/flying_toggle,
		/mob/living/proc/flying_vore_toggle,
		/mob/living/proc/start_wings_hovering,
		) //removed fetish verbs, since non-customs can pick neutral traits now. Also added flight, cause shapeshifter can grow wings.

/datum/species/protean/create_organs(mob/living/carbon/human/H)
	var/obj/item/nif/saved_nif = H.nif
	if(saved_nif)
		H.nif.unimplant(H) //Needs reference to owner to unimplant right.
		H.nif.moveToNullspace()
	..()
	if(saved_nif && !ismannequin(H))
		saved_nif.quick_implant(H)

/datum/species/protean/get_race_key()
	var/datum/species/real = GLOB.all_species[base_species]
	return real.race_key

/datum/species/protean/get_bodytype(mob/living/carbon/human/H)
	if(!H || base_species == name) return ..()
	var/datum/species/S = GLOB.all_species[base_species]
	return S.get_bodytype(H)

/datum/species/protean/get_icobase(mob/living/carbon/human/H, get_deform)
	if(!H || base_species == name) return ..(null, get_deform)
	var/datum/species/S = GLOB.all_species[base_species]
	return S.get_icobase(H, get_deform)

/datum/species/protean/get_valid_shapeshifter_forms(mob/living/carbon/human/H)
	var/list/protean_shapeshifting_forms = GLOB.playable_species.Copy() - SPECIES_PROMETHEAN //Removing the 'static' here fixes it returning an empty list. I do not know WHY that is the case, but it is for some reason. This needs to be investigated further, but this fixes the issue at the moment.
	return protean_shapeshifting_forms

/datum/species/protean/get_tail(mob/living/carbon/human/H)
	if(!H || base_species == name) return ..()
	var/datum/species/S = GLOB.all_species[base_species]
	return S.get_tail(H)

/datum/species/protean/get_tail_animation(mob/living/carbon/human/H)
	if(!H || base_species == name) return ..()
	var/datum/species/S = GLOB.all_species[base_species]
	return S.get_tail_animation(H)

/datum/species/protean/get_tail_hair(mob/living/carbon/human/H)
	if(!H || base_species == name) return ..()
	var/datum/species/S = GLOB.all_species[base_species]
	return S.get_tail_hair(H)

/datum/species/protean/get_blood_mask(mob/living/carbon/human/H)
	if(!H || base_species == name) return ..()
	var/datum/species/S = GLOB.all_species[base_species]
	return S.get_blood_mask(H)

/datum/species/protean/get_damage_mask(mob/living/carbon/human/H)
	if(!H || base_species == name) return ..()
	var/datum/species/S = GLOB.all_species[base_species]
	return S.get_damage_mask(H)

/datum/species/protean/get_damage_overlays(mob/living/carbon/human/H)
	if(!H || base_species == name) return ..()
	var/datum/species/S = GLOB.all_species[base_species]
	return S.get_damage_overlays(H)

/datum/species/protean/handle_post_spawn(mob/living/carbon/human/H)
	..()
	H.synth_color = TRUE

/datum/species/protean/equip_survival_gear(mob/living/carbon/human/H)
	..()
	var/obj/item/stack/material/steel/metal_stack = new(null, 5)

	var/obj/item/clothing/accessory/permit/nanotech/permit = new()
	permit.set_name(H.real_name)

	if(H.backbag == 1) //Somewhat misleading, 1 == no bag (not boolean)
		H.equip_to_slot_or_del(permit, slot_l_hand)
		H.equip_to_slot_or_del(metal_stack, slot_r_hand)
	else
		H.equip_to_slot_or_del(permit, slot_in_backpack)
		H.equip_to_slot_or_del(metal_stack, slot_in_backpack)

	addtimer(CALLBACK(src, PROC_REF(finish_survival_gear), H), 1) //Let their real nif load if they have one

/datum/species/protean/proc/finish_survival_gear(mob/living/carbon/human/H)
	if(QDELETED(H)) //Observing, mannequins, etc. can delete the human first.
		return
	if(!H.nif)
		var/obj/item/nif/protean/new_nif = new()
		new_nif.quick_implant(H)
	else
		H.nif.durability = 25
	new /obj/item/rig/protean(H, H)

/datum/species/protean/hug(mob/living/carbon/human/H, mob/living/target)
	return ..() //Wut

/datum/species/protean/get_blood_colour(mob/living/carbon/human/H)
	return rgb(80,80,80,230)

/datum/species/protean/get_flesh_colour(mob/living/carbon/human/H)
	return rgb(80,80,80,230)

/datum/species/protean/get_additional_examine_text(mob/living/carbon/human/H)
	return ..() //Hmm, what could be done here?

/datum/species/protean/update_misc_tabs(mob/living/carbon/human/H)
	..()
	var/list/L = list()
	var/obj/item/organ/internal/nano/refactory/refactory = H.nano_get_refactory()
	if(refactory && !(refactory.status & ORGAN_DEAD))
		L[++L.len] = list("- -- --- Refactory Metal Storage --- -- -", null, null, null, null)
		var/max = refactory.max_storage
		for(var/material in refactory.materials)
			var/amount = refactory.get_stored_material(material)
			L[++L.len] = list("[capitalize(material)]: [amount]/[max]", null, null, null, null)
	else
		L[++L.len] = list("- -- --- REFACTORY ERROR! --- -- -", null, null, null, null)

	L[++L.len] = list("- -- --- Abilities (Shift+LMB Examines) --- -- -", null, null, null, null)
	var/client/C = H.client
	var/list/powers = protean_powers()
	for(var/power_type in powers)
		var/datum/protean_power/P = powers[power_type]
		if(!P.button)
			continue
		var/img
		if(C)
			img = LAZYACCESS(C.misc_cache, P.name)
			if(!img)
				img = icon2html(P.button, C, sourceonly = TRUE)
				LAZYSET(C.misc_cache, P.name, img)
		L[++L.len] = list("[P.name]", P.name, img, P.button, REF(P.button))
	H.misc_tabs["Protean"] = L

// PAN Card
/obj/item/clothing/accessory/permit/nanotech
	name = "\improper P.A.N. card"
	desc = "This is a 'Permit for Advanced Nanotechnology' card. It allows the owner to possess and operate advanced nanotechnology on NanoTrasen property. It must be renewed on a monthly basis."
	icon = 'icons/mob/species/protean/protean.dmi'
	icon_state = "permit_pan"

	var/validstring = "VALID THROUGH END OF: "
	var/registring = "REGISTRANT: "

/obj/item/clothing/accessory/permit/nanotech/set_name(new_name)
	owner = 1
	if(new_name)
		name += " ([new_name])"
		validstring += "[time2text(world.timeofday, "Month") +" "+ num2text(text2num(time2text(world.timeofday, "YYYY"))+544)]"
		registring += "[new_name]"

/obj/item/clothing/accessory/permit/nanotech/examine(mob/user)
	. = ..()
	. += validstring
	. += registring
