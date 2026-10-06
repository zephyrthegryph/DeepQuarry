// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

// Based on railing.dmi from https://github.com/Endless-Horizon/CEV-Eris
/obj/structure/railing
	name = "railing"
	debris_type = /obj/item/stack/rods
	desc = "A standard steel railing, painted orange.  Play stupid games, win stupid prizes."
	icon = 'icons/obj/railing.dmi'
	density = TRUE
	throwpass = 1
	layer = WINDOW_LAYER
	anchored = TRUE
	flags = ON_BORDER
	icon_state = "railing0"
	var/broken = FALSE
	max_integrity = 70
	var/interactable = FALSE
	var/check = 0
	var/icon_modifier = ""

/obj/structure/railing/grey
	name = "grey railing"
	desc = "A standard steel railing. Prevents stupid people from falling to their doom."
	icon_modifier = "grey_"
	icon_state = "grey_railing0"

/// A railing a player built (its constructor param).
/obj/structure/railing/var/constructed = FALSE

// ALLOW(init/INSTANCE_STATE): a railing turns, a player-built one starts loose, and an anchored one joins its neighbours
/obj/structure/railing/Initialize(mapload)
	. = ..()
	// TODO - "constructed" is not passed to us. We need to find a way to do this safely.
	if (constructed) // player-constructed railings
		set_anchored(FALSE)
	make_rotatable()
	if(src.anchored)
		update_icon()

CAPABILITIES(/obj/structure/railing)
	climb(delay = 3.4 SECONDS, vaulting = TRUE, climbed = PROC_REF(climbed_over))
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))
	op("use_welder", tool(TOOL_WELDER), wait(0), costs(RES_FUEL, 0), then(PROC_REF(welder_used)))
	param(nameof(constructed), pos = 1)

/// A railing that is not anchored breaks under whoever climbed it.
/obj/structure/railing/proc/climbed_over(mob/living/climber)
	if(!anchored)
		take_damage(9999, BRUTE, MELEE)

DESTROY_EFFECTS(/obj/structure/railing, new /datum/destroy_effects_data(neighbor_type = /obj/structure/railing, neighbor_reconnect = FALSE))

/obj/structure/railing/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	if(get_dir(mover, target) == GLOB.reverse_dir[dir]) // From elsewhere to here, can't move against our dir
		return !density
	return TRUE

/obj/structure/railing/Uncross(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	if(get_dir(mover, target) == dir) // From here to elsewhere, can't move in our dir
		return !density
	return TRUE

/obj/structure/railing/atom_destruction(damage_flag)
	if(dq_destroy_effects_once(src))
		visible_message(span_warning("\The [src] breaks down!"))
		play_sfx(src, SFX_EFFECTS_GRILLEHIT)
	return ..()

/obj/structure/railing/proc/NeighborsCheck(UpdateNeighbors = 1)
	check = 0
	var/Rturn = turn(src.dir, -90)
	var/Lturn = turn(src.dir, 90)

	for(var/obj/structure/railing/R in src.loc)
		if ((R.dir == Lturn) && R.anchored)
			check |= 32
			if (UpdateNeighbors)
				R.update_icon()
		if ((R.dir == Rturn) && R.anchored)
			check |= 2
			if (UpdateNeighbors)
				R.update_icon()

	for (var/obj/structure/railing/R in get_step(src, Lturn))
		if ((R.dir == src.dir) && R.anchored)
			check |= 16
			if (UpdateNeighbors)
				R.update_icon()
	for (var/obj/structure/railing/R in get_step(src, Rturn))
		if ((R.dir == src.dir) && R.anchored)
			check |= 1
			if (UpdateNeighbors)
				R.update_icon()

	for (var/obj/structure/railing/R in get_step(src, (Lturn + src.dir)))
		if ((R.dir == Rturn) && R.anchored)
			check |= 64
			if (UpdateNeighbors)
				R.update_icon()
	for (var/obj/structure/railing/R in get_step(src, (Rturn + src.dir)))
		if ((R.dir == Lturn) && R.anchored)
			check |= 4
			if (UpdateNeighbors)
				R.update_icon()

DECLARE_APPEARANCE_PROC(/obj/structure/railing, TYPE_PROC_REF(/atom, appearance_overlays), list(CHANGE_NEIGHBOURS))
/obj/structure/railing/appearance_overlays()
	. = list()
	NeighborsCheck(FALSE)
	// Railings beside and across from us join with ours: tell them when we move, turn or anchor.
	appearance_notify_neighbours("[anchored]|[dir]|[x],[y],[z]", /obj/structure/railing)
	//layer = (dir == SOUTH) ? FLY_LAYER : initial(layer) // wtf does this even do
	if (!check || !anchored)//|| !anchored
		icon_state = "[icon_modifier]railing0"
	else
		icon_state = "[icon_modifier]railing1"
		if (check & 32)
			. += image(icon, src, "[icon_modifier]corneroverlay")
		if ((check & 16) || !(check & 32) || (check & 64))
			. += image(icon, src, "[icon_modifier]frontoverlay_l")
		if (!(check & 2) || (check & 1) || (check & 4))
			. += image(icon, src, "[icon_modifier]frontoverlay_r")
			if(check & 4)
				switch (src.dir)
					if (NORTH)
						. += image(icon, src, "[icon_modifier]mcorneroverlay", pixel_x = 32)
					if (SOUTH)
						. += image(icon, src, "[icon_modifier]mcorneroverlay", pixel_x = -32)
					if (EAST)
						. += image(icon, src, "[icon_modifier]mcorneroverlay", pixel_y = -32)
					if (WEST)
						. += image(icon, src, "[icon_modifier]mcorneroverlay", pixel_y = 32)

/obj/structure/railing/handle_rotation_verbs(angle, mob/user)
	if(!can_touch(user))
		return FALSE
	. = ..()
	if(.)
		update_icon()

/obj/structure/railing/proc/railing_flip_effect(mob/user, obj/item/held, datum/interaction/interaction) // This will help push railing to remote places, such as open space turfs

	if(user.incapacitated())
		return 0

	if (!can_touch(user) || has_trait(user, TRAIT_AMBIENT_PEST_MOB))
		return

	if(anchored)
		to_chat(user, "It is fastened to the floor therefore you can't flip it!")
		return 0

	var/obj/occupied = can_climb_neighbor_turf(src)
	if(occupied)
		to_chat(user, "You can't flip \the [src] because there's \a [occupied] in the way.")
		return 0

	src.forceMove(get_step(src, src.dir))
	set_dir(turn(dir, 180))
	update_icon()
	return

/obj/structure/railing/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/railing_item/harm,
		/datum/interaction/entry_item/railing_item,
	)
	var/static/list/flip_spec = INTERACT_VERB("Flip Railing", PROC_REF(railing_flip_effect))
	into += dq_interaction_from_spec(/obj/structure/railing, flip_spec)
	..()

/// Old attackby: slam/throw a grabbed mob over the railing, or take a weapon hit.
/datum/interaction/entry_item/railing_item
	id = "railing_item"
	name = "Use"
	effect = /obj/structure/railing/proc/interaction_item

/// Combat mode: a weak grab slams the victim's face against the railing.
/datum/interaction/entry_item/railing_item/harm
	id = "railing_item_harm"
	name = "Slam"
	stance = I_HURT

/obj/structure/railing/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	// Handle combat-mode grabbing/tabling.
	if(istype(W, /obj/item/grab) && get_dist(src,user)<2)
		var/obj/item/grab/G = W
		if (isliving(G?.grab_target()))
			var/mob/living/M = G?.grab_target()
			var/obj/occupied = can_climb_turf(src)
			if(occupied)
				to_chat(user, span_danger("There's \a [occupied] in the way."))
				return TRUE
			if (G.state < 2)
				if(interaction.stance == I_HURT)
					if (prob(15))	M.status_at_least(EFFECT_WEAKENED, 5)
					M.injure(INJURY_BLUNT, 8, BP_HEAD, src)
					take_damage(8, BRUTE, MELEE, sound_effect = FALSE)
					visible_message(span_danger("[G?.grab_assailant()] slams [M]'s face against \the [src]!"))
					play_sfx(src, SFX_EFFECTS_GRILLEHIT)
				else
					to_chat(user, span_danger("You need a better grip to do that!"))
					return TRUE
			else
				if (get_turf(M) == get_turf(src))
					M.forceMove(get_step(src, src.dir))
				else
					M.forceMove(get_turf(src))
				M.status_at_least(EFFECT_WEAKENED, 5)
				visible_message(span_danger("[G?.grab_assailant()] throws [M] over \the [src]!"))
			consume(W, user)
			return TRUE

	else
		play_sfx(src, SFX_EFFECTS_GRILLEHIT)
		receive_weapon_hit(W, user)
		user.setClickCooldown(user.get_attack_speed(W))

	return TRUE

/obj/structure/railing/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(anchored)
		return OP_OK
	playsound(src, W.usesound, 50, 1)
	om_task_timed(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(wrench_act_timed_done), done_args = list(user))
	return OP_OK

/obj/structure/railing/proc/wrench_act_timed_done(mob/user)
	act_message(user, src, MSG_SELF(span_notice("You dismantle %T%.")), MSG_OTHERS(span_infoplain(span_bold("%U%") + " dismantles %T%.")))
	replace_with(src, /obj/item/stack/material/steel, 2)

/obj/structure/railing/proc/welder_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(get_integrity() >= max_integrity)
		return OP_OK
	var/obj/item/weldingtool/F = W.get_welder()
	if(F.welding)
		playsound(src, F.usesound, 50, 1)
		om_task_timed(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(welder_act_timed_done), done_args = list(user))
	return OP_OK

/obj/structure/railing/proc/welder_act_timed_done(mob/user)
	act_message(user, src, MSG_SELF(span_notice("You repair some damage to %T%.")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " repairs some damage to %T%.")))
	repair_damage(max_integrity / 5)

/obj/structure/railing/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	act_message(user, src, others = span_info(span_bold("%U%") + " begins [anchored ? "unscrewing" : "fastening"] %T%."))
	playsound(src, W.usesound, 75, 1)
	om_task_timed(user, 1 SECOND, target = src, receiver = src, on_done = PROC_REF(screwdriver_act_timed_done), done_args = list(user))
	return OP_OK

/obj/structure/railing/proc/screwdriver_act_timed_done(mob/user)
	set_anchored(!anchored)
	to_chat(user, span_notice("You have [anchored ? "fastened \the [src] to" : "unfastened \the [src] from"] the floor."))
	update_icon()

/obj/structure/railing/overhang/hazard
	name = "hazardous ledge"
	desc = "An overhang made of a steel. It's painted with vibrant hazard markings."
	icon = 'icons/obj/railing.dmi'
	icon_modifier = "hazard_"
	icon_state = "hazard_railing0"
	interactable = TRUE

/obj/structure/railing/overhang/hazard/nanite
	icon_modifier = "inactive_"
	icon_state = "inactive_railing0"
	interactable = FALSE
