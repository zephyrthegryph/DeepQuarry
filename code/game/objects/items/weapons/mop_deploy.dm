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
	var/creator_handle
	var/mopping = 0
	var/mopcount = 0

/obj/item/mop_deploy/Initialize(mapload)
	. = ..()
	create_reagents(5)
	om_after(src, 0, PROC_REF(check_held))

/turf/proc/clean_deploy(atom/source)
	if(source.reagents.has_reagent(REAGENT_ID_WATER, 1))
		wash(CLEAN_SCRUB)
		if(istype(src, /turf/simulated))
			var/turf/simulated/T = src
			T.dirt = 0
		for(var/obj/effect/O in turf_contents_of_type(src, /obj/effect))
			if(istype(O,/obj/effect/rune) || istype(O,/obj/effect/decal/cleanable) || istype(O,/obj/effect/overlay))
				qdel(O)
/*	//Reagent code changed at some point and the below doesn't work.  To be fixed later.
	source.reagents.reaction(src, TOUCH, 10)	//10 is the multiplier for the reaction effect. probably needed to wet the floor properly.
	source.reagents.remove_any(1)				//reaction() doesn't use up the reagents
*/
/obj/item/mop_deploy/afterattack(atom/A, mob/user, proximity)
	if(!proximity) return
	if(istype(A, /turf) || istype(A, /obj/effect/decal/cleanable) || istype(A, /obj/effect/overlay) || istype(A, /obj/effect/rune))
		user.visible_message(span_warning("[user] begins to clean \the [get_turf(A)]."))

		om_do_after(user, 4 SECONDS, target = src, receiver = src, on_done = PROC_REF(afterattack_timed_done), done_args = list(A, user))

/obj/item/mop_deploy/proc/afterattack_timed_done(atom/A, mob/user)
	var/turf/T = get_turf(A)
	if(T)
		T.clean_deploy(src)
	to_chat(user, span_notice("You have finished mopping!"))

/obj/effect/attackby(obj/item/I, mob/user)
	if(istype(I, /obj/item/mop_deploy) || istype(I, /obj/item/soap))
		return
	..()

/obj/item/mop_deploy/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	user.drop_from_inventory(src)
	om_qdel_after(src, 1)

/// Goes away once it leaves its creator's hands: checked after it is made, dropped or moved
/// between hands, never polled.
/obj/item/mop_deploy/proc/check_held()
	if(!creator() || loc != creator() || !creator().item_is_in_hands(src))
		// Tidy up a bit.
		if(isliving(loc))
			var/mob/living/carbon/human/host = loc
			if(istype(host))
				for(var/obj/item/organ/external/organ in host.organs)
					for(var/obj/item/O in organ.implants)
						if(O == src)
							LAZYREMOVE(organ.implants, src)
			LAZYREMOVE(host.pinned, src)
			LAZYREMOVE(host.embedded, src)
			host.drop_from_inventory(src)
		om_qdel_after(src, 1)

/obj/item/mop_deploy/dropped(mob/user, equipping, slot)
	. = ..()
	om_after(src, 0, PROC_REF(check_held))

/obj/item/mop_deploy/equipped(mob/user, slot)
	. = ..()
	om_after(src, 0, PROC_REF(check_held))

/// LC-refs: creator -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/mop_deploy/proc/creator() as /mob/living
	return om_resolve(creator_handle)
