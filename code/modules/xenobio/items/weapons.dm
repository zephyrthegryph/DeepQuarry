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
				M.status_at_least(STAT_WEAKENED, 5)

		// Now for prommies.
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(H.species?.is_slime_bodied)
				var/agony_to_apply = 60 - agonyforce
				H.injure(INJURY_PAIN, agony_to_apply, source = src)

	..()
CAPABILITIES(/obj/item/melee/baton/slime/loaded)
	owns_one(nameof(bcell), /obj/item/cell, starts = /obj/item/cell/device) // starts with a cell installed

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
				L.status_at_least(STAT_WEAKENED, round(agony/2))

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

CAPABILITIES(/obj/item/xenobio)
	op("interaction_hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("interaction_self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("interaction_item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attack_hand.
/obj/item/xenobio/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.get_inactive_hand() == src && loaded_item)
		user.put_in_hands(loaded_item)
		act_message(user, src, MSG_SELF(span_notice("You remove [loaded_item] from %T%.")), MSG_OTHERS(span_notice("%U% removes [loaded_item] from %T%.")))
		loaded_item = null
		play_sfx(src, SFX_WEAPONS_EMPTY)
	else
		return OP_DECLINE
	return OP_OK

/// Old attackby.
/obj/item/xenobio/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, loadable_item))
		if(loaded_item)
			to_chat(user, span_warning("[I] doesn't seem to fit into [src]."))
			return OP_PASS
		if(!own_bring_in(src, nameof(loaded_item), I, null, user, TRUE, null, FALSE))
			return OP_PASS
		loaded_item = I
		act_message(user, src, MSG_SELF(span_notice("You slot [I] into %T%.")), MSG_OTHERS(span_notice("%U% inserts [I] into %T%.")))
		return OP_OK
	return OP_DECLINE

/// Old attack_self.
/obj/item/xenobio/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(loaded_item)
		user.put_in_hands(loaded_item)
		act_message(user, src, MSG_SELF(span_notice("You remove [loaded_item] from %T%.")), MSG_OTHERS(span_notice("%U% removes [loaded_item] from %T%.")))
		loaded_item = null
		play_sfx(src, SFX_WEAPONS_EMPTY)
	return OP_OK

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
	var/list/to_be_processed
	var/monkeys_recycled = 0

/// Set after a monkey is ground: make_cubes() runs every second while it is (every()).
/obj/item/slime_grinder/var/cube_making = FALSE
TRACKED(/obj/item/slime_grinder, cube_making)

/// What the grinder is working on: the REF text of the target of the running grind, or "cubes" while the last monkey's cubes are made. Null: free.
/obj/item/slime_grinder/var/grinding = null

// Instead of bringing the slime to the grinder, lets bring the grinder to the slime! This will process slimes and monkies one at a time:
// the grinder is busy for a whole grind, a slime's cores one timed action each, a monkey one timed action and then the cubes.
CAPABILITIES(/obj/item/slime_grinder)
	every(1 SECOND, then(PROC_REF(make_cubes)), when = nameof(cube_making))
	op("grind_monkey", at_target(/mob/living/carbon/human/monkey), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Grind"),
		needs(req_adjacent(), req_bool(PROC_REF(grinder_free), silent = TRUE), req_bool(PROC_REF(target_processable), because = PROC_REF(cannot_process_text))),
		claims(0), starts(PROC_REF(grind_started)), wait(1.5 SECONDS), on_interrupt(PROC_REF(grind_ended)), then(PROC_REF(grind_monkey)))
	op("grind_slime", at_target(/mob/living/simple_mob/slime), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Grind"),
		needs(req_adjacent(), req_bool(PROC_REF(grinder_free), silent = TRUE), req_bool(PROC_REF(target_processable), because = PROC_REF(cannot_process_text))),
		claims(0), starts(PROC_REF(grind_started)), wait(1.5 SECONDS), on_interrupt(PROC_REF(grind_ended)), then(PROC_REF(grind_core_done)))

/// Requirement: nothing else is being ground (another target, or the cubes of the last monkey). The grind the op itself started does not refuse it.
/obj/item/slime_grinder/proc/grinder_free(datum/act/op/A)
	var/working = read_once(grinding) // a plain var: the juicer starts inside the wait, and a published write there would re-check the op half-started
	return isnull(working) || working == "\ref[A.target]"

/// Requirement: the target is a dead slime or a dead monkey.
/obj/item/slime_grinder/proc/target_processable(datum/act/op/A)
	return can_insert(A.target)

/obj/item/slime_grinder/proc/cannot_process_text(datum/act/op/A)
	return span_warning("\The [src] cannot process \the [A.target] at this time.")

/// The juicer starts and the grinder is busy until the grind ends.
/obj/item/slime_grinder/proc/grind_started(datum/act/op/A)
	play_sfx(src, SFX_MACHINES_JUICER)
	grinding = "\ref[A.target]"

/// A grind that ends without finishing: the grinder is free again.
/obj/item/slime_grinder/proc/grind_ended(datum/act/op/A)
	grinding = null

/// One core out of the slime; the next core is the same op again, and a slime with none left is consumed.
/obj/item/slime_grinder/proc/grind_core_done(datum/act/op/A)
	var/mob/living/simple_mob/slime/S = A.target
	grinding = null
	if(S.cores > 0)
		new S.coretype(get_turf(S))
		play_sfx(src, SFX_EFFECTS_SPLAT)
		S.cores--
	if(S.cores > 0)
		log_game("slime grinder: [key_name(A.actor)] keeps grinding [S] ([S.cores] cores left)")
		perform_op(A.actor, S, "grind_slime", src, ORIGIN_SYSTEM, AUTH_PHYSICAL)
		return OP_OK
	consumed(S, src)
	return OP_OK

/obj/item/slime_grinder/proc/grind_monkey(datum/act/op/A)
	play_sfx(src, SFX_EFFECTS_SPLAT)
	consumed(A.target, src)
	monkeys_recycled++
	grinding = "cubes" // the grinder stays busy until the cubes are made
	set_cube_making(TRUE)
	return OP_OK

/// One monkey cube a second while four monkeys' worth is recycled.
/obj/item/slime_grinder/proc/make_cubes(datum/act/timer/A)
	if(monkeys_recycled < 4)
		grinding = null
		set_cube_making(FALSE)
		return
	new /obj/item/reagent_containers/food/snacks/monkeycube(get_turf(src))
	play_sfx(src, SFX_EFFECTS_SPLAT)
	monkeys_recycled -= 4

/obj/item/slime_grinder/proc/can_insert(atom/movable/AM)
	if(istype(AM, /mob/living/simple_mob/slime))
		var/mob/living/simple_mob/slime/S = AM
		if(read_once(S.stat) != DEAD)
			return FALSE
		return TRUE
	if(ishuman(AM))
		var/mob/living/carbon/human/H = AM
		if(!istype(read_once(H.species), /datum/species/monkey))
			return FALSE
		if(read_once(H.stat) != DEAD)
			return FALSE
		return TRUE
	return FALSE
