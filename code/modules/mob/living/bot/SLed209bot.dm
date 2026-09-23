/mob/living/bot/secbot/ed209/slime
	name = "SL-ED-209 Security Robot"
	desc = "A security robot.  He looks less than thrilled."
	icon = 'icons/obj/aibots.dmi'
	icon_state = "sled2090"
	density = TRUE
	endurance = 200

	is_ranged = 1
	preparing_arrest_sounds = new()

	combat_mode = TRUE
	mob_bump_flag = HEAVY
	mob_swap_flags = ~HEAVY
	mob_push_flags = HEAVY

	used_weapon = /obj/item/gun/energy/taser/xeno

	stun_strength = 10
	xeno_harm_strength = 9
	req_one_access = list(ACCESS_RESEARCH, ACCESS_ROBOTICS)
	botcard_access = list(ACCESS_RESEARCH, ACCESS_ROBOTICS, ACCESS_XENOBIOLOGY, ACCESS_XENOARCH, ACCESS_TOX, ACCESS_TOX_STORAGE, ACCESS_MAINT_TUNNELS)
	retaliates = FALSE
	var/xeno_stun_strength = 6

/mob/living/bot/secbot/ed209/slime/update_icons()
	if(on && busy)
		icon_state = "sled209-c"
	else
		icon_state = "sled209[on]"

/mob/living/bot/secbot/ed209/slime/RangedAttack(atom/A)
	if(last_shot + shot_delay > world.time)
		to_chat(src, "You are not ready to fire yet!")
		return

	last_shot = world.time

	var/projectile = /obj/item/projectile/beam/stun/xeno
	if(emagged)
		projectile = /obj/item/projectile/beam/shock

	playsound(src, emagged ? 'sound/weapons/laser3.ogg' : 'sound/weapons/taser.ogg', 50, 1)
	var/obj/item/projectile/P = new projectile(loc)

	P.firer = src
	P.old_style_target(A)
	P.fire()

/mob/living/bot/secbot/ed209/slime/UnarmedAttack(mob/living/L, proximity)
	..()

	if(istype(L, /mob/living/simple_mob/slime/xenobio))
		var/mob/living/simple_mob/slime/xenobio/S = L
		S.slimebatoned(src, xeno_stun_strength)

// Assembly

/obj/item/secbot_assembly/ed209_assembly/slime
	name = "SL-ED-209 assembly"
	desc = "Some sort of bizarre assembly."
	icon = 'icons/obj/aibots.dmi'
	icon_state = "ed209_frame"
	item_state = "buildpipe"
	created_name = "SL-ED-209 Security Robot"
	construction_graph = /datum/construction_graph/secbot_assembly/ed209_slime

// Renaming the finished bot is not construction: keep it a plain interaction.
// Here in the event it's added into a PoI or some such: standard construction
// relies on the standard ED-209 assembly up until the taser is added, then
// swaps to this type (see /datum/interaction/construction/secbot/ed209/taser_xeno),
// so this graph covers the same steps end to end for a directly-placed one.
/obj/item/secbot_assembly/ed209_assembly/slime/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/pen))
		var/t = sanitizeSafe(tgui_input_text(user, "Enter new robot name", name, created_name, MAX_NAME_LEN, encode = FALSE), MAX_NAME_LEN)
		if(!t)
			return
		if(!in_range(src, user) && src.loc != user)
			return
		created_name = t

/datum/construction_graph/secbot_assembly/ed209_slime
	id = "ed209_assembly_slime"
	states = list(0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
	initial_states = list(0)
	state_var = "build_step"
	edge_types = list(
		/datum/interaction/construction/secbot/sled209/leg_0,
		/datum/interaction/construction/secbot/sled209/leg_1,
		/datum/interaction/construction/secbot/sled209/vest,
		/datum/interaction/construction/secbot/sled209/weld_vest,
		/datum/interaction/construction/secbot/sled209/helmet,
		/datum/interaction/construction/secbot/sled209/prox,
		/datum/interaction/construction/secbot/sled209/wire,
		/datum/interaction/construction/secbot/sled209/taser_xeno,
		/datum/interaction/construction/secbot/sled209/attach_gun,
		/datum/interaction/construction/secbot/sled209/finish,
	)

/datum/interaction/construction/secbot/sled209/leg_0
	parent_type = /datum/interaction/construction/secbot/leg
	from_state = 0
	to_state = 1

/datum/interaction/construction/secbot/sled209/leg_1
	parent_type = /datum/interaction/construction/secbot/leg
	from_state = 1
	to_state = 2

/datum/interaction/construction/secbot/sled209/vest
	from_state = 2
	to_state = 3
	step_text = "add the armor"
	item_type = /obj/item/clothing/suit/storage/vest
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/sled209/vest/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/slime/assembly = target
	assembly.name = "vest/legs/frame assembly"
	assembly.item_state = "ed209_shell"
	assembly.icon_state = "ed209_shell"
	to_chat(actor, span_notice("You add the armor to [target]."))
	return TRUE

/datum/interaction/construction/secbot/sled209/weld_vest
	from_state = 3
	to_state = 4
	step_text = "weld the vest on"
	tool = TOOL_WELDER

/datum/interaction/construction/secbot/sled209/weld_vest/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/slime/assembly = target
	assembly.name = "shielded frame assembly"
	to_chat(actor, span_notice("You welded the vest to [target]."))
	return TRUE

/datum/interaction/construction/secbot/sled209/helmet
	from_state = 4
	to_state = 5
	step_text = "add the helmet"
	item_type = /obj/item/clothing/head/helmet
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/sled209/helmet/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/slime/assembly = target
	assembly.name = "covered and shielded frame assembly"
	assembly.item_state = "ed209_hat"
	assembly.icon_state = "ed209_hat"
	to_chat(actor, span_notice("You add the helmet to [target]."))
	return TRUE

/datum/interaction/construction/secbot/sled209/prox
	from_state = 5
	to_state = 6
	step_text = "add the prox sensor"
	item_type = /obj/item/assembly/prox_sensor
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/sled209/prox/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/slime/assembly = target
	assembly.name = "covered, shielded and sensored frame assembly"
	assembly.item_state = "ed209_prox"
	assembly.icon_state = "ed209_prox"
	to_chat(actor, span_notice("You add the prox sensor to [target]."))
	return TRUE

/datum/interaction/construction/secbot/sled209/wire
	from_state = 6
	to_state = 7
	step_text = "wire it"
	item_type = /obj/item/stack/cable_coil
	item_amount = 1
	item_use = CONSTRUCTION_ITEM_USE
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "You start to wire %TARGET%."

/datum/interaction/construction/secbot/sled209/wire/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/slime/assembly = target
	assembly.name = "wired ED-209 assembly"
	to_chat(actor, span_notice("You wire the ED-209 assembly."))
	return TRUE

/datum/interaction/construction/secbot/sled209/taser_xeno
	from_state = 7
	to_state = 8
	step_text = "add a xenotaser"
	item_type = /obj/item/gun/energy/taser/xeno
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/sled209/taser_xeno/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/slime/assembly = target
	assembly.name = "xenotaser SL-ED-209 assembly"
	assembly.item_state = "sled209_taser"
	assembly.icon_state = "sled209_taser"
	to_chat(actor, span_notice("You add [held] to [target]."))
	return TRUE

/datum/interaction/construction/secbot/sled209/attach_gun
	from_state = 8
	to_state = 9
	step_text = "attach the gun to the frame"
	tool = TOOL_SCREWDRIVER
	tool_volume = 100
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "Now attaching the gun to the frame..."

/datum/interaction/construction/secbot/sled209/attach_gun/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/slime/assembly = target
	assembly.name = "armed [assembly.name]"
	to_chat(actor, span_notice("Taser gun attached."))
	return TRUE

/datum/interaction/construction/secbot/sled209/finish
	from_state = 9
	to_state = CONSTRUCTION_DONE
	step_text = "install a cell to finish it"
	item_type = /obj/item/cell
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/sled209/finish/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/ed209_assembly/slime/assembly = target
	to_chat(actor, span_notice("You complete the ED-209."))
	var/turf/where = get_turf(assembly)
	new /mob/living/bot/secbot/ed209/slime(where, assembly.created_name, assembly.lasercolor)
	actor.drop_from_inventory(assembly)
	qdel(assembly)
	return TRUE
