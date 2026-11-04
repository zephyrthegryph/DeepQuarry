/*
 * Toy chainsaw
 */
/obj/item/toy/chainsaw
	name = "Toy Chainsaw"
	desc = "A toy chainsaw with a rubber edge. Ages 8 and up"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "chainsaw0"
	var/cooldown = 0

CAPABILITIES(/obj/item/toy/chainsaw)
	configure(movable_motion(throw_range = 20, throw_speed = 4))
	configure(item_thrown(force = 0))
	configure(item_combat(force = 0, attack_verbs = list("sawed", "cut", "hacked", "carved", "cleaved", "butchered", "felled", "timbered")))
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/chainsaw/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!cooldown)
		play_sfx(user, SFX_WEAPONS_CHAINSAW_STARTUP)
		cooldown = 1
		after(src, 5 SECONDS, PROC_REF(cooldownreset))
	return TRUE

/obj/item/toy/chainsaw/proc/cooldownreset()
	cooldown = 0
