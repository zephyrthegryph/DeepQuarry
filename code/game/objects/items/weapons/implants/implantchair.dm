//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32

/obj/machinery/implantchair
	name = "loyalty implanter"
	desc = "Used to implant occupants with loyalty implants."
	icon = 'icons/obj/machines/implantchair.dmi'
	icon_state = "implantchair"
	density = TRUE
	opacity = 0
	anchored = TRUE
	flags = REMOTEVIEW_ON_ENTER

	var/ready = 1
	var/malfunction = 0
	var/list/obj/item/implant/loyalty/implant_list
	var/max_implants = 5
	var/injection_cooldown = 600
	var/replenish_cooldown = 6000
	var/replenishing = 0
	var/injecting = 0

CAPABILITIES(/obj/machinery/implantchair)
	owns_many(nameof(implant_list), /obj/item/implant/loyalty)
	interface("ImplantChair", title = "Implanter Status", state = nameof(GLOB.tgui_default_state))
	op("implant", ui_act("implant"), then(PROC_REF(ui_act_implant)))
	op("replenish", ui_act("replenish"), then(PROC_REF(ui_act_replenish)))
	// a grabbed carbon goes into the chair
	op("put_in", item(/obj/item/grab), label("Put in chair"), then(PROC_REF(interaction_insert)))
	// the old verbs
	op("get_out", menu(), label("Eject occupant"), needs(req_conscious()), then(PROC_REF(interaction_get_out)))
	op("move_inside", menu(), label("Move Inside"), needs(req_conscious()), then(PROC_REF(interaction_move_inside)))
	op("open_ui_impl", hand(), ungated(), label("Use"), then(PROC_REF(interaction_open_ui_impl)))

/obj/machinery/implantchair/Initialize(mapload)
	. = ..()
	add_implants()

/// Sealed occupant slot (C8a, containment.md §10).
/datum/om/relation/slot/occupant/implant_chair
	holder = /obj/machinery/implantchair
	slot_id = OCCUPANT_SLOT_IMPLANT_CHAIR
	name = "implant chair"
	// The slot IS the occupant: read it with SLOT_ITEM(holder, slot_id).


// structured TGUI ImplantChair (see
// code/modules/admin/implant_chair_panel.dm).

/obj/machinery/implantchair/proc/start_implant(mob/user)
	if(get_dist(src, user) > 1 && !isAI(user))
		return
	if(src?.slot_item(OCCUPANT_SLOT_IMPLANT_CHAIR))
		injecting = 1
		go_out()
		ready = 0
		after(src, injection_cooldown, PROC_REF(set_ready))
	add_fingerprint(user)

/obj/machinery/implantchair/proc/start_replenish(mob/user)
	if(get_dist(src, user) > 1 && !isAI(user))
		return
	ready = 0
	after(src, replenish_cooldown, PROC_REF(replenished))
	add_fingerprint(user)


/// Old attackby: a grabbed mob goes in.
/obj/machinery/implantchair/proc/interaction_insert(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/grab/grab = A.held
	var/mob/M = grab?.grab_target()
	if(!ismob(M))
		return OP_OK
	if(M.has_buckled_mobs())
		to_chat(user, span_warning("\The [M] has other entities attached to them. Remove them first."))
		return OP_OK
	if(put_mob(M, user))
		consume(grab, user)
	src.updateUsrDialog(user)
	return OP_OK


/obj/machinery/implantchair/proc/go_out(mob/M)
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_IMPLANT_CHAIR)
	if(!occupant)
		return
	if(M == occupant) // so that the guy inside can't eject himself -Agouri
		return
	// The occupant slot's own unlink (C8 step 2) clears `occupant` as soon
	// as slot_remove() takes effect, so the mob to implant is captured first.
	var/mob/living/carbon/leaving = occupant
	slot_remove(leaving, get_turf(src))
	if(injecting)
		implant(leaving)
		injecting = 0
	icon_state = "implantchair"
	return


/obj/machinery/implantchair/proc/put_mob(mob/living/carbon/M, mob/user)
	if(!iscarbon(M))
		to_chat(user, span_warning("\The [src] cannot hold this!"))
		return
	if(src?.slot_item(OCCUPANT_SLOT_IMPLANT_CHAIR))
		to_chat(user, span_warning("\The [src] is already occupied!"))
		return
	M.stop_pulling()
	if(!move_into(src, OCCUPANT_SLOT_IMPLANT_CHAIR, M, user))
		to_chat(user, span_warning("\The [src] won't take [M]!"))
		return
	src.add_fingerprint(user)
	icon_state = "implantchair_on"
	return 1


/obj/machinery/implantchair/proc/implant(mob/M)
	if (!istype(M, /mob/living/carbon))
		return
	if(!length(implant_list))	return
	for(var/obj/item/implant/loyalty/imp in implant_list)
		if(!imp)	continue
		if(istype(imp, /obj/item/implant/loyalty))
			for (var/mob/O in viewers(M, null))
				O.show_message(span_warning("\The [M] has been implanted by \the [src]."), 1)

			if(imp.handle_implant(M, BP_TORSO))
				imp.post_implant(M)

			own_take_member(src, nameof(implant_list), imp)
			break
	return


/obj/machinery/implantchair/proc/add_implants()
	for(var/i=0, i<src.max_implants, i++)
		var/obj/item/implant/loyalty/I = new /obj/item/implant/loyalty(src)
		rel_add(src, nameof(implant_list), I)
	return

/obj/machinery/implantchair/proc/interaction_get_out(datum/act/op/A)
	var/mob/user = A.actor
	src.go_out(user)
	add_fingerprint(user)
	return OP_OK

/obj/machinery/implantchair/proc/interaction_move_inside(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return OP_OK
	put_mob(user, user)
	return OP_OK

/obj/machinery/implantchair/proc/replenished()
	add_implants()
	ready = 1

/obj/machinery/implantchair/proc/set_ready()
	ready = 1

