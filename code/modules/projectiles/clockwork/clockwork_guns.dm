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

	var/phase_power = 2400
	firemodes = list(
		list(mode_name="burst", burst=3, fire_delay=8, projectile_type=/obj/item/projectile/bullet/rifle/clockwork, charge_cost = 80),
		list(mode_name="volt beam", fire_delay=12, projectile_type=/obj/item/projectile/beam/shock/clockwork, charge_cost = 2400),
	)
	cell_type = /obj/item/cell/device/weapon/empproof

// Recharging is one op that waits a cycle at a time, 5 seconds each, until the cell is full; the gun is claimed for as long as it runs.
CAPABILITIES(/obj/item/gun/energy/clockwork)
	op("recharge", ai(), claims(), starts(PROC_REF(recharge_started)), wait(5 SECONDS, repeats = PROC_REF(recharge_more), after_step = PROC_REF(recharge_cycle)), on_interrupt(PROC_REF(recharge_end)), then(PROC_REF(recharge_end)))

/obj/item/gun/energy/clockwork/unload_ammo(mob/user)
	perform_op(user, src, "recharge", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)

/obj/item/gun/energy/clockwork/proc/recharge_started(datum/act/op/A)
	play_sfx(src, SFX_WEAPONS_CLOCKWORK_CLOCKWORK_COCK)
	act_message(A.actor, src, MSG_SELF(span_notice("You pull the charging handle on %T% and begin the reloading sequence.")), \
		MSG_OTHERS(span_notice("%U% pulls the charging handle on %T% and it whirrs to life!")))
	play_sfx(src, SFX_WEAPONS_CLOCKWORK_CWC_RIFLE_FABRICATE)

/// Another cycle follows while the cell has room.
/obj/item/gun/energy/clockwork/proc/recharge_more(datum/act/op/A)
	return power_supply && power_supply.charge < power_supply.maxcharge

/// One charging cycle done.
/obj/item/gun/energy/clockwork/proc/recharge_cycle(datum/act/op/A)
	var/mob/user = A.actor
	user.hud_used.update_ammo_hud(user, src)
	power_supply?.give(phase_power)

/obj/item/gun/energy/clockwork/proc/recharge_end(datum/act/op/A)
	var/mob/user = A.actor
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
