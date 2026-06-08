/obj/item/computer_hardware/
	name = "Hardware"
	desc = "Unknown Hardware."
	icon = 'icons/obj/modular_components.dmi'
	var/obj/item/modular_computer/holder2 = null

	/// If the hardware uses extra power, change this.
	var/power_usage = 0
	/// If the hardware is turned off set this to FALSE.
	var/enabled = TRUE
	/// Prevent disabling for important component, like the HDD.
	var/critical = 1
	/// Limits which devices can contain this component. 1: All, 2: Laptops/Consoles, 3: Consoles only
	var/hardware_size = 1
	/// Current damage level
	var/damage = 0
	/// Maximal damage level.
	var/max_damage = 100
	/// "Malfunction" threshold. When damage exceeds this value the hardware piece will semi-randomly fail and do !!FUN!! things
	var/damage_malfunction = 20
	/// "Failure" threshold. When damage exceeds this value the hardware piece will not work at all.
	var/damage_failure = 50
	/// Chance of malfunction when the component is damaged
	var/malfunction_probability = 10
	var/usage_flags = PROGRAM_ALL
	/// Whether attackby will be passed on it even with a closed panel
	var/external_slot

/obj/item/computer_hardware/attackby(obj/item/W as obj, mob/living/user as mob)
	// Multitool. Runs diagnostics
	if(istype(W, /obj/item/multitool))
		to_chat(user, "***** DIAGNOSTICS REPORT *****")
		diagnostics(user)
		to_chat(user, "******************************")
		return TRUE
	// Nanopaste. Repair all damage if present for a single unit.
	var/obj/item/stack/S = W
	if(istype(S, /obj/item/stack/nanopaste))
		if(!damage)
			to_chat(user, "\The [src] doesn't seem to require repairs.")
			return TRUE
		if(S.use(1))
			to_chat(user, "You apply a bit of \the [W] to \the [src]. It immediately repairs all damage.")
			damage = 0
		return TRUE
	// Cable coil. Works as repair method, but will probably require multiple applications and more cable.
	if(istype(S, /obj/item/stack/cable_coil))
		if(!damage)
			to_chat(user, "\The [src] doesn't seem to require repairs.")
			return 1
		if(S.use(1))
			to_chat(user, "You patch up \the [src] with a bit of \the [W].")
			take_damage(-10)
		return TRUE
	return ..()


/// Returns the name of the var on /obj/item/modular_computer that holds this
/// hardware slot, or null if this type has no dedicated named slot.
/// Each concrete hardware subtype overrides this so that
/// try_install_component / uninstall_component can work generically via
/// vars[] without requiring an explicit branch per hardware kind.
/// Adding a new hardware type only requires: defining the var on
/// /obj/item/modular_computer and overriding this proc — no edits to core.
/obj/item/computer_hardware/proc/get_slot_var()
	return null

/// Returns TRUE if hot-removing this component while the computer is running
/// should trigger an immediate shutdown (e.g. processor, primary hard drive).
/// Override to TRUE on hardware whose absence makes the computer inoperable.
/obj/item/computer_hardware/proc/is_critical_slot()
	return FALSE

/// Returns a list of lines containing diagnostic information for display.
/obj/item/computer_hardware/proc/diagnostics(mob/user)
	to_chat(user, "Hardware Integrity Test... (Corruption: [damage]/[max_damage]) [damage > damage_failure ? "FAIL" : damage > damage_malfunction ? "WARN" : "PASS"]")

/obj/item/computer_hardware/Initialize(mapload)
	. = ..()
	w_class = hardware_size
	if(istype(loc, /obj/item/modular_computer))
		holder2 = loc

/obj/item/computer_hardware/Destroy()
	holder2 = null
	return ..()

/// Handles damage checks
/obj/item/computer_hardware/proc/check_functionality()
	// Turned off
	if(!enabled)
		return FALSE
	// Too damaged to work at all.
	if(damage > damage_failure)
		return FALSE
	// Still working. Well, sometimes...
	if(damage > damage_malfunction)
		if(prob(malfunction_probability))
			return FALSE
	// Good to go.
	return TRUE

/obj/item/computer_hardware/examine(mob/user)
	. = ..()
	if(damage > damage_failure)
		. += span_danger("It seems to be severely damaged!")
	else if(damage > damage_malfunction)
		. += span_notice("It seems to be damaged!")
	else if(damage)
		. += "It seems to be slightly damaged."

/// Damages the component. Contains necessary checks. Negative damage "heals" the component.
/obj/item/computer_hardware/take_damage(amount)
	damage += round(amount) 					// We want nice rounded numbers here.
	damage = between(0, damage, max_damage)		// Clamp the value.
