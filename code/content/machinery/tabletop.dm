// Table-top and bulky machines that must be bolted to work (the hot plate, the condenser, the bunsen burner, the scale, the microscope, the book
// scanner and binder, the color mate, the spectrometer; the operating table, the ice cream vat and the processors).
//
//   tabletop()               bolted to work: STAT_OPERABLE needs `anchored`; a map-placed one starts bolted
//   tabletop(carry = TRUE)   ...and, while unbolted, an empty hand picks it up: the machine goes inside a /obj/item/tabletop_pack the actor carries
//
// A pack holds the very machine (owns_one), so its beaker, its dial and every other setting come back as they were when it is set down again, with
// the pack's "Set it down" op (in hand) or by clicking a floor or table tile with it. Wrench (machine_anchor, the base machine's op) bolts it and
// unbolts it; the bulky machines have no carry and simply refuse their controls while unbolted (req_bolted()).

MSG_DEF_SELF(tabletop/unbolted, "Bolt it to the floor first.")
MSG_DEF_SELF(tabletop/no_room, "There is no room to set it down there.")
MSG_DEF_SELF(tabletop/gone, "There is nothing in it to set down.")

/// The holder is bolted down (a control a bulky machine refuses while it is loose).
/proc/req_bolted()
	return req_is(nameof(/atom/movable::anchored), TRUE, because = MSG(tabletop/unbolted))

CAPABILITY_TYPE(tabletop, CAP_TABLETOP, /datum/capability/tabletop, key = NONE, carry = FALSE)

/datum/capability/tabletop
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/tabletop/entries()
	var/list/entries = list(contributes(STAT_OPERABLE, nameof(/atom/movable::anchored), key = "bolted_operable", reason = MSG(tabletop/unbolted)))
	// A wrench bolts and unbolts above the machine's own empty-hand controls: those match a hand holding a tool too (the hot plate's radial, a condenser's
	// "take the container"), and at the machine's own tier they answered a wrench click before the base machine's secure and unsecure ops did.
	entries += extend("machine_anchor", priority(OP_PRIORITY_PART))
	entries += extend("machine_unanchor", priority(OP_PRIORITY_PART))
	if(carry)
		// Above the machine's own empty-hand controls: a loose machine is picked up, not used.
		entries += op("tabletop_pick_up", hand(), ungated(), priority(OP_PRIORITY_PART), label("Pick up"),
			when(not(nameof(/atom/movable::anchored))),
			when(req_empty_hand()),
			needs(req_capable(), req_actor_kind(/mob/living/silicon/ai, not = TRUE)),
			then(CAP_PROC(pick_up)))
	return entries

/// A machine the map placed starts bolted, so the maps keep working; one built or spawned at run time starts loose.
/datum/capability/tabletop/on_holder_init(datum/act/eval/A)
	var/obj/machinery/holder = A.holder
	if(A.mapload && !holder.anchored)
		holder.set_anchored(TRUE)

/// An empty hand takes the loose machine: it goes into a pack with everything it holds, and the pack is in the actor's hand.
/datum/capability/tabletop/proc/pick_up(datum/act/op/A)
	var/obj/machinery/M = A.holder
	var/mob/user = A.actor
	var/obj/item/tabletop_pack/P = new(get_turf(M))
	P.pack(M)
	user.put_in_hands(P)
	to_chat(user, span_notice("You pick up \the [M]."))
	if(GLOB.fab_trace)
		log_world("TABLETOP: [user] picked up [M] ([M.type]) into [P]")
	return OP_OK

/// A loose machine carried as an item. It holds the machine itself, so nothing the machine held or was set to is copied or lost.
/obj/item/tabletop_pack
	name = "loose machine"
	desc = "A machine that is not bolted down."
	icon = 'icons/obj/device.dmi'
	icon_state = "bunsen0"
	w_class = ITEMSIZE_HUGE
	/// The machine carried.
	var/obj/machinery/machine

CAPABILITIES(/obj/item/tabletop_pack)
	owns_one(nameof(machine), /obj/machinery)
	op("tabletop_set_down", in_hand(), label("Set it down"), needs(req(PROC_REF(here_clear))), then(PROC_REF(set_down_here)))
	op("tabletop_set_down_on", at_target(/turf), at_target(/obj/structure/table), priority(OP_PRIORITY_PART), label("Set it down here"),
		needs(req_adjacent(), req(PROC_REF(target_clear))), then(PROC_REF(set_down_there)))

/// The machine goes into the pack and the pack looks like it.
/obj/item/tabletop_pack/proc/pack(obj/machinery/M)
	M.forceMove(src)
	rel_set(src, nameof(machine), M) // adopts the machine where it is: it already moved in
	name = M.name
	desc = "[M.desc] It is not bolted down."
	if(GLOB.fab_trace)
		log_world("TABLETOP: [src] packs [M] ([M.type]); its power area is [M.power_area || "none"]")

/// The pack looks like the machine it carries, overlays and all (a beaker on a hot plate), and follows the machine when it is redrawn.
/obj/item/tabletop_pack/draw(datum/look/look)
	..()
	look.mimic(machine)

/// Why the machine can't be set down on `T`, or null.
/obj/item/tabletop_pack/proc/spot_refusal(turf/T)
	if(!machine)
		return MSG(tabletop/gone)
	if(!isturf(T) || T.density)
		return MSG(tabletop/no_room)
	if(!machine.density || locate_on(T, /obj/structure/table))
		return null
	for(var/obj/O in turf_contents_of_type(T, /obj))
		if(O.density)
			return MSG(tabletop/no_room)
	return null

/obj/item/tabletop_pack/proc/here_clear(datum/act/op/A)
	var/mob/user = A.actor
	return spot_refusal(get_turf(user))

/obj/item/tabletop_pack/proc/target_clear(datum/act/op/A)
	return spot_refusal(get_turf(A.target))

/obj/item/tabletop_pack/proc/set_down_here(datum/act/op/A)
	return set_down(A.actor, get_turf(A.actor))

/obj/item/tabletop_pack/proc/set_down_there(datum/act/op/A)
	return set_down(A.actor, get_turf(A.target))

/// The machine leaves the pack for `T` as it was packed (still unbolted); the empty pack is used up.
/obj/item/tabletop_pack/proc/set_down(mob/user, turf/T)
	var/obj/machinery/M = machine
	if(!M || spot_refusal(T))
		return OP_REFUSED
	M.forceMove(T)
	rel_take(src, nameof(machine))
	if(GLOB.fab_trace)
		log_world("TABLETOP: [M] left its pack for [T]; its power area is [M.power_area || "none"]")
	to_chat(user, span_notice("You set \the [M] down."))
	if(GLOB.fab_trace)
		log_world("TABLETOP: [user] set [M] ([M.type]) down at [T] (bolted [M.anchored ? "yes" : "no"])")
	consume(src, user)
	return OP_OK

/obj/item/tabletop_pack/examine(mob/user)
	. = ..()
	if(machine)
		. += span_notice("Set it down and wrench it to the floor to use it.")
