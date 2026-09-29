/obj/item/inflatable
	name = "inflatable wall"
	desc = "A folded membrane which rapidly expands into a large cubical shape on activation."
	icon = 'icons/obj/inflatable.dmi'
	icon_state = "folded_wall"
	drop_sound = SFX_ITEMS_DROP_RUBBER
	w_class = ITEMSIZE_NORMAL
	var/deploy_path = /obj/structure/inflatable
	///Var used for attack_self chain
	var/special_handling = FALSE

DECLARE_INTERACTIONS(/obj/item/inflatable, INTERACT_SELF("Inflate", PROC_REF(inflatable_self)))

/// Old attack_self: inflate here. Subtypes with special_handling fall through.
/obj/item/inflatable/proc/inflatable_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(special_handling)
		return FALSE
	inflate(user,user.loc)
	return TRUE

/obj/item/inflatable/afterattack(atom/A, mob/user)
	..(A, user)
	if(!user)
		return
	if(!user.Adjacent(A))
		to_chat(user, "You can't reach!")
		return
	if(istype(A, /turf))
		inflate(user,A)

/obj/structure/inflatable
	name = "inflatable wall"
	desc = "An inflated membrane. Do not puncture."
	density = TRUE
	anchored = TRUE
	opacity = 0
	can_atmos_pass = ATMOS_PASS_DENSITY

	icon = 'icons/obj/inflatable.dmi'
	icon_state = "wall"

	max_integrity = 50
	/// Set once a hand deflate starts (old: the Deflate verb removed itself).
	var/deflating = FALSE

/obj/structure/inflatable/Initialize(mapload)
	. = ..()
	update_nearby_tiles(need_rebuild=1)

/obj/structure/inflatable/blob_act()
	puncture()

/obj/structure/inflatable/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/inflatable_hand,
		/datum/interaction/entry_item/inflatable_item,
	)
	into += dq_interaction_from_spec(type, INTERACT_VERB("Deflate", PROC_REF(hand_deflate_effect)))
	..()

/// Old attack_hand: just leaves a fingerprint.
/datum/interaction/entry_hand/inflatable_hand
	id = "inflatable_hand"
	name = "Use"
	effect = /obj/structure/inflatable/proc/interaction_hand

/obj/structure/inflatable/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	return TRUE

/// Old attackby: puncture with a sharp item, or take a weapon hit.
/datum/interaction/entry_item/inflatable_item
	id = "inflatable_item"
	name = "Use"
	effect = /obj/structure/inflatable/proc/interaction_item

/obj/structure/inflatable/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if (can_puncture(W))
		visible_message(span_danger("[user] pierces [src] with [W]!"))
		puncture()
	if(W.obj_damage_type())
		play_sfx(src, SFX_EFFECTS_GLASSHIT)
		receive_weapon_hit(W, user)
	return TRUE

/obj/structure/inflatable/click_ctrl(mob/user)
	hand_deflate_effect(user)

/obj/item/inflatable/proc/inflate(mob/user,location)
	play_sfx(location, SFX_ITEMS_ZIP)
	to_chat(user, span_notice("You inflate [src]."))
	var/obj/structure/inflatable/R = new deploy_path(location)
	src.transfer_fingerprints_to(R)
	R.add_fingerprint(user)
	consume(src, user)

/obj/structure/inflatable/proc/deflate()
	play_sfx(src, SFX_MACHINES_HISS, 1.5, vary = TRUE)
	visible_message("[src] slowly deflates.")
	om_after(src, 5 SECONDS, PROC_REF(deflate_finish))

/obj/structure/inflatable/proc/deflate_finish()
	var/obj/item/inflatable/R = new /obj/item/inflatable(loc)
	src.transfer_fingerprints_to(R)
	replace_with(src, R)

/obj/structure/inflatable/proc/puncture()
	play_sfx(src, SFX_MACHINES_HISS, 1.5, vary = TRUE)
	visible_message("[src] rapidly deflates!")
	var/obj/item/inflatable/torn/R = new /obj/item/inflatable/torn(loc)
	src.transfer_fingerprints_to(R)
	replace_with(src, R)

/obj/structure/inflatable/proc/hand_deflate_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(isobserver(user) || user.restrained() || !user.Adjacent(src))
		return

	if(deflating)
		return
	deflating = TRUE
	deflate()

/obj/structure/inflatable/attack_generic(mob/user, damage, attack_verb)
	user.do_attack_animation(src)
	if(get_integrity() - damage <= 0)
		user.visible_message(span_danger("[user] [attack_verb] open the [src]!"))
	else
		user.visible_message(span_danger("[user] [attack_verb] at [src]!"))
	receive_generic_attack(user, damage)
	return 1

// Reaching 0 integrity tears the membrane open.
/obj/structure/inflatable/atom_destruction(damage_flag)
	puncture()
	return ..()

/obj/item/inflatable/door/
	name = "inflatable door"
	desc = "A folded membrane which rapidly expands into a simple door on activation."
	icon = 'icons/obj/inflatable.dmi'
	icon_state = "folded_door"
	deploy_path = /obj/structure/inflatable/door

/obj/structure/inflatable/door //Based on mineral door code
	name = "inflatable door"
	density = TRUE
	anchored = TRUE
	opacity = 0

	icon = 'icons/obj/inflatable.dmi'
	icon_state = "door_closed"

	var/state = 0 //closed, 1 == open
	var/isSwitchingStates = 0

/// Old attack_ai: those aren't machinery, they're just big slabs of a mineral. Cyborgs next to it open it; the AI can't.
/obj/structure/inflatable/door/proc/inflatable_door_silicon_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(isAI(user)) //so the AI can't open it
		return TRUE
	if(isrobot(user) && get_dist(user,src) <= 1) //but cyborgs can, not remotely though
		TryToSwitchState(user)
	return TRUE

// The door's Use replaces (doesn't chain to) the base inflatable's fingerprint-only one.
/obj/structure/inflatable/door/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/inflatable_door_hand,
	)
	into += dq_interaction_from_spec(type, INTERACT_SILICON("Open", PROC_REF(inflatable_door_silicon_use)))
	into += dq_interaction_from_spec(type, INTERACT_VERB("Deflate", PROC_REF(hand_deflate_effect)))

/// Old attack_hand: open/close the door.
/datum/interaction/entry_hand/inflatable_door_hand
	id = "inflatable_door_hand"
	name = "Use"
	effect = /obj/structure/inflatable/door/proc/interaction_door_hand

/obj/structure/inflatable/door/proc/interaction_door_hand(mob/user, obj/item/held, datum/interaction/interaction)
	TryToSwitchState(user)
	return TRUE

/obj/structure/inflatable/door/CanPass(atom/movable/mover, turf/target)
	if(istype(mover, /obj/effect/beam))
		return !opacity
	return !density

/obj/structure/inflatable/door/proc/TryToSwitchState(atom/user)
	if(isSwitchingStates) return
	if(ismob(user))
		var/mob/M = user
		if(M.client)
			if(iscarbon(M))
				var/mob/living/carbon/C = M
				if(!C.get_equipped_item(SLOT_ID_HANDCUFFED))
					SwitchState()
			else
				SwitchState()
	else if(istype(user, /obj/mecha))
		SwitchState()

/obj/structure/inflatable/door/proc/SwitchState()
	if(state)
		Close()
	else
		Open()
	update_nearby_tiles()

/obj/structure/inflatable/door/proc/Open()
	isSwitchingStates = 1
	flick("door_opening",src)
	om_after(src, 1 SECOND, PROC_REF(open_finish))

/obj/structure/inflatable/door/proc/open_finish()
	set_density(FALSE)
	opacity = 0
	state = 1
	update_icon()
	isSwitchingStates = 0

/obj/structure/inflatable/door/proc/Close()
	isSwitchingStates = 1
	flick("door_closing",src)
	om_after(src, 1 SECOND, PROC_REF(close_finish))

/obj/structure/inflatable/door/proc/close_finish()
	set_density(TRUE)
	opacity = 0
	state = 0
	update_icon()
	isSwitchingStates = 0

/obj/structure/inflatable/door/update_icon()
	if(state)
		icon_state = "door_open"
	else
		icon_state = "door_closed"

/obj/structure/inflatable/door/deflate()
	play_sfx(src, SFX_MACHINES_HISS, 1.5, vary = TRUE)
	visible_message("[src] slowly deflates.")
	om_after(src, 5 SECONDS, PROC_REF(deflate_finish))

/obj/structure/inflatable/door/deflate_finish()
	var/obj/item/inflatable/door/R = new /obj/item/inflatable/door(loc)
	src.transfer_fingerprints_to(R)
	replace_with(src, R)

/obj/structure/inflatable/door/puncture()
	play_sfx(src, SFX_MACHINES_HISS, 1.5, vary = TRUE)
	visible_message("[src] rapidly deflates!")
	var/obj/item/inflatable/door/torn/R = new /obj/item/inflatable/door/torn(loc)
	src.transfer_fingerprints_to(R)
	replace_with(src, R)

/obj/item/inflatable/torn
	name = "torn inflatable wall"
	desc = "A folded membrane which rapidly expands into a large cubical shape on activation. It is too torn to be usable."
	icon = 'icons/obj/inflatable.dmi'
	icon_state = "folded_wall_torn"
	special_handling = TRUE

EXTEND_INTERACTIONS(/obj/item/inflatable/torn, INTERACT_USE("Inflate", PROC_REF(torn_inflatable_self)))

/// Old attack_self.
/obj/item/inflatable/torn/proc/torn_inflatable_self(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("The inflatable wall is too torn to be inflated!"))
	add_fingerprint(user)

/obj/item/inflatable/door/torn
	name = "torn inflatable door"
	desc = "A folded membrane which rapidly expands into a simple door on activation. It is too torn to be usable."
	icon = 'icons/obj/inflatable.dmi'
	icon_state = "folded_door_torn"
	special_handling = TRUE

EXTEND_INTERACTIONS(/obj/item/inflatable/door/torn, INTERACT_USE("Inflate", PROC_REF(torn_door_inflatable_self)))

/// Old attack_self.
/obj/item/inflatable/door/torn/proc/torn_door_inflatable_self(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("The inflatable door is too torn to be inflated!"))
	add_fingerprint(user)

/obj/item/storage/briefcase/inflatable
	name = "inflatable barrier box"
	desc = "Contains inflatable walls and doors."
	icon_state = "inf_box"
	w_class = ITEMSIZE_NORMAL
	max_storage_space = ITEMSIZE_COST_NORMAL * 7
	starts_with = list(/obj/item/inflatable/door = 3, /obj/item/inflatable = 4)

TYPE_TABLE(/obj/item/storage/briefcase/inflatable, hold_spec, list(HOLD_ONLY(list(/obj/item/inflatable)), HOLD_MAX_SIZE(ITEMSIZE_NORMAL)))
