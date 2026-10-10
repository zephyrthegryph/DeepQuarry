// What a table does to what comes at it and what is done to it: the movement checks and the cover for projectiles, and the conditions and effects of the
// ops its CAPABILITIES list (tables.dm) names: putting things on it, a person on it, a face against it.

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
	if(locate_within(get_turf(mover), /obj/structure/table/bench))
		return FALSE
	var/obj/structure/table/table = locate_within(get_turf(mover), /obj/structure/table)
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

// ---- putting things on the table ----

/// The held item is in the actor's hands (or a cyborg's module): not something mounted elsewhere.
/obj/structure/table/proc/held_is_carried(datum/act/op/A)
	return (A.held.loc == A.actor) ? null : MSG(table/not_in_hand) // ALLOW(reads): where the held item is read when it is put down; the click asks again

/// A held item goes onto the table (a click): a cyborg's gripper sets down what it carries; anything else the actor lets go of, aligned to where they clicked.
/obj/structure/table/proc/place_held(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(isrobot(user))
		if(istype(W, /obj/item/gripper))
			var/obj/item/gripper/robot_gripper = W
			var/obj/item/item_to_drop = robot_gripper.get_wrapped_item()
			robot_gripper.drop_item_nm(loc)
			item_to_drop.do_drop_animation(user)
			auto_align(item_to_drop, dq_interaction_click_params(user))
		return OP_OK
	// Placing stuff on tables
	if(user.unEquip(W, 0, src.loc) && user.client?.prefs?.read_preference(/datum/preference/toggle/precision_placement))
		W.do_drop_animation(user)
		auto_align(W, dq_interaction_click_params(user))
	return OP_OK

/// An energy blade or a changeling's arm blade cuts the table apart.
/obj/structure/table/proc/sliced_apart(datum/act/op/A)
	var/mob/user = A.actor
	if(istype(A.held, /obj/item/melee/energy/blade))
		fx_sparks(src.loc, 5, FALSE)
		play_sfx(src, SFX_WEAPONS_BLADE1)
		play_sfx(src, SFX_SPARKS)
	act_message(src, user, others = span_danger("%U% was sliced apart by %T%!"))
	break_to_parts()
	return OP_OK

/// A drag onto the table is the reinforcing of a plated one with a steel stack held in hand: the build ladder's edge takes that drag when it can, and
/// otherwise, with the stack held in hand, the table says why it cannot be reinforced and nothing is put down.
/obj/structure/table/proc/reinforce_refusal(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!(can_reinforce && isliving(user) && istype(A.held, /obj/item/stack/material) && A.held.loc == user)) // ALLOW(reads): where the dragged stack is read when it is dropped on the table; the drop asks again
		return null
	if(reinforced())
		return /datum/msg/table/already_reinforced
	if(!material())
		return /datum/msg/table/plate_first
	if(flipped)
		return /datum/msg/table/put_back_first
	return null

/// A thing dragged onto the table (an old MouseDrop_T): an item from the hand is let go onto it; a small one lying beside it is pushed on.
/obj/structure/table/proc/place_dragged(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/O = A.held
	if(user.stat)
		return OP_OK
	if(ismob(O.loc)) //If placing an item
		if(!isitem(O) || user.get_active_hand() != O)
			return OP_OK
		if(isrobot(user))
			return OP_OK
		user.drop_item()
		if(O.loc != src.loc)
			step(O, get_dir(O, src))
	else if(isturf(O.loc) && isitem(O)) //If pushing an item on the tabletop
		var/obj/item/I = O
		if(I.anchored)
			return OP_OK
		if((isliving(user)) && (Adjacent(user)) && !(user.incapacitated()))
			if(O.w_class <= user.can_pull_size)
				O.forceMove(loc)
				auto_align(I, dq_interaction_click_params(user), TRUE)
			else
				to_chat(user, span_warning("\The [I] is too big for you to move!"))
	return OP_OK

// ---- a person on the table, or against it ----

/// The held thing is a grab on somebody, with the grabber at the table.
/obj/structure/table/proc/person_grabbed(datum/act/op/A)
	var/obj/item/grab/G = A.held
	return (get_dist(src, A.actor) < 2 && isliving(G?.grab_target())) ? null : /datum/msg/req_failed

/// A grab that can put its person on the table: nothing in the way (the person must also be at the grabber's side: the effect asks).
/obj/structure/table/proc/person_can_go_on(datum/act/op/A)
	return can_climb_turf(src) ? /datum/msg/table/in_the_way : null

/// A firm grab sets the person on the table and knocks them down; a loose one lets go of them (the grab is used up either way).
/obj/structure/table/proc/put_person_on(datum/act/op/A)
	var/obj/item/grab/G = A.held
	var/mob/living/M = G?.grab_target()
	if(!A.actor.Adjacent(M))
		return OP_REFUSED
	if(G.state < 2)
		to_chat(A.actor, span_danger("You need a better grip to do that!"))
	else if(G.state > GRAB_AGGRESSIVE || COOLDOWN_FINISHED(G, upgrade_cooldown))
		M.forceMove(get_turf(src))
		M.status_at_least(STAT_WEAKENED, 5)
		visible_message(span_danger("[G?.grab_assailant()] puts [G?.grab_target()] on \the [src]."))
	consume(G, A.actor)
	return OP_OK

/// The slam applies to a loose grab on somebody in reach with nothing in the way: a firmer grab puts the person on the table instead.
/obj/structure/table/proc/slam_applies(datum/act/op/A)
	var/obj/item/grab/G = A.held
	var/mob/living/M = G?.grab_target()
	if(get_dist(src, A.actor) >= 2 || G.state >= 2) // ALLOW(reads): how firm a grab is is read when it is used; the click asks again
		return /datum/msg/req_failed
	return (isliving(M) && !can_climb_turf(src)) ? null : /datum/msg/req_failed

/// A loosely grabbed person's face is slammed against the table (combat mode only).
/obj/structure/table/proc/slam_face(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/grab/G = A.held
	var/mob/living/M = G?.grab_target()
	if(!user.Adjacent(M))
		return OP_REFUSED
	if (prob(15))	M.status_at_least(STAT_WEAKENED, 5)
	M.injure(INJURY_BLUNT, 8, BP_HEAD, src)
	visible_message(span_danger("[G?.grab_assailant()] slams [G?.grab_target()]'s face against \the [src]!"))
	if(material())
		playsound(src, material().tableslam_noise, 50, 1)
	else
		play_sfx(src, SFX_WEAPONS_TABLEHIT1, 2, extrarange = 0)
	last_break_shards = null
	take_damage(rand(1,5), BRUTE, MELEE)
	var/list/L = last_break_shards
	last_break_shards = null
	// Shards. Extra damage, plus potentially the fact YOU LITERALLY HAVE A PIECE OF GLASS/METAL/WHATEVER IN YOUR FACE
	for(var/obj/item/material/shard/S in L)
		if(prob(50))
			act_message(M, null, MSG_SELF(span_danger("%I% slices your face messily!")), MSG_OTHERS(span_danger("%I% slices %U%'s face messily!")), item = S)
			M.injure(INJURY_BLUNT, 10, BP_HEAD, src)
			if(prob(2))
				M.embed(S, def_zone = BP_HEAD)
	consume(G, user)
	return OP_OK
