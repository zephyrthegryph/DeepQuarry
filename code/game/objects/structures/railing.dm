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
	var/icon_modifier = ""
TRACKED(/obj/structure/railing, icon_modifier)

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

CAPABILITIES(/obj/structure/railing)
	climb(delay = 3.4 SECONDS, vaulting = TRUE, climbed = PROC_REF(climbed_over))
	op("slam", item(/obj/item), stance(I_HURT), label("Slam"), then(PROC_REF(interaction_slam)))
	op("item", item(/obj/item), stance(I_HELP, I_DISARM, I_GRAB), label("Use"), then(PROC_REF(interaction_item)))
	op("flip", menu(), label("Flip Railing"), then(PROC_REF(railing_flip_effect)))
	op("use_wrench", tool(TOOL_WRENCH), wait(2 SECONDS), needs(req_bool(PROC_REF(loose), silent = TRUE)), then(PROC_REF(wrench_act_done)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(1 SECOND), begins(PROC_REF(screwdriver_begins)), then(PROC_REF(screwdriver_act_done)))
	op("use_welder", lit_welder(fuel = 0), needs(req_bool(PROC_REF(damaged), silent = TRUE)), starts(PROC_REF(welder_sound)), wait(2 SECONDS), then(PROC_REF(welder_act_timed_done)))
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

/// The sides of this railing that join a neighbour (a bitmask of 1, 2, 4, 16, 32 and 64): anchored railings on its tile turned along it, beside it and diagonally ahead.
/// The draw hears of each of them (a railing arriving, leaving, turning or being fastened) and of the tiles they stand on.
/obj/structure/railing/proc/joined_sides(datum/look/look)
	. = 0
	var/Rturn = turn(dir, -90)
	var/Lturn = turn(dir, 90)

	for(var/obj/structure/railing/R as anything in look.neighbours(src, 0, /obj/structure/railing))
		if(R.anchored && R.dir == Lturn)
			. |= 32
		if(R.anchored && R.dir == Rturn)
			. |= 2
	for(var/obj/structure/railing/R as anything in look.neighbours(src, Lturn, /obj/structure/railing))
		if(R.anchored && R.dir == dir)
			. |= 16
	for(var/obj/structure/railing/R as anything in look.neighbours(src, Rturn, /obj/structure/railing))
		if(R.anchored && R.dir == dir)
			. |= 1
	for(var/obj/structure/railing/R as anything in look.neighbours(src, Lturn + dir, /obj/structure/railing))
		if(R.anchored && R.dir == Rturn)
			. |= 64
	for(var/obj/structure/railing/R as anything in look.neighbours(src, Rturn + dir, /obj/structure/railing))
		if(R.anchored && R.dir == Lturn)
			. |= 4

/obj/structure/railing/draw(datum/look/look)
	..()
	var/check = joined_sides(look)
	if (!check || !anchored)
		look.state("[icon_modifier]railing0")
		return
	look.state("[icon_modifier]railing1")
	if (check & 32)
		look.overlay(look_overlay_image(icon, "[icon_modifier]corneroverlay"))
	if ((check & 16) || !(check & 32) || (check & 64))
		look.overlay(look_overlay_image(icon, "[icon_modifier]frontoverlay_l"))
	if (!(check & 2) || (check & 1) || (check & 4))
		look.overlay(look_overlay_image(icon, "[icon_modifier]frontoverlay_r"))
		if(check & 4)
			switch (dir)
				if (NORTH)
					look.overlay(look_overlay_image(icon, "[icon_modifier]mcorneroverlay", pixel_x = 32))
				if (SOUTH)
					look.overlay(look_overlay_image(icon, "[icon_modifier]mcorneroverlay", pixel_x = -32))
				if (EAST)
					look.overlay(look_overlay_image(icon, "[icon_modifier]mcorneroverlay", pixel_y = -32))
				if (WEST)
					look.overlay(look_overlay_image(icon, "[icon_modifier]mcorneroverlay", pixel_y = 32))

/obj/structure/railing/handle_rotation_verbs(angle, mob/user)
	if(!can_touch(user))
		return FALSE
	return ..()

/// The old Flip Railing verb: this will help push railing to remote places, such as open space turfs.
/obj/structure/railing/proc/railing_flip_effect(datum/act/op/A)
	var/mob/user = A.actor
	if(user.incapacitated())
		return OP_OK

	if (!can_touch(user) || has_trait(user, TRAIT_AMBIENT_PEST_MOB))
		return OP_OK

	if(anchored)
		to_chat(user, "It is fastened to the floor therefore you can't flip it!")
		return OP_OK

	var/obj/occupied = can_climb_neighbor_turf(src)
	if(occupied)
		to_chat(user, "You can't flip \the [src] because there's \a [occupied] in the way.")
		return OP_OK

	src.forceMove(get_step(src, src.dir))
	set_dir(turn(dir, 180))
	return OP_OK

/// Combat mode: a weak grab slams the victim's face against the railing.
/obj/structure/railing/proc/interaction_slam(datum/act/op/A)
	return railing_item_used(A, TRUE)

/// Old attackby: slam/throw a grabbed mob over the railing, or take a weapon hit.
/obj/structure/railing/proc/interaction_item(datum/act/op/A)
	return railing_item_used(A, FALSE)

/obj/structure/railing/proc/railing_item_used(datum/act/op/A, harm)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	// Handle combat-mode grabbing/tabling.
	if(istype(W, /obj/item/grab) && get_dist(src,user)<2)
		var/obj/item/grab/G = W
		if (isliving(G?.grab_target()))
			var/mob/living/M = G?.grab_target()
			var/obj/occupied = can_climb_turf(src)
			if(occupied)
				to_chat(user, span_danger("There's \a [occupied] in the way."))
				return OP_OK
			if (G.state < 2)
				if(harm)
					if (prob(15))	M.status_at_least(STAT_WEAKENED, 5)
					M.injure(INJURY_BLUNT, 8, BP_HEAD, src)
					take_damage(8, BRUTE, MELEE, sound_effect = FALSE)
					visible_message(span_danger("[G?.grab_assailant()] slams [M]'s face against \the [src]!"))
					play_sfx(src, SFX_EFFECTS_GRILLEHIT)
				else
					to_chat(user, span_danger("You need a better grip to do that!"))
					return OP_OK
			else
				if (get_turf(M) == get_turf(src))
					M.forceMove(get_step(src, src.dir))
				else
					M.forceMove(get_turf(src))
				M.status_at_least(STAT_WEAKENED, 5)
				visible_message(span_danger("[G?.grab_assailant()] throws [M] over \the [src]!"))
			consume(W, user)
			return OP_OK

	else
		play_sfx(src, SFX_EFFECTS_GRILLEHIT)
		receive_weapon_hit(W, user)
		user.setClickCooldown(user.get_attack_speed(W))

	return OP_OK

/// A wrench only takes a loose railing apart.
/obj/structure/railing/proc/loose(datum/act/op/A)
	return !anchored

/obj/structure/railing/proc/wrench_act_done(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, MSG_SELF(span_notice("You dismantle %T%.")), MSG_OTHERS(span_infoplain(span_bold("%U%") + " dismantles %T%.")))
	replace_with(src, /obj/item/stack/material/steel, 2)

/obj/structure/railing/proc/damaged(datum/act/op/A)
	return get_integrity_damage() > 0

/obj/structure/railing/proc/welder_sound(datum/act/op/A)
	var/obj/item/tool = A.held
	playsound(src, tool.usesound, 50, 1)

/obj/structure/railing/proc/welder_act_timed_done(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF(span_notice("You repair some damage to %T%.")), 		MSG_OTHERS(span_infoplain(span_bold("%U%") + " repairs some damage to %T%.")))
	repair_damage(max_integrity / 5)

MSG_DEF(railing/unscrewing, null, span_info(span_bold("%U%") + " begins unscrewing %T%."))
MSG_DEF(railing/fastening, null, span_info(span_bold("%U%") + " begins fastening %T%."))

/obj/structure/railing/proc/screwdriver_begins(datum/act/op/A)
	return anchored ? /datum/msg/railing/unscrewing : /datum/msg/railing/fastening

/obj/structure/railing/proc/screwdriver_act_done(datum/act/op/A)
	var/mob/user = A.actor
	set_anchored(!anchored)
	to_chat(user, span_notice("You have [anchored ? "fastened \the [src] to" : "unfastened \the [src] from"] the floor."))

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
