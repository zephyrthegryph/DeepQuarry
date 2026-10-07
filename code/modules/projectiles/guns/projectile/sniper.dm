////////////// PTR-7 Anti-Materiel Rifle //////////////

/obj/item/gun/projectile/heavysniper
	name = "anti-materiel rifle"
	desc = "A portable anti-armour rifle fitted with a scope, the HI PTR-7 Rifle was originally designed to used against armoured exosuits. It is capable of punching through windows and non-reinforced walls with ease. Fires armor piercing 14.5mm shells."
	description_fluff = "The leading arms producer in the SCG, Hephaestus typically only uses its 'top level' branding for its military-grade equipment used by professional armed forces across human space."
	icon_state = "heavysniper"
	wielded_item_state = "heavysniper-wielded"
	w_class = ITEMSIZE_HUGE // So it can't fit in a backpack.
	force = 10
	slot_flags = SLOT_BACK
	actions_types = list(/datum/action/item_action/use_scope)
	caliber = "14.5mm"
	recoil = 5 //extra kickback
	handle_casings = HOLD_CASINGS
	load_method = SINGLE_CASING
	max_shells = 1
	ammo_type = /obj/item/ammo_casing/a145
	projectile_type = /obj/item/projectile/bullet/rifle/a145
	accuracy = -75
	scoped_accuracy = 75
	one_handed_penalty = 90
	bolt_open = 0
	special_weapon_handling = TRUE

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/heavysniper/draw(datum/look/look)
	..()
	look.state("heavysniper[bolt_open ? "-open" : ""]")

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()).
/obj/item/gun/projectile/heavysniper/gun_self(datum/act/op/A, callback)
	var/mob/user = A.actor
	. = ..()
	if(. == OP_OK)
		return OP_OK
	play_sfx(src, SFX_WEAPONS_FLIPBLADE)
	set_bolt_open(!bolt_open)
	if(bolt_open)
		if(chambered)
			to_chat(user, span_notice("You work the bolt open, ejecting [chambered]!"))
			chambered.forceMove(get_turf(src))
			own_take_member(src, nameof(loaded), chambered)
			rel_clear(src, nameof(chambered))
		else
			to_chat(user, span_notice("You work the bolt open."))
	else
		to_chat(user, span_notice("You work the bolt closed."))
		set_bolt_open(0)
	add_fingerprint(user)

/obj/item/gun/projectile/heavysniper/special_check(mob/user)
	if(bolt_open)
		to_chat(user, span_warning("You can't fire [src] while the bolt is open!"))
		return 0
	return ..()

/obj/item/gun/projectile/heavysniper/load_ammo(obj/item/A, mob/user)
	if(!bolt_open)
		return
	..()

/obj/item/gun/projectile/heavysniper/unload_ammo(mob/user, allow_dump=1)
	if(!bolt_open)
		return
	..()

/obj/item/gun/projectile/heavysniper/ui_action_click(mob/user, actiontype)
	perform_scope_interaction(user, PROC_REF(heavysniper_verb_scope))

CAPABILITIES(/obj/item/gun/projectile/heavysniper)
	op("heavysniper_verb_scope", menu(), label("Use Scope"), needs(carried(), req(PROC_REF(zoom_view_allowed_holds), because = PROC_REF(zoom_view_allowed_refusal))), then(PROC_REF(heavysniper_verb_scope_op)))

/// Requirement (was REQ_* zoom_view_allowed): the legacy check answers TRUE to pass.
/obj/item/gun/projectile/heavysniper/proc/zoom_view_allowed_holds(datum/act/op/A)
	var/answer = zoom_view_allowed(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why zoom_view_allowed_holds refuses: the legacy check's text, else the clause's own reason.
/obj/item/gun/projectile/heavysniper/proc/zoom_view_allowed_refusal(datum/act/op/A)
	var/answer = zoom_view_allowed(A.actor, src, A.held)
	return istext(answer) ? answer : "You are too distracted to do that."

/// The heavysniper_verb_scope op: the verb's effect, as the old resolver ran it.
/obj/item/gun/projectile/heavysniper/proc/heavysniper_verb_scope_op(datum/act/op/A)
	heavysniper_verb_scope(A.actor, A.held, null)
	return OP_OK

/// Old Use Scope verb.
/obj/item/gun/projectile/heavysniper/proc/heavysniper_verb_scope(mob/user, obj/item/held, datum/interaction/interaction)
	toggle_scope(2.0, user)

////////////// Dragunov Sniper Rifle //////////////

/obj/item/gun/projectile/SVD
	name = "sniper rifle"
	desc = "The PCA S19 Jalgarr, also known by its translated name the 'Dragon', is mass produced with an Optical Sniper Sight so simple that even a Tajaran can use it. Too bad for you that the inscriptions are written in Siik. Uses 7.62mm rounds."
	icon_state = "SVD"
	item_state = "SVD"
	wielded_item_state = "heavysniper-wielded" //Placeholder
	w_class = ITEMSIZE_HUGE // So it can't fit in a backpack.
	force = 10
	slot_flags = SLOT_BACK // Needs a sprite.
	actions_types = list(/datum/action/item_action/use_scope)
	caliber = "7.62mm"
	load_method = MAGAZINE
	accuracy = -45 //shooting at the hip
	scoped_accuracy = 0
	one_handed_penalty = 60 // The weapon itself is heavy, and the long barrel makes it hard to hold steady with just one hand.
	fire_sound = SFX_WEAPONS_GUNSHOT_SVD // Has a very unique sound.
	magazine_type = /obj/item/ammo_magazine/m762svd
	allowed_magazines = list(/obj/item/ammo_magazine/m762svd)

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/SVD/draw(datum/look/look)
	..()
	look.state("SVD[ammo_magazine ? "" : "-empty"]")

/obj/item/gun/projectile/SVD/ui_action_click(mob/user, actiontype)
	perform_scope_interaction(user, PROC_REF(svd_verb_scope))

CAPABILITIES(/obj/item/gun/projectile/SVD)
	op("svd_verb_scope", menu(), label("Use Scope"), needs(carried(), req(PROC_REF(zoom_view_allowed_holds), because = PROC_REF(zoom_view_allowed_refusal))), then(PROC_REF(svd_verb_scope_op)))

/// Requirement (was REQ_* zoom_view_allowed): the legacy check answers TRUE to pass.
/obj/item/gun/projectile/SVD/proc/zoom_view_allowed_holds(datum/act/op/A)
	var/answer = zoom_view_allowed(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why zoom_view_allowed_holds refuses: the legacy check's text, else the clause's own reason.
/obj/item/gun/projectile/SVD/proc/zoom_view_allowed_refusal(datum/act/op/A)
	var/answer = zoom_view_allowed(A.actor, src, A.held)
	return istext(answer) ? answer : "You are too distracted to do that."

/// The svd_verb_scope op: the verb's effect, as the old resolver ran it.
/obj/item/gun/projectile/SVD/proc/svd_verb_scope_op(datum/act/op/A)
	svd_verb_scope(A.actor, A.held, null)
	return OP_OK

/// Old Use Scope verb.
/obj/item/gun/projectile/SVD/proc/svd_verb_scope(mob/user, obj/item/held, datum/interaction/interaction)
	toggle_scope(2.0, user)
