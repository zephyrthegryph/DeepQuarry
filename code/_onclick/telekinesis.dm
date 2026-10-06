/obj
	/// A telekinetic reach can grab or poke this (the telekinesis adapter's default). Structures refuse
	/// unless they declare an INTERACT_TK of their own.
	var/tk_reach = TRUE

/*
	This is similar to item attack_self, but applies to anything
	that you can grab with a telekinetic grab.

	It is used for manipulating things at range, for example, opening and closing closets.
	There are not a lot of defaults at this time, add more where appropriate.
*/
/atom/proc/attack_self_tk(mob/user)
	return

/*
	TK Grab Item (the workhorse of old TK)

	* If you have not grabbed something, do a normal tk attack
	* If you have something, throw it at the target.  If it is already adjacent, do a normal attackby()
	* If you click what you are holding, or attack_self(), do an attack_self_tk() on it.
	* Deletes itself if it is ever not in your hand, or if you should have no access to TK.
*/
/obj/item/tk_grab
	name = "Telekinetic Grab"
	desc = "Magic"
	icon = 'icons/obj/magic.dmi'//Needs sprites
	icon_state = "2"
	flags = NOBLUDGEON
	w_class = ITEMSIZE_NO_CONTAINER
	layer = HUD_LAYER

	COOLDOWN_DECLARE(throw_cooldown)
	var/atom/movable/focus
	var/mob/living/host
	item_flags = DROPDEL | NOSTRIP

/obj/item/tk_grab/dropped(mob/user, equipping, slot)
	..()
	if(focus() && user && loc != user && loc != user.loc) // drop_item() gets called when you tk-attack a table/closet with an item
		if(focus().Adjacent(loc))
			focus().forceMove(loc)

//stops TK grabs being equipped anywhere but into hands
/obj/item/tk_grab/equipped(mob/user, slot)
	..()
	if( (slot == SLOT_ID_HAND_L) || (slot== SLOT_ID_HAND_R) )	return
	spent(src, user)
	return

CAPABILITIES(/obj/item/tk_grab)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/tk_grab/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(focus())
		focus().attack_self_tk(user)
	return TRUE

/obj/item/tk_grab/afterattack(atom/target as mob|obj|turf|area, mob/living/user as mob|obj, proximity, click_parameters, stance = I_HURT)//TODO: go over this
	if(!target || !user)	return
	if(!COOLDOWN_FINISHED(src, throw_cooldown))	return
	if(!host() || host() != user)
		consume(src, user)
		return
	if(!host().has_telegrip())
		consume(src, user)
		return
	if(isobj(target) && !isturf(target.loc))
		return

	if(user.is_remote_viewing()) // Extremely bad exploits if allowed to TK while remote viewing
		to_chat(user, TK_DENIED_MESSAGE)
		return

	var/d = get_dist(user, target)
	if(focus())
		d = max(d, get_dist(user, focus())) // whichever is further
	if(d > TK_MAXRANGE)
		to_chat(user, TK_OUTRANGED_MESSAGE)
		return

	if(!focus())
		focus_object(target, user)
		return

	if(target == focus())
		target.attack_self_tk(user)
		return // todo: something like attack_self not laden with assumptions inherent to attack_self


	if(!istype(target, /turf) && istype(focus(),/obj/item) && target.Adjacent(focus()))
		var/obj/item/I = focus()
		var/resolved = target.attackby(I, user, user:get_organ_target())
		if(!resolved && target && I)
			I.afterattack(target, user, 1, click_parameters, stance) // for splashing with beakers
	else
		apply_focus_overlay()
		focus().throw_at(target, 10, 1, user)
		COOLDOWN_START(src, throw_cooldown, 0.3 SECONDS)
		if(ishuman(user))
			var/mob/living/carbon/human/H_user = user
			if(istype(H_user.get_equipped_item(SLOT_ID_GLOVES),/obj/item/clothing/gloves/telekinetic))
				var/obj/item/clothing/gloves/telekinetic/TKG = H_user.get_equipped_item(SLOT_ID_GLOVES)
				TKG.use_grip_power(user,TRUE)
				if(!TKG.has_grip_power())
					spent(src, user) // Drop TK
	return

/obj/item/tk_grab/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	return ITEM_INTERACT_FAILURE


/obj/item/tk_grab/proc/focus_object(obj/target, mob/living/user)
	if(!istype(target,/obj))	return//Cant throw non objects atm might let it do mobs later
	if(target.anchored || !isturf(target.loc))
		consume(src, user)
		return
	rel_set(src, nameof(focus), target)
	apply_focus_overlay()
	return

/obj/item/tk_grab/proc/apply_focus_overlay()
	if(!focus())	return
	var/obj/effect/overlay/O = new /obj/effect/overlay(locate(focus().x,focus().y,focus().z))
	O.name = "sparkles"
	O.set_anchored(TRUE)
	O.set_density(FALSE)
	O.layer = FLY_LAYER
	O.set_dir(pick(GLOB.cardinal))
	O.icon = 'icons/effects/effects.dmi'
	O.icon_state = "nothing"
	flick("empdisable",O)
	O.expire(5)
	return

/obj/item/tk_grab/draw(datum/look/look)
	..()
	if(focus() && focus().icon && focus().icon_state)
		look.overlay(icon(focus().icon, focus().icon_state))

/// The thing held by telekinesis (a relation view: null once that is deleted).
/obj/item/tk_grab/proc/focus() as /atom/movable
	return focus

/// The mob using telekinesis (a relation view: null once that is deleted).
/obj/item/tk_grab/proc/host() as /mob/living
	return host
