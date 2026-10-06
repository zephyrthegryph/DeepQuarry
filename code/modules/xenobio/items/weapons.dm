/obj/item/melee/baton/slime/get_mechanics_info(list/additional_information)
	return ..(list("This baton will stun a slime or other slime-based lifeform for about five seconds, if hit with it while on.") + additional_information)

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

/obj/item/melee/baton/slime/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(istype(M) && status) // Is it on?
		if(M.mob_class & MOB_CLASS_SLIME) // Are they some kind of slime? (Prommies might pass this check someday).
			if(isslime(M))
				var/mob/living/simple_mob/slime/S = M
				S.slimebatoned(user, 5) // Feral and xenobio slimes will react differently to this.
			else
				M.status_at_least(EFFECT_WEAKENED, 5)

		// Now for prommies.
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(H.species?.is_slime_bodied)
				var/agony_to_apply = 60 - agonyforce
				H.injure(INJURY_PAIN, agony_to_apply, source = src)

	..()
/obj/item/melee/baton/slime/loaded/Initialize(mapload)
	rel_set(src, nameof(bcell), new/obj/item/cell/device(src))
	update_icon()
	return ..()

// Xeno stun gun + projectile
/obj/item/gun/energy/taser/xeno/get_mechanics_info(list/additional_information)
	return ..(list("This gun will stun a slime or other lesser slimy lifeform for about two seconds if hit with the projectile it fires.") + additional_information)

/obj/item/gun/energy/taser/xeno
	name = "xeno taser gun"
	desc = "Straight out of NT's testing laboratories, this small gun is used to subdue non-humanoid xeno life forms. \
	While marketed towards handling slimes, it may be useful for other creatures."
	icon_state = "taserblue"
	fire_sound = SFX_WEAPONS_TASER2
	charge_cost = 120 // Twice as many shots.
	projectile_type = /obj/item/projectile/beam/stun/xeno
	accuracy = 30 // Make it a bit easier to hit the slimes.
	description_fluff = "An easy to use weapon designed by NanoTrasen, for NanoTrasen. This weapon is based on the NT Mk30 NL, \
	it's core components swaped out for a new design made to subdue lesser slime-based xeno lifeforms at a distance.  It is \
	ineffective at stunning non-slimy lifeforms such as humanoids."
	recoil_mode = 0

/*
REMOVAL
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
				L.status_at_least(EFFECT_WEAKENED, round(agony/2))

		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			if(H.species?.is_slime_bodied)
				if(agony == initial(agony)) // ??????
					agony = round((14 * agony) - agony) //60-4 = 56, 56 / 4 = 14. Prior was flat 60 - agony of the beam to equate to 60.

	..()


/obj/item/xenobio
	name = "xenobio gun"
	desc = "You shouldn't see this!"
	icon = 'icons/obj/gun.dmi'
	icon_state = "harpoon-2"
	var/loadable_item = null
	var/loaded_item = null
	var/loadable_name = null
	COOLDOWN_DECLARE(firable)
/obj/item/xenobio/examine(mob/user)
	. = ..()
	if(loaded_item)
		.+= "A [loaded_item] is slotted into the side."
	else
		.+= "There appears to be an empty slot for attaching a [loadable_name]."

DECLARE_INTERACTIONS(/obj/item/xenobio, \
	INTERACT_HAND(null, PROC_REF(interaction_hand)), \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_hand.
/obj/item/xenobio/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.get_inactive_hand() == src && loaded_item)
		user.put_in_hands(loaded_item)
		act_message(user, src, MSG_SELF(span_notice("You remove [loaded_item] from %T%.")), MSG_OTHERS(span_notice("%U% removes [loaded_item] from %T%.")))
		loaded_item = null
		play_sfx(src, SFX_WEAPONS_EMPTY)
	else
		return FALSE
	return TRUE

/// Old attackby.
/obj/item/xenobio/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, loadable_item))
		if(loaded_item)
			to_chat(user, span_warning("[I] doesn't seem to fit into [src]."))
			return INTERACTION_HANDLED_PASS
		if(!own_bring_in(src, nameof(loaded_item), I, null, user, TRUE, null, FALSE))
			return INTERACTION_HANDLED_PASS
		loaded_item = I
		act_message(user, src, MSG_SELF(span_notice("You slot [I] into %T%.")), MSG_OTHERS(span_notice("%U% inserts [I] into %T%.")))
		return 1
	return FALSE

/// Old attack_self.
/obj/item/xenobio/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(loaded_item)
		user.put_in_hands(loaded_item)
		act_message(user, src, MSG_SELF(span_notice("You remove [loaded_item] from %T%.")), MSG_OTHERS(span_notice("%U% removes [loaded_item] from %T%.")))
		loaded_item = null
		play_sfx(src, SFX_WEAPONS_EMPTY)
	return TRUE

/obj/item/xenobio/afterattack(atom/A, mob/user as mob)
	if(!loaded_item)
		to_chat(user,span_warning("\The [src] shot fizzles, it appears you need to load something!"))
		play_sfx(src, SFX_WEAPONS_EMPTY)
		return
	if(!COOLDOWN_FINISHED(src, firable))
		return

	play_sfx(src, SFX_WEAPONS_WAVE, vary = TRUE)

	act_message(user, src, MSG_SELF(span_warning("You fire %T%!")), MSG_OTHERS(span_warning("%U% fires %T%!")))

	fx_sparks(A, 4)
	fx_sparks(user, 4)

/obj/item/xenobio/monkey_gun
	name = "Bluespace Cube Rehydrator"
	desc = "Based on the technology of the 'Bluespace Harpoon' this device can teleport a loaded cube to a given target and rehydrate it."
	loadable_item = /obj/item/reagent_containers/food/snacks/monkeycube
	loadable_name = "Monkey Cube"

/obj/item/xenobio/monkey_gun/afterattack(atom/A, mob/user as mob)
	..()

	if(!COOLDOWN_FINISHED(src, firable))
		return

	var/turf/T = get_turf(A)
	if(!T || (T.check_density(ignore_mobs = TRUE)))
		to_chat(user,span_warning("Your rehydrator flashes an error as it attempts to process your target."))
		play_sfx(src, SFX_WEAPONS_EMPTY)
		return
	if(isliving(A))
		to_chat(user,span_warning("The rehydrator's saftey systems prevent firing into living creatures!"))
		play_sfx(src, SFX_WEAPONS_EMPTY)
		return
	if(loaded_item)
		var/obj/item/reagent_containers/food/snacks/monkeycube/cube = loaded_item
		cube.forceMove(A)
		cube.Expand()
		loaded_item = null
		COOLDOWN_START(src, firable, 2 SECONDS)

// Instead of bringing the slime to the grinder, lets bring the grinder to the slime! This will process slimes and monkies one at a time.
/obj/item/slime_grinder
	name = "portable slime processor"
	desc = "An industrial grinder used to automate the process of slime core extraction.  It can also recycle biomatter. This one appears miniturized"
	icon_state = "chainsaw0"
	var/processing = FALSE // So I heard you like processing.
	var/list/to_be_processed
	var/monkeys_recycled = 0

/// Set after a monkey is ground: make_cubes() runs every second while it is (DECLARE_REPEAT).
OM_FIELD(/obj/item/slime_grinder, cube_making, FALSE, CHANGE_EXPLICIT)
DECLARE_REPEAT(/obj/item/slime_grinder, 1 SECOND, make_cubes, "cube_making")

/// Grinds `AM`: one core per timed action for slimes; a monkey is one timed action, then cubes.
/obj/item/slime_grinder/proc/extract(atom/movable/AM, mob/living/user)
	processing = TRUE
	if(istype(AM, /mob/living/simple_mob/slime))
		grind_core(AM, user)
		return
	if(istype(AM, /mob/living/carbon/human/monkey))
		play_sfx(src, SFX_MACHINES_JUICER)
		om_task_timed(user, 1.5 SECONDS, src, src, PROC_REF(grind_monkey), list(AM), on_fail = PROC_REF(grind_ended))
		return
	processing = FALSE

/obj/item/slime_grinder/proc/grind_core(mob/living/simple_mob/slime/S, mob/living/user)
	if(!S.cores)
		consumed(S, src)
		processing = FALSE
		return
	play_sfx(src, SFX_MACHINES_JUICER)
	om_task_timed(user, 1.5 SECONDS, src, src, PROC_REF(grind_core_done), list(S, user), on_fail = PROC_REF(grind_ended))

/obj/item/slime_grinder/proc/grind_core_done(mob/living/simple_mob/slime/S, mob/living/user)
	new S.coretype(get_turf(S))
	play_sfx(src, SFX_EFFECTS_SPLAT)
	S.cores--
	grind_core(S, user)

/obj/item/slime_grinder/proc/grind_monkey(mob/living/carbon/human/M)
	play_sfx(src, SFX_EFFECTS_SPLAT)
	consumed(M, src)
	monkeys_recycled++
	set_cube_making(TRUE)

/// One monkey cube a second while four monkeys' worth is recycled.
/obj/item/slime_grinder/proc/make_cubes()
	if(monkeys_recycled < 4)
		processing = FALSE
		set_cube_making(FALSE)
		return REPEAT_STOP
	new /obj/item/reagent_containers/food/snacks/monkeycube(get_turf(src))
	play_sfx(src, SFX_EFFECTS_SPLAT)
	monkeys_recycled -= 4

/obj/item/slime_grinder/proc/grind_ended()
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
		play_sfx(src, SFX_MACHINES_BUZZ_SIGH, vary = TRUE)
		return ITEM_INTERACT_FAILURE

	extract(M, user)
	return ..()
