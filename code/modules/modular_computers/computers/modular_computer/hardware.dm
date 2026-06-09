// Hardware slot management — data-driven via get_slot_var() virtual dispatch.
//
// To add a new hardware type without editing this file:
//   1. Declare the typed var on /obj/item/modular_computer (variables.dm).
//   2. Override get_slot_var() on the new /obj/item/computer_hardware subtype
//      to return that var's name as a string.
//   3. Override is_critical_slot() on the new type to return TRUE if hot-removing
//      it while the computer is running should trigger a shutdown.
//
// No branches in this file ever need changing for new hardware types.

// Installs hardware into the appropriate named slot, determined by the hardware's
// get_slot_var() proc. Rejects installation when the slot is already occupied.
/obj/item/modular_computer/proc/try_install_component(mob/living/user, obj/item/computer_hardware/H, found = 0)
	var/slot = H.get_slot_var()
	if(!slot)
		return // Hardware type has no registered slot; cannot be installed.

	var/existing = vars[slot]
	if(existing)
		to_chat(user, "This computer's [H.name] slot is already occupied by \the [existing].")
		return

	vars[slot] = H
	found = 1

	if(found)
		to_chat(user, "You install \the [H] into \the [src]")
		H.holder2 = src
		user.drop_from_inventory(H)
		H.forceMove(src)
		update_verbs()

// Installs hardware during preset construction (no user interaction).
// Used by install_default_hardware() overrides and the laptop vendor.
// Sets holder2 without dropping from inventory or moving the item; callers
// must ensure the hardware is already inside src (e.g. new/path(src)).
/obj/item/modular_computer/proc/install_hardware(obj/item/computer_hardware/H)
	if(!H)
		return
	var/slot = H.get_slot_var()
	if(!slot)
		return
	vars[slot] = H
	H.holder2 = src

// Uninstalls a component. Found and Critical vars may be passed by parent types
// when they carry additional hardware slots beyond the base set.
/obj/item/modular_computer/proc/uninstall_component(mob/living/user, obj/item/computer_hardware/H, found = 0, critical = 0)
	var/slot = H.get_slot_var()
	if(slot && (vars[slot] == H))
		vars[slot] = null
		found = 1
		// Processor and hard drive removal shuts down the computer.
		// is_critical_slot() lets new hardware types declare themselves critical
		// without requiring a branch here.
		if(H.is_critical_slot())
			critical = 1

	if(found)
		if(user)
			to_chat(user, "You remove \the [H] from \the [src].")
		H.forceMove(get_turf(src))
		H.holder2 = null
		update_verbs()
	if(critical && enabled)
		if(user)
			to_chat(user, span_danger("\The [src]'s screen freezes for few seconds and then displays an \"HARDWARE ERROR: Critical component disconnected. Please verify component connection and reboot the device. If the problem persists contact technical support for assistance.\" warning."))
		shutdown_computer()
		update_icon()


// Checks all installed hardware pieces for a name match and returns the first hit.
/obj/item/modular_computer/proc/find_hardware_by_name(name)
	for(var/obj/item/computer_hardware/H in get_all_components())
		if(H.name == name)
			return H
	return null

// Returns a list of all currently installed hardware components.
// This is the single authoritative enumeration used for iteration throughout
// core.dm, damage.dm, power.dm and interaction.dm.
/obj/item/modular_computer/proc/get_all_components()
	var/list/all_components = list()
	// Iterate every item currently inside src; only typed computer_hardware counts.
	// This naturally picks up any hardware slot, including future additions,
	// without requiring an explicit list here.
	for(var/obj/item/computer_hardware/H in src)
		all_components.Add(H)
	return all_components
