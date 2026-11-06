/obj/item/electronic_assembly/device
	name = "electronic device"
	icon_state = "setup_device"
	desc = "It's a tiny electronic device with specific use for attaching to other devices."
	var/tmp/obj/item/assembly/electronic_assembly/holder
	w_class = ITEMSIZE_TINY
	max_components = IC_COMPONENTS_BASE * 3/4
	max_complexity = IC_COMPLEXITY_BASE * 3/4

CAPABILITIES(/obj/item/electronic_assembly/device)
	setup(PROC_REF(make_builtin_device_pins))
	ref_one(nameof(holder), /obj/item/assembly/electronic_assembly)

/obj/item/electronic_assembly/device/proc/make_builtin_device_pins()
	var/obj/item/integrated_circuit/built_in/device_input/input = new(src)
	var/obj/item/integrated_circuit/built_in/device_output/output = new(src)
	rel_set(input, nameof(input.assembly), src)
	rel_set(output, nameof(output.assembly), src)


// The holder device owns us (its EA default child); holder is a plain relation back.
/obj/item/electronic_assembly/device/check_interactivity(mob/user)
	if(!CanInteract(user, state = GLOB.tgui_deep_inventory_state))
		return 0
	return 1

/// The holder this refers to (a relation view: null once that is deleted).
/obj/item/electronic_assembly/device/proc/holder() as /obj/item/assembly/electronic_assembly
	return holder
