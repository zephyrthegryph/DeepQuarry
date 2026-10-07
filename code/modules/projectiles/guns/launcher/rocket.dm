/obj/item/gun/launcher/rocket
	name = "rocket launcher"
	desc = "MAGGOT."
	icon_state = "rocket"
	item_state = "rocket"
	w_class = ITEMSIZE_HUGE //.
	throw_speed = 2
	throw_range = 10
	force = 5.0
	slot_flags = 0
	fire_sound = SFX_WEAPONS_RPG

	release_force = 15
	throw_distance = 30
	var/max_rockets = 1
	var/list/rockets

/obj/item/gun/launcher/rocket/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		. += span_blue("[length(rockets)] / [max_rockets] rockets.")

// Loaded rockets sit in the launcher's contents.
/obj/item/gun/launcher/rocket/ownership()
	. = ..()
	. += owns(nameof(rockets), policy = OWN_CONTAINED, is_list = TRUE)

/// Old attackby. It never called ..(): any item stops here, but afterattack still follows.
/obj/item/gun/launcher/rocket/gun_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	. = OP_PASS
	if(istype(I, /obj/item/ammo_casing/rocket))
		if(length(rockets) < max_rockets)
			if(!move_into(src, nameof(src.rockets), I, user))
				return
			to_chat(user, span_blue("You put the rocket in [src]."))
			to_chat(user, span_blue("[length(rockets)] / [max_rockets] rockets."))
		else
			to_chat(user, span_red(">[src] cannot hold more rockets."))

/obj/item/gun/launcher/rocket/consume_next_projectile()
	if(length(rockets))
		var/obj/item/ammo_casing/rocket/I = LAZYACCESS(rockets, 1)
		var/projectile_path = I.projectile_type
		own_remove(src, nameof(rockets), I) // the rocket is spent
		return new projectile_path(src)
	return null

/obj/item/gun/launcher/rocket/handle_post_fire(mob/user, atom/target)
	message_admins("[key_name_admin(user)] fired a rocket from a rocket launcher ([src.name]) at [target].")
	log_game("[key_name_admin(user)] used a rocket launcher ([src.name]) at [target].")
	..()
