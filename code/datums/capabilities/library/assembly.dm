// cap_assembly(): the holder takes one /obj/item/assembly (a signaler, timer, igniter, sensor, ...) as
// its trigger. Attaching needs the assembly unsecured, as the tank transfer valve does; it is
// secured once inside. The holder owns it in `attached_assembly` (own_set()). "Trigger" activates
// it (activate(), with its own cooldown); when the attached assembly pulses (its timer ran out, its
// signal arrived, its sensor tripped) the capability's on_pulse proc runs on the holder.
//
//	/obj/item/grenade/rigged/capabilities()
//		. = ..()
//		. += cap_assembly(attach_types = list(/obj/item/assembly/timer, /obj/item/assembly/signaler), on_pulse = PROC_REF(detonate))

/obj
	/// The assembly attached by the assembly capability (owned: own_set()).
	var/obj/item/assembly/attached_assembly

/datum/capability/assembly
	log = LOG_GAME
	works_broken = TRUE
	works_unpowered = TRUE
	/// The assembly types that fit (subtypes count).
	var/list/attach_types
	/// PROC_REF on the holder, (obj/item/assembly/source): runs when the attached assembly pulses.
	var/on_pulse
	/// The tool that takes the assembly back out, or null for an empty hand.
	var/detach_tool
	/// An overlay drawn while an assembly is attached, or null.
	var/attached_state

/proc/cap_assembly(list/attach_types = list(/obj/item/assembly), on_pulse, detach_tool = TOOL_SCREWDRIVER, attached_state, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME)
	var/datum/capability/assembly/C = new
	C.attach_types = attach_types
	C.on_pulse = on_pulse
	C.detach_tool = detach_tool
	C.attached_state = attached_state
	cap_gating(C, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered)
	return C

/datum/capability/assembly/interactions(atom/holder)
	var/datum/interaction/capability/attach = adopt_entry(cap_insert("Attach", attach_types, TYPE_PROC_REF(/obj, cap_assembly_attach), needs = TYPE_PROC_REF(/obj, cap_assembly_can_attach), works_broken = TRUE, works_unpowered = TRUE))
	var/datum/capability/entry/detach_wrapper
	if(detach_tool)
		detach_wrapper = cap_tool("Detach assembly", detach_tool, TYPE_PROC_REF(/obj, cap_assembly_detach), needs = TYPE_PROC_REF(/obj, cap_assembly_present), else_say = "nothing is attached to it")
	else
		detach_wrapper = cap_hand("Detach assembly", TYPE_PROC_REF(/obj, cap_assembly_detach), needs = TYPE_PROC_REF(/obj, cap_assembly_present), else_say = "nothing is attached to it", works_broken = TRUE, works_unpowered = TRUE)
	var/datum/interaction/capability/detach = adopt_entry(detach_wrapper)
	var/datum/interaction/capability/trigger = adopt_entry(cap_hand("Trigger", TYPE_PROC_REF(/obj, cap_assembly_trigger), needs = TYPE_PROC_REF(/obj, cap_assembly_present), else_say = "nothing is attached to it", works_broken = TRUE, works_unpowered = TRUE))
	trigger.default_action = null // Menu only: an empty hand keeps doing the holder's own thing
	if(!detach_tool)
		detach.default_action = null
	return list(attach, detach, trigger)

/datum/capability/assembly/examine(atom/holder, mob/user)
	var/obj/O = holder
	if(!istype(O) || !O.attached_assembly)
		return null
	return list("\A [O.attached_assembly] is attached to it.")

/datum/capability/assembly/draw(atom/holder, datum/look/look)
	var/obj/O = holder
	look.part(attached_state, !!(istype(O) && !isnull(O.attached_assembly)))

/datum/capability/assembly/ui_data(atom/holder, mob/user, list/data)
	var/obj/O = holder
	data["attached_assembly"] = O.attached_assembly ? "[O.attached_assembly]" : null

/// The assembly capability of A, or null.
/proc/cap_assembly_cap(atom/A)
	return cap_of(A, /datum/capability/assembly)

/obj/proc/cap_assembly_present(mob/user, obj/item/held)
	return !isnull(attached_assembly)

/obj/proc/cap_assembly_can_attach(mob/user, obj/item/assembly/held)
	if(attached_assembly)
		return "something is already attached to it"
	if(!istype(held))
		return "that isn't an assembly"
	if(held.secured)
		return "unsecure \the [held] first"
	return TRUE

/// Puts A into O as its attached assembly and secures it. TRUE when attached.
/proc/cap_assembly_put(obj/O, obj/item/assembly/A, mob/user)
	if(O.attached_assembly || !istype(A))
		return FALSE
	// One call takes A out of the hand (or wherever it is), moves it in and adopts it. No `user`:
	// the calling handler refuses with its own message and is already recorded by its dispatch.
	if(!own_set(O, nameof(/obj::attached_assembly), A, into = TRUE))
		return FALSE
	if(!A.secured)
		A.toggle_secure()
	changed(O, CHANGE_CAPABILITY)
	return TRUE

/obj/proc/cap_assembly_attach(mob/user, obj/item/assembly/held)
	if(!cap_assembly_put(src, held, user))
		return refuse(user, "You can't attach \the [held] to \the [src].")
	act_message(user, src, self = span_notice("You attach \the [held] to %T%."), others = span_notice("%U% attaches \the [held] to %T%."), item = held)
	return TRUE

/obj/proc/cap_assembly_detach(mob/user, obj/item/held)
	var/obj/item/assembly/A = own_take(src, nameof(/obj::attached_assembly))
	if(!A)
		return refuse(user, "Nothing is attached to \the [src].")
	if(A.secured)
		A.toggle_secure()
	A.forceMove(drop_location())
	user?.put_in_hands(A)
	act_message(user, src, self = span_notice("You detach \the [A] from %T%."), others = span_notice("%U% detaches \the [A] from %T%."), item = held)
	return TRUE

/obj/proc/cap_assembly_trigger(mob/user, obj/item/held)
	if(!attached_assembly.activate())
		return refuse(user, "\The [attached_assembly] isn't ready.")
	act_message(user, src, self = span_notice("You trigger %T%."), others = span_notice("%U% triggers %T%."))
	return TRUE

/// The attached assembly A pulsed: run the capability's on_pulse on O. Called from
/// /obj/item/assembly/pulse() when the assembly sits in an assembly capability holder.
/proc/cap_assembly_pulsed(obj/O, obj/item/assembly/A)
	var/datum/capability/assembly/C = cap_assembly_cap(O)
	if(!C || O.attached_assembly != A)
		return FALSE
	if(C.on_pulse)
		call(O, C.on_pulse)(A)
	changed(O, CHANGE_CAPABILITY)
	return TRUE
