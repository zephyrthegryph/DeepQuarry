/mob/living/bot/secbot/ed209
	name = "ED-209 Security Robot"
	desc = "A security robot.  He looks less than thrilled."
	icon = 'icons/obj/aibots.dmi'
	icon_state = "ed2090"
	density = TRUE
	endurance = 200

	is_ranged = 1
	preparing_arrest_sounds = new()

	combat_mode = TRUE
	mob_bump_flag = HEAVY
	mob_swap_flags = ~HEAVY
	mob_push_flags = HEAVY

	used_weapon = /obj/item/gun/energy/taser

	var/shot_delay = 4
	var/last_shot = 0

/mob/living/bot/secbot/ed209/update_icons()
	if(on && busy)
		icon_state = "ed209-c"
	else
		icon_state = "ed209[on]"

/mob/living/bot/secbot/ed209/explode()
	visible_message(span_warning("[src] blows apart!"))
	var/turf/Tsec = get_turf(src)

	new /obj/item/secbot_assembly/ed209_assembly(Tsec)

	var/obj/item/gun/energy/taser/G = new used_weapon(Tsec)
	G.power_supply.charge = 0
	if(prob(50))
		new /obj/item/robot_parts/l_leg(Tsec)
	if(prob(50))
		new /obj/item/robot_parts/r_leg(Tsec)
	if(prob(50))
		if(prob(50))
			new /obj/item/clothing/head/helmet(Tsec)
		else
			new /obj/item/clothing/suit/storage/vest(Tsec)

	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(3, 1, src)
	s.start()

	new /obj/effect/decal/cleanable/blood/oil(Tsec)
	return ..()

/mob/living/bot/secbot/ed209/handleRangedTarget()
	RangedAttack(target)

/mob/living/bot/secbot/ed209/RangedAttack(atom/A)
	if(last_shot + shot_delay > world.time)
		to_chat(src, "You are not ready to fire yet!")
		return

	last_shot = world.time

	var/projectile = /obj/item/projectile/beam/stun
	if(emagged)
		projectile = /obj/item/projectile/beam

	playsound(src, emagged ? 'sound/weapons/Laser.ogg' : 'sound/weapons/taser.ogg', 50, 1)
	var/obj/item/projectile/P = new projectile(loc)

	P.firer = src
	P.old_style_target(A)
	P.fire()

// Assembly

/obj/item/secbot_assembly/ed209_assembly
	name = "ED-209 assembly"
	desc = "Some sort of bizarre assembly."
	icon = 'icons/obj/aibots.dmi'
	icon_state = "ed209_frame"
	item_state = "buildpipe"
	created_name = "ED-209 Security Robot"
	var/lasercolor = ""
	construction_graph = /datum/construction_graph/secbot_assembly/ed209

// Renaming the finished bot is not construction: keep it a plain interaction.
/obj/item/secbot_assembly/ed209_assembly/attackby(obj/item/W, mob/user)
	..()
	if(istype(W, /obj/item/pen))
		var/t = sanitizeSafe(tgui_input_text(user, "Enter new robot name", name, created_name, MAX_NAME_LEN, encode = FALSE), MAX_NAME_LEN)
		if(!t)
			return
		if(!in_range(src, user) && src.loc != user)
			return
		created_name = t

/// A robot leg: two robot_parts types, or a robotic external leg organ by name.
/datum/interaction/construction/secbot/leg
	item_type = list(/obj/item/robot_parts/l_leg, /obj/item/robot_parts/r_leg, /obj/item/organ/external/leg)
	item_name = "a robot leg"
	item_use = CONSTRUCTION_ITEM_DELETE
	step_text = "add a robot leg"

/datum/interaction/construction/secbot/leg/item_matches(obj/item/held)
	if(istype(held, /obj/item/robot_parts/l_leg) || istype(held, /obj/item/robot_parts/r_leg))
		return TRUE
	return istype(held, /obj/item/organ/external/leg) && (held.name == "robotic right leg" || held.name == "robotic left leg")

/datum/interaction/construction/secbot/leg/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = target
	assembly.name = "legs/frame assembly"
	assembly.icon_state = (after == 1) ? "ed209_leg" : "ed209_legs"
	to_chat(actor, span_notice("You add the robot leg to [target]."))
	return TRUE

/datum/construction_graph/secbot_assembly/ed209
	id = "ed209_assembly"
	states = list(0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
	initial_states = list(0)
	state_var = "build_step"
	edge_types = list(
		/datum/interaction/construction/secbot/ed209/leg_0,
		/datum/interaction/construction/secbot/ed209/leg_1,
		/datum/interaction/construction/secbot/ed209/vest,
		/datum/interaction/construction/secbot/ed209/weld_vest,
		/datum/interaction/construction/secbot/ed209/helmet,
		/datum/interaction/construction/secbot/ed209/prox,
		/datum/interaction/construction/secbot/ed209/wire,
		/datum/interaction/construction/secbot/ed209/taser,
		/datum/interaction/construction/secbot/ed209/taser_xeno,
		/datum/interaction/construction/secbot/ed209/attach_gun,
		/datum/interaction/construction/secbot/ed209/finish,
	)

/datum/interaction/construction/secbot/ed209/leg_0
	parent_type = /datum/interaction/construction/secbot/leg
	from_state = 0
	to_state = 1

/datum/interaction/construction/secbot/ed209/leg_1
	parent_type = /datum/interaction/construction/secbot/leg
	from_state = 1
	to_state = 2

/datum/interaction/construction/secbot/ed209/vest
	from_state = 2
	to_state = 3
	step_text = "add the armor"
	item_type = /obj/item/clothing/suit/storage/vest
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/ed209/vest/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = target
	assembly.name = "vest/legs/frame assembly"
	assembly.item_state = "ed209_shell"
	assembly.icon_state = "ed209_shell"
	to_chat(actor, span_notice("You add the armor to [target]."))
	return TRUE

/datum/interaction/construction/secbot/ed209/weld_vest
	from_state = 3
	to_state = 4
	step_text = "weld the vest on"
	tool = TOOL_WELDER

/datum/interaction/construction/secbot/ed209/weld_vest/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = target
	assembly.name = "shielded frame assembly"
	to_chat(actor, span_notice("You welded the vest to [target]."))
	return TRUE

/datum/interaction/construction/secbot/ed209/helmet
	from_state = 4
	to_state = 5
	step_text = "add the helmet"
	item_type = /obj/item/clothing/head/helmet
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/ed209/helmet/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = target
	assembly.name = "covered and shielded frame assembly"
	assembly.item_state = "ed209_hat"
	assembly.icon_state = "ed209_hat"
	to_chat(actor, span_notice("You add the helmet to [target]."))
	return TRUE

/datum/interaction/construction/secbot/ed209/prox
	from_state = 5
	to_state = 6
	step_text = "add the prox sensor"
	item_type = /obj/item/assembly/prox_sensor
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/ed209/prox/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = target
	assembly.name = "covered, shielded and sensored frame assembly"
	assembly.item_state = "ed209_prox"
	assembly.icon_state = "ed209_prox"
	to_chat(actor, span_notice("You add the prox sensor to [target]."))
	return TRUE

/datum/interaction/construction/secbot/ed209/wire
	from_state = 6
	to_state = 7
	step_text = "wire it"
	item_type = /obj/item/stack/cable_coil
	item_amount = 1
	item_use = CONSTRUCTION_ITEM_USE
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "You start to wire %TARGET%."

/datum/interaction/construction/secbot/ed209/wire/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = target
	assembly.name = "wired ED-209 assembly"
	to_chat(actor, span_notice("You wire the ED-209 assembly."))
	return TRUE

/datum/interaction/construction/secbot/ed209/taser
	from_state = 7
	to_state = 8
	step_text = "add a taser"
	item_type = /obj/item/gun/energy/taser
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/ed209/taser/item_matches(obj/item/held)
	return istype(held, /obj/item/gun/energy/taser) && !istype(held, /obj/item/gun/energy/taser/xeno)

/datum/interaction/construction/secbot/ed209/taser/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = target
	assembly.name = "taser ED-209 assembly"
	assembly.item_state = "ed209_taser"
	assembly.icon_state = "ed209_taser"
	to_chat(actor, span_notice("You add [held] to [target]."))
	return TRUE

/datum/interaction/construction/secbot/ed209/taser_xeno
	from_state = 7
	to_state = CONSTRUCTION_DONE
	step_text = "add a xenotaser"
	item_type = /obj/item/gun/energy/taser/xeno
	item_use = CONSTRUCTION_ITEM_DELETE
	priority = 5

/datum/interaction/construction/secbot/ed209/taser_xeno/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = target
	to_chat(actor, span_notice("You add [held] to [assembly]."))
	var/turf/where = get_turf(assembly)
	var/obj/item/secbot_assembly/ed209_assembly/slime/slime_assembly = new(where)
	slime_assembly.name = "xenotaser SL-ED-209 assembly"
	slime_assembly.item_state = "sled209_taser"
	slime_assembly.icon_state = "sled209_taser"
	slime_assembly.build_step = 8
	slime_assembly.created_name = assembly.created_name
	slime_assembly.lasercolor = assembly.lasercolor
	actor.drop_from_inventory(assembly)
	qdel(assembly)
	return TRUE

/datum/interaction/construction/secbot/ed209/attach_gun
	from_state = 8
	to_state = 9
	step_text = "attach the gun to the frame"
	tool = TOOL_SCREWDRIVER
	tool_volume = 100
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "Now attaching the gun to the frame..."

/datum/interaction/construction/secbot/ed209/attach_gun/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = target
	assembly.name = "armed [assembly.name]"
	to_chat(actor, span_notice("Taser gun attached."))
	return TRUE

/datum/interaction/construction/secbot/ed209/finish
	from_state = 9
	to_state = CONSTRUCTION_DONE
	step_text = "install a cell to finish it"
	item_type = /obj/item/cell
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/ed209/finish/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = target
	to_chat(actor, span_notice("You complete the ED-209."))
	var/turf/where = get_turf(assembly)
	var/mob/living/bot/secbot/ed209/bot = new /mob/living/bot/secbot/ed209(where)
	bot.name = assembly.created_name
	actor.drop_from_inventory(assembly)
	qdel(assembly)
	return TRUE
