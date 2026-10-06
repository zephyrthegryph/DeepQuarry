/obj/item/melee/chainofcommand
	name = "chain of command"
	desc = "A tool used by great men to placate the frothing masses."
	icon_state = "chain"
	slot_flags = SLOT_BELT
	force = 10
	throwforce = 7
	w_class = ITEMSIZE_NORMAL
	attack_verb = list("flogged", "whipped", "lashed", "disciplined")
	hitsound = SFX_WEAPONS_WHIP
	reach = 2

/obj/item/melee/chainofcommand/curator_whip
	name = "leather whip"
	desc = "A fine weapon for some treasure hunting."
	icon_state = "curator_whip"
	force = 5
	throwforce = 5

/obj/item/melee/chainofcommand/curator_whip/toy
	name = "toy whip"
	desc = "A fake whip. Perfect for fake treasure hunting"
	force = 2
	throwforce = 2

/obj/item/melee/umbrella
	name = "umbrella"
	desc = "To keep the rain off you. Use with caution on windy days."
	icon = 'icons/obj/items.dmi'
	icon_state = "umbrella_closed"
	addblends = "umbrella_closed_a"
	slot_flags = SLOT_BELT
	force = 5
	throwforce = 5
	w_class = ITEMSIZE_NORMAL
	var/open = FALSE

TRACKED(/obj/item/melee/umbrella, open)

CAPABILITIES(/obj/item/melee/umbrella)
	op("toggle", in_hand(), label("Open or close umbrella"), then(PROC_REF(umbrella_toggled)))

/// The native held-item activation preserves the complete equipment change.
/obj/item/melee/umbrella/proc/umbrella_toggled(datum/act/op/A)
	toggle_umbrella()
	return OP_OK

/obj/item/melee/umbrella/proc/toggle_umbrella()
	set_open(!open)
	icon_state = "umbrella_[open ? "open" : "closed"]"
	addblends = icon_state + "_a"
	item_state = icon_state
	if(ishuman(src.loc))
		var/mob/living/carbon/human/H = src.loc
		H.update_inv_l_hand(0)
		H.update_inv_r_hand()

CAPABILITIES(/obj/item/melee/umbrella/random)
	rolls(nameof(color), PROC_REF(roll_color))

/// Rolled before init (rolls()): any colour (get_random_colour()'s distribution).
/obj/item/melee/umbrella/random/proc/roll_color(datum/roller/R)
	return R.hex_colour()

/obj/item/melee/cursedblade
	name = "crystal blade"
	desc = "The red crystal blade's polished surface glints in the light, giving off a faint glow."
	icon_state = "soulblade"
	slot_flags = SLOT_BELT | SLOT_BACK
	force = 30
	throwforce = 10
	w_class = ITEMSIZE_NORMAL
	sharp = TRUE
	edge = TRUE
	injury_kind = INJURY_CUT
	attack_verb = list("attacked", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut")
	hitsound = SFX_WEAPONS_BLADESLICE
	can_speak = 1
	var/list/voice_mobs //The curse of the sword is that it has someone trapped inside.

CAPABILITIES(/obj/item/melee/cursedblade)
	owns_many(nameof(voice_mobs))


/obj/item/melee/cursedblade/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	if(default_parry_check(user, attacker, damage_source) && prob(50))
		act_message(user, src, others = span_danger("%U% parries [attack_text] with %T%!"))
		play_sfx(src, SFX_WEAPONS_PUNCHMISS, 2, extrarange = 0)
		return 1
	return 0

/obj/item/melee/cursedblade/proc/ghost_inhabit(mob/candidate)
	if(!isobserver(candidate))
		return
	//Handle moving the ghost into the new shell.
	announce_ghost_joinleave(candidate, 0, "They are occupying a cursed sword now.")
	var/mob/living/voice/new_voice = new /mob/living/voice(src) 	//Make the voice mob the ghost is going to be.
	new_voice.transfer_identity(candidate) 	//Now make the voice mob load from the ghost's active character in preferences.
	rel_set(new_voice, nameof(new_voice.mind), candidate.mind) //Transfer the mind, if any.
	new_voice.ckey = candidate.ckey			//Finally, bring the client over.
	new_voice.name = "cursed sword"			//Cursed swords shouldn't be known characters.
	new_voice.real_name = "cursed sword"
	rel_add(src, nameof(voice_mobs), new_voice)
	registry_join(REGISTRY_LISTENING_OBJECTS, src)


/obj/item/melee/rapier
	name = "rapier"
	desc = "A gleaming steel blade with a gold handguard and inlayed with an outstanding red gem."
	icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "rapier"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_melee_vr.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_melee_vr.dmi',
		)
	force = 15
	throwforce = 10
	w_class = ITEMSIZE_NORMAL
	sharp = TRUE
	edge = FALSE
	injury_kind = INJURY_PIERCE
	attack_verb = list("stabbed", "lunged at", "dextrously struck", "sliced", "lacerated", "impaled", "diced", "charioted")
	hitsound = SFX_WEAPONS_BLADESLICE

/obj/item/melee/hammer
	name = "claw hammer"
	desc = "A simple claw hammer for hitting things or people with, and the claw part probably does something too."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "claw_hammer"
	force = 15
	throwforce = 10
	w_class = ITEMSIZE_SMALL
	attack_verb = list("smashed", "swung at", "pummelled", "nailed", "crushed", "bonked", "hammered", "cracked")
	defend_chance = 0

/obj/item/melee/hammer/apply_hit_effect(mob/living/target, mob/living/user, hit_zone, attack_modifier)
	if(ishuman(target))
		var/mob/living/carbon/human/H = target
		if(prob(50))
			var/obj/item/organ/external/affecting = H.get_organ(hit_zone)
			affecting.fracture()
	return ..()

/obj/item/melee/hammer/afterattack(atom/A as mob|obj|turf|area, mob/user as mob, proximity)
	if(!proximity) return
	..()
	if(A)
		if(istype(A,/obj/structure/window))
			var/obj/structure/window/W = A
			if(prob(50))
				W.visible_message(span_warning("\The [W] shatters under the force of the impact!"))
				W.shatter()
		else if(istype(A,/obj/structure/barricade))
			var/obj/structure/barricade/B = A
			if(prob(50))
				B.visible_message(span_warning("\The [B] is broken apart with ease!"))
				B.dismantle()
		else if(istype(A,/obj/structure/grille))
			if(prob(50))
				A.visible_message(span_warning("\The [A] is smashed open!"))
				consumed(A, src)
