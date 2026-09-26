
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
	var/mob/living/occupant // Mob who has been put inside
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
	// C8 step 2: replaces the separate occupant_of relation this machine used
	// to hand-link.
	// No view fields (OM relations step 3): `occupant` is still an ordinary
	// var every reader here uses, but this slot's own on_link()/on_unlink()
	// are its only writer now -- there is no generic field-link mechanism
	// left to do it for them.

/datum/om/relation/slot/occupant/gibber/on_link(mob/living/source, obj/machinery/gibber/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(target))
		target.occupant = source

/datum/om/relation/slot/occupant/gibber/on_unlink(mob/living/source, obj/machinery/gibber/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(target) && target.occupant == source)
		target.occupant = null

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

	move_into_gibber(user,G.affecting)
	// Grab() process should clean up the grab item, no need to del it.

/obj/machinery/gibber/MouseDrop_T(mob/target, mob/user)
	if(user.stat || user.restrained())
		return
	move_into_gibber(user,target)

/obj/machinery/gibber/proc/move_into_gibber(mob/user,mob/living/victim)

	if(src.occupant)
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
	if(do_after(user, 3 SECONDS, target = src) && victim.Adjacent(src) && user.Adjacent(src) && victim.Adjacent(user) && !occupant)
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
	if(operating || !src.occupant)
		return
	for(var/obj/O in src)
		O.loc = src.loc
	slot_remove(src.occupant, get_turf(src))
	update_icon()
	return


/obj/machinery/gibber/proc/startgibbing(mob/user as mob)
	if(src.operating)
		return
	if(!src.occupant)
		visible_message(span_danger("You hear a loud metallic grinding sound."))
		return

	use_power(1000)
	visible_message(span_danger("You hear a loud [occupant.isSynthetic() ? "metallic" : "squelchy"] grinding sound."))
	src.operating = 1
	update_icon()

	var/slab_name = occupant.name
	var/slab_count = 2 + occupant.meat_amount
	var/slab_type = occupant.meat_type ? occupant.meat_type : /obj/item/reagent_containers/food/snacks/meat
	var/slab_nutrition = src.occupant.nutrition / 15

	var/list/byproducts = occupant?.butchery_loot?.Copy()

	if(ishuman(src.occupant))
		var/mob/living/carbon/human/H = occupant
		slab_name = src.occupant.real_name
		slab_type = H.isSynthetic() ? /obj/item/stack/material/steel : H.species.meat_type

	// Small mobs don't give as much nutrition.
	if(issmall(src.occupant))
		slab_nutrition *= 0.5
	slab_nutrition /= slab_count

	for(var/i=1 to slab_count)
		var/obj/item/reagent_containers/food/snacks/meat/new_meat = new slab_type(src, rand(3,8))
		if(istype(new_meat))
			new_meat.name = "[slab_name] [new_meat.name]"
			new_meat.reagents.add_reagent(REAGENT_ID_NUTRIMENT,slab_nutrition)
			if(src.occupant.reagents)
				src.occupant.reagents.trans_to_obj(new_meat, round(occupant.reagents.total_volume/(2 + occupant.meat_amount),1))

	add_attack_logs(user,occupant,"Used [src] to gib")

	src.occupant.ghostize()

	spawn(gib_time)
		var/mob/living/gibbed = occupant
		gibbed.gib()
		if(occupant) // gib() may not always hard-delete (e.g. a synthetic's remains): the
			// remains stay physically in the slot, but are no longer "the occupant" (the
			// slot IS the occupant_of relation now, C8 step 2, so this clears the view
			// field without a ledger move).
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
