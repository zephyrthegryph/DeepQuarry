/obj/item/assembly/electronic_assembly
	name = "electronic device"
	desc = "It's a case for building electronics with. It can be attached to other small devices."
	icon_state = "setup_device"
	var/opened = 0

	var/obj/item/electronic_assembly/device/EA

	special_handling = TRUE

TRACKED(/obj/item/assembly/electronic_assembly, opened)

CAPABILITIES(/obj/item/assembly/electronic_assembly)
	// the device answers an item itself (circuits when opened, the assembly attach when closed): the parent's attach op would clash at the same tier
	without("attach")
	owns_one(nameof(EA), starts = /obj/item/electronic_assembly/device)
	op("electronic_assembly_interaction_item", item(/obj/item), then(PROC_REF(electronic_assembly_interaction_item)))
	op("device_assembly_verb_toggle", menu(), label("Open/Close Device Assembly"), needs(carried()), then(PROC_REF(device_assembly_verb_toggle)))
	op("use_crowbar", tool(TOOL_CROWBAR), wait(0), then(PROC_REF(crowbar_used)))

/obj/item/assembly/electronic_assembly/Initialize(mapload)
	. = ..()
	rel_set(EA, nameof(EA.holder), src)


/// Old attackby.
/obj/item/assembly/electronic_assembly/proc/electronic_assembly_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(opened)
		EA.attackby(I, user)
	else
		return interaction_item(A)
	return OP_PASS

/obj/item/assembly/electronic_assembly/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	toggle_open(user)
	return OP_OK

/obj/item/assembly/electronic_assembly/proc/toggle_open(mob/user)
	play_sfx(src, SFX_ITEMS_CROWBAR)
	set_opened(!opened)
	EA.set_opened(opened)
	to_chat(user, span_notice("You [opened ? "opened" : "closed"] \the [src]."))
	set_secured(TRUE)

/// The look (the draw sweep: from its template).
/obj/item/assembly/electronic_assembly/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][EA ? "" : "0"][opened ? "-open" : ""]")

/// Old attack_self (the assembly self-use chain: /obj/item/assembly/proc/interaction_self()): use the circuit inside.
/obj/item/assembly/electronic_assembly/interaction_self(mob/user, obj/item/held)
	. = ..()
	if(.)
		return TRUE
	if(EA)
		EA.attack_self(user)
	return TRUE

/obj/item/assembly/electronic_assembly/pulsed(radio = 0)						//Called when another assembly acts on this one, var/radio will determine where it came from for wire calcs
	if(EA)
		for(var/obj/item/integrated_circuit/built_in/device_input/I in contents_of(EA))
			I.do_work()
		return

/obj/item/assembly/electronic_assembly/examine(mob/user)
	. = ..()
	if(EA)
		FOR_REAL_CONTENTS(var/obj/item/integrated_circuit/IC, EA)
			. += IC.external_examine(user)

/// Old Open/Close Device Assembly verb: Open or close device assembly!
/obj/item/assembly/electronic_assembly/proc/device_assembly_verb_toggle(datum/act/op/A)
	var/mob/user = A.actor
	toggle_open(user)

/obj/item/electronic_assembly/device
	name = "electronic device"
	icon_state = "setup_device"
	desc = "It's a tiny electronic device with specific use for attaching to other devices."
	var/tmp/obj/item/assembly/electronic_assembly/holder
	w_class = ITEMSIZE_TINY
	max_components = IC_COMPONENTS_BASE * 3/4
	max_complexity = IC_COMPLEXITY_BASE * 3/4

/obj/item/electronic_assembly/device/Initialize(mapload)
	. = ..()
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

