/obj/item/extinguisher
	name = "fire extinguisher"
	desc = "A traditional red fire extinguisher."
	icon = 'icons/obj/items.dmi'
	icon_state = "fire_extinguisher0"
	item_state = "fire_extinguisher"
	hitsound = 'sound/weapons/smash.ogg'
	throwforce = 10
	w_class = ITEMSIZE_NORMAL
	throw_speed = 2
	throw_range = 10
	force = 10
	MATERIAL_BULK(MAT_STEEL, 90)
	attack_verb = list("slammed", "whacked", "bashed", "thunked", "battered", "bludgeoned", "thrashed")
	drop_sound = 'sound/items/drop/gascan.ogg'
	pickup_sound = 'sound/items/pickup/gascan.ogg'

	var/spray_particles = 3
	var/spray_amount = 10	//units of liquid per particle
	var/max_water = 300
	COOLDOWN_DECLARE(use_cooldown)
	var/safety = 1
	var/sprite_name = "fire_extinguisher"
	var/rand_overlays = 6

/obj/item/extinguisher/mini
	name = "fire extinguisher"
	desc = "A light and compact fibreglass-framed model fire extinguisher."
	icon_state = "miniFE0"
	item_state = "miniFE"
	hitsound = null	//it is much lighter, after all.
	throwforce = 2
	w_class = ITEMSIZE_SMALL
	force = 3.0
	max_water = 150
	spray_particles = 3
	sprite_name = "miniFE"
	rand_overlays = 0

/obj/item/extinguisher/atmo
	name = "atmospheric fire extinguisher"
	desc = "A heavy duty fire extinguisher meant to fight large fires."
	icon_state = "atmos_extinguisher0"
	item_state = "atmos_extinguisher"
	throwforce = 12
	force = 12
	w_class = ITEMSIZE_LARGE
	max_water = 600
	spray_particles = 3
	sprite_name = "atmos_extinguisher"
	rand_overlays = 0

/obj/item/extinguisher/Initialize(mapload)
	create_reagents(max_water)
	reagents.add_reagent(REAGENT_ID_FIREFOAM, max_water)
	if(rand_overlays)
		var/choice = rand(1,rand_overlays)
		add_overlay("[item_state]O[choice]")
	. = ..()

/obj/item/extinguisher/examine(mob/user)
	. = ..()
	if(get_dist(user, src) == 0)
		. += "[src] has [src.reagents.total_volume] units of foam left!"

/obj/item/extinguisher/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	safety = !safety
	icon_state = "[sprite_name][!safety]"
	desc = "The safety is [safety ? "on" : "off"]."
	to_chat(user, "The safety is [safety ? "on" : "off"].")

/obj/item/extinguisher/proc/propel_object(obj/O, mob/user, movementdirection)
	if(O.anchored) return

	// Six pushes slowing down (each sets a chair's propelled countdown), then three more.
	var/list/move_speed = list(1, 1, 1, 2, 2, 3, 3, 3, 3)
	var/delay = 0
	for(var/i in 1 to 9)
		om_after(O, delay, TYPE_PROC_REF(/obj, extinguisher_propel_step), user, movementdirection, i <= 6 ? 6 - i : null)
		delay += move_speed[i]

/// One push of an extinguisher's recoil on the thing its user sits on.
/obj/proc/extinguisher_propel_step(mob/user, movementdirection, propelled)
	var/obj/structure/bed/chair/C = src
	if(istype(C) && !isnull(propelled))
		C.propelled = propelled
	Move(get_step(user, movementdirection), movementdirection)

/obj/item/extinguisher/afterattack(atom/target, mob/user, flag)
	//TODO; Add support for reagents in water.

	if( istype(target, /obj/structure/reagent_dispensers) && flag)
		var/obj/o = target
		var/amount = o.reagents.trans_to_obj(src, 50)
		to_chat(user, span_notice("You fill [src] with [amount] units of the contents of [target]."))
		playsound(src, 'sound/effects/refill.ogg', 50, 1, -6)
		return

	if (!safety)
		if (src.reagents.total_volume < 1)
			to_chat(user, span_notice("\The [src] is empty."))
			return

		if (!COOLDOWN_FINISHED(src, use_cooldown))
			return

		COOLDOWN_START(src, use_cooldown, 20)

		playsound(src, 'sound/effects/extinguish.ogg', 75, 1, -3)

		var/direction = get_dir(src,target)

		if(user?.buckled_to() && isobj(user?.buckled_to()))
			propel_object(user?.buckled_to(), user, turn(direction,180))

		var/turf/T = get_turf(target)
		var/turf/T1 = get_step(T,turn(direction, 90))
		var/turf/T2 = get_step(T,turn(direction, -90))

		var/list/the_targets = list(T,T1,T2)

		for(var/a = 1 to spray_particles)
			spray_particle(a, the_targets)

		if((istype(user.loc, /turf/space)) || (user.lastarea.get_gravity() == 0))
			user.inertia_dir = get_dir(target, user)
			step(user, user.inertia_dir)
	else
		return ..()
	return

/obj/item/extinguisher/proc/spray_particle(a, list/the_targets)
	if(!src || !reagents.total_volume) return

	var/obj/effect/effect/water/W = new /obj/effect/effect/water(get_turf(src))
	var/turf/my_target
	if(a <= the_targets.len)
		my_target = the_targets[a]
	else
		my_target = pick(the_targets)
	W.create_reagents(spray_amount)
	reagents.trans_to_obj(W, spray_amount)
	W.set_color()
	W.set_up(my_target)
