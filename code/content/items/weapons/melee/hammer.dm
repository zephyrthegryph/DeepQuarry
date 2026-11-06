/obj/item/melee/hammer
	name = "claw hammer"
	desc = "A simple claw hammer for hitting things or people with, and the claw part probably does something too."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "claw_hammer"
	w_class = ITEMSIZE_SMALL
	defend_chance = 0

CAPABILITIES(/obj/item/melee/hammer)
	configure(item_thrown(force = 10))
	configure(item_combat(force = 15, attack_verbs = list("smashed", "swung at", "pummelled", "nailed", "crushed", "bonked", "hammered", "cracked")))

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
