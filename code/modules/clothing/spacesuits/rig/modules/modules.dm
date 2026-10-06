/*
 * Rigsuit upgrades/abilities.
 */

/datum/rig_charge
	var/short_name = "undef"
	var/display_name = "undefined"
	var/product_type = "undefined"
	var/charges = 0

MATERIAL_MIX(/obj/item/rig_module, list(MAT_STEEL = 20000, MAT_PLASTIC = 30000, MAT_GLASS = 5000))
/obj/item/rig_module
	name = "hardsuit upgrade"
	desc = "It looks pretty sciency."
	icon = 'icons/obj/rig_modules.dmi'
	icon_state = "module"

	var/damage = 0
	var/obj/item/rig/holder

	var/module_cooldown = 10
	var/next_use = 0

	var/toggleable                      // Set to 1 for the device to show up as an active effect.
	var/usable                          // Set to 1 for the device to have an on-use effect.
	var/selectable                      // Set to 1 to be able to assign the device as primary system.
	var/redundant                       // Set to 1 to ignore duplicate module checking when installing.
	var/permanent                       // If set, the module can't be removed.
	var/disruptive = 1                  // Can disrupt by other effects.
	var/activates_on_touch              // If set, unarmed attacks will call engage() on the target.

	var/active                          // Basic module status
	var/disruptable                     // Will deactivate if some other powers are used.

	var/use_power_cost = 0              // Power used when single-use ability called.
	var/active_power_cost = 0           // Power used when turned on.
	var/passive_power_cost = 0          // Power used when turned off.

	var/list/charges                    // Associative list of charge types and remaining numbers.
	var/charge_selected                 // Currently selected option used for charge dispensing.

	// Icons.
	var/suit_overlay
	var/suit_overlay_icon = 'icons/mob/rig_modules.dmi'
	var/suit_overlay_active             // If set, drawn over icon and mob when effect is active.
	var/suit_overlay_inactive           // As above, inactive.

	//Display fluff
	var/interface_name = "hardsuit upgrade"
	var/interface_desc = "A generic hardsuit upgrade."
	var/engage_string = "Engage"
	var/activate_string = "Activate"
	var/deactivate_string = "Deactivate"

	var/list/stat_modules

CAPABILITIES(/obj/item/rig_module)
	owns_many(nameof(stat_modules))

/obj/item/rig_module/examine()
	. = ..()
	switch(damage)
		if(0)
			. += "It is undamaged."
		if(1)
			. += "It is badly damaged."
		if(2)
			. += "It is almost completely destroyed."

DECLARE_INTERACTIONS(/obj/item/rig_module, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/rig_module/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)

	if(istype(W,/obj/item/stack/nanopaste))

		if(damage == 0)
			to_chat(user, "There is no damage to mend.")
			return INTERACTION_HANDLED_PASS

		to_chat(user, "You start mending the damaged portions of \the [src]...")
		om_task_timed(user, 3 SECONDS, src, src, PROC_REF(mend_with_paste), list(user, W))
		return INTERACTION_HANDLED_PASS

	else if(istype(W,/obj/item/stack/cable_coil))

		switch(damage)
			if(0)
				to_chat(user, "There is no damage to mend.")
				return INTERACTION_HANDLED_PASS
			if(2)
				to_chat(user, "There is no damage that you are capable of mending with such crude tools.")
				return INTERACTION_HANDLED_PASS

		var/obj/item/stack/cable_coil/cable = W
		if(cable.get_amount() < 5)
			to_chat(user, "You need five units of cable to repair \the [src].")
			return INTERACTION_HANDLED_PASS

		to_chat(user, "You start mending the damaged portions of \the [src]...")
		om_task_timed(user, 3 SECONDS, src, src, PROC_REF(mend_with_cable), list(user, cable))
		return INTERACTION_HANDLED_PASS
	return FALSE

/obj/item/rig_module/proc/mend_with_paste(mob/user, obj/item/stack/nanopaste/paste)
	damage = 0
	to_chat(user, "You mend the damage to [src] with [paste].")
	paste.use(1)

/obj/item/rig_module/proc/mend_with_cable(mob/user, obj/item/stack/cable_coil/cable)
	if(damage != 1 && cable.use(5))
		damage = 1
		to_chat(user, "You mend some of damage to [src] with [cable], but you will need more advanced tools to fix it completely.")

/obj/item/rig_module/Initialize(mapload)
	. = ..()
	if(suit_overlay_inactive)
		suit_overlay = suit_overlay_inactive

	if(charges && charges.len)
		var/list/processed_charges = list()
		for(var/list/charge in charges)
			var/datum/rig_charge/charge_dat = new

			charge_dat.short_name   = charge[1]
			charge_dat.display_name = charge[2]
			charge_dat.product_type = charge[3]
			charge_dat.charges      = charge[4]

			if(!charge_selected) charge_selected = charge_dat.short_name
			processed_charges[charge_dat.short_name] = charge_dat

		charges = processed_charges

	rel_add(src, nameof(stat_modules), new/atom/movable/stat_rig_module/activate(src))
	rel_add(src, nameof(stat_modules), new/atom/movable/stat_rig_module/deactivate(src))
	rel_add(src, nameof(stat_modules), new/atom/movable/stat_rig_module/engage(src))
	rel_add(src, nameof(stat_modules), new/atom/movable/stat_rig_module/select(src))
	rel_add(src, nameof(stat_modules), new/atom/movable/stat_rig_module/charge(src))


// Called when the module is installed into a suit.
/obj/item/rig_module/proc/installed(obj/item/rig/new_holder)
	rel_set(src, nameof(holder), new_holder)
	return

//Proc for one-use abilities like teleport.
/obj/item/rig_module/proc/engage(atom/target, notify_ai, mob/user)

	if(!user)
		return 0

	if(damage >= 2)
		to_chat(user, span_warning("The [interface_name] is damaged beyond use!"))
		return 0

	if(!COOLDOWN_FINISHED(src, next_use))
		to_chat(user, span_warning("You cannot use the [interface_name] again so soon."))
		return 0

	if(!holder || holder.canremove)
		to_chat(user, span_warning("The suit is not initialized."))
		return 0

	if(user.lying || user.stat || user.has_status(EFFECT_STUNNED) || user.has_status(EFFECT_PARALYZED) || user.has_status(EFFECT_WEAKENED))
		to_chat(user, span_warning("You cannot use the suit in this state."))
		return 0

	if(holder.wearer() && holder.wearer().lying)
		to_chat(user, span_warning("The suit cannot function while the wearer is prone."))
		return 0

	if(holder.security_check_enabled && !holder.check_suit_access(user))
		to_chat(user, span_danger("Access denied."))
		return 0

	if(!holder.check_power_cost(user, use_power_cost, 0, src, (istype(user,/mob/living/silicon) ? 1 : 0) ) )
		return 0

	COOLDOWN_START(src, next_use, module_cooldown)

	return 1

// Proc for toggling on active abilities.
/obj/item/rig_module/proc/activate(skip_engage = 0, mob/user) // Allow us to skip the engage call.
	// Allow us to skip the engage call
	if(active)
		return 0
	if(!skip_engage && !engage(null, FALSE, user))
		return 0
	active = 1

	after(src, 0.1 SECONDS, PROC_REF(refresh_suit_overlay))

	return 1

// Proc for toggling off active abilities.
/obj/item/rig_module/proc/deactivate(forced = FALSE, mob/user)

	if(!active)
		return 0

	active = 0

	after(src, 0.1 SECONDS, PROC_REF(refresh_suit_overlay))

	return 1

// Called when the module is uninstalled from a suit.
/obj/item/rig_module/proc/removed()
	deactivate()
	rel_clear(src, nameof(holder))
	return

// Called by the hardsuit each rig process tick.
/obj/item/rig_module/periodic_step()
	if(active)
		return active_power_cost
	else
		return passive_power_cost

// Called by holder rigsuit attackby()
// Checks if an item is usable with this module and handles it if it is
/obj/item/rig_module/proc/accepts_item(obj/item/input_device)
	return 0

/atom/movable/stat_rig_module
	var/module_mode = ""
	var/obj/item/rig_module/module

// ALLOW(init/INSTANCE_STATE): binds to the rig module it is made inside
/atom/movable/stat_rig_module/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(module), loc)
	if(!istype(module))
		return INITIALIZE_HINT_QDEL

/atom/movable/stat_rig_module/proc/AddHref(list/href_list)
	return

/atom/movable/stat_rig_module/proc/CanUse()
	return 0

CAPABILITIES(/atom/movable/stat_rig_module)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm): the stat-panel button runs
/// its module's mode for the clicking mob.
/atom/movable/stat_rig_module/proc/click_input(datum/act/input/A)
	var/mob/user = A.actor
	if(CanUse())
		switch(module_mode)
			if("select")
				rel_set(module.holder, nameof(/datum/tgui_module/robot_ui_module::selected_module), module)
			if("engage")
				module.engage(null, FALSE, user)
			if("activate")
				module.activate(FALSE, user)
			if("deactivate")
				module.deactivate(FALSE, user)
			if("toggle")
				if(module.active)
					module.deactivate(FALSE, user)
				else
					module.activate(FALSE, user)
			if("select_charge_type")
				var/charge_index = module.charges.Find(module.charge_selected)
				charge_index = charge_index == module.charges.len ? 1 : charge_index + 1
				module.charge_selected = module.charges[charge_index]
	return TRUE

/atom/movable/stat_rig_module/DblClick()
	return Click()

// ALLOW(init/INSTANCE_STATE): names itself from the module it is made inside
/atom/movable/stat_rig_module/activate/Initialize(mapload)
	. = ..()
	if(!istype(module))
		return INITIALIZE_HINT_QDEL
	name = module.activate_string
	if(module.active_power_cost)
		name += " ([module.active_power_cost*10]A)"
	module_mode = "activate"

/atom/movable/stat_rig_module/activate/CanUse()
	return module.toggleable && !module.active

// ALLOW(init/INSTANCE_STATE): names itself from the module it is made inside
/atom/movable/stat_rig_module/deactivate/Initialize(mapload)
	. = ..()
	if(!istype(module))
		return INITIALIZE_HINT_QDEL
	name = module.deactivate_string
	// Show cost despite being 0, if it means changing from an active cost.
	if(module.active_power_cost || module.passive_power_cost)
		name += " ([module.passive_power_cost*10]P)"

	module_mode = "deactivate"

/atom/movable/stat_rig_module/deactivate/CanUse()
	return module.toggleable && module.active

// ALLOW(init/INSTANCE_STATE): names itself from the module it is made inside
/atom/movable/stat_rig_module/engage/Initialize(mapload)
	. = ..()
	if(!istype(module))
		return INITIALIZE_HINT_QDEL
	name = module.engage_string
	if(module.use_power_cost)
		name += " ([module.use_power_cost*10]E)"
	module_mode = "engage"

/atom/movable/stat_rig_module/engage/CanUse()
	return module.usable

/atom/movable/stat_rig_module/select
	name = "Select"
	module_mode = "select"

/atom/movable/stat_rig_module/select/CanUse()
	if(module.selectable)
		name = module.holder.selected_module == module ? "Selected" : "Select"
		return 1
	return 0

/atom/movable/stat_rig_module/charge
	name = "Change Charge"
	module_mode = "select_charge_type"

/atom/movable/stat_rig_module/charge/AddHref(list/href_list)
	var/charge_index = module.charges.Find(module.charge_selected)
	if(!charge_index)
		charge_index = 0
	else
		charge_index = charge_index == module.charges.len ? 1 : charge_index+1

	href_list["charge_type"] = module.charges[charge_index]

/atom/movable/stat_rig_module/charge/CanUse()
	if(module.charges && module.charges.len)
		var/datum/rig_charge/charge = module.charges[module.charge_selected]
		name = "[charge.display_name] ([charge.charges]C) - Change"
		return 1
	return 0

/// The suit overlay follows the module's state, a tick after it changes.
/obj/item/rig_module/proc/refresh_suit_overlay()
	if(active)
		suit_overlay = suit_overlay_active
	else
		suit_overlay = suit_overlay_inactive
	holder?.update_icon()

