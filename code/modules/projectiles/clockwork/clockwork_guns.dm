//clockcult gun

/obj/item/gun/energy/clockwork
	name = "clockwork rifle"
	desc = "A rifle that looks to be made entirely out of brass. It has a charging handle on the side, but doesn't seem to have a way to eject the magazine underneath."
	icon = 'icons/obj/guns/clockwork/guns_ch.dmi'
	icon_state = "clockrifle"
	item_state = "clockrifle"
	wielded_item_state = "clockrifle-wielded"
	slot_flags = SLOT_BACK
	item_icons = list(slot_l_hand_str = 'icons/mob/items/lefthand_guns_ch.dmi', slot_r_hand_str = 'icons/mob/items/righthand_guns_ch.dmi', "slot_back" = 'icons/mob/guns_back_ch.dmi')
	projectile_type = /obj/item/projectile/bullet/rifle/clockwork
	w_class = ITEMSIZE_HUGE
	one_handed_penalty = 90
	accuracy = 45
	charge_cost = 300

	battery_lock = 1
	unacidable = TRUE

	var/recharging = 0
	var/phase_power = 2400
	firemodes = list(
		list(mode_name="burst", burst=3, fire_delay=8, projectile_type=/obj/item/projectile/bullet/rifle/clockwork, charge_cost = 80),
		list(mode_name="volt beam", fire_delay=12, projectile_type=/obj/item/projectile/beam/shock/clockwork, charge_cost = 2400),
	)
	cell_type = /obj/item/cell/device/weapon/empproof

/obj/item/gun/energy/clockwork/unload_ammo(mob/user)
	if(recharging)
		return
	recharging = 1
	play_sfx(src, SFX_WEAPONS_CLOCKWORK_CLOCKWORK_COCK)
	act_message(user, src, MSG_SELF(span_notice("You pull the charging handle on %T% and begin the reloading sequence.")), \
		MSG_OTHERS(span_notice("%U% pulls the charging handle on %T% and it whirrs to life!")))
	play_sfx(src, SFX_WEAPONS_CLOCKWORK_CWC_RIFLE_FABRICATE)
	task_timed(user, 5 SECONDS, src, src, PROC_REF(recharge_cycle), list(user), on_fail = PROC_REF(recharge_end), fail_args = list(user))

/// One charging cycle every 5 seconds (a timed action each) until full.
/obj/item/gun/energy/clockwork/proc/recharge_cycle(mob/user)
	user.hud_used.update_ammo_hud(user, src)
	if(power_supply.give(phase_power) < phase_power)
		recharge_end(user)
		return
	task_timed(user, 5 SECONDS, src, src, PROC_REF(recharge_cycle), list(user), on_fail = PROC_REF(recharge_end), fail_args = list(user))

/obj/item/gun/energy/clockwork/proc/recharge_end(mob/user)
	recharging = 0
	user?.hud_used?.update_ammo_hud(user, src) // Update one last time once we're finished!

/obj/item/projectile/bullet/rifle/clockwork
	fire_sound = SFX_WEAPONS_CLOCKWORK_CWC_RIFLE_FIRE
	damage = 20 //Old 10
	hud_state = "rifle_heavy"

/obj/item/projectile/beam/shock/clockwork
	name = "shock beam"
	fire_sound = SFX_WEAPONS_CLOCKWORK_VOLTBEAM_FIRE
	icon_state = "lightning"

	muzzle_type = /obj/effect/projectile/muzzle/voltbeam
	tracer_type = /obj/effect/projectile/tracer/voltbeam
	impact_type = /obj/effect/projectile/impact/voltbeam

	damage = 40 //Old 20
	agony = 15
	eyeblur = 2
	hitsound = SFX_EFFECTS_LIGHTNINGSHOCK
	hitsound_wall = SFX_WEAPONS_CLOCKWORK_VOLTBEAMSEARWALL
	hud_state = "taser"

/obj/effect/projectile/muzzle/voltbeam
	icon = 'icons/obj/guns/clockwork/projectiles_tracer_ch.dmi'
	icon_state = "muzzle_volt_ray"
	light_range = 2
	light_power = 1
	light_color = "#DAAA18"

/obj/effect/projectile/tracer/voltbeam
	icon = 'icons/obj/guns/clockwork/projectiles_tracer_ch.dmi'
	icon_state = "volt_ray"
	light_range = 2
	light_power = 1
	light_color = "#DAAA18"

/obj/effect/projectile/impact/voltbeam
	icon = 'icons/obj/guns/clockwork/projectiles_tracer_ch.dmi'
	icon_state = "impact_volt_ray"
	light_range = 2
	light_power = 1
	light_color = "#DAAA18"
