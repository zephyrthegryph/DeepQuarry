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

	//self-recharging
	var/self_recharge = 0	//if set, the weapon will recharge itself
	var/use_external_power = 0 //if set, the weapon will look for an external power source to draw from, otherwise it recharges magically
	var/use_organic_power = 0 // If set, the weapon will draw from nutrition or blood.
	/// Self-recharge: one step of 20% every recharge_time periods of ENERGY_RECHARGE_PERIOD, once
	/// charge_delay has passed since the last shot. Each step is a REACT_AT.
	var/recharge_time = 4
	/// Unused since S4 (steps are timers); kept for subtypes and var edits that set it.
	var/charge_tick = 0
	/// REACT_AT token of the next recharge step (null: none).
	var/tmp/recharge_timer
	var/charge_delay = 75	//delay between firing and charging
	var/shot_counter = TRUE // does this gun tell you how many shots it has?

	var/battery_lock = 0	//If set, weapon cannot switch batteries
	var/random_start_ammo = FALSE	//if TRUE, the weapon will spawn with randomly-determined ammo

/obj/item/gun/energy/Initialize(mapload)
	. = ..()
	if(self_recharge)
		power_supply = new /obj/item/cell/device/weapon(src)
		schedule_recharge()
	else
		if(cell_type)
			power_supply = new cell_type(src)
		else
			power_supply = null
	//random starting power! gives us a random number of shots in the battery between 0 and the max possible
	if(random_start_ammo && cell_type)
		power_supply.charge = charge_cost*rand(0,power_supply.maxcharge/charge_cost)
	update_icon()

/obj/item/gun/energy/Destroy()
	recharge_timer = null // REACT_CLEAR in the base Destroy() drops it
	if(power_supply?.loc == src && !QDELETED(power_supply))
		qdel(power_supply)
	power_supply = null
	return ..()

/obj/item/gun/energy/get_cell()
	return power_supply

/// A recharge step used to take recharge_time SSobj fires (2 s each).
#define ENERGY_RECHARGE_PERIOD (2 SECONDS)

/// Arms the next recharge step: recharge_time periods after the later of now and the end of
/// charge_delay after the last shot. Nothing while full or not self-recharging.
/obj/item/gun/energy/proc/schedule_recharge()
	if(!self_recharge || !power_supply || power_supply.charge >= power_supply.maxcharge || QDELETED(src))
		recharge_timer = REACT_REARM(src, recharge_timer, null)
		return
	var/start = max(world.time, last_shot + charge_delay)
	recharge_timer = REACT_REARM(src, recharge_timer, start + recharge_time * ENERGY_RECHARGE_PERIOD)

/obj/item/gun/energy/on_react(reason, source, source_kind)
	. = ..()
	if(!(reason & REACT_REASON_TIMER) || source != recharge_timer)
		return
	recharge_timer = null
	if(!self_recharge || !power_supply || power_supply.charge >= power_supply.maxcharge)
		return
	if(world.time < last_shot + charge_delay) // fired since the step was armed
		schedule_recharge()
		return
	recharge_step()
	schedule_recharge()

/obj/item/gun/energy/react_sleep_violation()
	if(self_recharge && power_supply && power_supply.charge < power_supply.maxcharge && isnull(recharge_timer))
		return "self-recharging gun below full with no recharge timer"
	return null

/// One recharge step: 20% of the cell, paid from external power or the wielder's body if set.
/obj/item/gun/energy/proc/recharge_step()
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
	update_icon()
	var/mob/living/M = loc // TGMC Ammo HUD
	if(istype(M)) // TGMC Ammo HUD
		M.hud_used?.update_ammo_hud(M, src) // TGMC Ammo HUD

/obj/item/gun/energy/switch_firemodes(mob/user)
	if(..())
		update_icon()

/obj/item/gun/energy/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	update_icon()

/obj/item/gun/energy/consume_next_projectile()
	if(!power_supply) return null
	if(!ispath(projectile_type)) return null
	var/output_envelope = power_supply.material_output_envelope(charge_cost)
	var/enhanced_cost = charge_cost * output_envelope
	if(!power_supply.checked_use(enhanced_cost)) return null
	power_supply.material_record_enhanced_output(charge_cost, output_envelope)
	if(self_recharge)
		schedule_recharge() // last_shot is set after this returns; the step re-checks it
	var/mob/living/M = loc // TGMC Ammo HUD
	if(istype(M)) // TGMC Ammo HUD
		M?.hud_used.update_ammo_hud(M, src)
	var/obj/item/projectile/projectile = new projectile_type(src)
	if(output_envelope > 1)
		projectile.damage *= output_envelope
		projectile.armor_penetration += round((output_envelope - 1) * 20)
		projectile.color = "#88ddff"
	return projectile

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
				user.visible_message("[user] is reloading [src].", span_notice("You start to insert [P] into [src]."))
				if(do_after(user, reload_time * P.w_class, target = src))
					user.remove_from_mob(P)
					power_supply = P
					P.loc = src
					user.visible_message("[user] inserts [P] into [src].", span_notice("You insert [P] into [src]."))
					playsound(src, 'sound/weapons/flipblade.ogg', 50, 1)
					update_icon()
					update_held_icon()
					user.hud_used?.update_ammo_hud(user, src) // TGMC Ammo HUD
		else
			to_chat(user, span_notice("This cell is not fitted for [src]."))
	return

/obj/item/gun/energy/proc/unload_ammo(mob/user)
	if(self_recharge || battery_lock)
		to_chat(user, span_notice("[src] does not have a battery port."))
		return
	if(power_supply)
		user.put_in_hands(power_supply)
		power_supply.update_icon()
		user.visible_message("[user] removes [power_supply] from [src].", span_notice("You remove [power_supply] from [src]."))
		power_supply = null
		playsound(src, 'sound/weapons/empty.ogg', 50, 1)
		update_icon()
		update_held_icon()
		user.hud_used.update_ammo_hud(user, src) // TGMC Ammo HUD
	else
		to_chat(user, span_notice("[src] does not have a power cell."))

/obj/item/gun/energy/attackby(obj/item/A as obj, mob/user as mob)
	..()
	load_ammo(A, user)

/obj/item/gun/energy/attack_hand(mob/user as mob)
	if(user.get_inactive_hand() == src)
		unload_ammo(user)
	else
		return ..()

/obj/item/gun/energy/proc/get_external_power_supply()
	if(isrobot(src.loc))
		var/mob/living/silicon/robot/R = src.loc
		return R.cell
	if(istype(src.loc, /obj/item/rig_module))
		var/obj/item/rig_module/module = src.loc
		if(module.holder && module.holder.wearer)
			var/mob/living/carbon/human/H = module.holder.wearer
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

/obj/item/gun/energy/update_icon(ignore_inhands)
	if(power_supply == null)
		if(modifystate)
			icon_state = "[modifystate]_open"
		else
			icon_state = "[initial(icon_state)]_open"
		return
	else if(charge_meter)
		var/ratio = power_supply.charge / power_supply.maxcharge

		//make sure that rounding down will not give us the empty state even if we have charge for a shot left.
		if(power_supply.charge < charge_cost)
			ratio = 0
		else
			ratio = max(round(ratio, 0.25) * 100, 25)

		if(modifystate)
			icon_state = "[modifystate][ratio]"
		else
			icon_state = "[initial(icon_state)][ratio]"

	else if(power_supply)
		if(modifystate)
			icon_state = "[modifystate]"
		else
			icon_state = "[initial(icon_state)]"

	if(!ignore_inhands) update_held_icon()

/obj/item/gun/energy/proc/start_recharge()
	if(power_supply == null)
		power_supply = new /obj/item/cell/device/weapon(src)
	self_recharge = 1
	schedule_recharge()
	update_icon()

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
