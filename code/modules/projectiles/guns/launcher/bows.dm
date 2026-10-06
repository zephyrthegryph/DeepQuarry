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
	consume(src)

/obj/item/arrow/energy/equipped()
	if(isliving(loc))
		var/mob/living/L = loc
		L.drop_from_inventory(src)
	consume(src) // An equipped hardlight arrow dissipates after its compulsory drop.

/obj/item/gun/launcher/crossbow/bow
	name = "shortbow"
	desc = "A common shortbow, capable of firing arrows at high speed towards a target. Useful for hunting while keeping quiet."
	icon = 'icons/obj/guns/projectile/bows.dmi'
	icon_override = 'icons/obj/guns/projectile/bows.dmi'
	icon_state = "bow"
	item_state = "bow"
	fire_sound = SFX_WEAPONS_PUNCHMISS // TODO: Decent THWOK noise.
	fire_sound_text = "a solid thunk"
	fire_delay = 25
	slot_flags = SLOT_BACK
	release_force = 20
	release_speed = 15
	var/drawn = FALSE
	is_bow = TRUE

	///Var for attack_self chain
	var/hardlight = FALSE
TRACKED(/obj/item/gun/launcher/crossbow/bow, drawn)

/obj/item/gun/launcher/crossbow/bow/update_release_force(obj/item/projectile)
	return 0

/obj/item/gun/launcher/crossbow/bow/proc/unload(mob/user)
	var/obj/item/arrow/A = bolt
	rel_take(src, nameof(bolt))
	set_drawn(FALSE)
	A.forceMove(get_turf(user))
	user.put_in_hands(A)

/obj/item/gun/launcher/crossbow/bow/consume_next_projectile(mob/user)
	if(!drawn)
		to_chat(user, span_warning("\The [src] is not drawn back!"))
		return null
	return bolt

/obj/item/gun/launcher/crossbow/bow/handle_post_fire(mob/user, atom/target)
	rel_take(src, nameof(bolt))
	set_drawn(FALSE)
	..()

CAPABILITIES(/obj/item/gun/launcher/crossbow/bow)
	op("interaction_hand", hand(), then(PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/item/gun/launcher/crossbow/bow/proc/interaction_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(loc == user && bolt && !drawn)
		act_message(user, src, MSG_SELF(span_infoplain("You remove [bolt] from %T%.")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " removes [bolt] from %T%.")))
		unload(user)
	else
		return OP_DECLINE
	return TRUE

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()).
/obj/item/gun/launcher/crossbow/bow/gun_self(mob/living/user, obj/item/held, datum/interaction/interaction, callback)
	. = ..()
	if(.)
		return TRUE
	if(hardlight)
		return FALSE
	if(drawn)
		act_message(user, src, MSG_SELF(span_infoplain("You relax the tension on %T%'s string.")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " relaxes the tension on %T%'s string.")))
		set_drawn(FALSE)
	else
		draw_string(user)

/obj/item/gun/launcher/crossbow/bow/draw_string(mob/user)
	if(!bolt)
		to_chat(user, span_infoplain("You don't have anything nocked to [src]."))
		return

	if(user.restrained())
		return

	current_user = user
	act_message(user, src, MSG_SELF(span_notice("You begin to draw back the string of %T%.")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " begins to draw back the string of %T%.")))
	task_timed(user, 2.5 SECONDS, src, src, PROC_REF(drawn_fully), list(user))

/obj/item/gun/launcher/crossbow/bow/proc/drawn_fully(mob/user)
	set_drawn(TRUE)
	act_message(user, src, MSG_SELF(span_infoplain("You draw the string on %T% back fully!")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + "draws the string on %T% back fully!")))

/// Old attackby. It never called ..(): any item stops here, but afterattack still follows.
/obj/item/gun/launcher/crossbow/bow/gun_item(mob/user, obj/item/W, datum/interaction/interaction)
	. = INTERACTION_HANDLED_PASS
	if(!bolt && istype(W,/obj/item/arrow/standard))
		if(!move_into(src, nameof(src.bolt), W, user))
			return
		act_message(user, src, MSG_SELF(span_infoplain("You slide [bolt] into %T%.")), MSG_OTHERS(span_infoplain("%U% slides [bolt] into %T%.")))

/obj/item/gun/launcher/crossbow/bow/appearance_draw_suffix()
	if(drawn)
		return "_firing"
	if(bolt)
		return "_loaded"
	return ""
/// The look (the draw sweep: from its template).
/obj/item/gun/launcher/crossbow/bow/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][appearance_draw_suffix()]")



/obj/item/gun/launcher/crossbow/bow/hardlight
	name = "hardlight bow"
	icon_state = "bow_hardlight"
	item_state = "bow_hardlight"
	desc = "An energy bow, capable of producing arrows from an internal power supply."
	hardlight = TRUE

/obj/item/gun/launcher/crossbow/bow/hardlight/unload(mob/user)
	own_clear(src, nameof(bolt), OWN_DELETE)

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()).
/obj/item/gun/launcher/crossbow/bow/hardlight/gun_self(mob/user, obj/item/held, datum/interaction/interaction, callback)
	. = ..()
	if(.)
		return TRUE
	if(drawn)
		act_message(user, src, MSG_SELF(span_infoplain("You relax the tension on %T%'s string.")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " relaxes the tension on %T%'s string.")))
		set_drawn(FALSE)
		return
	// Automatically knock the arrow as it forms
	if(!bolt)
		act_message(user, src, MSG_SELF(span_infoplain("You fabricate a new hardlight projectile with %T%.")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " fabricates a new hardlight projectile with %T%.")))
		rel_set(src, nameof(bolt), new /obj/item/arrow/energy(src))
	draw_string(user)

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
