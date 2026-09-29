/obj/item/assembly/electronic_assembly
	name = "electronic device"
	desc = "It's a case for building electronics with. It can be attached to other small devices."
	icon_state = "setup_device"
	var/opened = 0

	var/obj/item/electronic_assembly/device/EA

	special_handling = TRUE

DECLARE_DEFAULT_CHILD(/obj/item/assembly/electronic_assembly, "EA", /obj/item/electronic_assembly/device)

/obj/item/assembly/electronic_assembly/Initialize(mapload)
	. = ..()
	rel_set(EA, "holder", src)


EXTEND_INTERACTIONS(/obj/item/assembly/electronic_assembly, \
	INTERACT_ITEM(null, PROC_REF(electronic_assembly_interaction_item)), \
	INTERACT_VERB("Open/Close Device Assembly", PROC_REF(device_assembly_verb_toggle), REQ_IN_INVENTORY), \
)

/// Old attackby.
/obj/item/assembly/electronic_assembly/proc/electronic_assembly_interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(opened)
		EA.attackby(I, user)
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

/obj/item/assembly/electronic_assembly/crowbar_act(mob/user, obj/item/tool)
	toggle_open(user)
	return TRUE

/obj/item/assembly/electronic_assembly/proc/toggle_open(mob/user)
	play_sfx(src, SFX_ITEMS_CROWBAR)
	opened = !opened
	EA.opened = opened
	to_chat(user, span_notice("You [opened ? "opened" : "closed"] \the [src]."))
	secured = 1
	update_icon()

APPEARANCE_TEMPLATE(/obj/item/assembly/electronic_assembly, "{initial(icon_state)}{EA?:0}{opened?-open:}")

/// Old attack_self (the assembly self-use chain: /obj/item/assembly/proc/interaction_self()): use the circuit inside.
/obj/item/assembly/electronic_assembly/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
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
/obj/item/assembly/electronic_assembly/proc/device_assembly_verb_toggle(mob/user, obj/item/held, datum/interaction/interaction)
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
	rel_set(input, "assembly", src)
	rel_set(output, "assembly", src)

// The holder device owns us (its EA default child); holder is a plain relation back.

/obj/item/electronic_assembly/device/check_interactivity(mob/user)
	if(!CanInteract(user, state = GLOB.tgui_deep_inventory_state))
		return 0
	return 1

/// The holder this refers to (a relation view: null once that is deleted).
/obj/item/electronic_assembly/device/proc/holder() as /obj/item/assembly/electronic_assembly
	return holder

