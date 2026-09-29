/obj/item/assembly
	name = "assembly"
	desc = "A small electronic device that should never exist."
	icon = 'icons/obj/assemblies/new_assemblies.dmi'
	icon_state = ""
	w_class = ITEMSIZE_SMALL
	MATERIAL_BULK(MAT_STEEL, 100)
	throwforce = 2
	throw_speed = 3
	throw_range = 10
	drop_sound = SFX_ITEMS_DROP_COMPONENT
	pickup_sound =  SFX_ITEMS_PICKUP_COMPONENT

	var/secured = 1
	var/list/attached_overlays = null
	var/tmp/obj/item/assembly_holder/holder
	var/cooldown = FALSE //To prevent spam
	var/wires_type = WIRE_RECEIVE | WIRE_PULSE

	var/const/WIRE_RECEIVE = 1			//Allows Pulsed(0) to call Activate()
	var/const/WIRE_PULSE = 2				//Allows Pulse(0) to act on the holder
	var/const/WIRE_PULSE_SPECIAL = 4		//Allows Pulse(0) to act on the holders special assembly
	var/const/WIRE_RADIO_RECEIVE = 8		//Allows Pulsed(1) to call Activate()
	var/const/WIRE_RADIO_PULSE = 16		//Allows Pulse(1) to send a radio message

	///var used for attack_self chain
	var/special_handling = FALSE

	COOLDOWN_DECLARE(next_activate)
	var/activation_cooldown = 3 SECONDS

/obj/item/assembly/proc/holder_movement()
	return

/obj/item/assembly/proc/pulsed(radio = 0)
	if(holder() && (wires_type & WIRE_RECEIVE))
		activate()
	if(radio && (wires_type & WIRE_RADIO_RECEIVE))
		activate()
	return 1

/obj/item/assembly/proc/pulse(radio = 0)
	if(holder() && (wires_type & WIRE_PULSE))
		holder().process_activation(src, 1, 0)
	if(holder() && (wires_type & WIRE_PULSE_SPECIAL))
		holder().process_activation(src, 0, 1)
	return 1

/obj/item/assembly/proc/activate()
	if(QDELETED(src) || !secured || !COOLDOWN_FINISHED(src, next_activate))
		return FALSE
	COOLDOWN_START(src, next_activate, activation_cooldown)
	return TRUE

/obj/item/assembly/proc/toggle_secure()
	secured = !secured
	update_icon()
	return secured

/obj/item/assembly/proc/attach_assembly(obj/item/assembly/A, mob/user)
	rel_set(src, "holder", new/obj/item/assembly_holder(get_turf(src)))
	if(holder().attach(A,src,user))
		to_chat(user, span_notice("You attach \the [A] to \the [src]!"))
		return TRUE

DECLARE_INTERACTIONS(/obj/item/assembly, \
	INTERACT_ITEM("Use", PROC_REF(interaction_item)), \
	INTERACT_USE("Use", PROC_REF(interaction_self)), \
)

/// Old attackby: attach another unsecured assembly.
/obj/item/assembly/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(isassembly(W))
		var/obj/item/assembly/A = W
		if((!A.secured) && (!secured))
			attach_assembly(A,user)
			return TRUE
	return FALSE

/obj/item/assembly/screwdriver_act(mob/user, obj/item/tool)
	if(toggle_secure())
		to_chat(user, span_notice("\The [src] is ready!"))
	else
		to_chat(user, span_notice("\The [src] can now be attached!"))
	return ITEM_INTERACT_SUCCESS

/obj/item/assembly/periodic_step()
	return PROCESS_KILL

/obj/item/assembly/examine(mob/user)
	. = ..()
	if((in_range(src, user) || loc == user))
		if(secured)
			. += "\The [src] is ready!"
		else
			. += "\The [src] can be attached!"

/// Old attack_self: subtypes override interaction_self() and call ..() first, matching the
/// old override chain (a subtype's own handling takes priority; this base opens the UI).
/// Compact INTERACT_USE dispatches virtually by proc name, so every subtype's override
/// (voice, igniter, shock_kit, mousetrap, ...) is reached with no interaction of its own -
/// one shared /datum/interaction/generic singleton covers the whole hierarchy.
/obj/item/assembly/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(special_handling)
		return FALSE
	if(!user)
		return FALSE
	tgui_interact(user)
	return TRUE

/obj/item/assembly/tgui_state(mob/user)
	return GLOB.tgui_deep_inventory_state

/obj/item/assembly/tgui_interact(mob/user, datum/tgui/ui)
	return // tgui goes here

/obj/item/assembly/tgui_host()
	if(istype(loc, /obj/item/assembly_holder))
		return loc.tgui_host()
	return ..()

/// the holder this refers to (a relation view: null once it is deleted).
/obj/item/assembly/proc/holder() as /obj/item/assembly_holder
	return holder
