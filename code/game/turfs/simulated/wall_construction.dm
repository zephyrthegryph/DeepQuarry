/**
 * Wall construction graph (doc/rewrite/interactions.md §10).
 *
 * A plain wall ("plain") is cut open with a welder (or a plasma cutter, an
 * energy blade or a pickaxe). A reinforced wall goes 6 -> 0 through its
 * layers, and some steps go back. The state is the wall's `construction_stage`
 * (null on plain walls, which state_of() reports as "plain").
 *
 * Welder work that isn't construction (burning off wallrot, lighting thermite,
 * repairing damage) is ordinary interactions below, ahead of the graph's edges.
 */
/turf/simulated/wall
	construction_graph = /datum/construction_graph/wall

/datum/construction_graph/wall
	id = "wall"
	states = list("plain", 6, 5, 4, 3, 2, 1, 0)
	initial_states = list("plain", 6)
	state_var = null
	edge_requires = list(REQ_PROC(/proc/dq_wall_worker_ok, "you can't work on walls"))
	edge_types = list(
		/datum/interaction/construction/wall/cut_plain,
		/datum/interaction/construction/wall/cut_grille,
		/datum/interaction/construction/wall/mend_grille,
		/datum/interaction/construction/wall/unscrew_lines,
		/datum/interaction/construction/wall/screw_lines,
		/datum/interaction/construction/wall/slice_cover,
		/datum/interaction/construction/wall/pry_cover,
		/datum/interaction/construction/wall/loosen_bolts,
		/datum/interaction/construction/wall/slice_rods,
		/datum/interaction/construction/wall/pry_sheath,
	)

/datum/construction_graph/wall/state_of(atom/target)
	var/turf/simulated/wall/wall = target
	if(!istype(wall))
		return null
	if(!wall.reinf_material || isnull(wall.construction_stage))
		return "plain"
	return wall.construction_stage

/datum/construction_graph/wall/set_state(atom/target, state)
	var/turf/simulated/wall/wall = target
	if(istype(wall) && isnum(state))
		wall.set_construction_stage(state)

/datum/construction_graph/wall/on_step_started(atom/target, mob/actor, obj/item/held)
	var/turf/simulated/wall/wall = target
	actor.setClickCooldown(actor.get_attack_speed(held))
	if(istype(wall) && held)
		wall.touched_by_tool(held)

/datum/construction_graph/wall/on_traversed(atom/target, mob/actor, datum/interaction/construction/edge, before, after)
	if(after == CONSTRUCTION_DONE)
		return
	actor.update_examine_panel(target)

/// A worker who can do wall work: dexterous and standing on a turf. TRUE or why not.
/proc/dq_wall_worker_ok(mob/actor, atom/target, obj/item/held)
	if(!actor.IsAdvancedToolUser())
		return "you don't have the dexterity to do this"
	if(!isturf(actor.loc))
		return "you can't do this from in here"
	return TRUE

/// A tool touching the wall: it radiates, and a hot tool heats it.
/turf/simulated/wall/proc/touched_by_tool(obj/item/tool)
	radiate()
	var/heat = is_hot(tool)
	if(heat)
		burn(heat)

/datum/interaction/construction/wall
	tool_volume = 100

// ---- Plain wall ----

/datum/interaction/construction/wall/cut_plain
	feedback = /datum/msg/interaction/construction/wall/cut_plain
	start_feedback = /datum/msg/start/interaction/construction/wall/cut_plain
	from_state = "plain"
	to_state = CONSTRUCTION_DONE
	step_text = "cut through the outer plating"
	tool = TOOL_WELDER
	alt_item_types = list(/obj/item/melee/energy/blade, /obj/item/pickaxe)

/datum/msg/interaction/construction/wall/cut_plain
	self = "You remove the outer plating."

/datum/msg/start/interaction/construction/wall/cut_plain
	self = "You begin cutting through the outer plating."

/// 60 deciseconds less the material's cut_delay, scaled by the tool.
/datum/interaction/construction/wall/cut_plain/proc/cut_delay(atom/target)
	var/turf/simulated/wall/wall = target
	return max(0, 60 - wall.material.cut_delay)

/datum/interaction/construction/wall/cut_plain/base_duration(mob/actor, atom/target)
	return cut_delay(target)

/datum/interaction/construction/wall/cut_plain/duration_for(mob/actor, atom/target, obj/item/held)
	return tool_delay(actor, held, cut_delay(target), tool)

/datum/interaction/construction/wall/cut_plain/alt_delay(mob/actor, atom/target, obj/item/held)
	var/delay = 60 - target_material_cut(target)
	if(istype(held, /obj/item/melee/energy/blade))
		delay *= 0.5
	else if(istype(held, /obj/item/pickaxe))
		var/obj/item/pickaxe/pick = held
		delay -= pick.digspeed
	return max(0, delay)

/datum/interaction/construction/wall/cut_plain/proc/target_material_cut(atom/target)
	var/turf/simulated/wall/wall = target
	return wall.material.cut_delay

/datum/interaction/construction/wall/cut_plain/alt_sound(obj/item/held)
	if(istype(held, /obj/item/melee/energy/blade))
		return SFX_SPARKS
	if(istype(held, /obj/item/pickaxe))
		var/obj/item/pickaxe/pick = held
		return pick.drill_sound
	return ..()

/datum/interaction/construction/wall/cut_plain/start_feedback_for(mob/actor, atom/target, obj/item/held)
	if(istype(held, /obj/item/melee/energy/blade))
		return /datum/msg/start/interaction/construction/wall/cut_plain/blade
	if(istype(held, /obj/item/pickaxe))
		return /datum/msg/start/interaction/construction/wall/cut_plain/pickaxe
	return ..()

MSG_DEF_SELF(start/interaction/construction/wall/cut_plain/blade, "You begin slicing through the outer plating.")

/// The pickaxe's own drilling verb.
/datum/msg/start/interaction/construction/wall/cut_plain/pickaxe/texts(atom/user, atom/target, obj/item/item)
	var/obj/item/pickaxe/pick = item
	return list("You begin [istype(pick) ? pick.drill_verb : "digging"] through the outer plating.", null, null)

/datum/interaction/construction/wall/cut_plain/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/turf/simulated/wall/wall = target
	wall.dismantle_wall()
	act_message(actor, target, others = MSG_OTHERS(span_warning("The wall was torn open by %U%!")))
	return TRUE

// ---- Reinforced wall ----

/datum/interaction/construction/wall/cut_grille
	feedback = /datum/msg/interaction/construction/wall/cut_grille
	from_state = 6
	to_state = 5
	step_text = "cut the outer grille"
	tool = TOOL_WIRECUTTER

/datum/msg/interaction/construction/wall/cut_grille
	self = "You cut through the outer grille."

/datum/interaction/construction/wall/mend_grille
	feedback = /datum/msg/interaction/construction/wall/mend_grille
	from_state = 5
	to_state = 6
	step_text = "mend the outer grille"
	tool = TOOL_WIRECUTTER

/datum/msg/interaction/construction/wall/mend_grille
	self = "You mend the outer grille."

/datum/interaction/construction/wall/unscrew_lines
	feedback = /datum/msg/interaction/construction/wall/unscrew_lines
	start_feedback = /datum/msg/start/interaction/construction/wall/unscrew_lines
	from_state = 5
	to_state = 4
	step_text = "unscrew the support lines"
	tool = TOOL_SCREWDRIVER
	duration = 4 SECONDS

/datum/msg/interaction/construction/wall/unscrew_lines
	self = "You unscrew the support lines."

/datum/msg/start/interaction/construction/wall/unscrew_lines
	self = "You begin removing the support lines."

/datum/interaction/construction/wall/screw_lines
	feedback = /datum/msg/interaction/construction/wall/screw_lines
	start_feedback = /datum/msg/start/interaction/construction/wall/screw_lines
	from_state = 4
	to_state = 5
	step_text = "screw down the support lines"
	tool = TOOL_SCREWDRIVER
	duration = 4 SECONDS

/datum/msg/interaction/construction/wall/screw_lines
	self = "You screw down the support lines."

/datum/msg/start/interaction/construction/wall/screw_lines
	self = "You begin screwing down the support lines."

/datum/interaction/construction/wall/slice_cover
	feedback = /datum/msg/interaction/construction/wall/slice_cover
	start_feedback = /datum/msg/start/interaction/construction/wall/slice_cover
	from_state = 4
	to_state = 3
	step_text = "slice through the metal cover"
	tool = TOOL_WELDER
	alt_item_types = list(/obj/item/pickaxe/plasmacutter)
	duration = 6 SECONDS

/datum/msg/interaction/construction/wall/slice_cover
	self = "You press firmly on the cover, dislodging it."

/datum/msg/start/interaction/construction/wall/slice_cover
	self = "You begin slicing through the metal cover."

/datum/interaction/construction/wall/pry_cover
	feedback = /datum/msg/interaction/construction/wall/pry_cover
	start_feedback = /datum/msg/start/interaction/construction/wall/pry_cover
	from_state = 3
	to_state = 2
	step_text = "pry off the cover"
	tool = TOOL_CROWBAR
	duration = 10 SECONDS

/datum/msg/interaction/construction/wall/pry_cover
	self = "You pry off the cover."

/datum/msg/start/interaction/construction/wall/pry_cover
	self = "You struggle to pry off the cover."

/datum/interaction/construction/wall/loosen_bolts
	feedback = /datum/msg/interaction/construction/wall/loosen_bolts
	start_feedback = /datum/msg/start/interaction/construction/wall/loosen_bolts
	from_state = 2
	to_state = 1
	step_text = "loosen the anchoring bolts"
	tool = TOOL_WRENCH
	duration = 4 SECONDS

/datum/msg/interaction/construction/wall/loosen_bolts
	self = "You remove the bolts anchoring the support rods."

/datum/msg/start/interaction/construction/wall/loosen_bolts
	self = "You start loosening the anchoring bolts which secure the support rods to their frame."

/datum/interaction/construction/wall/slice_rods
	feedback = /datum/msg/interaction/construction/wall/slice_rods
	start_feedback = /datum/msg/start/interaction/construction/wall/slice_rods
	from_state = 1
	to_state = 0
	step_text = "slice through the support rods"
	tool = TOOL_WELDER
	alt_item_types = list(/obj/item/pickaxe/plasmacutter)
	duration = 7 SECONDS

/datum/msg/interaction/construction/wall/slice_rods
	self = "You slice through the support rods."

/datum/msg/start/interaction/construction/wall/slice_rods
	self = "You begin slicing through the support rods."

/datum/interaction/construction/wall/pry_sheath
	feedback = /datum/msg/interaction/construction/wall/pry_sheath
	start_feedback = /datum/msg/start/interaction/construction/wall/pry_sheath
	from_state = 0
	to_state = CONSTRUCTION_DONE
	step_text = "pry off the outer sheath"
	tool = TOOL_CROWBAR
	duration = 10 SECONDS

/datum/msg/interaction/construction/wall/pry_sheath
	self = "You pry off the outer sheath."

/datum/msg/start/interaction/construction/wall/pry_sheath
	self = "You struggle to pry off the outer sheath."

/datum/interaction/construction/wall/pry_sheath/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/turf/simulated/wall/wall = target
	wall.dismantle_wall()
	return TRUE

// ---------------------------------------------------------------------------
// Welder work that isn't construction. It comes before the graph's edges.

/turf/simulated/wall/declare_interactions(list/into)
	..()
	into += list(
		/datum/interaction/wall_burn_rot,
		/datum/interaction/wall_light_thermite,
		/datum/interaction/wall_repair,
	)

/datum/interaction/wall_burn_rot
	id = "wall_burn_rot"
	name = "Burn away the fungi"
	category = INTERACTION_CAT_REPAIR
	priority = 30
	default_action = INPUT_ACTION_USE
	tool = TOOL_WELDER
	tool_volume = 10
	requires = list(REQ_REACH_ADJACENT, REQ_PROC(/proc/dq_wall_worker_ok, "you can't work on walls"))
	effect = /turf/simulated/wall/proc/burn_away_rot
	feedback = /datum/msg/interaction/wall_burn_rot

/datum/interaction/wall_burn_rot/applies_to(atom/target)
	return (locate_within(target, /obj/effect/overlay/wallrot)) ? TRUE : FALSE

MSG_DEF_SELF(interaction/wall_burn_rot, "You burn away the fungi with %I%.")

/turf/simulated/wall/proc/burn_away_rot(mob/actor, obj/item/held, datum/interaction/interaction)
	touched_by_tool(held)
	for(var/obj/effect/overlay/wallrot/rot in turf_contents_of_type(src, /obj/effect/overlay/wallrot))
		dissolved(rot, actor)
	return TRUE

/datum/interaction/wall_light_thermite
	id = "wall_light_thermite"
	name = "Ignite the thermite"
	category = INTERACTION_CAT_REPAIR
	priority = 25
	default_action = INPUT_ACTION_USE
	tool = TOOL_WELDER
	tool_volume = 0
	requires = list(REQ_REACH_ADJACENT, REQ_PROC(/proc/dq_wall_worker_ok, "you can't work on walls"))
	effect = /turf/simulated/wall/proc/light_thermite
	tags = list(INTERACTION_TAG_HOSTILE)

/datum/interaction/wall_light_thermite/applies_to(atom/target)
	var/turf/simulated/wall/wall = target
	return istype(wall) && wall.thermite && !(locate_on(wall, /obj/effect/overlay/wallrot))

/turf/simulated/wall/proc/light_thermite(mob/actor, obj/item/held, datum/interaction/interaction)
	touched_by_tool(held)
	thermitemelt(actor)
	return TRUE

/datum/interaction/wall_repair
	id = "wall_repair"
	feedback = /datum/msg/interaction/wall_repair
	start_feedback = /datum/msg/start/interaction/wall_repair
	name = "Repair the wall"
	category = INTERACTION_CAT_REPAIR
	priority = 20
	default_action = INPUT_ACTION_USE
	tool = TOOL_WELDER
	tool_volume = 100
	requires = list(REQ_REACH_ADJACENT, REQ_PROC(/proc/dq_wall_worker_ok, "you can't work on walls"))
	effect = /turf/simulated/wall/proc/finish_weld_repair

/datum/interaction/wall_repair/applies_to(atom/target)
	var/turf/simulated/wall/wall = target
	if(!istype(wall) || wall.thermite || (locate_on(wall, /obj/effect/overlay/wallrot)))
		return FALSE
	return wall.get_integrity() < wall.max_integrity

/// At least half a second; longer the more damage there is.
/datum/interaction/wall_repair/duration_for(mob/actor, atom/target, obj/item/held)
	var/turf/simulated/wall/wall = target
	return tool_delay(actor, held, max(5, (wall.max_integrity - wall.get_integrity()) / 5), tool)

MSG_DEF_SELF(start/interaction/wall_repair, "You start repairing the damage to %T%.")

MSG_DEF_SELF(interaction/wall_repair, "You finish repairing the damage to %T%.")

/turf/simulated/wall/proc/finish_weld_repair(mob/actor, obj/item/held, datum/interaction/interaction)
	touched_by_tool(held)
	repair_damage(max_integrity)
	actor.update_examine_panel(src)
	return TRUE
