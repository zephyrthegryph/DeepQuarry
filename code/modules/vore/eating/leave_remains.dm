/datum/species
	var/skull_type = /obj/item/digestion_remains/skull
/datum/species/tajaran
	skull_type = /obj/item/digestion_remains/skull/tajaran
/datum/species/unathi
	skull_type = /obj/item/digestion_remains/skull/unathi
/datum/species/skrell
	skull_type = /obj/item/digestion_remains/skull/skrell
/datum/species/spider
	skull_type = /obj/item/digestion_remains/skull/vasilissan
/datum/species/akula
	skull_type = /obj/item/digestion_remains/skull/akula
/datum/species/harpy
	skull_type = /obj/item/digestion_remains/skull/rapala
/datum/species/vulpkanin
	skull_type = /obj/item/digestion_remains/skull/vulpkanin
/datum/species/sergal
	skull_type = /obj/item/digestion_remains/skull/sergal
/datum/species/hi_zorren
	skull_type = /obj/item/digestion_remains/skull/zorren
/datum/species/nevrean
	skull_type = /obj/item/digestion_remains/skull/nevrean
/datum/species/teshari
	skull_type = /obj/item/digestion_remains/skull/teshari
/datum/species/vox
	skull_type = /obj/item/digestion_remains/skull/vox
/datum/species/monkey
	skull_type = /obj/item/digestion_remains/skull
/datum/species/monkey/tajaran
	skull_type = /obj/item/digestion_remains/skull/tajaran
/datum/species/monkey/unathi
	skull_type = /obj/item/digestion_remains/skull/unathi
/datum/species/monkey/skrell
	skull_type = /obj/item/digestion_remains/skull/skrell
/datum/species/monkey/shark
	skull_type = /obj/item/digestion_remains/skull/akula
/datum/species/monkey/sparra
	skull_type = /obj/item/digestion_remains/skull/rapala
/datum/species/monkey/vulpkanin
	skull_type = /obj/item/digestion_remains/skull/vulpkanin
/datum/species/monkey/sergal
	skull_type = /obj/item/digestion_remains/skull/sergal

/obj/belly/proc/handle_remains_leaving(mob/living/M)
	if(!isliving(M))	//Are we even a living thing? (Sorry ghosts)
		return
	//Moving some vars here for both borgs and carbons to use
	var/bones_amount = rand(2,4) //some random variety in amount of bones left
	if(isrobot(M)) //If borg, handle differently

		var/list/borg_bones = list( //Borg bones are the same at this point. might change in the future if borgs or synths get
			/obj/item/digestion_remains/synth, // different remains in the future.
			/obj/item/digestion_remains/synth/variant1,
			/obj/item/digestion_remains/synth/variant2,
			/obj/item/digestion_remains/synth/variant3
		)
		for(var/i = 1, i <= bones_amount, i++)	//Just fill them with bones. Borgs dont have anything special.
			var/new_bone = pick(borg_bones)
			new new_bone(src,owner)
		return //Dont need to do carbon stuff after this

	if(ismouse(M)) //Mice dont have massive bones to leave behind
		return
	if(isanimal(M)) //If they are a simplemob
		var/list/organic_bones = list( //Generic bone variation system
			/obj/item/digestion_remains,
			/obj/item/digestion_remains/variant1,
			/obj/item/digestion_remains/variant2,
			/obj/item/digestion_remains/variant3
		)
		for(var/i = 1, i <= bones_amount, i++)
			var/new_bone = pick(organic_bones)
			new new_bone(src,owner)
		return


	var/mob/living/carbon/human/H = M

	if((H.species.name in GLOB.remainless_species))	//Don't leave anything if there is nothing to leave
		return

	if(prob(20) && !HAS_SYNTHETIC_BIOLOGY(H))	//ribcage surviving whole is some luck //Edit: no robor
		new /obj/item/digestion_remains/ribcage(src,owner)
		bones_amount--

	var/list/organic_bones = list( //Generic bone variation system
		/obj/item/digestion_remains,
		/obj/item/digestion_remains/variant1,
		/obj/item/digestion_remains/variant2,
		/obj/item/digestion_remains/variant3
	)
	var/list/synthetic_bones = list(
		/obj/item/digestion_remains/synth,
		/obj/item/digestion_remains/synth/variant1,
		/obj/item/digestion_remains/synth/variant2,
		/obj/item/digestion_remains/synth/variant3
	)
	for(var/i = 1, i <= bones_amount, i++)	//throw in the rest
		var/new_bone = HAS_SYNTHETIC_BIOLOGY(H) ? pick(synthetic_bones) : pick(organic_bones)
		new new_bone(src,owner)

	if(HAS_SYNTHETIC_BIOLOGY(H)) // Synths dont have skulls, atleast not any that survive digestion.
		return			// TODO: add synth skulls and remove this.
	var/skull_amount = 1
	if(H.species.skull_type)
		new H.species.skull_type(src, owner, H)
		skull_amount--

	if(skull_amount && H.species.selects_bodytype)
		// We still haven't found correct skull...
		if(H.species.base_species == SPECIES_HUMAN)
			new /obj/item/digestion_remains/skull/unknown(src, owner, H)
		else
			new /obj/item/digestion_remains/skull/unknown/anthro(src, owner, H)
	else if(skull_amount)
		// Something entirely different...
		new /obj/item/digestion_remains/skull/unknown(src, owner, H)


/obj/item/digestion_remains
	name = "bone"
	desc = "A bleached bone. It's very non-descript and its hard to tell what species or part of the body it came from."
	icon = 'icons/obj/bones_vr.dmi'
	icon_state = "generic-1"
	drop_sound = SFX_ITEMS_DROP_WOODEN   //sounds kinda like a bone
	pickup_sound = SFX_ITEMS_PICKUP_WOODWEAPON
	force = 0
	throwforce = 0
	item_state = "bone"
	w_class = ITEMSIZE_SMALL
	var/pred_ckey
	var/pred_name

/obj/item/digestion_remains/synth
	name = "ruined component"
	desc = "A ruined component. It seems to have come from some sort of robotic entity, but there's no telling what kind."
	icon_state = "synth-1"
	drop_sound = SFX_ITEMS_DROP_DEVICE   //not organic bones, so they get different sounds
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE

/// Who digested whom (its constructor params, dropped once noted).
/obj/item/digestion_remains/var/tmp/mob/living/pred_at_make
/obj/item/digestion_remains/var/tmp/mob/living/prey_at_make

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). The remains note their predator and keep the prey's size.
/obj/item/digestion_remains/proc/note_meal(mob/living/prey)
	var/mob/living/pred = pred_at_make
	if(!pred && !prey)
		return
	pred_ckey = pred?.ckey
	pred_name = pred?.name
	if(prey && isliving(prey) && prey.size_multiplier != 1)
		icon_scale_x = prey.size_multiplier
		icon_scale_y = prey.size_multiplier
		update_transform()

CAPABILITIES(/obj/item/digestion_remains)
	op("remains_crumble_self", in_hand(), stance(I_HURT), label("Crumble"), then(PROC_REF(remains_crumble_self)))
	param(nameof(pred_at_make), pos = 1, keep = FALSE)
	param(nameof(prey_at_make), pos = 2, apply = PROC_REF(note_meal), keep = FALSE)

/// Old attack_self: squeezed in combat mode, the remains crumble away.
/obj/item/digestion_remains/proc/remains_crumble_self(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user,span_warning("As you squeeze the [name], it crumbles into dust and falls apart into nothing!"))
	consume(src, user)
	return TRUE

/obj/item/digestion_remains/ribcage
	name = "ribcage"
	desc = "A bleached ribcage. It's very white and definitely has seen better times. Hard to tell what it belonged to."
	icon_state = "ribcage"

/obj/item/digestion_remains/variant1 //Generic bone variations
	icon_state = "generic-2"

/obj/item/digestion_remains/variant2
	icon_state = "generic-3"

/obj/item/digestion_remains/variant3
	icon_state = "generic-4"

/obj/item/digestion_remains/synth/variant1 //synthbones start
	icon_state = "synth-2"

/obj/item/digestion_remains/synth/variant2
	icon_state = "synth-3"

/obj/item/digestion_remains/synth/variant3
	icon_state = "synth-4"

/obj/item/digestion_remains/skull
	name = "skull"
	desc = "A bleached skull. It looks very weakened. Seems like it belonged to a human."
	icon_state = "skull"

/obj/item/digestion_remains/skull/tajaran
	desc = "A bleached skull. It looks very weakened. Seems like it belonged to a tajara."
	icon_state = "skull_taj"

/obj/item/digestion_remains/skull/unathi
	desc = "A bleached skull. It looks very weakened. Seems like it belonged to an unathi."
	icon_state = "skull_unathi"

/obj/item/digestion_remains/skull/skrell
	desc = "A bleached skull. It looks very weakened. Seems like it belonged to a skrell."
	icon_state = "skull"

/obj/item/digestion_remains/skull/vasilissan
	desc = "A bleached skull. It looks very weakened. Seems like it belonged to a vasilissan."
	icon_state = "skull"

/obj/item/digestion_remains/skull/akula
	desc = "A bleached skull. It looks very weakened. Seems like it belonged to an akula."
	icon_state = "skull_unathi"

/obj/item/digestion_remains/skull/rapala
	desc = "A bleached skull. It looks very weakened. Seems like it belonged to a rapala."
	icon_state = "skull"

/obj/item/digestion_remains/skull/vulpkanin
	desc = "A bleached skull. It looks very weakened. Seems like it belonged to a vulpkanin."
	icon_state = "skull_taj"

/obj/item/digestion_remains/skull/sergal
	desc = "A bleached skull. It looks very weakened. Seems like it belonged to a sergal."
	icon_state = "skull_taj"

/obj/item/digestion_remains/skull/zorren
	desc = "A bleached skull. It looks very weakened. Seems like it belonged to a zorren."
	icon_state = "skull_taj"

/obj/item/digestion_remains/skull/nevrean
	desc = "A bleached skull. It looks very weakened. Seems like it belonged to a nevrean."
	icon_state = "skull_taj"

/obj/item/digestion_remains/skull/teshari
	desc = "A bleached skull. It looks very weakened. Seems like it belonged to a teshari."
	icon_state = "skull_taj"

/obj/item/digestion_remains/skull/vox
	desc = "A bleached skull. It looks very weakened. Seems like it belonged to a vox."
	icon_state = "skull_taj"

/obj/item/digestion_remains/skull/unknown
	desc = "A bleached skull. It looks very weakened. You can't quite tell what species it belonged to."
	icon_state = "skull"

/obj/item/digestion_remains/skull/unknown/anthro
	icon_state = "skull_taj"
