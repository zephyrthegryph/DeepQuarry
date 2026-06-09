/obj/item/melee/chainofcommand
	name = "chain of command"
	desc = "A tool used by great men to placate the frothing masses."
	icon_state = "chain"
	slot_flags = SLOT_BELT
	force = 10
	throwforce = 7
	w_class = ITEMSIZE_NORMAL
	attack_verb = list("flogged", "whipped", "lashed", "disciplined")
	hitsound = 'sound/weapons/whip.ogg'
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

/obj/item/melee/umbrella/Initialize(mapload)
	. = ..()
	update_icon()

/obj/item/melee/umbrella/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	toggle_umbrella()

/obj/item/melee/umbrella/proc/toggle_umbrella()
	open = !open
	icon_state = "umbrella_[open ? "open" : "closed"]"
	addblends = icon_state + "_a"
	item_state = icon_state
	update_icon()
	if(ishuman(src.loc))
		var/mob/living/carbon/human/H = src.loc
		H.update_inv_l_hand(0)
		H.update_inv_r_hand()

// Randomizes color
/obj/item/melee/umbrella/random/Initialize(mapload)
	. = ..()
	color = get_random_colour()

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
	attack_verb = list("attacked", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut")
	hitsound = 'sound/weapons/bladeslice.ogg'
	can_speak = 1
	var/list/voice_mobs = list() //The curse of the sword is that it has someone trapped inside.


/obj/item/melee/cursedblade/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	if(default_parry_check(user, attacker, damage_source) && prob(50))
		user.visible_message(span_danger("\The [user] parries [attack_text] with \the [src]!"))
		playsound(src, 'sound/weapons/punchmiss.ogg', 50, 1)
		return 1
	return 0

/obj/item/melee/cursedblade/proc/ghost_inhabit(mob/candidate)
	if(!isobserver(candidate))
		return
	//Handle moving the ghost into the new shell.
	announce_ghost_joinleave(candidate, 0, "They are occupying a cursed sword now.")
	var/mob/living/voice/new_voice = new /mob/living/voice(src) 	//Make the voice mob the ghost is going to be.
	new_voice.transfer_identity(candidate) 	//Now make the voice mob load from the ghost's active character in preferences.
	new_voice.mind = candidate.mind			//Transfer the mind, if any.
	new_voice.ckey = candidate.ckey			//Finally, bring the client over.
	new_voice.name = "cursed sword"			//Cursed swords shouldn't be known characters.
	new_voice.real_name = "cursed sword"
	voice_mobs.Add(new_voice)
	GLOB.listening_objects |= src


// === merged from misc_vr.dm during hard-fork de-suffix (verified no override-order change) ===
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
	attack_verb = list("stabbed", "lunged at", "dextrously struck", "sliced", "lacerated", "impaled", "diced", "charioted")
	hitsound = 'sound/weapons/bladeslice.ogg'

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
				qdel(A)
