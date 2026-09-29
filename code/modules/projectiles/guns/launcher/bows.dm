/obj/item/arrow/standard
	name = "arrow"
	desc = "It's got a tip for you - get the point?"
	icon = 'icons/obj/guns/projectile/bows.dmi'
	icon_state = "arrow"
	item_state = "bolt"
	throwforce = 8
	w_class = ITEMSIZE_NORMAL
	sharp = TRUE
	edge = FALSE

/obj/item/arrow/energy
	name = "hardlight arrow"
	desc = "An arrow made out of energy! Classic?"
	icon = 'icons/obj/guns/projectile/bows.dmi'
	icon_state = "hardlight"
	item_state = "bolt"
	throwforce = 10
	w_class = ITEMSIZE_NORMAL
	sharp = TRUE
	edge = TRUE
	injury_kind = INJURY_CUT
	embed_chance = 0 // it fizzles!
	catchable = FALSE // oh god

/obj/item/arrow/energy/throw_impact(atom/hit_atom)
	. = ..()
	qdel(src)

/obj/item/arrow/energy/equipped()
	if(isliving(loc))
		var/mob/living/L = loc
		L.drop_from_inventory(src)
	qdel(src) // noh

/obj/item/gun/launcher/crossbow/bow
	name = "shortbow"
	desc = "A common shortbow, capable of firing arrows at high speed towards a target. Useful for hunting while keeping quiet."
	icon = 'icons/obj/guns/projectile/bows.dmi'
	icon_override = 'icons/obj/guns/projectile/bows.dmi'
	icon_state = "bow"
	item_state = "bow"
	fire_sound = 'sound/weapons/punchmiss.ogg' // TODO: Decent THWOK noise.
	fire_sound_text = "a solid thunk"
	fire_delay = 25
	slot_flags = SLOT_BACK
	release_force = 20
	release_speed = 15
	var/drawn = FALSE
	is_bow = TRUE

	///Var for attack_self chain
	var/hardlight = FALSE

/obj/item/gun/launcher/crossbow/bow/update_release_force(obj/item/projectile)
	return 0

/obj/item/gun/launcher/crossbow/bow/proc/unload(mob/user)
	var/obj/item/arrow/A = bolt
	own_take(src, "bolt")
	drawn = FALSE
	A.forceMove(get_turf(user))
	user.put_in_hands(A)
	update_icon()

/obj/item/gun/launcher/crossbow/bow/consume_next_projectile(mob/user)
	if(!drawn)
		to_chat(user, span_warning("\The [src] is not drawn back!"))
		return null
	return bolt

/obj/item/gun/launcher/crossbow/bow/handle_post_fire(mob/user, atom/target)
	own_take(src, "bolt")
	drawn = FALSE
	update_icon()
	..()

DECLARE_INTERACTIONS(/obj/item/gun/launcher/crossbow/bow, INTERACT_HAND(null, PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/item/gun/launcher/crossbow/bow/proc/interaction_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(loc == user && bolt && !drawn)
		user.visible_message(span_infoplain(span_bold("[user]") + " removes [bolt] from [src]."),span_infoplain("You remove [bolt] from [src]."))
		unload(user)
	else
		return FALSE
	return TRUE

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()).
/obj/item/gun/launcher/crossbow/bow/gun_self(mob/living/user, obj/item/held, datum/interaction/interaction, callback)
	. = ..()
	if(.)
		return TRUE
	if(hardlight)
		return FALSE
	if(drawn)
		user.visible_message(span_infoplain(span_bold("[user]") + " relaxes the tension on [src]'s string."),span_infoplain("You relax the tension on [src]'s string."))
		drawn = FALSE
		update_icon()
	else
		draw(user)

/obj/item/gun/launcher/crossbow/bow/draw(mob/user)
	if(!bolt)
		to_chat(user, span_infoplain("You don't have anything nocked to [src]."))
		return

	if(user.restrained())
		return

	current_user = user
	user.visible_message(span_infoplain(span_bold("[user]") + " begins to draw back the string of [src]."),span_notice("You begin to draw back the string of [src]."))
	om_task_timed(user, 2.5 SECONDS, src, src, PROC_REF(drawn_fully), list(user))
	update_icon()

/obj/item/gun/launcher/crossbow/bow/proc/drawn_fully(mob/user)
	drawn = TRUE
	user.visible_message(span_infoplain(span_bold("[user]") + "draws the string on [src] back fully!"), span_infoplain("You draw the string on [src] back fully!"))
	update_icon()

/// Old attackby. It never called ..(): any item stops here, but afterattack still follows.
/obj/item/gun/launcher/crossbow/bow/gun_item(mob/user, obj/item/W, datum/interaction/interaction)
	. = INTERACTION_HANDLED_PASS
	if(!bolt && istype(W,/obj/item/arrow/standard))
		user.drop_from_inventory(W, src)
		own_set(src, "bolt", W)
		user.visible_message(span_infoplain("[user] slides [bolt] into [src]."),span_infoplain("You slide [bolt] into [src]."))
		update_icon()

/obj/item/gun/launcher/crossbow/bow/update_icon()
	if(drawn)
		icon_state = "[initial(icon_state)]_firing"
	else if(bolt)
		icon_state = "[initial(icon_state)]_loaded"
	else
		icon_state = "[initial(icon_state)]"



/obj/item/gun/launcher/crossbow/bow/hardlight
	name = "hardlight bow"
	icon_state = "bow_hardlight"
	item_state = "bow_hardlight"
	desc = "An energy bow, capable of producing arrows from an internal power supply."
	hardlight = TRUE

/obj/item/gun/launcher/crossbow/bow/hardlight/unload(mob/user)
	own_clear(src, "bolt", OWN_DELETE)
	update_icon()

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()).
/obj/item/gun/launcher/crossbow/bow/hardlight/gun_self(mob/user, obj/item/held, datum/interaction/interaction, callback)
	. = ..()
	if(.)
		return TRUE
	if(drawn)
		user.visible_message(span_infoplain(span_bold("[user]") + " relaxes the tension on [src]'s string."),span_infoplain("You relax the tension on [src]'s string."))
		drawn = FALSE
		update_icon()
		return
	// Automatically knock the arrow as it forms
	if(!bolt)
		user.visible_message(span_infoplain(span_bold("[user]") + " fabricates a new hardlight projectile with [src]."),span_infoplain("You fabricate a new hardlight projectile with [src]."))
		own_set(src, "bolt", new /obj/item/arrow/energy(src))
		update_icon()
	draw(user)

/obj/item/gun/launcher/crossbow/bow/glamour
	name = "glamour bow"
	desc = "A glamour bow, capable of firing arrows at high speed towards a target. Useful for hunting while keeping quiet."
	icon = 'icons/obj/guns/projectile/bows.dmi'
	icon_override = 'icons/obj/guns/projectile/bows.dmi'
	icon_state = "gbow"
	item_state = "gbow"

/obj/item/arrow/standard/glamour
	name = "glamour arrow"
	icon = 'icons/obj/guns/projectile/bows.dmi'
	icon_state = "garrow"
	edge = TRUE
	injury_kind = INJURY_CUT
