/**
 * The gun itself
 */
MATERIAL_MIX(/obj/item/gun/projectile/smartgun, list(MAT_STEEL = 6000, MAT_DIAMOND = 2000, MAT_URANIUM = 2000))
/obj/item/gun/projectile/smartgun/get_mechanics_info(list/additional_information)
	return ..(list("The rifle can't be unloaded while ready, and takes a few seconds to get ready before firing.") + additional_information)

/obj/item/gun/projectile/smartgun
	name ="\improper OP-15 'S.M.A.R.T.' Rifle"
	desc = "Suppressive Manual Action Reciprocating Taser rifle. A modified version of an Armadyne heavy machine gun fitted to fire miniature shock-bolts."
	icon = 'icons/obj/guns/projectile/smartgun_item.dmi'
	icon_state = "smartgun"
	icon_override = 'icons/obj/guns/projectile/smartgun_mob.dmi'
	item_state = "smartgun"
	w_class = ITEMSIZE_LARGE
	recoil = 1
	projectile_type = /obj/item/projectile/bullet/smartgun	//Only used for chameleon guns
	slot_flags = SLOT_BACK
	accuracy = -15
	one_handed_penalty = 50

	caliber = "smartgun"
	handle_casings = EJECT_CASINGS
	load_method = MAGAZINE

	magazine_type = null	//the type of magazine that the gun comes preloaded with
	allowed_magazines = list(/obj/item/ammo_magazine/smartgun)	//determines list of which magazines will fit in the gun

	var/closed = TRUE
	var/cycling = FALSE

/obj/item/gun/projectile/smartgun/make_worn_icon(body_type, slot_name, inhands, default_icon, default_layer, icon/clip_mask)
	var/image/I = ..()
	if(I)
		I.pixel_x = -16
	return I

/obj/item/gun/projectile/smartgun/loaded
	magazine_type = /obj/item/ammo_magazine/smartgun

/obj/item/gun/projectile/smartgun/consume_next_projectile()
	if(!closed)
		return null
	return ..()

/obj/item/gun/projectile/smartgun/load_ammo(obj/item/A, mob/user)
	if(closed)
		to_chat(user, span_warning("[src] can't be loaded until you un-ready it. (Alt-click)"))
		return
	return ..()

/obj/item/gun/projectile/smartgun/unload_ammo(mob/user, allow_dump=0)
	if(closed)
		to_chat(user, span_warning("[src] can't be unloaded until you un-ready it. (Alt-click)"))
		return
	return ..()

TRACKED(/obj/item/gun/projectile/smartgun, closed)
TRACKED(/obj/item/gun/projectile/smartgun, cycling)

CAPABILITIES(/obj/item/gun/projectile/smartgun)
	op("ready", hand(), answers(INTENT_TOGGLE), label("Ready or unready rifle"), then(PROC_REF(readiness_toggled)))

/obj/item/gun/projectile/smartgun/proc/readiness_toggled(datum/act/op/A)
	var/mob/user = A.actor
	if(ishuman(user) && !user.incapacitated() && Adjacent(user))
		if(cycling)
			to_chat(user, span_warning("[src] is still cycling!"))
			return OP_OK

		set_cycling(TRUE)

		if(closed)
			play_sfx(src, SFX_WEAPONS_SMARTGUNOPEN)
			to_chat(user, span_notice("You unready [src] so that it can be reloaded."))
		else
			play_sfx(src, SFX_WEAPONS_SMARTGUNCLOSE)
			to_chat(user, span_notice("You ready [src] so that it can be fired."))
		after(src, 2 SECONDS, PROC_REF(toggle_real_state), key = "smartgun_cycle")
	return OP_OK

/obj/item/gun/projectile/smartgun/proc/toggle_real_state()
	set_cycling(FALSE)
	set_closed(!closed)

/// The look: the open or closed receiver (the target state while it cycles), and the magazine.
/obj/item/gun/projectile/smartgun/draw(datum/look/look)
	..()
	if(cycling)
		look.state("[initial(icon_state)][closed ? "_open" : "_closed"]")
	else if(!closed)
		look.state("[initial(icon_state)]_open")
	look.overlay("smartgun_mag", when = !!ammo_magazine)

/**
 * The bullet that flies through the air
 */
/obj/item/projectile/bullet/smartgun
	name = "smartgun rail"
	icon_state = "smartgunproj"
	icon = 'icons/obj/guns/projectile/smartgun_32.dmi'
	fire_sound = SFX_WEAPONS_GUNSHOT4 // hmm

	// Slight damage and big stun
	damage = 10
	agony = 70
	embed_chance = 0 // There's a separate sprite for this, but for now let's just not embed
	accuracy = -30 // 2 turfs closer for the purpose of accuracy

	muzzle_type = /obj/effect/projectile/muzzle/lightning

/obj/item/projectile/bullet/smartgun/launch_projectile(atom/target, target_zone, mob/user, params, angle_override, forced_spread)
	. = ..()
	if(ismob(target))
		Beam(get_turf(target), icon_state = "sniper_beam", time = 0.25 SECONDS, maxdistance = 15)
		set_homing_target(target)

/**
 * The item of ammo that holds the bullet
 */
/obj/item/ammo_casing/smartgun
	name = "smartgun rail"
	desc = "A smartgun rail casing."
	icon = 'icons/obj/guns/projectile/smartgun_32.dmi'
	icon_state = "smartguncase"
	randpixel = 10
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_SMALL

	leaves_residue = FALSE
	caliber = "smartgun"
	projectile_type = /obj/item/projectile/bullet/smartgun

/**
 * The magazine that holds the items of ammo
 */
/obj/item/ammo_magazine/smartgun
	name = "smartgun magazine"
	desc = "A holder for smartgun rails for the S.M.A.R.T. rifle."
	icon = 'icons/obj/guns/projectile/smartgun_32.dmi'
	icon_state = "smartgunmag"
	slot_flags = SLOT_BELT
	MATERIAL_BULK(MAT_STEEL, 500)
	w_class = ITEMSIZE_SMALL

	mag_type = MAGAZINE
	caliber = "smartgun"
	max_ammo = 5
	ammo_type = /obj/item/ammo_casing/smartgun
	multiple_sprites = TRUE
