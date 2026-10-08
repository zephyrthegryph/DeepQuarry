/obj/item/gun/energy
	name = "energy gun"
	desc = "A basic energy-based gun."
	icon_state = "energy"
	fire_sound_text = "laser blast"

	var/obj/item/cell/power_supply //What type of power cell this uses
	var/charge_cost = 240 //How much energy is needed to fire.

	var/accept_cell_type = /obj/item/cell/device
	var/cell_type = /obj/item/cell/device/weapon
	projectile_type = /obj/item/projectile/beam/practice

	var/modifystate
	var/charge_meter = 1	//if set, the icon state will be chosen based on the current charge

	reload_time = 5		//Energy weapons are slower to reload than ballistics by default, but this is no change from current values

	//self-recharge
	var/use_external_power = 0 //if set, the weapon will look for an external power source to draw from, otherwise it recharges magically
	var/use_organic_power = 0 // If set, the weapon will draw from nutrition or blood.
	var/recharge_time = 4
	var/charge_tick = 0
	var/charge_delay = 75	//delay between firing and charging
	/// Self-recharge is held off until charge_delay after the last shot.
	COOLDOWN_DECLARE(recharge_cooldown)
	var/shot_counter = TRUE // does this gun tell you how many shots it has?

	var/battery_lock = 0	//If set, weapon cannot switch batteries
	var/random_start_ammo = FALSE	//if TRUE, the weapon will spawn with randomly-determined ammo

//if set, the weapon will recharge itself
/obj/item/gun/energy/var/self_recharge = 0
/// TRUE while a self-recharging gun may be below full: firing raises it, a step that finds the cell full drops it.
/obj/item/gun/energy/var/tmp/recharge_due = TRUE
TRACKED(/obj/item/gun/energy, self_recharge)
TRACKED(/obj/item/gun/energy, modifystate)
TRACKED(/obj/item/gun/energy, charge_cost)
TRACKED(/obj/item/gun/energy, recharge_due)

/obj/item/gun/energy/Initialize(mapload)
	. = ..()
	if(self_recharge)
		rel_set(src, nameof(power_supply), new /obj/item/cell/device/weapon(src))
	else
		if(cell_type)
			rel_set(src, nameof(power_supply), new cell_type(src))
		else
			rel_clear(src, nameof(power_supply))
	//random starting power! gives us a random number of shots in the battery between 0 and the max possible
	if(random_start_ammo && cell_type)
		power_supply.set_charge(charge_cost*rand(0,power_supply.maxcharge/charge_cost))

/obj/item/gun/energy/get_cell()
	return power_supply

/// Self-recharge: full, it parks; firing wakes it after a discharge.
/obj/item/gun/energy/proc/energy_gun_recharge_step(datum/act/timer/A)
	if(self_recharge) //Every [recharge_time] ticks, recharge a shot for the battery
		if(COOLDOWN_FINISHED(src, recharge_cooldown))	//Doesn't work if you've fired recently
			if(!power_supply || power_supply.charge >= power_supply.maxcharge)
				set_recharge_due(FALSE)
				return

			charge_tick++
			if(charge_tick < recharge_time) return
			charge_tick = 0

			var/rechargeamt = power_supply.maxcharge*0.2

			if(use_external_power)
				var/obj/item/cell/external = get_external_power_supply()
				if(!external || !external.use(rechargeamt)) //Take power from the borg...
					return

			if(use_organic_power)
				var/mob/living/carbon/human/H
				if(ishuman(loc))
					H = loc

				if(istype(loc, /obj/item/organ))
					var/obj/item/organ/O = loc
					if(O.owner)
						H = O.owner

				if(istype(H))
					var/start_nutrition = H.nutrition
					var/end_nutrition = 0

					H.adjust_nutrition(-rechargeamt / 15)

					end_nutrition = H.nutrition

					var/deficit = (rechargeamt / 15) - (start_nutrition - max(0, end_nutrition))
					if(deficit > 0)
						// The shortfall is drawn from the host. Biology decides the cost:
						// the power fault only lands on synthetic parts, and bloodless
						// bodies lose no blood.
						H.injure(INJURY_ELECTRIC, deficit, BP_TORSO, src, affliction = /datum/affliction/synthetic/power_fault, flags = INJURE_SILENT)
						H.remove_blood(deficit)

			power_supply.give(rechargeamt) //... to recharge 1/5th the battery
			var/mob/living/M = loc // TGMC Ammo HUD
			if(istype(M)) // TGMC Ammo HUD
				M.hud_used?.update_ammo_hud(M, src) // TGMC Ammo HUD
		else
			charge_tick = 0

/obj/item/gun/energy/consume_next_projectile()
	if(!power_supply) return null
	if(!ispath(projectile_type)) return null
	var/output_envelope = power_supply.material_output_envelope(charge_cost)
	var/enhanced_cost = charge_cost * output_envelope
	if(!power_supply.checked_use(enhanced_cost)) return null
	power_supply.material_record_enhanced_output(charge_cost, output_envelope)
	// Charge was drawn: wake the recharge.
	set_recharge_due(TRUE)
	var/mob/living/M = loc // TGMC Ammo HUD
	if(istype(M)) // TGMC Ammo HUD
		M?.hud_used?.update_ammo_hud(M, src)
	var/obj/item/projectile/projectile = new projectile_type(src)
	if(output_envelope > 1)
		projectile.damage *= output_envelope
		projectile.armor_penetration += round((output_envelope - 1) * 20)
		projectile.color = "#88ddff"
	return projectile

/obj/item/gun/energy/proc/cell_inserted(mob/user, obj/item/cell/P)
	if(power_supply)
		return
	user.remove_from_mob(P)
	rel_set(src, nameof(power_supply), P)
	P.forceMove(src)
	act_message(user, src, MSG_SELF(span_notice("You insert [P] into %T%.")), MSG_OTHERS("%U% inserts [P] into %T%."))
	play_sfx(src, SFX_WEAPONS_FLIPBLADE)
	user.hud_used?.update_ammo_hud(user, src) // TGMC Ammo HUD

/obj/item/gun/energy/proc/load_ammo(obj/item/C, mob/user)
	if(istype(C, /obj/item/cell))
		if(self_recharge || battery_lock)
			to_chat(user, span_notice("[src] does not have a battery port."))
			return
		if(istype(C, accept_cell_type))
			var/obj/item/cell/P = C
			if(power_supply)
				to_chat(user, span_notice("[src] already has a power cell."))
			else
				act_message(user, src, MSG_SELF(span_notice("You start to insert [P] into %T%.")), MSG_OTHERS("%U% is reloading %T%."))
				task_timed(user, reload_time * P.w_class, src, src, PROC_REF(cell_inserted), list(user, P))
		else
			to_chat(user, span_notice("This cell is not fitted for [src]."))
	return

/obj/item/gun/energy/proc/unload_ammo(mob/user)
	if(self_recharge || battery_lock)
		to_chat(user, span_notice("[src] does not have a battery port."))
		return
	if(power_supply)
		user.put_in_hands(power_supply)
		act_message(user, src, MSG_SELF(span_notice("You remove [power_supply] from %T%.")), MSG_OTHERS("%U% removes [power_supply] from %T%."))
		rel_clear(src, nameof(power_supply))
		play_sfx(src, SFX_WEAPONS_EMPTY)
		user.hud_used?.update_ammo_hud(user, src) // TGMC Ammo HUD
	else
		to_chat(user, span_notice("[src] does not have a power cell."))

/// Old attackby: the parent's first, then loading.
/obj/item/gun/energy/gun_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	. = ..()
	load_ammo(held, user)

// power_supply names the cell in the gun's contents (the contents own it and it goes with the gun), or, for
// the shield generator's gun, the generator's cell: a relation view across the hierarchy.
CAPABILITIES(/obj/item/gun/energy)
	ref_one(nameof(power_supply))
	every(2 SECONDS, then(PROC_REF(energy_gun_recharge_step)), when = cond_all(nameof(self_recharge), nameof(recharge_due)))
	op("interaction_hand", hand(), then(PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/item/gun/energy/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.get_inactive_hand() == src)
		unload_ammo(user)
	else
		return OP_DECLINE
	return TRUE

/obj/item/gun/energy/proc/get_external_power_supply()
	if(isrobot(src.loc))
		var/mob/living/silicon/robot/R = src.loc
		return R.cell
	if(istype(src.loc, /obj/item/rig_module))
		var/obj/item/rig_module/module = src.loc
		if(module.holder && module.holder.wearer())
			var/mob/living/carbon/human/H = module.holder.wearer()
			if(istype(H) && H.get_rig())
				var/obj/item/rig/suit = H.get_rig()
				if(istype(suit))
					return suit.cell
	return null

/obj/item/gun/energy/examine(mob/user)
	. = ..()
	if(shot_counter)
		if(power_supply)
			if(charge_cost)
				var/shots_remaining = round(power_supply.charge / max(1, charge_cost))	// Paranoia
				. += "Has [shots_remaining] shot\s remaining."
			else
				. += "Has infinite shots remaining."
		else
			. += "Does not have a power cell."

/// The look: the charge meter state, over what the capabilities and the gun base drew.
/obj/item/gun/energy/draw(datum/look/look)
	..()
	draw_charge_state(look)

/// The base name of the gun's charge states ("laser" for laser100): the fire mode's state, else the icon's own.
/obj/item/gun/energy/proc/charge_state_name()
	return modifystate ? modifystate : initial(icon_state)

/// The charge meter state (a quarter step of the cell, at least a quarter while a shot is left), or the open state without a cell.
/// A gun that draws its charge as overlays instead overrides this.
/obj/item/gun/energy/proc/draw_charge_state(datum/look/look)
	var/base = charge_state_name()
	if(!power_supply)
		look.state("[base]_open")
	else if(charge_meter)
		var/ratio = power_supply.maxcharge > 0 ? power_supply.charge / power_supply.maxcharge : 0
		//make sure that rounding down will not give us the empty state even if we have charge for a shot left.
		if(power_supply.charge < charge_cost)
			ratio = 0
		else
			ratio = max(round(ratio, 0.25) * 100, 25)
		look.state("[base][ratio]")
	else
		look.state(base)

/obj/item/gun/energy/proc/start_recharge()
	if(power_supply == null)
		rel_set(src, nameof(power_supply), new /obj/item/cell/device/weapon(src))
	set_self_recharge(1)

/obj/item/gun/energy/get_description_interaction()
	var/list/results = list()

	if(!battery_lock && !self_recharge)
		if(power_supply)
			results += "[desc_panel_image("offhand")]to remove the weapon cell."
		else
			results += "[desc_panel_image("weapon cell")]to add a new weapon cell."

	results += ..()

	return results

// TGMC AMMO HUD
/obj/item/gun/energy/has_ammo_counter()
	return TRUE

/obj/item/gun/energy/get_ammo_type()
	if(!projectile_type)
		return list("unknown", "unknown")
	else
		var/obj/item/projectile/P = projectile_type
		return list(initial(P.hud_state), initial(P.hud_state_empty))

/obj/item/gun/energy/get_ammo_count()
	if(!power_supply)
		return 0
	else
		return FLOOR(power_supply.charge / max(charge_cost, 1), 1)


/obj/item/gun/energy/note_shot()
	..()
	COOLDOWN_START(src, recharge_cooldown, charge_delay)
