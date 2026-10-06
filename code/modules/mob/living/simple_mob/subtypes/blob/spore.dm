// Spores are made from blob factories.
// They are very weak and expendable, but can overwhelm when a lot of them are together.
// When attacking, spores will hit harder if near other friendly spores.
// Some blobs can infest dead non-robotic mobs, making them into Not Zombies.

/mob/living/simple_mob/blob/spore
	name = "blob spore"
	desc = "A floating, fragile spore."

	icon_state = "blobpod"
	icon_living = "blobpod"
	glow_range = 3
	glow_intensity = 5
	layer = ABOVE_MOB_LAYER // Over the blob.

	endurance = 30
	melee_damage_lower = 2
	melee_damage_upper = 4
	movement_cooldown = -2
	// dq_get_hovering(src) type-default moved to GLOB.dq_hovering_by_type

	attacktext = list("slammed into")
	attack_sound = SFX_EFFECTS_SLIME_SQUISH
	say_list_type = /datum/say_list/spore

	organ_names = /datum/decl/mob_organ_names/spore

	var/mob/living/carbon/human/infested = null // The human this thing is totally not making into a zombie.
	var/can_infest = FALSE
	var/is_infesting = FALSE

	can_pain_emote = FALSE

CAPABILITIES(/mob/living/simple_mob/blob/spore)
	param(nameof(factory), /obj/structure/blob/factory, pos = 1)

/datum/say_list/spore
	emote_see = list("sways", "inflates briefly")

/datum/say_list/infested
	emote_see = list("shambles around", "twitches", "stares")

/mob/living/simple_mob/blob/spore/infesting
	name = "infesting blob spore"
	can_infest = TRUE

/mob/living/simple_mob/blob/spore/weak
	name = "fragile blob spore"
	endurance = 15
	melee_damage_lower = 1
	melee_damage_upper = 2


// Destroy() drops the body out before letting go.

// the infested body falls out as the spore bursts.
/mob/living/simple_mob/blob/spore/on_destroy(force)
	if(infested)
		infested.forceMove(get_turf(src))
		visible_message(span_warning("\The [infested] falls to the ground as the blob spore bursts.")) // ALLOW(decl): message names the infested mob
	..()

/mob/living/simple_mob/blob/spore
	delete_on_death = TRUE
	death_message = "bursts!"

/mob/living/simple_mob/blob/spore/on_death(gibbed)
	. = ..()
	if(overmind)
		overmind.blob_type.on_spore_death(src)

/mob/living/simple_mob/blob/spore/update_icons()
	..() // This will cut our overlays.

	if(overmind)
		color = overmind.blob_type.complementary_color
		set_glow_color(color)
		set_glow_toggle(TRUE)
	else if(blob_type)
		color = blob_type.complementary_color
		set_glow_color(color)
		set_glow_toggle(TRUE)
	else
		color = null
		set_glow_color(null)
		set_glow_toggle(FALSE)

	if(is_infesting)
		icon = infested.icon
		copy_overlays(infested)
		var/mutable_appearance/blob_head_overlay = mutable_appearance('icons/mob/blob.dmi', "blob_head")
		if(overmind)
			blob_head_overlay.color = overmind.blob_type.complementary_color
		color = initial(color)//looks better.
		add_overlay(blob_head_overlay)

/mob/living/simple_mob/blob/spore/life_special_due()
	return TRUE

/mob/living/simple_mob/blob/spore/life_special(datum/seq_frame/life/F)
	..()
	if(src.can_infest && !src.is_infesting && isturf(src.loc))
		for(var/mob/living/carbon/human/H in view(src,1))
			if(H.stat != DEAD) // We want zombies.
				continue
			if(HAS_SYNTHETIC_BIOLOGY(H)) // Not philosophical zombies.
				continue
			src.infest(H)
			break

	if(src.overmind)
		src.overmind.blob_type.on_spore_lifetick(src)

	if(src.factory && src.z != src.factory.z) // This is to prevent spores getting lost in space and making the factory useless.
		spent(src)

/mob/living/simple_mob/blob/spore/proc/infest(mob/living/carbon/human/H)
	is_infesting = TRUE
	endurance += H.body?.worn_armor(UPPER_TORSO, MELEE) //That zombie's got armor, I want armor!

	endurance += 40
	fully_heal()
	name = "Infested [H.real_name]" // Not using the Z word.
	desc = "A parasitic organism attached to a deceased body, controlling it directly as if it were a puppet."
	melee_damage_lower += 8  // 10 total.
	melee_damage_upper += 11 // 15 total.
	attacktext = list("clawed")

	H.forceMove(src)
	rel_set(src, nameof(infested), H)

	rel_set(src, nameof(say_list), new /datum/say_list/infested())

	update_icons()
	visible_message(span_warning("The corpse of [H.name] suddenly rises!"))

/mob/living/simple_mob/blob/spore/GetIdCard()
	if(infested) // If we've infested someone, use their ID.
		return infested.GetIdCard()

/mob/living/simple_mob/blob/spore/apply_bonus_melee_damage(A, damage_to_do)
	var/helpers = 0
	for(var/mob/living/simple_mob/blob/spore/S in view(1, src))
		if(S == src) // Don't count ourselves.
			continue
		if(!IIsAlly(S)) // Only friendly spores make us stronger.
			continue
		// Friendly spores contribute 1/4th of their averaged attack power to our attack.
		damage_to_do += ((S.melee_damage_lower + S.melee_damage_upper) / 2) / 4
		helpers++

	if(helpers)
		to_chat(src, span_notice("Your attack is assisted by [helpers] other spore\s."))
	return damage_to_do

/datum/decl/mob_organ_names/spore
TYPE_TABLE(/datum/decl/mob_organ_names/spore, mob_organ_hit_zones, list("sporangium", "stolon", "sporangiophore"))
