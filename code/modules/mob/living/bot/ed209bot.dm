/mob/living/bot/secbot/ed209
	name = "ED-209 Security Robot"
	desc = "A security robot.  He looks less than thrilled."
	icon = 'icons/obj/aibots.dmi'
	icon_state = "ed2090"
	density = TRUE
	endurance = 200

	is_ranged = 1
	preparing_arrest_sounds = null

	combat_mode = TRUE
	mob_bump_flag = HEAVY
	mob_swap_flags = ~HEAVY
	mob_push_flags = HEAVY

	used_weapon = /obj/item/gun/energy/taser

	var/shot_delay = 4
	COOLDOWN_DECLARE(shot_cooldown)

/mob/living/bot/secbot/ed209/update_icons()
	if(on && bot_busy())
		icon_state = "ed209-c"
	else
		icon_state = "ed209[on]"

/mob/living/bot/secbot/ed209/explode()
	act_message(src, null, others = span_warning("%U% blows apart!"))
	var/turf/Tsec = get_turf(src)

	new /obj/item/secbot_assembly/ed209_assembly(Tsec)

	var/obj/item/gun/energy/taser/G = new used_weapon(Tsec)
	G.power_supply.set_charge(0)
	if(prob(50))
		new /obj/item/robot_parts/l_leg(Tsec)
	if(prob(50))
		new /obj/item/robot_parts/r_leg(Tsec)
	if(prob(50))
		if(prob(50))
			new /obj/item/clothing/head/helmet(Tsec)
		else
			new /obj/item/clothing/suit/storage/vest(Tsec)

	fx_sparks(src, 3)

	new /obj/effect/decal/cleanable/blood/oil(Tsec)
	return ..()

/mob/living/bot/secbot/ed209/handleRangedTarget()
	RangedAttack(target)

/mob/living/bot/secbot/ed209/RangedAttack(atom/A)
	if(!COOLDOWN_FINISHED(src, shot_cooldown))
		to_chat(src, "You are not ready to fire yet!")
		return

	COOLDOWN_START(src, shot_cooldown, shot_delay)

	var/projectile = /obj/item/projectile/beam/stun
	if(emagged)
		projectile = /obj/item/projectile/beam

	play_sfx(src, emagged ? SFX_WEAPONS_LASER : SFX_WEAPONS_TASER, volume = 50)
	var/obj/item/projectile/P = new projectile(loc)

	rel_set(P, nameof(P.firer), src)
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

// Renaming with a pen is inherited from /obj/item/secbot_assembly (secbot_assembly_rename).

STAGE_DEF(ed209, armoured)
STAGE_DEF(ed209, shielded)
STAGE_DEF(ed209, helmeted)
STAGE_DEF(ed209, sensing)
STAGE_DEF(ed209, wired)
STAGE_DEF(ed209, tasered)
STAGE_DEF(ed209, armed)
STAGE_DEF(ed209, finished)
STAGE_DEF(ed209, swapped)

MSG_DEF_SELF(stage/ed209/armoured, "It has its armor on.")
MSG_DEF_SELF(stage/ed209/shielded, "Its armor is welded on.")
MSG_DEF_SELF(stage/ed209/helmeted, "It has its helmet.")
MSG_DEF_SELF(stage/ed209/sensing, "It has its proximity sensor.")
MSG_DEF_SELF(stage/ed209/wired, "It is wired.")
MSG_DEF_SELF(stage/ed209/tasered, "It has its gun.")
MSG_DEF_SELF(stage/ed209/armed, "Its gun is attached to the frame.")
MSG_DEF_SELF(stage/ed209/finished, "It is finished.")
MSG_DEF_SELF(stage/ed209/swapped, "It has been made into an SL-ED-209 assembly.")
MSG_DEF_SELF(ed209/start_attach_gun, "Now attaching the gun to the frame...")

/// The ED-209 ladder from its armor to its wiring, which the SL-ED-209 assembly shares.
/proc/ed209_body()
	return list(
		stage(STAGE_ED209_ARMOURED, item(/obj/item/clothing/suit/storage/vest), consumes(), wait(0), then(TYPE_PROC_REF(/obj/item/secbot_assembly/ed209_assembly, vest_added)), undo = NO_UNDO),
		stage(STAGE_ED209_SHIELDED, tool(TOOL_WELDER), wait(0), then(TYPE_PROC_REF(/obj/item/secbot_assembly/ed209_assembly, vest_welded)), undo = NO_UNDO),
		stage(STAGE_ED209_HELMETED, item(/obj/item/clothing/head/helmet), consumes(), wait(0), then(TYPE_PROC_REF(/obj/item/secbot_assembly/ed209_assembly, helmet_added)), undo = NO_UNDO),
		stage(STAGE_ED209_SENSING, item(/obj/item/assembly/prox_sensor), consumes(), wait(0), then(TYPE_PROC_REF(/obj/item/secbot_assembly/ed209_assembly, sensor_added)), undo = NO_UNDO),
		stage(STAGE_ED209_WIRED, stack(/obj/item/stack/cable_coil, 1), wait(4 SECONDS), begins(MSG(bot_frame/start_wire)), then(TYPE_PROC_REF(/obj/item/secbot_assembly/ed209_assembly, wired_up)), undo = NO_UNDO))

/// Fixing the gun to the frame, which the SL-ED-209 assembly shares.
/proc/ed209_gun_attached()
	return stage(STAGE_ED209_ARMED, tool(TOOL_SCREWDRIVER), wait(4 SECONDS), begins(MSG(ed209/start_attach_gun)), then(TYPE_PROC_REF(/obj/item/secbot_assembly/ed209_assembly, gun_attached)), undo = NO_UNDO)

CAPABILITIES(/obj/item/secbot_assembly/ed209_assembly)
	without(CAP_CONSTRUCTION)
	construction(start(STAGE_BOT_FRAME_BARE), bot_frame_legs(), ed209_body(),
		stage(STAGE_ED209_TASERED, item(/obj/item/gun/energy/taser), when(req(PROC_REF(plain_taser_held))), consumes(), wait(0), then(PROC_REF(taser_added)), undo = NO_UNDO),
		ed209_gun_attached(),
		stage(STAGE_ED209_FINISHED, item(/obj/item/cell), consumes(), wait(0), then(PROC_REF(finished)), undo = NO_UNDO),
		stage(STAGE_ED209_SWAPPED, item(/obj/item/gun/energy/taser/xeno), consumes(), wait(0), then(PROC_REF(swapped_to_slime)), from = STAGE_ED209_WIRED, undo = NO_UNDO))

/obj/item/secbot_assembly/ed209_assembly/proc/vest_added(datum/act/op/A)
	name = "vest/legs/frame assembly"
	item_state = "ed209_shell"
	icon_state = "ed209_shell"
	to_chat(A.actor, span_notice("You add the armor to [src]."))
	return OP_OK

/obj/item/secbot_assembly/ed209_assembly/proc/vest_welded(datum/act/op/A)
	name = "shielded frame assembly"
	to_chat(A.actor, span_notice("You welded the vest to [src]."))
	return OP_OK

/obj/item/secbot_assembly/ed209_assembly/proc/helmet_added(datum/act/op/A)
	name = "covered and shielded frame assembly"
	item_state = "ed209_hat"
	icon_state = "ed209_hat"
	to_chat(A.actor, span_notice("You add the helmet to [src]."))
	return OP_OK

/obj/item/secbot_assembly/ed209_assembly/sensor_added(datum/act/op/A)
	name = "covered, shielded and sensored frame assembly"
	item_state = "ed209_prox"
	icon_state = "ed209_prox"
	to_chat(A.actor, span_notice("You add the prox sensor to [src]."))
	return OP_OK

/obj/item/secbot_assembly/ed209_assembly/proc/wired_up(datum/act/op/A)
	name = "wired ED-209 assembly"
	to_chat(A.actor, span_notice("You wire the ED-209 assembly."))
	return OP_OK

/// A xenotaser belongs to the SL-ED-209 assembly: the plain taser step does not take one.
/obj/item/secbot_assembly/ed209_assembly/proc/plain_taser_held(datum/act/op/A)
	return (istype(A.held, /obj/item/gun/energy/taser) && !istype(A.held, /obj/item/gun/energy/taser/xeno)) ? null : /datum/msg/req_failed

/obj/item/secbot_assembly/ed209_assembly/proc/taser_added(datum/act/op/A)
	name = "taser ED-209 assembly"
	item_state = "ed209_taser"
	icon_state = "ed209_taser"
	to_chat(A.actor, span_notice("You add [A.held] to [src]."))
	return OP_OK

/obj/item/secbot_assembly/ed209_assembly/proc/gun_attached(datum/act/op/A)
	name = "armed [name]"
	to_chat(A.actor, span_notice("Taser gun attached."))
	return OP_OK

/// A xenotaser at the wired stage swaps the assembly for the SL-ED-209 kind, which picks up at its gun stage.
/obj/item/secbot_assembly/ed209_assembly/proc/swapped_to_slime(datum/act/op/A)
	to_chat(A.actor, span_notice("You add [A.held] to [src]."))
	var/turf/where = get_turf(src)
	var/obj/item/secbot_assembly/ed209_assembly/slime/slime_assembly = new(where)
	slime_assembly.name = "xenotaser SL-ED-209 assembly"
	slime_assembly.item_state = "sled209_taser"
	slime_assembly.icon_state = "sled209_taser"
	graph_place(slime_assembly, STAGE_ED209_TASERED)
	slime_assembly.created_name = created_name
	slime_assembly.lasercolor = lasercolor
	consume(src, A.actor)
	return OP_OK

/obj/item/secbot_assembly/ed209_assembly/finished(datum/act/op/A)
	to_chat(A.actor, span_notice("You complete the ED-209."))
	var/turf/where = get_turf(src)
	var/mob/living/bot/secbot/ed209/bot = new /mob/living/bot/secbot/ed209(where)
	bot.name = created_name
	consume(src, A.actor)
	return OP_OK
