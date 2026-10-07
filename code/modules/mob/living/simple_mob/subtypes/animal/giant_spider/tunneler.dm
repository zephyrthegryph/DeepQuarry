// Tunnelers have a special ability that allows them to charge at an enemy by tunneling towards them.
// Any mobs inbetween the tunneler's path and the target will be stunned if the tunneler hits them.
// The target will suffer a stun as well, if the tunneler hits them at the end. A successful hit will stop the tunneler.
// If the target moves fast enough, the tunneler can miss, causing it to overshoot.
// If the tunneler hits a solid wall, the tunneler will suffer a stun.

/datum/category_item/catalogue/fauna/giant_spider/tunneler_spider
	name = "Giant Spider - Tunneler"
	desc = "This specific spider has been catalogued as 'Tunneler', \
	and it belongs to the 'Hunter' caste. \
	The spider has a brown appearance, perhaps as camouflage. It also often has pieces of dirt, sand, or rock lying on it. \
	Their eyes have a bright yellow shine.\
	<br><br>\
	Tunnelers generally reside in subterranean environments, as they are able to dig rapidly in soft materials.  \
	They often use this ability as an offensive tactic against prey, burrowing into the ground and tunneling, \
	towards their target, before striking them from below. This powerful tactic does have a notable flaw, \
	in that the spider is unable to actually see where they are going while burrowing, instead checking for \
	increased weight from above as a sign that their prey is above them. This flaw means that Tunnelers \
	often overshoot if the prey happens to move while it is underground, and can result in a collision if \
	the prey happened to be standing near something hard and dense. \
	<br><br>\
	Tunneler venom is also dangerous, as it is known to both promotes concentrated production of the \
	serotonin neurotransmitter, as well as causing brain damage. The feeling of happiness a bite causes \
	afterwards can delay seeking medical treatment, making it extra dangerous."
	value = CATALOGUER_REWARD_MEDIUM

/mob/living/simple_mob/animal/giant_spider/tunneler
	desc = "Sandy and brown, it makes you shudder to look at it. This one has glittering yellow eyes."
	catalogue_data = list(/datum/category_item/catalogue/fauna/giant_spider/tunneler_spider)

	icon_state = "tunneler"
	icon_living = "tunneler"
	icon_dead = "tunneler_dead"

	endurance = 120

	melee_damage_lower = 10
	melee_damage_upper = 10

	poison_chance = 15
	poison_per_bite = 3
	poison_type = REAGENT_ID_SEROTROTIUMV

	player_msg = "You <b>can perform a tunneling attack</b> by clicking on someone from a distance.<br>\
	There is a noticable travel delay as you tunnel towards the tile the target was at when you started the tunneling attack.<br>\
	Any entities inbetween you and the targeted tile will be stunned for a brief period of time.<br>\
	Whatever is on the targeted tile when you arrive will suffer a potent stun.<br>\
	If nothing is on the targeted tile, you will overshoot and keep going for a few more tiles.<br>\
	If you hit a wall or other solid structure during that time, you will suffer a lengthy stun and be vulnerable to more harm."

	// Tunneling is a special attack, similar to the hunter's Leap.
	special_attack_min_range = 2
	special_attack_max_range = 6
	special_attack_cooldown = 10 SECONDS

	var/tunnel_warning = 0.5 SECONDS	// How long the dig telegraphing is.
	var/tunnel_tile_speed = 2			// How long to wait between each tile. Higher numbers result in an easier to dodge tunnel attack.

/mob/living/simple_mob/animal/giant_spider/tunneler/frequent
	special_attack_cooldown = 5 SECONDS

/mob/living/simple_mob/animal/giant_spider/tunneler/fast
	tunnel_tile_speed = 1

/mob/living/simple_mob/animal/giant_spider/tunneler/should_special_attack(atom/A)
	// Make sure its possible for the spider to reach the target so it doesn't try to go through a window.
	var/turf/destination = get_turf(A)
	var/turf/starting_turf = get_turf(src)
	var/turf/T = starting_turf
	for(var/i = 1 to get_dist(starting_turf, destination))
		if(T == destination)
			break

		T = get_step(T, get_dir(T, destination))
		if(T.check_density(ignore_mobs = TRUE))
			return FALSE
	return T == destination


/mob/living/simple_mob/animal/giant_spider/tunneler/do_special_attack(atom/A, stance)
	ai_busy_begin()
	// Save where we're gonna go soon.
	var/turf/destination = get_turf(A)
	var/turf/starting_turf = get_turf(src)

	// Telegraph to give a small window to dodge if really close.
	do_windup_animation(A, tunnel_warning)
	after(src, tunnel_warning, PROC_REF(tunnel_dig), with = list(A, destination, starting_turf), keeps_dead = TRUE) // For the telegraphing.

/mob/living/simple_mob/animal/giant_spider/tunneler/proc/tunnel_dig(atom/A, turf/destination, turf/starting_turf)
	if(!destination || !starting_turf)
		ai_busy_end()
		return
	// Do the dig!
	act_message(src, A, null, MSG_OTHERS(span_danger("%U% tunnels towards %T%!")))
	submerge()
	handle_tunnel(destination, PROC_REF(tunnel_arrived), list(destination, starting_turf))

/// First tunnel finished (result FALSE/null means it stopped short).
/mob/living/simple_mob/animal/giant_spider/tunneler/proc/tunnel_arrived(result, turf/destination, turf/starting_turf)
	if(result == FALSE || !destination || !starting_turf)
		tunnel_surface()
		return

	// Did we make it?
	if(!(src in destination))
		tunnel_surface()
		return

	var/overshoot = TRUE

	// Test if something is at destination.
	for(var/mob/living/L in turf_contents_of_type(destination, /mob/living))
		if(L == src)
			continue

		act_message(src, L, null, MSG_OTHERS(span_danger("%U% erupts from underneath, and hits %T%!")))
		play_sfx(src, SFX_WEAPONS_HEAVYSMASH)
		L.apply_body_effect(/datum/body_effect/entangled, 3 SECONDS) //L.status_at_least(STAT_WEAKENED, 3)
		overshoot = FALSE

	if(!overshoot) // We hit the target, or something, at destination, so we're done.
		tunnel_surface()
		return

	// Otherwise we need to keep going.
	to_chat(src, span_warning("You overshoot your target!"))
	play_sfx(src, SFX_WEAPONS_PUNCHMISS, 3, extrarange = 0)
	var/dir_to_go = get_dir(starting_turf, destination)
	for(var/i = 1 to rand(2, 4))
		destination = get_step(destination, dir_to_go)

	handle_tunnel(destination, PROC_REF(tunnel_surface_after))

/mob/living/simple_mob/animal/giant_spider/tunneler/proc/tunnel_surface_after(result)
	tunnel_surface()

/mob/living/simple_mob/animal/giant_spider/tunneler/proc/tunnel_surface()
	ai_busy_end()
	emerge()

/// Tunnels toward destination a tile per tunnel_tile_speed, then calls
/// then_proc(result, extra...): FALSE if stopped, null if the run ended.
/mob/living/simple_mob/animal/giant_spider/tunneler/proc/handle_tunnel(turf/destination, then_proc, list/extra)
	tunnel_step(destination, get_dist(src, destination), then_proc, extra)

/mob/living/simple_mob/animal/giant_spider/tunneler/proc/tunnel_finish(result, then_proc, list/extra)
	var/list/call_args = list(result)
	if(extra)
		call_args += extra
	call(src, then_proc)(arglist(call_args))

/mob/living/simple_mob/animal/giant_spider/tunneler/proc/tunnel_step(turf/destination, steps_left, then_proc, list/extra)
	if(steps_left <= 0)
		tunnel_finish(null, then_proc, extra)
		return
	if(stat)
		tunnel_finish(FALSE, then_proc, extra) // We died or got knocked out on the way.
		return

	var/last_loc = loc
	if(last_loc == destination)
		tunnel_finish(null, then_proc, extra) // We somehow got there early.
		return

	var/turf/T = get_step(src, get_dir(src, destination))
	if(!T) //There is no turf in that direction.
		tunnel_finish(FALSE, then_proc, extra) //Hit a non-existant turf.
		return
	if(T.check_density(ignore_mobs = TRUE))
		to_chat(src, span_critical("You hit something really solid!"))
		play_sfx(src, SFX_PUNCH, 1.5)
		status_at_least(STAT_WEAKENED, 5)
		apply_body_effect(/datum/body_effect/tunneler_vulnerable, 10 SECONDS)
		tunnel_finish(FALSE, then_proc, extra) // Hit a wall.
		return

	// Stun anyone in our way.
	for(var/mob/living/L in contents_of(T))
		play_sfx(src, SFX_WEAPONS_HEAVYSMASH)
		L.status_at_least(STAT_WEAKENED, 2)

	// Get into the tile.
	forceMove(T)

	// Visuals and sound.
	dig_under_floor(get_turf(src))
	play_sfx(src, SFX_EFFECTS_BREAK_STONE)
	after(src, tunnel_tile_speed, PROC_REF(tunnel_step_check), with = list(destination, steps_left - 1, last_loc, then_proc, extra), keeps_dead = TRUE)

/mob/living/simple_mob/animal/giant_spider/tunneler/proc/tunnel_step_check(turf/destination, steps_left, last_loc, then_proc, list/extra)
	if(!destination)
		tunnel_finish(FALSE, then_proc, extra)
		return
	if(last_loc == loc)
		tunnel_finish(FALSE, then_proc, extra)
		return
	tunnel_step(destination, steps_left, then_proc, extra)

// For visuals.
/mob/living/simple_mob/animal/giant_spider/tunneler/proc/submerge()
	alpha = 0
	dig_under_floor(get_turf(src))
	new /obj/effect/temporary_effect/tunneler_hole(get_turf(src))

// Ditto.
/mob/living/simple_mob/animal/giant_spider/tunneler/proc/emerge()
	alpha = 255
	dig_under_floor(get_turf(src))
	new /obj/effect/temporary_effect/tunneler_hole(get_turf(src))

/mob/living/simple_mob/animal/giant_spider/tunneler/proc/dig_under_floor(turf/T)
	new /obj/item/ore/glass(T) // This will be rather weird when on station but the alternative is too much work.

/obj/effect/temporary_effect/tunneler_hole
	name = "hole"
	desc = "A collapsing tunnel hole."
	icon_state = "tunnel_hole"
	time_to_die = 1 MINUTE

/datum/body_effect/tunneler_vulnerable
	name = "Vulnerable"
	desc = "You are vulnerable to more harm than usual."
	on_created_text = span_warning("You feel vulnerable...")
	on_expired_text = span_notice("You feel better.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_EVASION = -100, BF_INCOMING_ALL = 2)

/mob/living/simple_mob/animal/giant_spider/tunneler/cave
	name = "cave spider"
	desc = "Sandy and brown, it makes you shudder to look at it. However, this one doesn't seem very interested in bothering you."
	endurance = 25
	harm_intent_damage = 5
	melee_damage_lower = 5
	melee_damage_upper = 5
	meat_amount = 1 // Scrawny little things! It's no wonder they don't want to fight you!

/mob/living/simple_mob/animal/giant_spider/tunneler/cave/Initialize(mapload)
	. = ..()
	resize(0.50)
