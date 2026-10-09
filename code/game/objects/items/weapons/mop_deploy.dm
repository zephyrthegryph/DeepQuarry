/obj/item/mop_deploy
	name = "mop"
	desc = "Deployable mop."
	icon = 'icons/obj/janitor.dmi'
	icon_state = "mop"
	item_flags = DROPDEL | NOSTRIP
	force = 3
	anchored = TRUE    // Never spawned outside of inventory, should be fine.
	throwforce = 1  //Throwing or dropping the item deletes it.
	throw_speed = 1
	throw_range = 1
	w_class = ITEMSIZE_LARGE//So you can't hide it in your pocket or some such.
	attack_verb = list("mopped", "bashed", "bludgeoned", "whacked")
	var/mob/living/creator
	var/mopping = 0
	var/mopcount = 0


/turf/proc/clean_deploy(atom/source)
	if(source.reagents.has_reagent(REAGENT_ID_WATER, 1))
		wash(CLEAN_SCRUB)
		if(istype(src, /turf/simulated))
			var/turf/simulated/T = src
			T.dirt = 0
		for(var/obj/effect/O in turf_contents_of_type(src, /obj/effect))
			if(istype(O,/obj/effect/rune) || istype(O,/obj/effect/decal/cleanable) || istype(O,/obj/effect/overlay))
				consume(O)
/*	//Reagent code changed at some point and the below doesn't work.  To be fixed later.
	source.reagents.reaction(src, TOUCH, 10)	//10 is the multiplier for the reaction effect. probably needed to wet the floor properly.
	source.reagents.remove_any(1)				//reaction() doesn't use up the reagents
*/
MSG_DEF(mop_deploy/cleaning, null, span_warning("%U% begins to clean the floor."))

/obj/item/mop_deploy/proc/mopped(datum/act/op/A)
	var/turf/T = get_turf(A.target)
	if(T)
		T.clean_deploy(src)
	to_chat(A.actor, span_notice("You have finished mopping!"))
	return OP_OK

// Mops and soap on an effect (decals, runes, overlays) go straight to their afterattack
// cleaning: nothing else about the effect (signals, less specific interactions) reacts.
CAPABILITIES(/obj/effect)
	// effects are not things to swing at: a decal, a spark, a gas cloud (the few that take a blow, the web and the weeds, declare melee_hit again)
	without("melee_hit")
	op("pass_insert", item(/obj/item/mop_deploy), label("Insert a mop"), passes())
	op("pass_insert_2", item(/obj/item/soap), label("Insert a soap"), passes())

CAPABILITIES(/obj/item/mop_deploy)
	reagents(5)
	after_init(1, then(PROC_REF(check_held))) // after the hand that made it has taken it
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	op("mop", at_target(/turf), at_target(/obj/effect/decal/cleanable), at_target(/obj/effect/overlay), at_target(/obj/effect/rune), begins(MSG(mop_deploy/cleaning)), wait(4 SECONDS), then(PROC_REF(mopped)))

/// Old attack_self.
/obj/item/mop_deploy/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	user.drop_from_inventory(src)
	expire(1)
	return TRUE

/// Goes away once it leaves its creator's hands: checked after it is made, dropped or moved
/// between hands, never polled.
/obj/item/mop_deploy/proc/check_held(datum/act/A)
	if(!creator() || loc != creator() || !creator().item_is_in_hands(src))
		// Tidy up a bit.
		if(isliving(loc))
			var/mob/living/carbon/human/host = loc
			if(istype(host))
				for(var/obj/item/organ/external/organ in host.organs)
					for(var/obj/item/O in organ.implants)
						if(O == src)
							rel_remove(organ, nameof(organ.implants), src)
			rel_remove(host, nameof(host.pinned), src)
			LAZYREMOVE(host.embedded, src)
			host.drop_from_inventory(src)
		expire(1)

/obj/item/mop_deploy/dropped(mob/user, equipping, slot)
	. = ..()
	after(src, 0, PROC_REF(check_held))

/obj/item/mop_deploy/equipped(mob/user, slot)
	. = ..()
	after(src, 0, PROC_REF(check_held))

/// Relation view: creator (reads null once it is gone).
/obj/item/mop_deploy/proc/creator() as /mob/living
	return creator
