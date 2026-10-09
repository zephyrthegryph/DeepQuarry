/mob/living/bot/secbot/ed209/slime
	name = "SL-ED-209 Security Robot"
	desc = "A security robot.  He looks less than thrilled."
	icon = 'icons/obj/aibots.dmi'
	icon_state = "sled2090"
	density = TRUE
	endurance = 200

	is_ranged = 1
	preparing_arrest_sounds = null

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
	if(on && bot_busy())
		icon_state = "sled209-c"
	else
		icon_state = "sled209[on]"

/mob/living/bot/secbot/ed209/slime/RangedAttack(atom/A)
	if(!COOLDOWN_FINISHED(src, shot_cooldown))
		to_chat(src, "You are not ready to fire yet!")
		return

	COOLDOWN_START(src, shot_cooldown, shot_delay)

	var/projectile = /obj/item/projectile/beam/stun/xeno
	if(emagged)
		projectile = /obj/item/projectile/beam/shock

	play_sfx(src, emagged ? SFX_WEAPONS_LASER3 : SFX_WEAPONS_TASER, volume = 50)
	var/obj/item/projectile/P = new projectile(loc)

	rel_set(P, nameof(P.firer), src)
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

// Renaming with a pen is inherited from /obj/item/secbot_assembly (secbot_assembly_rename).
// Here in the event it's added into a PoI or some such: standard construction
// relies on the standard ED-209 assembly up until the taser is added, then
// swaps to this type (see swapped_to_slime on the ED-209 assembly),
// so this ladder covers the same steps end to end for a directly-placed one.

CAPABILITIES(/obj/item/secbot_assembly/ed209_assembly/slime)
	without(CAP_CONSTRUCTION)
	construction(start(STAGE_BOT_FRAME_BARE), bot_frame_legs(), ed209_body(),
		stage(STAGE_ED209_TASERED, item(/obj/item/gun/energy/taser/xeno), consumes(), wait(0), then(PROC_REF(xeno_taser_added)), undo = null),
		ed209_gun_attached(),
		stage(STAGE_ED209_FINISHED, item(/obj/item/cell), consumes(), wait(0), then(PROC_REF(finished)), undo = null))

/obj/item/secbot_assembly/ed209_assembly/slime/proc/xeno_taser_added(datum/act/op/A)
	name = "xenotaser SL-ED-209 assembly"
	item_state = "sled209_taser"
	icon_state = "sled209_taser"
	to_chat(A.actor, span_notice("You add [A.held] to [src]."))
	return OP_OK

/obj/item/secbot_assembly/ed209_assembly/slime/finished(datum/act/op/A)
	to_chat(A.actor, span_notice("You complete the ED-209."))
	var/turf/where = get_turf(src)
	new /mob/living/bot/secbot/ed209/slime(where, created_name, lasercolor)
	consume(src, A.actor)
	return OP_OK
