/* Alien Effects!
 * Contains:
 *		effect/alien
 *		Weeds
 *		Acid
 */

/*
 * effect/alien
 */
/obj/effect/alien
	name = "alien thing"
	desc = "there's something alien about this"
	icon = 'icons/mob/alien.dmi'

/*
 * Weeds
 */
#define NODERANGE 3
#define WEED_NORTH_EDGING "north"
#define WEED_SOUTH_EDGING "south"
#define WEED_EAST_EDGING "east"
#define WEED_WEST_EDGING "west"
#define WEED_NODE_GLOW "glow"
#define WEED_NODE_BASE "nodebase"

/obj/effect/alien/weeds
	uses_integrity = TRUE
	name = "growth"
	desc = "Weird organic growth."
	icon_state = "weeds"
	anchored = TRUE
	density = FALSE
	unacidable = TRUE
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER
	var/delete_me

	max_integrity = 15
	var/obj/effect/alien/weeds/node/linked_node
	var/static/list/weedImageCache // ALLOW(cache): constant table of four edge images

// ALLOW(init/INSTANCE_STATE): weeds do not grow in space, nor where a node already marked them for removal
/obj/effect/alien/weeds/Initialize(mapload)
	. = ..()
	if(isspace(loc) || delete_me)
		return INITIALIZE_HINT_QDEL
//	if(newcolor)
// color = newcolor // No coloration.

	if(icon_state == "weeds")
		icon_state = pick("weeds", "weeds1", "weeds2", "weeds3", "weeds4", "weeds5", "weeds6", "weeds7", "weeds8", "weeds9", "weeds10", "weeds11", "weeds12", "weeds13", "weeds14", "weeds15") // More icons variants.

	fullUpdateWeedOverlays()

// neighbouring weeds redraw their overlays without it.
/obj/effect/alien/weeds/on_destroy(force)
	var/turf/T = get_turf(src)
	// To not mess up the overlay updates.
	moveToNullspace()

	for (var/obj/effect/alien/weeds/W in range(1,T))
		W.updateWeedOverlays()

	rel_clear(src, nameof(linked_node))
	..()

/obj/effect/alien/weeds/node
	icon_state = "weednode"
	name = "glowing growth"
	desc = "Weird glowing organic growth."
	layer = ABOVE_TURF_LAYER+0.01
	light_range = NODERANGE
	light_on = TRUE
	light_color = "#673972"

	var/node_range = NODERANGE

/obj/effect/alien/weeds/node/Initialize(mapload, node, newcolor)
	. = ..()

	for(var/obj/effect/alien/weeds/existing in contents_of(loc))
		if(existing == src)
			continue
		else
			if(!(existing.flags & ATOM_INITIALIZED))
				existing.delete_me = TRUE
				continue
			spent(existing)

	rel_set(src, nameof(linked_node), src)

// Only the node processes in a subsystem, the rest are process()'d by the node
DECLARE_PERIODIC(/obj/effect/alien/weeds/node, PERIODIC_SLOW)

/obj/effect/alien/weeds/proc/updateWeedOverlays()
	cut_overlays()

	if(!weedImageCache)
		weedImageCache = list()
		weedImageCache[WEED_NORTH_EDGING] = image('icons/mob/alien.dmi', "weeds_side_n", layer=2.11, pixel_y = -32)
		weedImageCache[WEED_SOUTH_EDGING] = image('icons/mob/alien.dmi', "weeds_side_s", layer=2.11, pixel_y = 32)
		weedImageCache[WEED_EAST_EDGING] = image('icons/mob/alien.dmi', "weeds_side_e", layer=2.11, pixel_x = -32)
		weedImageCache[WEED_WEST_EDGING] = image('icons/mob/alien.dmi', "weeds_side_w", layer=2.11, pixel_x = 32)

	var/turf/N = get_step(src, NORTH)
	var/turf/S = get_step(src, SOUTH)
	var/turf/E = get_step(src, EAST)
	var/turf/W = get_step(src, WEST)
	if(istype(N, /turf/simulated/floor) && !locate_on(N, /obj/effect/alien))
		add_overlay(weedImageCache[WEED_SOUTH_EDGING])
	if(istype(S, /turf/simulated/floor) && !locate_on(S, /obj/effect/alien))
		add_overlay(weedImageCache[WEED_NORTH_EDGING])
	if(istype(E, /turf/simulated/floor) && !locate_on(E, /obj/effect/alien))
		add_overlay(weedImageCache[WEED_WEST_EDGING])
	if(istype(W, /turf/simulated/floor) && !locate_on(W, /obj/effect/alien))
		add_overlay(weedImageCache[WEED_EAST_EDGING])

/obj/effect/alien/weeds/proc/fullUpdateWeedOverlays()
	for (var/obj/effect/alien/weeds/W in range(1,src))
		W.updateWeedOverlays()

	return

// NB: This is not actually called by a processing subsystem, it's called by the node processing
/obj/effect/alien/weeds/periodic_step()
	set background = 1
	var/turf/U = get_turf(src)

	if(isspace(U))
		consume(src)
		return

	if(!linked_node())
		return

	if(get_dist(linked_node(), src) > linked_node().node_range)
		return

	for(var/dirn in GLOB.cardinal)
		var/turf/T1 = get_turf(src)
		var/turf/T2 = get_step(src, dirn)

		if(!istype(T2) || locate_on(T2, /obj/effect/alien/weeds) || istype(T2.loc, /area/arrival) || isspace(T2))
			continue

		if(T1.c_airblock(T2) == BLOCKED)
			continue

		new /obj/effect/alien/weeds(T2, linked_node()) // No coloration.

/obj/effect/alien/weeds/node/periodic_step()
	set background = 1
	. = ..()

	var/list/nearby_weeds = list()
	for(var/obj/effect/alien/weeds/W in orange(node_range, src))
		nearby_weeds |= W

	for(var/obj/effect/alien/weeds/W as anything in nearby_weeds)

		if(!W.linked_node())
			rel_set(W, nameof(W.linked_node), src)

// W.color = W.linked_node.set_color // No coloration.

		if(prob(max(10, 60 - (5 * nearby_weeds.len))))
			W.periodic_step()

EXTEND_INTERACTIONS(/obj/effect/alien/weeds, \
	INTERACT_ITEM(null, PROC_REF(interaction_hit_weeds)), \
	INTERACT_HAND_AS(I_HURT, "Tear up", PROC_REF(interaction_touch_weeds)), \
	INTERACT_HAND(null, PROC_REF(interaction_touch_weeds)), \
)

/// Old attackby: any item hits the weeds (afterattack still follows, as before).
/obj/effect/alien/weeds/proc/interaction_hit_weeds(mob/user, obj/item/held, datum/interaction/interaction)
	var/obj/item/W = held
	user.setClickCooldown(user.get_attack_speed(W))
	if(LAZYLEN(W.attack_verb))
		act_message(src, user, others = span_danger("%U% have been [pick(W.attack_verb)] with %I%[user ? " by %T%." : "."]"), item = W)
	else
		act_message(src, user, others = span_danger("%U% have been attacked with %I%[user ? " by %T%." : "."]"), item = W)

	var/damage = W.force / 4.0

	take_damage(damage, BRUTE, MELEE, sound_effect = FALSE)
	return INTERACTION_HANDLED_PASS

CAPABILITIES(/obj/effect/alien/weeds)
	op("use_welder", tool(TOOL_WELDER), wait(0), costs(RES_FUEL, 0), then(PROC_REF(welder_used)))
	param(nameof(linked_node), pos = 1)

/obj/effect/alien/weeds/proc/welder_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder.remove_fuel(0, user))
		return OP_OK
	user.setClickCooldown(user.get_attack_speed(tool))
	act_message(src, user, others = span_danger("%U% have been burned with %I% by %T%."), item = tool)
	play_sfx(src, SFX_ITEMS_WELDER)
	take_damage(15, BRUTE, MELEE, sound_effect = FALSE)
	return OP_OK

// start - Smaller-ranged nodes for Xenomorph Hybrids, node/weed deletion.
/// Old attack_hand: hulks tear the weeds up; hivenode carriers melt them on harm intent.
/obj/effect/alien/weeds/proc/interaction_touch_weeds(mob/user, obj/item/held, datum/interaction/interaction)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(user.has_mutation(HULK))
		act_message(user, null, others = span_warning("%U% destroys the [name]!"))
		take_damage(get_integrity(), BRUTE, MELEE, sound_effect = FALSE)
	else

		// Aliens can get straight through these.
		if(istype(user,/mob/living/carbon))
			if(interaction.stance == I_HURT)
				var/mob/living/carbon/M = user
				if(locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/hivenode))
					act_message(user, null, others = span_warning("%U% strokes the [name] and it melts away!"))
					take_damage(get_integrity(), BRUTE, MELEE, sound_effect = FALSE)
					return TRUE
	return TRUE

/obj/effect/alien/weeds/node/weak
	light_range = 2
	node_range = 1
// end.

#undef NODERANGE
#undef WEED_NORTH_EDGING
#undef WEED_SOUTH_EDGING
#undef WEED_EAST_EDGING
#undef WEED_WEST_EDGING
#undef WEED_NODE_GLOW
#undef WEED_NODE_BASE

/*
 * Acid
 */
/obj/effect/alien/acid
	name = "acid"
	desc = "Burbling corrossive stuff. I wouldn't want to touch it."
	icon_state = "acid"

	density = FALSE
	opacity = 0
	anchored = TRUE

	var/atom/target
	var/ticks = 0
	var/target_strength = 0

CAPABILITIES(/obj/effect/alien/acid)
	owns_one(nameof(target), /atom)
	param(nameof(target), pos = 1, apply = PROC_REF(start_melting))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). Acid takes twice as long on a turf.
/obj/effect/alien/acid/proc/start_melting(atom/melting)
	if(isturf(melting))
		target_strength = 8
	else
		target_strength = 4
	tick()

DECLARE_REPEAT(/obj/effect/alien/acid, "acid_tick_delay", tick, null)

/// Deciseconds until the acid's next bite (read each time the repeat re-arms).
/obj/effect/alien/acid/proc/acid_tick_delay()
	return rand(15 SECONDS, 20 SECONDS)

/obj/effect/alien/acid/proc/tick()
	if(!target)
		consume(src)
		return REPEAT_STOP

	ticks += 1
	if(ticks >= target_strength)

		for(var/mob/O in hearers(src, null))
			O.show_message(span_alium("[src.target] collapses under its own weight into a puddle of goop and undigested debris!"), 1)

		if(iswall(target))
			var/turf/simulated/wall/W = target
			W.dismantle_wall()
		else if(isfloor(target))
			var/turf/simulated/floor/T = target
			T.ex_act(1)
		else if(isobj(target))
			spent(target)
		consume(src)
		return REPEAT_STOP

	switch(target_strength - ticks)
		if(6)
			visible_message(span_alium("[src.target] is holding up against the acid!"))
		if(4)
			visible_message(span_alium("[src.target]\s structure is being melted by the acid!"))
		if(2)
			visible_message(span_alium("[src.target] is struggling to withstand the acid!"))
		if(0 to 1)
			visible_message(span_alium("[src.target] begins to crumble under the acid!"))

//Xenomorph Effect egg removed, replaced with Structure Egg.


/// Relation view: linked node (reads null once it is gone).
/obj/effect/alien/weeds/proc/linked_node() as /obj/effect/alien/weeds/node
	return linked_node
