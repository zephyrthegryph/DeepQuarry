
/obj/machinery/gibber
	name = "gibber"
	desc = "The name isn't descriptive enough?"
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "grinder"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	req_access = list(ACCESS_KITCHEN,ACCESS_MORGUE)
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 4 SECONDS

	var/operating = 0 //Is it on?
	var/dirty = 0 // Does it need cleaning?
	var/gib_time = 40        // Time from starting until meat appears
	var/gib_throw_dir = WEST // Direction to spit meat and gibs in.

	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 500

//auto-gibs anything that bumps into it
/obj/machinery/gibber/autogibber
	var/turf/input_plate

/obj/machinery/gibber/autogibber/Initialize(mapload)
	. = ..()
	for(var/i in GLOB.cardinal)
		var/obj/machinery/mineral/input/input_obj = locate( /obj/machinery/mineral/input, get_step(src.loc, i) )
		if(input_obj)
			if(isturf(input_obj.loc))
				input_plate = input_obj.loc
				gib_throw_dir = i
				qdel(input_obj)
				break

	if(!input_plate)
		log_world("## MISC a [src] didn't find an input plate.")

/obj/machinery/gibber/Destroy()
	// The occupant slot's own teardown (destroy transaction phase 5, before
	// Destroy(), C8 step 2) already cleared occupant if one was present.
	return ..()

/// Sealed occupant slot (C8a, containment.md §10).
/datum/om/relation/slot/occupant/gibber
	holder = /obj/machinery/gibber
	slot_id = OCCUPANT_SLOT_GIBBER
	name = "gibber"
	// The slot IS the occupant: read it with SLOT_ITEM(holder, slot_id).


/obj/machinery/gibber/autogibber/Destroy()
	input_plate = null
	return ..()

/obj/machinery/gibber/autogibber/Bumped(atom/A)
	if(!input_plate) return

	if(ismob(A))
		var/mob/M = A

		if(M.loc == input_plate
		)
			M.forceMove(src)
			M.gib()


/obj/machinery/gibber/Initialize(mapload)
	. = ..()
	add_overlay("grjam")

/obj/machinery/gibber/update_icon()
	var/mob/living/occupant = src?.slot_item(OCCUPANT_SLOT_GIBBER)
	cut_overlays()
	if (dirty)
		add_overlay("grbloody")
	if(stat & (NOPOWER|BROKEN))
		return
	if (!occupant)
		add_overlay("grjam")
	else if (operating)
		add_overlay("gruse")
	else
		add_overlay("gridle")

/obj/machinery/gibber/relaymove(mob/user as mob)
	src.go_out()
	return

/obj/machinery/gibber/attack_hand(mob/user as mob)
	if(stat & (NOPOWER|BROKEN))
		return
	if(operating)
		to_chat(user, span_danger("The gibber is locked and running, wait for it to finish."))
		return
	else
		src.startgibbing(user)

/obj/machinery/gibber/examine()
	. = ..()
	. += "The safety guard is [emagged ? span_danger("disabled") : "enabled"]."

/obj/machinery/gibber/emag_act(remaining_charges, mob/user)
	emagged = !emagged
	to_chat(user, span_danger("You [emagged ? "disable" : "enable"] the gibber safety guard."))
	return 1

/obj/machinery/gibber/attackby(obj/item/W, mob/user)
	if(default_part_replacement(user, W))
		return

	var/obj/item/grab/G = W
	if(!istype(G))
		return ..()

	if(G.state < 2)
		to_chat(user, span_danger("You need a better grip to do that!"))
		return

	move_into_gibber(user,G?.grab_target())
	// Grab() process should clean up the grab item, no need to del it.

/obj/machinery/gibber/MouseDrop_T(mob/target, mob/user)
	if(user.stat || user.restrained())
		return
	move_into_gibber(user,target)

/obj/machinery/gibber/proc/move_into_gibber(mob/user,mob/living/victim)
	var/mob/living/occupant = src?.slot_item(OCCUPANT_SLOT_GIBBER)

	if(occupant)
		to_chat(user, span_danger("The gibber is full, empty it first!"))
		return

	if(operating)
		to_chat(user, span_danger("The gibber is locked and running, wait for it to finish."))
		return

	if(!(iscarbon(victim)) && !(isanimal(victim)) )
		to_chat(user, span_danger("This is not suitable for the gibber!"))
		return

	if(ishuman(victim) && !emagged)
		to_chat(user, span_danger("The gibber safety guard is engaged!"))
		return


	if(victim.abiotic(1))
		to_chat(user, span_danger("Subject may not have abiotic items on."))
		return

	user.visible_message(span_danger("[user] starts to put [victim] into the gibber!"))
	src.add_fingerprint(user)
	om_do_after(user, 3 SECONDS, src, src, PROC_REF(stuff_done), list(user, victim))

/obj/machinery/gibber/proc/stuff_done(mob/user, mob/living/victim)
	if(!victim.Adjacent(src) || !user.Adjacent(src) || !victim.Adjacent(user) || src?.slot_item(OCCUPANT_SLOT_GIBBER))
		return
	if(!victim.move_into(src, OCCUPANT_SLOT_GIBBER, user))
		return
	user.visible_message(span_danger("[user] stuffs [victim] into the gibber!"))
	update_icon()

/obj/machinery/gibber/verb/eject()
	set category = "Object"
	set name = "Empty Gibber"
	set src in oview(1)

	if (usr.stat != 0)
		return
	src.go_out()
	add_fingerprint(usr)
	return

/obj/machinery/gibber/proc/go_out()
	var/mob/living/occupant = src?.slot_item(OCCUPANT_SLOT_GIBBER)
	if(operating || !occupant)
		return
	for(var/obj/O in src)
		O.loc = src.loc
	slot_remove(occupant, get_turf(src))
	update_icon()
	return


/obj/machinery/gibber/proc/startgibbing(mob/user as mob)
	var/mob/living/occupant = src?.slot_item(OCCUPANT_SLOT_GIBBER)
	if(src.operating)
		return
	if(!occupant)
		visible_message(span_danger("You hear a loud metallic grinding sound."))
		return

	use_power(1000)
	visible_message(span_danger("You hear a loud [occupant.isSynthetic() ? "metallic" : "squelchy"] grinding sound."))
	src.operating = 1
	update_icon()

	var/slab_name = occupant.name
	var/slab_count = 2 + occupant.meat_amount
	var/slab_type = occupant.meat_type ? occupant.meat_type : /obj/item/reagent_containers/food/snacks/meat
	var/slab_nutrition = occupant.nutrition / 15

	var/list/byproducts = occupant?.butchery_loot?.Copy()

	if(ishuman(occupant))
		var/mob/living/carbon/human/H = occupant
		slab_name = occupant.real_name
		slab_type = H.isSynthetic() ? /obj/item/stack/material/steel : H.species.meat_type

	// Small mobs don't give as much nutrition.
	if(issmall(occupant))
		slab_nutrition *= 0.5
	slab_nutrition /= slab_count

	for(var/i=1 to slab_count)
		var/obj/item/reagent_containers/food/snacks/meat/new_meat = new slab_type(src, rand(3,8))
		if(istype(new_meat))
			new_meat.name = "[slab_name] [new_meat.name]"
			new_meat.reagents.add_reagent(REAGENT_ID_NUTRIMENT,slab_nutrition)
			if(occupant.reagents)
				occupant.reagents.trans_to_obj(new_meat, round(occupant.reagents.total_volume/(2 + occupant.meat_amount),1))

	add_attack_logs(user,occupant,"Used [src] to gib")

	occupant.ghostize()

	om_after(src, gib_time, PROC_REF(finish_gibbing), om_handle(occupant), byproducts)

/obj/machinery/gibber/proc/finish_gibbing(occupant_handle, list/byproducts)
	var/mob/living/occupant = om_resolve(occupant_handle)
	occupant?.gib()
	occupant = src?.slot_item(OCCUPANT_SLOT_GIBBER) // re-fetch: this runs after a delay, so the slot may have changed since capture
	if(occupant) // gib() may not always hard-delete (e.g. a synthetic's remains): the
		// remains stay physically in the slot, but are no longer "the occupant" --
		// unlink without a ledger move (the remains stay physically where they are).
		om_unlink(occupant, src, /datum/om/relation/slot/occupant/gibber)
	playsound(src, 'sound/effects/splat.ogg', 50, 1)
	operating = 0
	if(LAZYLEN(byproducts))
		for(var/path in byproducts)
			while(byproducts[path])
				if(prob(min(90,30 * byproducts[path])))
					new path(src)

				byproducts[path] -= 1

	for (var/obj/thing in contents)
		// There's a chance that the gibber will fail to destroy or butcher some evidence.
		if(istype(thing,/obj/item/organ) && prob(80))
			var/obj/item/organ/OR = thing
			if(OR.can_butcher(src))
				OR.butcher(src, null, src)	// Butcher it, and add it to our list of things to launch.
			else
				qdel(thing)
			continue
		thing.forceMove(get_turf(thing)) // Drop it onto the turf for throwing.
		thing.throw_at(get_edge_target_turf(src,gib_throw_dir),rand(0,3),emagged ? 100 : 50) // Being pelted with bits of meat and bone would hurt.

	update_icon()
