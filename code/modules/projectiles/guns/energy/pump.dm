// For general use
/obj/item/gun/energy/imperial
	name = "imperial energy pistol"
	desc = "An elegant weapon developed by the Imperium Auream. Their weaponsmiths have cleverly found a way to make a gun that is only about the size of an average energy pistol, yet with the fire power of a laser carbine."
	icon_state = "ge_pistol"
	item_state = "ge_pistol"
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_NORMAL
	force = 10
	MATERIAL_BULK(MAT_STEEL, 2000)
	fire_sound = SFX_WEAPONS_MANDALORIAN
	projectile_type = /obj/item/projectile/beam/imperial

// Removed because gun64_vr.dmi guns don't work.

//////////////////// Energy Weapons ////////////////////

// ------------ Energy Luger ------------
//MOVED TO nuclear.dm

//////////////////// Eris Ported Guns ////////////////////
//HoP gun
/obj/item/gun/energy/gun/martin
	name = "holdout energy gun"
	desc = "The FS PDW E \"Martin\" is small holdout e-gun. Don't miss!"
	icon_state = "pdw"
	item_state = "gun"
	w_class = ITEMSIZE_SMALL
	projectile_type = /obj/item/projectile/beam/stun
	charge_cost = 1200
	charge_meter = 0
	modifystate = null
	battery_lock = 1
	fire_sound = SFX_WEAPONS_TASER
	firemodes = list(
		list(mode_name="stun", projectile_type=/obj/item/projectile/beam/stun, fire_sound=SFX_WEAPONS_TASER, charge_cost = 600),
		list(mode_name="lethal", projectile_type=/obj/item/projectile/beam, fire_sound=SFX_WEAPONS_LASER, charge_cost = 1200),
		)

/obj/item/gun/energy/gun/martin/proc/update_mode()
	var/datum/firemode/current_mode = LAZYACCESS(firemodes, sel_mode)
	switch(current_mode.name)
		if("lethal") add_overlay("lazer_pdw")
		if("stun") add_overlay("taser_pdw")

DECLARE_APPEARANCE_PROC(/obj/item/gun/energy/gun/martin, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/gun/energy/gun/martin/appearance_overlays()
	. = list()
	update_mode()

//Gun Locking Mechanism
/obj/item/gun/energy/locked
	req_access = list(ACCESS_ARMORY) //for toggling safety
	var/locked = 1
	var/lockable = 1

/// Old attackby.
/obj/item/gun/energy/locked/gun_item(mob/user, obj/item/I, datum/interaction/interaction)
	var/obj/item/card/id/id = I.GetID()
	if(istype(id) && lockable)
		if(check_access(id))
			locked = !locked
			to_chat(user, span_warning("You [locked ? "enable" : "disable"] the safety lock on \the [src]."))
		else
			to_chat(user, span_warning("Access denied."))
		act_message(user, src, others = span_notice("%U% swipes %I% against %T%."), item = I)
		return INTERACTION_HANDLED_PASS
	return ..()

/obj/item/gun/energy/locked/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	..()
	if(lockable)
		locked = !locked
		to_chat(user, span_warning("You [locked ? "enable" : "disable"] the safety lock on \the [src]!"))

/obj/item/gun/energy/locked/special_check(mob/user)
	if(locked)
		var/turf/T = get_turf(src)
		if(T.z in using_map.station_levels)
			to_chat(user, span_warning("The safety device prevents the gun from firing this close to the facility."))
			return 0
	return ..()

////////////////Expedition Frontier Phaser////////////////

/obj/item/gun/energy/locked/frontier
	resistance_flags = BOMB_PROOF
	/// Rugged: a pulse reaches the internal cells two steps weaker (energy_gun_emp_refresh()).
	emp_protection_flags = EMP_PROTECT_CONTENTS
	name = "frontier phaser"
	desc = "An extraordinarily rugged laser weapon, built to last and requiring effectively no maintenance. Includes a built-in crank charger for recharging away from civilization. This one has a safety interlock that prevents firing while in proximity to the facility."
	description_fluff = "The NT Brand Model E2 Secured Phaser System, a specialty phaser that has an intergrated chip that prevents the user from opperating the weapon within the vicinity of any NanoTrasen opperated outposts/stations/bases. However, this chip can be disabled so the weapon CAN BE used in the vicinity of any NanoTrasen opperated outposts/stations/bases. The weapon doesn't use traditional weapon power cells and instead works via a pump action that recharges the internal cells. It is a staple amongst exploration personell who usually don't have the license to opperate a lethal weapon through NT and provides them with a weapon that can be recharged away from civilization."
	icon_state = "phaserkill"
	item_state = "phaser"
	item_icons = list(slot_l_hand_str = 'icons/mob/items/lefthand_guns_vr.dmi', slot_r_hand_str = 'icons/mob/items/righthand_guns_vr.dmi', "slot_belt" = 'icons/inventory/belt/mob.dmi')
	fire_sound = SFX_WEAPONS_LASER2
	charge_cost = 100 // Reduced cost

	battery_lock = 1
	unacidable = TRUE

	var/recharging = 0
	var/phase_power = 15

	projectile_type = /obj/item/projectile/beam/phaser
	//Changed beam type to new phaser beam type.
	firemodes = list(
		list(mode_name="lethal", fire_delay=10, projectile_type=/obj/item/projectile/beam/phaser, charge_cost = 80), // Reduced cost
		list(mode_name="low-power", fire_delay=5, projectile_type=/obj/item/projectile/beam/phaser/light, charge_cost = 40), // Reduced cost
	) // Adjusts cost and fire delay to match adjusted beams.
	recoil_mode = 0

/obj/item/gun/energy/locked/frontier/unload_ammo(mob/user)
	if(recharging)
		return
	recharging = 1
	update_icon()
	act_message(user, src, MSG_SELF(span_notice("You open %T% and start pumping the handle.")), \
		MSG_OTHERS(span_notice("%U% opens %T% and starts pumping the handle.")))
	task_timed(user, 1 SECOND, src, src, PROC_REF(pump_cycle), list(user), on_fail = PROC_REF(pump_end), fail_args = list(user))

/// One pump every second (a timed action each) until full.
/obj/item/gun/energy/locked/frontier/proc/pump_cycle(mob/user)
	play_sfx(src, SFX_ITEMS_CHANGE_DRILL)
	user.hud_used?.update_ammo_hud(user, src)
	if(power_supply.give(phase_power) < phase_power)
		pump_end(user)
		return
	task_timed(user, 1 SECOND, src, src, PROC_REF(pump_cycle), list(user), on_fail = PROC_REF(pump_end), fail_args = list(user))

/obj/item/gun/energy/locked/frontier/proc/pump_end(mob/user)
	recharging = 0
	update_icon()
	user?.hud_used?.update_ammo_hud(user, src) // Update one last time once we're finished!

DECLARE_APPEARANCE_PROC(/obj/item/gun/energy/locked/frontier, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/gun/energy/locked/frontier/appearance_overlays()
	. = list()
	if(recharging)
		icon_state = "[initial(icon_state)]_pump"
		update_held_icon()
		return .
	. += ..()

/// Rugged: the pulse reaches the internal cells two steps weaker.
/obj/item/gun/energy/locked/frontier/energy_gun_emp_refresh(datum/damage_packet/packet)
	for(var/atom/A as anything in contents)
		A.emp_act(packet.severity + 2)
	..()

/obj/item/gun/energy/locked/frontier/unlocked
	desc = "An extraordinarily rugged laser weapon, built to last and requiring effectively no maintenance. Includes a built-in crank charger for recharging away from civilization."
	req_access = newlist() //for toggling safety
	locked = 0
	lockable = 0

////////////////Phaser Carbine////////////////

/obj/item/gun/energy/locked/frontier/carbine
	name = "frontier carbine"
	desc = "A larger and more efficient version of the venerable frontier phaser, the carbine is a fairly new weapon, and has only been produced in limited numbers so far.  Includes a built-in crank charger for recharging away from civilization. This one has a safety interlock that prevents firing while in proximity to the facility."
	description_fluff = "The NT Brand Model AT2 Secured Phaser System, a specialty phaser that has an intergrated chip that prevents the user from opperating the weapon within the vicinity of any NanoTrasen opperated outposts/stations/bases. However, this chip can be disabled so the weapon CAN BE used in the vicinity of any NanoTrasen opperated outposts/stations/bases. The weapon doesn't use traditional weapon power cells and instead works via a pump action that recharges the internal cells. It is a staple amongst exploration personell who usually don't have the license to opperate a lethal weapon through NT and provides them with a weapon that can be recharged away from civilization."
	icon_state = "carbinekill"
	item_state = "energykill"
	item_icons = list(slot_l_hand_str = 'icons/mob/items/lefthand_guns.dmi', slot_r_hand_str = 'icons/mob/items/righthand_guns.dmi')
	phase_power = 25
	one_handed_penalty = 15 // Added this, same as phase carbine.
	w_class = ITEMSIZE_LARGE // Should be bigger.

	modifystate = "carbinekill"
	//Changed beam type to new phaser beam type.
	firemodes = list(
		list(mode_name="lethal", fire_delay=10, projectile_type=/obj/item/projectile/beam/phaser, modifystate="carbinekill", charge_cost = 60), // Reduced cost
		list(mode_name="low-power", fire_delay=5, projectile_type=/obj/item/projectile/beam/phaser/light, modifystate="carbinestun", charge_cost = 30), // Reduced cost
		list(mode_name="burst", burst=3, fire_delay=10, move_delay=4, burst_accuracy=list(0,0,0), dispersion=list(0.0, 0.2, 0.5), projectile_type=/obj/item/projectile/beam/phaser/light, charge_cost = 90), // Added this
	)

DECLARE_APPEARANCE_PROC(/obj/item/gun/energy/locked/frontier/carbine, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/gun/energy/locked/frontier/carbine/appearance_overlays()
	. = list()
	if(recharging)
		icon_state = "[modifystate]_pump"
		update_held_icon()
		return .
	. += ..()

/obj/item/gun/energy/locked/frontier/carbine/unlocked
	desc = "An ergonomically improved version of the venerable frontier phaser, the carbine is a fairly new weapon, and has only been produced in limited numbers so far. Includes a built-in crank charger for recharging away from civilization."
	req_access = newlist() //for toggling safety
	locked = 0
	lockable = 0

////////////////Expeditionary Holdout Phaser Pistol////////////////

/obj/item/gun/energy/locked/frontier/holdout
	name = "holdout frontier phaser"
	desc = "An minaturized weapon designed for the purpose of expeditionary support to defend themselves on the field. Includes a built-in crank charger for recharging away from civilization. This one has a safety interlock that prevents firing while in proximity to the facility."
	icon_state = "holdoutkill"
	item_state = null
	phase_power = 15

	w_class = ITEMSIZE_SMALL
	charge_cost = 200 // Reduced cost
	modifystate = "holdoutkill"
	//Changed beam type to new phaser beam type.
	firemodes = list(
		list(mode_name="lethal", fire_delay=20, projectile_type=/obj/item/projectile/beam/phaser, modifystate="holdoutkill", charge_cost = 200), // Reduced cost
		list(mode_name="low-power", fire_delay=10, projectile_type=/obj/item/projectile/beam/phaser/light, modifystate="holdoutstun", charge_cost = 50), // Reduced cost
		list(mode_name="stun", fire_delay=12, projectile_type=/obj/item/projectile/beam/stun/med, modifystate="holdoutshock", charge_cost = 300),
	)

/obj/item/gun/energy/locked/frontier/holdout/unlocked
	desc = "An minaturized weapon designed for the purpose of expeditionary support to defend themselves on the field. Includes a built-in crank charger for recharging away from civilization."
	req_access = newlist() //for toggling safety
	locked = 0
	lockable = 0

////////////////Phaser Rifle////////////////

/obj/item/gun/energy/locked/frontier/rifle
	name = "frontier marksman rifle"
	desc = "A much larger, heavier weapon than the typical frontier-type weapons, this DMR can be fired both from the hip, and in scope. Includes a built-in crank charger for recharging away from civilization. This one has a safety interlock that prevents firing while in proximity to the facility."
	icon_state = "riflekill"
	item_state = "sniper"
	item_state_slots = list(slot_r_hand_str = "lsniper", slot_l_hand_str = "lsniper")
	wielded_item_state = "lsniper-wielded"
	actions_types = list(/datum/action/item_action/use_scope)
	w_class = ITEMSIZE_LARGE
	item_icons = list(slot_l_hand_str = 'icons/mob/items/lefthand_guns.dmi', slot_r_hand_str = 'icons/mob/items/righthand_guns.dmi')
	accuracy = -15 //better than most snipers but still has penalty
	scoped_accuracy = 40
	one_handed_penalty = 50 // The weapon itself is heavy, and the long barrel makes it hard to hold steady with just one hand.
	phase_power = 30 // efficient crank charger
	projectile_type = /obj/item/projectile/beam/phaser/heavy
	modifystate = "riflekill"
	//Changed beam type to new phaser beam type.
	firemodes = list(
		list(mode_name="lethal", fire_delay=12, projectile_type=/obj/item/projectile/beam/phaser, modifystate="riflestun", charge_cost = 60), // Reduced cost
		list(mode_name="sniper", fire_delay=35, move_delay=4, projectile_type=/obj/item/projectile/beam/phaser/heavy, modifystate="riflekill", charge_cost = 100), // Reduced cost
	)

/obj/item/gun/energy/locked/frontier/rifle/ui_action_click(mob/user, actiontype)
	perform_scope_interaction(user, PROC_REF(frontier_rifle_verb_scope))

EXTEND_INTERACTIONS(/obj/item/gun/energy/locked/frontier/rifle, INTERACT_VERB("Use Scope", PROC_REF(frontier_rifle_verb_scope), REQ_IN_INVENTORY, REQ_ON(PRED_TARGET, /obj/item/proc/zoom_view_allowed, "You are too distracted to do that.")))

/// Old Use Scope verb.
/obj/item/gun/energy/locked/frontier/rifle/proc/frontier_rifle_verb_scope(mob/user, obj/item/held, datum/interaction/interaction)
	toggle_scope(2.0, user)

DECLARE_APPEARANCE_PROC(/obj/item/gun/energy/locked/frontier/rifle, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/gun/energy/locked/frontier/rifle/appearance_overlays()
	. = list()
	if(recharging)
		icon_state = "[modifystate]_pump"
		update_held_icon()
		return .
	. += ..()

/obj/item/gun/energy/locked/frontier/rifle/unlocked
	desc = "A much larger, heavier weapon than the typical frontier-type weapons, this DMR can be fired both from the hip, and in scope. Includes a built-in crank charger for recharging away from civilization."
	req_access = newlist() //for toggling safety
	locked = 0
	lockable = 0

///phaser bow///

/obj/item/gun/energy/locked/frontier/handbow
	name = "phaser handbow"
	desc = "An minaturized weapon that fires a bolt of energy. Includes a built-in crank charger for recharging away from civilization. This one has a safety interlock that prevents firing while in proximity to the facility."
	icon_state = "handbowkill"
	item_state = null
	phase_power = 20

	w_class = ITEMSIZE_SMALL
	charge_cost = 200 // Reduced cost
	modifystate = "handbowkill"
	firemodes = list(
		list(mode_name="lethal", fire_delay=12, projectile_type=/obj/item/projectile/energy/phase/bolt/heavy, modifystate="handbowkill", charge_cost = 200),
		list(mode_name="low-power", fire_delay=8, projectile_type=/obj/item/projectile/energy/phase/bolt, modifystate="handbowstun", charge_cost = 100),
	)

/obj/item/gun/energy/locked/frontier/handbow/unlocked
	desc = "An minaturized weapon that fires a bolt of engery. Includes a built-in crank charger for recharging away from civilization."
	req_access = newlist() //for toggling safety
	locked = 0
	lockable = 0
