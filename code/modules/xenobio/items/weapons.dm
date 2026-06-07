/obj/item/melee/baton/slime
	name = "slimebaton"
	desc = "A modified stun baton designed to stun slimes and other lesser slimy xeno lifeforms for handling."
	icon_state = "slimebaton"
	item_state = "slimebaton"
	slot_flags = SLOT_BELT
	force = 9
	lightcolor = "#33CCFF"
	agonyforce = 10	//It's not supposed to be great at stunning human beings.
	hitcost = 48	//Less zap for less cost
	description_info = "This baton will stun a slime or other slime-based lifeform for about five seconds, if hit with it while on."

/obj/item/melee/baton/slime/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(istype(M) && status) // Is it on?
		if(M.mob_class & MOB_CLASS_SLIME) // Are they some kind of slime? (Prommies might pass this check someday).
			if(isslime(M))
				var/mob/living/simple_mob/slime/S = M
				S.slimebatoned(user, 5) // Feral and xenobio slimes will react differently to this.
			else
				M.Weaken(5)

		// Now for prommies.
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(H.species && H.species.name == SPECIES_PROMETHEAN)
				var/agony_to_apply = 60 - agonyforce
				H.apply_damage(agony_to_apply, HALLOSS)

	..()
/obj/item/melee/baton/slime/loaded/Initialize(mapload)
	bcell = new/obj/item/cell/device(src)
	update_icon()
	return ..()

// Xeno stun gun + projectile
/obj/item/gun/energy/taser/xeno
	name = "xeno taser gun"
	desc = "Straight out of NT's testing laboratories, this small gun is used to subdue non-humanoid xeno life forms. \
	While marketed towards handling slimes, it may be useful for other creatures."
	icon_state = "taserblue"
	fire_sound = 'sound/weapons/taser2.ogg'
	charge_cost = 120 // Twice as many shots.
	projectile_type = /obj/item/projectile/beam/stun/xeno
	accuracy = 30 // Make it a bit easier to hit the slimes.
	description_info = "This gun will stun a slime or other lesser slimy lifeform for about two seconds if hit with the projectile it fires."
	description_fluff = "An easy to use weapon designed by NanoTrasen, for NanoTrasen. This weapon is based on the NT Mk30 NL, \
	it's core components swaped out for a new design made to subdue lesser slime-based xeno lifeforms at a distance.  It is \
	ineffective at stunning non-slimy lifeforms such as humanoids."
	recoil_mode = 0

/*
VORESTATION REMOVAL
/obj/item/gun/energy/taser/xeno/sec //NT's corner-cutting option for their on-station security.
	desc = "An NT Mk30 NL retrofitted to fire beams for subduing non-humanoid slimy xeno life forms."
	icon_state = "taserblue"
	item_state = "taser"
	projectile_type = /obj/item/projectile/beam/stun/xeno/weak
	charge_cost = 480
	accuracy = 0 //Same accuracy as a normal Sec taser.
	description_fluff = "An NT Mk30 NL retrofitted after the events that occurred aboard the NRS Prometheus."

/obj/item/gun/energy/taser/xeno/sec/robot //Cyborg variant of the security xeno-taser.
	self_recharge = 1
	use_external_power = 1
	recharge_time = 3
*/

/obj/item/projectile/beam/stun/xeno
	icon_state = "omni"
	agony = 4
	nodamage = TRUE
	// For whatever reason the projectile qdels itself early if this is on, meaning on_hit() won't be called on prometheans.
	// Probably for the best so that it doesn't harm the slime.
	taser_effect = FALSE

	muzzle_type = /obj/effect/projectile/muzzle/laser_omni
	tracer_type = /obj/effect/projectile/tracer/laser_omni
	impact_type = /obj/effect/projectile/impact/laser_omni

/obj/item/projectile/beam/stun/xeno/weak //Weaker variant for non-research equipment, turrets, or rapid fire types.
	agony = 3

/obj/item/projectile/beam/stun/xeno/on_hit(atom/target, blocked = 0, def_zone = null)
	if(isliving(target))
		var/mob/living/L = target
		if(L.mob_class & MOB_CLASS_SLIME)
			if(isslime(L))
				var/mob/living/simple_mob/slime/S = L
				S.slimebatoned(firer, round(agony/2))
			else
				L.Weaken(round(agony/2))

		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			if(H.species && H.species.name == SPECIES_PROMETHEAN)
				if(agony == initial(agony)) // ??????
					agony = round((14 * agony) - agony) //60-4 = 56, 56 / 4 = 14. Prior was flat 60 - agony of the beam to equate to 60.

	..()


// === merged from weapons_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/xenobio
	name = "xenobio gun"
	desc = "You shouldn't see this!"
	icon = 'icons/obj/gun.dmi'
	icon_state = "harpoon-2"
	var/loadable_item = null
	var/loaded_item = null
	var/loadable_name = null
	var/firable = TRUE
/obj/item/xenobio/examine(mob/user)
	. = ..()
	if(loaded_item)
		.+= "A [loaded_item] is slotted into the side."
	else
		.+= "There appears to be an empty slot for attaching a [loadable_name]."

/obj/item/xenobio/attack_hand(mob/user as mob)
	if(user.get_inactive_hand() == src && loaded_item)
		user.put_in_hands(loaded_item)
		user.visible_message(span_notice("[user] removes [loaded_item] from [src]."), span_notice("You remove [loaded_item] from [src]."))
		loaded_item = null
		playsound(src, 'sound/weapons/empty.ogg', 50, 1)
	else
		return ..()

/obj/item/xenobio/attackby(obj/item/I as obj, mob/user as mob)
	if(istype(I, loadable_item))
		if(loaded_item)
			to_chat(user, span_warning("[I] doesn't seem to fit into [src]."))
			return
		//var/obj/item/reagent_containers/glass/beaker/B = I
		user.drop_item()
		I.loc = src
		loaded_item = I
		user.visible_message(span_notice("[user] inserts [I] into [src]."), span_notice("You slot [I] into [src]."))
		return 1
	..()

/obj/item/xenobio/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(loaded_item)
		user.put_in_hands(loaded_item)
		user.visible_message(span_notice("[user] removes [loaded_item] from [src]."), span_notice("You remove [loaded_item] from [src]."))
		loaded_item = null
		playsound(src, 'sound/weapons/empty.ogg', 50, 1)

/obj/item/xenobio/afterattack(atom/A, mob/user as mob)
	if(!loaded_item)
		to_chat(user,span_warning("\The [src] shot fizzles, it appears you need to load something!"))
		//playsound(src, 'sound/weapons/wave.ogg', 60, 1)
		playsound(src, 'sound/weapons/empty.ogg', 50, 1)
		return
	if(!firable)
		return

	playsound(src, 'sound/weapons/wave.ogg', 60, 1)

	user.visible_message(span_warning("[user] fires \the [src]!"),span_warning("You fire \the [src]!"))

	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(4, 1, A)
	s.start()
	s = new /datum/effect/effect/system/spark_spread
	s.set_up(4, 1, user)
	s.start()

/obj/item/xenobio/monkey_gun
	name = "Bluespace Cube Rehydrator"
	desc = "Based on the technology of the 'Bluespace Harpoon' this device can teleport a loaded cube to a given target and rehydrate it."
	loadable_item = /obj/item/reagent_containers/food/snacks/monkeycube
	loadable_name = "Monkey Cube"
	//projectile_type = /obj/item/projectile/beam/xenobio/monkey

/obj/item/xenobio/monkey_gun/afterattack(atom/A, mob/user as mob)
	..()

	if(!firable)
		return

	var/turf/T = get_turf(A)
	if(!T || (T.check_density(ignore_mobs = TRUE)))
		to_chat(user,span_warning("Your rehydrator flashes an error as it attempts to process your target."))
		playsound(src, 'sound/weapons/empty.ogg', 50, 1)
		return
	if(isliving(A))
		to_chat(user,span_warning("The rehydrator's saftey systems prevent firing into living creatures!"))
		playsound(src, 'sound/weapons/empty.ogg', 50, 1)
		return
	if(loaded_item)
		var/obj/item/reagent_containers/food/snacks/monkeycube/cube = loaded_item
		cube.loc = A
		cube.Expand()
		loaded_item = null
		firable = FALSE
		VARSET_IN(src, firable, TRUE, 2 SECONDS)

// Instead of bringing the slime to the grinder, lets bring the grinder to the slime! This will process slimes and monkies one at a time.
/obj/item/slime_grinder
	name = "portable slime processor"
	desc = "An industrial grinder used to automate the process of slime core extraction.  It can also recycle biomatter. This one appears miniturized"
	//icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "chainsaw0"
	var/processing = FALSE // So I heard you like processing.
	var/list/to_be_processed = list()
	var/monkeys_recycled = 0
	description_info = "Click a monkey or slime to begin processing."

/obj/item/slime_grinder/proc/extract(atom/movable/AM, mob/living/user)
	processing = TRUE
	if(istype(AM, /mob/living/simple_mob/slime))
		var/mob/living/simple_mob/slime/S = AM
		while(S.cores)
			playsound(src, 'sound/machines/juicer.ogg', 25, 1)
			if(do_after(user, 15, target = src))
				var/atom/new_core = new S.coretype(get_turf(AM))
				SEND_GLOBAL_SIGNAL(COMSIG_GLOB_HARVEST_SLIME_CORE, new_core)
				playsound(src, 'sound/effects/splat.ogg', 50, 1)
				S.cores--
		qdel(S)

	if(istype(AM, /mob/living/carbon/human/monkey))
		playsound(src, 'sound/machines/juicer.ogg', 25, 1)
		if(do_after(user, 15, target = src))
			var/mob/living/carbon/human/M = AM
			playsound(src, 'sound/effects/splat.ogg', 50, 1)
			qdel(M)
			monkeys_recycled++
			sleep(1 SECOND)
		while(monkeys_recycled >= 4)
			new /obj/item/reagent_containers/food/snacks/monkeycube(get_turf(src))
			playsound(src, 'sound/effects/splat.ogg', 50, 1)
			monkeys_recycled -= 4
			sleep(1 SECOND)
	processing = FALSE

/obj/item/slime_grinder/proc/can_insert(atom/movable/AM)
	if(istype(AM, /mob/living/simple_mob/slime))
		var/mob/living/simple_mob/slime/S = AM
		if(S.stat != DEAD)
			return FALSE
		return TRUE
	if(ishuman(AM))
		var/mob/living/carbon/human/H = AM
		if(!istype(H.species, /datum/species/monkey))
			return FALSE
		if(H.stat != DEAD)
			return FALSE
		return TRUE
	return FALSE

/obj/item/slime_grinder/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(processing)
		return ITEM_INTERACT_FAILURE
	if(!can_insert(M))
		to_chat(user, span_warning("\The [src] cannot process \the [M] at this time."))
		playsound(src, 'sound/machines/buzz-sigh.ogg', 50, 1)
		return ITEM_INTERACT_FAILURE

	extract(M, user)
	return ..()
