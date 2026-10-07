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

/// Secured (ready to act); unsecured it can be attached to other assemblies.
/obj/item/assembly/var/secured = TRUE
TRACKED(/obj/item/assembly, secured)

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
	if(!holder() && isobj(loc) && (wires_type & WIRE_PULSE))
		var/obj/host = loc
		if(host.attached_assembly == src) // attached through the assembly capability
			cap_assembly_pulsed(host, src)
	return 1

/obj/item/assembly/proc/activate()
	if(QDELETED(src) || !secured || !COOLDOWN_FINISHED(src, next_activate))
		return FALSE
	COOLDOWN_START(src, next_activate, activation_cooldown)
	return TRUE

/obj/item/assembly/proc/toggle_secure()
	set_secured(!secured)
	update_icon()
	return secured

/obj/item/assembly/proc/attach_assembly(obj/item/assembly/A, mob/user)
	rel_set(src, nameof(holder), new/obj/item/assembly_holder(get_turf(src)))
	if(holder().attach(A,src,user))
		to_chat(user, span_notice("You attach \the [A] to \the [src]!"))
		return TRUE

CAPABILITIES(/obj/item/assembly)
	op("attach", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("use", in_hand(), label("Use"), then(PROC_REF(interaction_self)))

/// Old attackby: attach another unsecured assembly.
/obj/item/assembly/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(isassembly(W))
		var/obj/item/assembly/other = W
		if((!other.secured) && (!secured))
			attach_assembly(other, user)
			return OP_OK
	return OP_DECLINE

/obj/item/assembly/screwdriver_act(mob/user, obj/item/tool)
	if(toggle_secure())
		to_chat(user, span_notice("\The [src] is ready!"))
	else
		to_chat(user, span_notice("\The [src] can now be attached!"))
	return ITEM_INTERACT_SUCCESS

/obj/item/assembly/examine(mob/user)
	. = ..()
	if((in_range(src, user) || loc == user))
		if(secured)
			. += "\The [src] is ready!"
		else
			. += "\The [src] can be attached!"

/// Old attack_self: the base opens the UI. A subtype with special_handling overrides this (without ..()) and
/// does its own thing; the op is virtual by proc name, so every override is reached through the one "use" op.
/obj/item/assembly/proc/interaction_self(datum/act/op/A)
	if(special_handling)
		return OP_DECLINE
	tgui_interact(A.actor)
	return OP_OK



/obj/item/assembly/tgui_host()
	if(istype(loc, /obj/item/assembly_holder))
		return loc.tgui_host()
	return ..()

/// the holder this refers to (a relation view: null once it is deleted).
/obj/item/assembly/proc/holder() as /obj/item/assembly_holder
	return holder
