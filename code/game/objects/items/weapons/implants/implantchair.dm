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
	var/mob/living/carbon/occupant = null
	var/injecting = 0

/obj/machinery/implantchair/Initialize(mapload)
	. = ..()
	add_implants()

/// Sealed occupant slot (C8a, containment.md §10).
/datum/om/relation/slot/occupant/implant_chair
	holder = /obj/machinery/implantchair
	slot_id = OCCUPANT_SLOT_IMPLANT_CHAIR
	name = "implant chair"
	// C8 step 2: replaces the separate occupant_of relation this machine used
	// to hand-link in put_mob()/go_out().
	target_ref_field = "occupant"


// structured TGUI ImplantChair (see
// code/modules/admin/implant_chair_panel.dm).

/obj/machinery/implantchair/Topic(href, href_list)
	if((get_dist(src, usr) <= 1) || isAI(usr))
		if(href_list["implant"])
			if(src.occupant)
				injecting = 1
				go_out()
				ready = 0
				spawn(injection_cooldown)
					ready = 1

		if(href_list["replenish"])
			ready = 0
			spawn(replenish_cooldown)
				add_implants()
				ready = 1

		src.updateUsrDialog(usr)
		src.add_fingerprint(usr)
		return


/obj/machinery/implantchair/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/implantchair_insert,
		/datum/interaction/machine_verb/implantchair_get_out,
		/datum/interaction/machine_verb/implantchair_move_inside,
	)
	..()

/// Old attackby: never called ..(), so the whole thing (including the non-grab no-op) stays in the effect.
/datum/interaction/machine_item/implantchair_insert
	id = "implantchair_insert"
	name = "Put in chair"
	effect = /obj/machinery/implantchair/proc/interaction_insert

/obj/machinery/implantchair/proc/interaction_insert(mob/user, obj/item/G, datum/interaction/interaction)
	if(istype(G, /obj/item/grab))
		var/obj/item/grab/grab = G
		if(!ismob(grab.affecting))
			return TRUE
		if(grab.affecting.has_buckled_mobs())
			to_chat(user, span_warning("\The [grab.affecting] has other entities attached to them. Remove them first."))
			return TRUE
		var/mob/M = grab.affecting
		if(put_mob(M))
			qdel(G)
	src.updateUsrDialog(user)
	return TRUE


/obj/machinery/implantchair/proc/go_out(mob/M)
	if(!( src.occupant ))
		return
	if(M == occupant) // so that the guy inside can't eject himself -Agouri
		return
	// The occupant slot's own om_unlink (C8 step 2) clears `occupant` as soon
	// as slot_remove() takes effect, so the mob to implant is captured first.
	var/mob/living/carbon/leaving = src.occupant
	slot_remove(leaving, get_turf(src))
	if(injecting)
		implant(leaving)
		injecting = 0
	icon_state = "implantchair"
	return


/obj/machinery/implantchair/proc/put_mob(mob/living/carbon/M)
	if(!iscarbon(M))
		to_chat(usr, span_warning("\The [src] cannot hold this!"))
		return
	if(src.occupant)
		to_chat(usr, span_warning("\The [src] is already occupied!"))
		return
	M.stop_pulling()
	if(!M.move_into(src, OCCUPANT_SLOT_IMPLANT_CHAIR, usr))
		to_chat(usr, span_warning("\The [src] won't take [M]!"))
		return
	src.add_fingerprint(usr)
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

			LAZYREMOVE(implant_list, imp)
			break
	return


/obj/machinery/implantchair/proc/add_implants()
	for(var/i=0, i<src.max_implants, i++)
		var/obj/item/implant/loyalty/I = new /obj/item/implant/loyalty(src)
		LAZYADD(implant_list, I)
	return

/datum/interaction/machine_verb/implantchair_get_out
	id = "implantchair_get_out"
	name = "Eject occupant"
	effect = /obj/machinery/implantchair/proc/interaction_get_out

/obj/machinery/implantchair/proc/interaction_get_out(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.stat != 0)
		return TRUE
	src.go_out(user)
	add_fingerprint(user)
	return TRUE

/datum/interaction/machine_verb/implantchair_move_inside
	id = "implantchair_move_inside"
	name = "Move Inside"
	effect = /obj/machinery/implantchair/proc/interaction_move_inside

/obj/machinery/implantchair/proc/interaction_move_inside(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.stat != 0 || stat & (NOPOWER|BROKEN))
		return TRUE
	put_mob(user)
	return TRUE
