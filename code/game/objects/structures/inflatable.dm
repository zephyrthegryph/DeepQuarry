/obj/item/inflatable
	name = "inflatable wall"
	desc = "A folded membrane which rapidly expands into a large cubical shape on activation."
	icon = 'icons/obj/inflatable.dmi'
	icon_state = "folded_wall"
	drop_sound = SFX_ITEMS_DROP_RUBBER
	w_class = ITEMSIZE_NORMAL
	var/deploy_path = /obj/structure/inflatable

CAPABILITIES(/obj/item/inflatable)
	op("inflate", in_hand(), label("Inflate"), then(PROC_REF(inflatable_self)))

/// Old attack_self: inflate here. A torn one re-declares the op.
/obj/item/inflatable/proc/inflatable_self(datum/act/op/A)
	var/mob/user = A.actor
	inflate(user,user.loc)
	return OP_OK

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

CAPABILITIES(/obj/structure/inflatable)
	extend(/datum/act/hit/blob, instead(then(PROC_REF(inflatable_blob))))
	op("use_hand", hand(), then(PROC_REF(interaction_hand)))
	op("use_item", item(/obj/item), then(PROC_REF(interaction_item)))
	op("deflate", menu(), label("Deflate"), then(PROC_REF(hand_deflate_effect)))

/// A blob punctures the inflatable.
/obj/structure/inflatable/proc/inflatable_blob(datum/act/hit/blob/A)
	puncture()
	return TRUE

/// Old attack_hand: just leaves a fingerprint.
/obj/structure/inflatable/proc/interaction_hand(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/// Old attackby: puncture with a sharp item, or take a weapon hit.
/obj/structure/inflatable/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if (can_puncture(W))
		act_message(user, src, others = span_danger("%U% pierces %T% with [W]!"))
		puncture()
	if(W.obj_damage_type())
		play_sfx(src, SFX_EFFECTS_GLASSHIT)
		receive_weapon_hit(W, user)
	return TRUE

/obj/structure/inflatable/click_ctrl(mob/user)
	deflate_by(user)

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
	after(src, 5 SECONDS, PROC_REF(deflate_finish))

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

/// Old verb "Deflate".
/obj/structure/inflatable/proc/hand_deflate_effect(datum/act/op/A)
	deflate_by(A.actor)

/// `user` lets the air out (ctrl-click, the Deflate pick): once, by someone free and next to it.
/obj/structure/inflatable/proc/deflate_by(mob/user)
	if(isobserver(user) || user.restrained() || !user.Adjacent(src))
		return

	if(deflating)
		return
	deflating = TRUE
	deflate()

/obj/structure/inflatable/attack_generic(mob/user, damage, attack_verb)
	user.do_attack_animation(src)
	if(get_integrity() - damage <= 0)
		act_message(user, src, others = span_danger("%U% [attack_verb] open %T%!"))
	else
		act_message(user, src, others = span_danger("%U% [attack_verb] at %T%!"))
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

/// Old attack_ai: those aren't machinery, they're just big slabs of a mineral. A cyborg next to it opens it; the AI can't (the op is a cyborg's).
/obj/structure/inflatable/door/proc/inflatable_door_silicon_use(datum/act/op/A)
	TryToSwitchState(A.actor)
	return OP_OK

// The door's Use replaces the base inflatable's fingerprint-only one, and it has no item use of its own (the old door's list left it out).
CAPABILITIES(/obj/structure/inflatable/door)
	op("use_hand", hand(), then(PROC_REF(interaction_door_hand)))
	without("use_item")
	op("silicon_open", remote(), label("Open"), when(req(/mob/living/silicon/robot, of = ON_ACTOR)), needs(req_adjacent()), then(PROC_REF(inflatable_door_silicon_use)))

/// Old attack_hand: open/close the door.
/obj/structure/inflatable/door/proc/interaction_door_hand(datum/act/op/A)
	TryToSwitchState(A.actor)
	return OP_OK

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
	after(src, 1 SECOND, PROC_REF(open_finish))

/obj/structure/inflatable/door/proc/open_finish()
	set_density(FALSE)
	set_opacity(0)
	state = 1
	update_icon()
	isSwitchingStates = 0

/obj/structure/inflatable/door/proc/Close()
	isSwitchingStates = 1
	flick("door_closing",src)
	after(src, 1 SECOND, PROC_REF(close_finish))

/obj/structure/inflatable/door/proc/close_finish()
	set_density(TRUE)
	set_opacity(0)
	state = 0
	update_icon()
	isSwitchingStates = 0

APPEARANCE_TEMPLATE(/obj/structure/inflatable/door, "door_{state?open:closed}")

/obj/structure/inflatable/door/deflate()
	play_sfx(src, SFX_MACHINES_HISS, 1.5, vary = TRUE)
	visible_message("[src] slowly deflates.")
	after(src, 5 SECONDS, PROC_REF(deflate_finish))

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

CAPABILITIES(/obj/item/inflatable/torn)
	op("inflate", in_hand(), label("Inflate"), then(PROC_REF(torn_inflatable_self)))

/// Used in hand: it is too torn to inflate.
/obj/item/inflatable/torn/proc/torn_inflatable_self(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("The inflatable wall is too torn to be inflated!"))
	add_fingerprint(user)
	return OP_OK

/obj/item/inflatable/door/torn
	name = "torn inflatable door"
	desc = "A folded membrane which rapidly expands into a simple door on activation. It is too torn to be usable."
	icon = 'icons/obj/inflatable.dmi'
	icon_state = "folded_door_torn"

CAPABILITIES(/obj/item/inflatable/door/torn)
	op("inflate", in_hand(), label("Inflate"), then(PROC_REF(torn_door_inflatable_self)))

/// Used in hand: it is too torn to inflate.
/obj/item/inflatable/door/torn/proc/torn_door_inflatable_self(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("The inflatable door is too torn to be inflated!"))
	add_fingerprint(user)
	return OP_OK

/obj/item/storage/briefcase/inflatable
	name = "inflatable barrier box"
	desc = "Contains inflatable walls and doors."
	icon_state = "inf_box"
	w_class = ITEMSIZE_NORMAL
	max_storage_space = ITEMSIZE_COST_NORMAL * 7
	starts_with = list(/obj/item/inflatable/door = 3, /obj/item/inflatable = 4)


CAPABILITIES(/obj/item/storage/briefcase/inflatable)
	configure(storage(accepts = list(/obj/item/inflatable)))
