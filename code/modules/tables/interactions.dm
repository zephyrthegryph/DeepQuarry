/obj/structure/table/CanPass(atom/movable/mover, turf/target)
	if(istype(mover,/obj/item/projectile))
		return (check_cover(mover,target))
	if(mover.z > z)
		return TRUE //This allows mobs to drop down onto tables from above
	if(flipped == 1)
		if(get_dir(mover, target) == GLOB.reverse_dir[dir]) // From elsewhere to here, can't move against our dir
			return !density
		return TRUE
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	if(locate(/obj/structure/table/bench) in get_turf(mover))
		return FALSE
	var/obj/structure/table/table = locate(/obj/structure/table) in get_turf(mover)
	if(table && !(table.flipped == 1))
		return TRUE
	return FALSE

/obj/structure/table/Uncross(atom/movable/mover, turf/target)
	if(flipped == 1 && (get_dir(mover, target) == dir)) // From here to elsewhere, can't move in our dir
		return !density
	return TRUE

//checks if projectile 'P' from turf 'from' can hit whatever is behind the table. Returns 1 if it can, 0 if bullet stops.
/obj/structure/table/proc/check_cover(obj/item/projectile/P, turf/from)
	var/turf/cover
	if(flipped==1)
		cover = get_turf(src)
	else if(flipped==0)
		cover = get_step(loc, get_dir(from, loc))
	if(!cover)
		return 1
	if (get_dist(P.starting, loc) <= 1) //Tables won't help you if people are THIS close
		return 1
	if (get_turf(P.original()) == cover)
		var/chance = 20
		if (ismob(P.original()))
			var/mob/M = P.original()
			if (M.lying)
				chance += 20				//Lying down lets you catch less bullets
		if(flipped==1)
			if(get_dir(loc, from) == dir)	//Flipped tables catch mroe bullets
				chance += 20
			else
				return 1					//But only from one side
		if(prob(chance))
			take_damage(P.damage/2, P.obj_damage_type(), BULLET)
			if(!QDELETED(src))
				visible_message(span_warning("[P] hits \the [src]!"))
				return 0
			else
				return 1
	return 1

/// Old MouseDrop_T: reinforce with a dragged stack, or place or push an item onto the table.
/obj/structure/table/proc/interaction_drag(mob/user, obj/O, datum/interaction/interaction)
	if(user.stat)
		return INTERACTION_HANDLED_PASS
	if(can_reinforce && isliving(user) && istype(O, /obj/item/stack/material) && user.get_active_hand() == O && Adjacent(user))
		reinforce_table(O, user)
	else if(ismob(O.loc)) //If placing an item
		if(!isitem(O) || user.get_active_hand() != O)
			return FALSE
		if(isrobot(user))
			return INTERACTION_HANDLED_PASS
		user.drop_item()
		if(O.loc != src.loc)
			step(O, get_dir(O, src))

	else if(isturf(O.loc) && isitem(O)) //If pushing an item on the tabletop
		var/obj/item/I = O
		if(I.anchored)
			return INTERACTION_HANDLED_PASS

		if((isliving(user)) && (Adjacent(user)) && !(user.incapacitated()))
			if(O.w_class <= user.can_pull_size)
				O.forceMove(loc)
				auto_align(I, dq_interaction_click_params(user), TRUE)
			else
				to_chat(user, span_warning("\The [I] is too big for you to move!"))
			return INTERACTION_HANDLED_PASS

	return FALSE


/// Old attackby (interactions.dm): table a grabbed mob, cut the table apart, or put the item on it.
/obj/structure/table/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if (!W) return INTERACTION_HANDLED_PASS

	// Tabling a grabbed mob (slamming one is the hostile interaction_slam()).
	if(istype(W, /obj/item/grab) && get_dist(src,user)<2)
		var/obj/item/grab/G = W
		if (isliving(G?.grab_target()))
			var/mob/living/M = G?.grab_target()
			var/obj/occupied = can_climb_turf(src)
			if(occupied)
				to_chat(user, span_danger("There's \a [occupied] in the way."))
				return INTERACTION_HANDLED_PASS
			if(!user.Adjacent(M))
				return INTERACTION_HANDLED_PASS
			if (G.state < 2)
				to_chat(user, span_danger("You need a better grip to do that!"))
				return INTERACTION_HANDLED_PASS
			else if(G.state > GRAB_AGGRESSIVE || world.time >= (G.last_action + UPGRADE_COOLDOWN))
				M.forceMove(get_turf(src))
				M.status_at_least(EFFECT_WEAKENED, 5)
				visible_message(span_danger("[G?.grab_assailant()] puts [G?.grab_target()] on \the [src]."))
			consume(W, user)
			return INTERACTION_HANDLED_PASS

	// Handle dismantling or placing things on the table from here on.
	if(isrobot(user))
		if(istype(W, /obj/item/gripper))
			var/obj/item/gripper/robot_gripper = W
			var/obj/item/item_to_drop = robot_gripper.get_wrapped_item()
			robot_gripper.drop_item_nm(loc)
			item_to_drop.do_drop_animation(user)
			auto_align(item_to_drop, dq_interaction_click_params(user))
		return INTERACTION_HANDLED_PASS

	if(W.loc != user) // This should stop mounted modules ending up outside the module.
		return INTERACTION_HANDLED_PASS

	if(istype(W, /obj/item/melee/energy/blade))
		var/datum/effect/effect/system/spark_spread/spark_system = new /datum/effect/effect/system/spark_spread()
		spark_system.set_up(5, 0, src.loc)
		spark_system.start()
		playsound(src, 'sound/weapons/blade1.ogg', 50, 1)
		playsound(src, "sparks", 50, 1)
		user.visible_message(span_danger("\The [src] was sliced apart by [user]!"))
		break_to_parts()
		return INTERACTION_HANDLED_PASS

	if(istype(W, /obj/item/melee/changeling/arm_blade))
		user.visible_message(span_danger("\The [src] was sliced apart by [user]!"))
		break_to_parts()
		return INTERACTION_HANDLED_PASS

	if(can_plate && !material())
		to_chat(user, span_warning("There's nothing to put \the [W] on! Try adding plating to \the [src] first."))
		return INTERACTION_HANDLED_PASS

// Placing stuff on tables
	if(user.unEquip(W, 0, src.loc) && user.client?.prefs?.read_preference(/datum/preference/toggle/precision_placement))
		W.do_drop_animation(user)
		auto_align(W, dq_interaction_click_params(user))
		return 1
	return INTERACTION_HANDLED_PASS

/// Old attackby's harm branch: slam a loosely grabbed mob's face into the table (combat mode only).
/// A firmer grab falls through to interaction_item(), which puts them on the table.
/obj/structure/table/proc/interaction_slam(mob/user, obj/item/grab/G, datum/interaction/interaction)
	if(get_dist(src, user) >= 2 || G.state >= 2)
		return FALSE
	var/mob/living/M = G?.grab_target()
	if(!isliving(M) || can_climb_turf(src) || !user.Adjacent(M))
		return FALSE
	if (prob(15))	M.status_at_least(EFFECT_WEAKENED, 5)
	M.injure(INJURY_BLUNT, 8, BP_HEAD, src)
	visible_message(span_danger("[G?.grab_assailant()] slams [G?.grab_target()]'s face against \the [src]!"))
	if(material)
		playsound(src, material.tableslam_noise, 50, 1)
	else
		playsound(src, 'sound/weapons/tablehit1.ogg', 50, 1)
	last_break_shards = null
	take_damage(rand(1,5), BRUTE, MELEE)
	var/list/L = last_break_shards
	last_break_shards = null
	// Shards. Extra damage, plus potentially the fact YOU LITERALLY HAVE A PIECE OF GLASS/METAL/WHATEVER IN YOUR FACE
	for(var/obj/item/material/shard/S in L)
		if(prob(50))
			M.visible_message(span_danger("\The [S] slices [M]'s face messily!"),
								span_danger("\The [S] slices your face messily!"))
			M.injure(INJURY_BLUNT, 10, BP_HEAD, src)
			if(prob(2))
				M.embed(S, def_zone = BP_HEAD)
	consume(G, user)
	return TRUE

/obj/structure/table/attack_tk() // no telehulk sorry
	return
